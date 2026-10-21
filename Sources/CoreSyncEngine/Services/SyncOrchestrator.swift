import Foundation
import Combine

public enum SyncState: String, Sendable {
    case idle
    case scanning
    case syncing
    case pausedForStorage
    case completed
    case cancelled
    case error
}

public final class SyncOrchestrator: ObservableObject, @unchecked Sendable {
    public let imageCaptureManager: ImageCaptureManager
    public let photoKitManager: PhotoKitSourceManager
    public let adbClient: ADBClient
    public let database: SyncDatabase
    @Published public var config: SyncConfiguration

    @Published public var selectedSourceType: MediaSourceType = .icloudPhotos
    @Published public var state: SyncState = .idle
    @Published public var progress: SyncProgress = SyncProgress()
    @Published public var availableIPhones: [ConnectedIPhone] = []
    @Published public var selectedIPhoneId: String? = nil
    @Published public var availableAndroidDevices: [AndroidDevice] = []
    @Published public var selectedPixelSerial: String? = nil
    @Published public var pixelStorage: StorageInfo? = nil
    @Published public var allDiscoveredMedia: [MediaItem] = []
    @Published public var pendingQueue: [MediaItem] = []
    @Published public var syncedInSession: [MediaItem] = []
    @Published public var triageQueue: [MediaItem] = []
    @Published public var markedForICloudDeletion: [MediaItem] = []
    @Published public var markedToKeepInICloud: [MediaItem] = []
    @Published public var totalICloudBytesFreed: Int64 = 0
    @Published public var lastErrorMessage: String? = nil
    @Published public var isCatalogComplete: Bool = false
    @Published public var skippedFailedItems: [MediaItem] = []
    @Published public var skippedItems: [SkippedItem] = []
    @Published public var autoRetrySkippedAtEnd: Bool = true

    public var connectedIPhone: ConnectedIPhone? {
        if let id = selectedIPhoneId {
            return availableIPhones.first(where: { $0.id == id }) ?? availableIPhones.first
        }
        return availableIPhones.first
    }

    public var connectedPixel: AndroidDevice? {
        if let serial = selectedPixelSerial {
            return availableAndroidDevices.first(where: { $0.serial == serial }) ?? availableAndroidDevices.first
        }
        return availableAndroidDevices.first(where: { $0.isAuthorized }) ?? availableAndroidDevices.first
    }

    private var isCancelled = false
    private var timer: Timer?

    public init(
        customADBPath: String? = nil,
        customDBPath: String? = nil,
        config: SyncConfiguration = SyncConfiguration()
    ) {
        self.config = config
        self.imageCaptureManager = ImageCaptureManager()
        self.photoKitManager = PhotoKitSourceManager()
        self.adbClient = ADBClient(customPath: customADBPath ?? config.customADBPath)
        self.database = SyncDatabase(customPath: customDBPath)

        setupBindings()
    }

    private func setupBindings() {
        imageCaptureManager.onDeviceListChanged = { [weak self] phones in
            DispatchQueue.main.async {
                self?.availableIPhones = phones
                if self?.selectedIPhoneId == nil || !phones.contains(where: { $0.id == self?.selectedIPhoneId }) {
                    self?.selectedIPhoneId = phones.first?.id
                }
            }
        }

        imageCaptureManager.onMediaItemsLoaded = { [weak self] items in
            guard let self = self, self.selectedSourceType == .usbIPhone else { return }
            DispatchQueue.main.async {
                self.allDiscoveredMedia = items
            }
        }

        imageCaptureManager.onCatalogCompleted = { [weak self] in
            guard let self = self, self.selectedSourceType == .usbIPhone else { return }
            DispatchQueue.main.async {
                self.isCatalogComplete = true
                self.recalculatePendingQueue()
            }
        }

        photoKitManager.onMediaItemsLoaded = { [weak self] items in
            guard let self = self, self.selectedSourceType == .icloudPhotos else { return }
            DispatchQueue.main.async {
                self.allDiscoveredMedia = items
            }
        }

        photoKitManager.onCatalogCompleted = { [weak self] in
            guard let self = self, self.selectedSourceType == .icloudPhotos else { return }
            DispatchQueue.main.async {
                self.isCatalogComplete = true
                self.recalculatePendingQueue()
            }
        }
    }

    public func selectSourceType(_ type: MediaSourceType) {
        selectedSourceType = type
        isCatalogComplete = false
        allDiscoveredMedia.removeAll()
        pendingQueue.removeAll()

        switch type {
        case .usbIPhone:
            photoKitManager.stopCataloging()
            allDiscoveredMedia = imageCaptureManager.discoveredMediaItems
            isCatalogComplete = imageCaptureManager.isCatalogComplete
            recalculatePendingQueue()
        case .icloudPhotos:
            photoKitManager.updateAuthorizationStatus()
            photoKitManager.startCataloging()
        }
    }

    public func refreshIPhone() {
        isCatalogComplete = false
        if selectedSourceType == .usbIPhone {
            imageCaptureManager.refreshActiveCamera()
        } else {
            photoKitManager.startCataloging()
        }
    }

    public func waitForMedia(timeout: TimeInterval = 10.0) async -> Bool {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if let phone = connectedIPhone, !phone.isLocked {
                if isCatalogComplete && !allDiscoveredMedia.isEmpty {
                    return true
                }
                if !allDiscoveredMedia.isEmpty && Date().timeIntervalSince(start) >= 2.5 {
                    return true
                }
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return !allDiscoveredMedia.isEmpty
    }

    public func selectSourceIPhone(id: String) {
        selectedIPhoneId = id
        imageCaptureManager.selectCamera(id: id)
    }

    public func selectTargetPixel(serial: String) {
        selectedPixelSerial = serial
        Task {
            if let storage = try? await adbClient.getStorage(serial: serial) {
                await MainActor.run {
                    self.pixelStorage = storage
                }
            }
        }
    }

    public func startMonitoring() {
        imageCaptureManager.startBrowsing()
        photoKitManager.updateAuthorizationStatus()
        if selectedSourceType == .icloudPhotos {
            photoKitManager.startCataloging()
        }
        pollADB()
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.pollADB()
        }
    }

    public func stopMonitoring() {
        imageCaptureManager.stopBrowsing()
        photoKitManager.stopCataloging()
        timer?.invalidate()
        timer = nil
    }

    public func pollADB() {
        Task {
            do {
                let devices = try await adbClient.listDevices()
                var currentSerial = self.selectedPixelSerial
                if currentSerial == nil || !devices.contains(where: { $0.serial == currentSerial }) {
                    currentSerial = devices.first(where: { $0.isAuthorized })?.serial ?? devices.first?.serial
                }

                var storage: StorageInfo? = nil
                if let serial = currentSerial {
                    storage = try? await adbClient.getStorage(serial: serial)
                }

                let finalDevices = devices
                let finalSerial = currentSerial
                let finalStorage = storage
                await MainActor.run {
                    self.availableAndroidDevices = finalDevices
                    if self.selectedPixelSerial == nil {
                        self.selectedPixelSerial = finalSerial
                    }
                    self.pixelStorage = finalStorage
                }
            } catch {
                // Background poll failure is normal when no devices are connected
            }
        }
    }

    public func recalculatePendingQueue() {
        let syncedSet = database.getAllSyncedFingerprints()
        var pending: [MediaItem] = []

        for item in allDiscoveredMedia {
            if syncedSet.contains(item.fingerprint) {
                continue
            }
            if !config.includeScreenshots && (item.mediaType == .screenshot || item.mediaType == .screenRecording) {
                continue
            }
            if !config.includeVideos && item.mediaType == .video {
                continue
            }
            pending.append(item)
        }

        self.pendingQueue = pending
    }

    public func cancelSync() {
        isCancelled = true
        state = .cancelled
    }

    public func startSync() async throws {
        guard let pixel = connectedPixel, pixel.isAuthorized else {
            throw ADBError.deviceNotFound
        }

        if selectedSourceType == .usbIPhone {
            guard connectedIPhone != nil else {
                throw NSError(
                    domain: "PixOS.Sync",
                    code: 404,
                    userInfo: [NSLocalizedDescriptionKey: "No iPhone connected via USB. Please unlock phone and trust computer."]
                )
            }
        } else {
            if photoKitManager.authorizationStatus != .authorized && photoKitManager.authorizationStatus != .limited {
                let granted = await photoKitManager.requestAuthorization()
                guard granted else {
                    throw PhotoKitError.notAuthorized
                }
            }
        }

        isCancelled = false
        state = .syncing
        lastErrorMessage = nil
        recalculatePendingQueue()

        let itemsToSync = pendingQueue
        guard !itemsToSync.isEmpty else {
            state = .completed
            return
        }

        let stagingDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".pixos/staging", isDirectory: true)
        try? FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)

        let targetDir = config.targetPixelPath
        try await adbClient.createDirectory(remotePath: targetDir, serial: pixel.serial)

        let totalBytes = itemsToSync.reduce(0) { $0 + $1.fileSize }
        await MainActor.run {
            self.progress = SyncProgress(
                currentItem: "",
                currentItemIndex: 0,
                totalItems: itemsToSync.count,
                bytesTransferred: 0,
                totalBytes: totalBytes,
                currentBatchIndex: 1,
                totalBatches: 1,
                speedBytesPerSecond: 0,
                statusDescription: "Initializing sync pipeline..."
            )
        }

        // Partition into batches based on batchSizeLimitBytes
        var batches: [[MediaItem]] = []
        if config.batchSizeLimitBytes == SyncConfiguration.unlimitedBatchSize {
            batches = [itemsToSync]
        } else {
            var currentBatch: [MediaItem] = []
            var currentBatchSize: Int64 = 0

            for item in itemsToSync {
                currentBatch.append(item)
                currentBatchSize += item.fileSize
                if currentBatchSize >= config.batchSizeLimitBytes {
                    batches.append(currentBatch)
                    currentBatch = []
                    currentBatchSize = 0
                }
            }
            if !currentBatch.isEmpty {
                batches.append(currentBatch)
            }
        }

        let totalBatches = batches.count
        await MainActor.run {
            self.progress.totalBatches = totalBatches
        }

        var overallTransferredBytes: Int64 = 0
        var itemCounter = 0
        var recentTransfers: [(date: Date, bytes: Int64)] = []
        let concurrency = max(1, config.concurrentStreams)
        var prefetchTasks: [String: Task<(primaryURL: URL, companionVideoURL: URL?), Error>] = [:]

        func spawnPrefetch(for itm: MediaItem) {
            guard selectedSourceType == .icloudPhotos else { return }
            let id = itm.id
            guard prefetchTasks[id] == nil else { return }
            let timeout: TimeInterval = itm.isVideo ? 300.0 : 120.0
            prefetchTasks[id] = Task.detached(priority: .userInitiated) { [weak self] in
                guard let self = self else { throw PhotoKitError.resourceNotFound }
                return try await self.photoKitManager.downloadAssetWithRetry(id: id, to: stagingDir, timeout: timeout, maxRetries: 3)
            }
        }

        for (bIndex, batch) in batches.enumerated() {
            if isCancelled { break }

            let currentBatchNum = bIndex + 1
            await MainActor.run {
                self.progress.currentBatchIndex = currentBatchNum
            }

            // Check Pixel free storage before starting batch
            let storage = try await adbClient.getStorage(serial: pixel.serial)
            let updatedStorage = storage
            await MainActor.run { self.pixelStorage = updatedStorage }

            let batchBytes = batch.reduce(0) { $0 + $1.fileSize }
            let isUnlimited = (config.batchSizeLimitBytes == SyncConfiguration.unlimitedBatchSize)
            let storageCheckFailed = isUnlimited 
                ? (storage.freeBytes < 500 * 1024 * 1024)
                : (storage.freeBytes < (batchBytes + config.safeFreeStorageThresholdBytes))

            if storageCheckFailed {
                await MainActor.run {
                    self.state = .pausedForStorage
                    self.progress.isPausedForStorage = true
                    self.progress.statusDescription = "Paused: Pixel storage critical. Free up space on Pixel Google Photos to continue."
                }
                return
            }

            // Prime the concurrent prefetch queue for the batch
            if selectedSourceType == .icloudPhotos {
                for itm in batch.prefix(concurrency) {
                    spawnPrefetch(for: itm)
                }
            }

            // Process each item in batch
            for (idx, item) in batch.enumerated() {
                if isCancelled { break }
                itemCounter += 1

                // Stream ahead: start prefetching the next item concurrently from iCloud
                if selectedSourceType == .icloudPhotos && idx + concurrency < batch.count {
                    spawnPrefetch(for: batch[idx + concurrency])
                }

                // Check Mac available disk space to protect user's SSD
                let macFree = PhotoKitSourceManager.getMacFreeDiskBytes()
                if macFree < 2 * 1024 * 1024 * 1024 { // Under 2GB free on Mac
                    PhotoKitSourceManager.cleanStagingDirectory()
                    if PhotoKitSourceManager.getMacFreeDiskBytes() < 1 * 1024 * 1024 * 1024 {
                        await MainActor.run {
                            self.state = .pausedForStorage
                            self.progress.isPausedForStorage = true
                            self.progress.statusDescription = "Paused: Mac internal storage critically low (<1 GB free). Free space to resume."
                        }
                        return
                    }
                }

                let currentItemNum = itemCounter
                let currentItemName = item.filename
                await MainActor.run {
                    self.progress.currentItem = currentItemName
                    self.progress.currentItemIndex = currentItemNum
                    self.progress.statusDescription = "Staging \(currentItemName)..."
                }

                do {
                    // Download primary file and companion video to staging
                    var stagedPrimaryURL: URL
                    var stagedVideoURL: URL? = nil
                    var isMotionPhoto = false

                    if selectedSourceType == .icloudPhotos {
                        let timeout: TimeInterval = item.isVideo ? 300.0 : 120.0
                        let task = prefetchTasks.removeValue(forKey: item.id) ?? Task.detached(priority: .userInitiated) { [weak self] in
                            guard let self = self else { throw PhotoKitError.resourceNotFound }
                            return try await self.photoKitManager.downloadAssetWithRetry(id: item.id, to: stagingDir, timeout: timeout, maxRetries: 3)
                        }

                        let res = try await task.value
                        stagedPrimaryURL = res.primaryURL
                        stagedVideoURL = res.companionVideoURL
                    } else {
                        stagedPrimaryURL = try await imageCaptureManager.downloadFile(named: item.filename, to: stagingDir)
                        if item.isLivePhoto && config.combineLivePhotos, let companionName = item.companionVideoName {
                            stagedVideoURL = try? await imageCaptureManager.downloadFile(named: companionName, to: stagingDir)
                        }
                    }

                    var fileToPush = stagedPrimaryURL

                    // Handle Live Photo combination
                    if item.isLivePhoto && config.combineLivePhotos, let companionURL = stagedVideoURL {
                        await MainActor.run {
                            self.progress.statusDescription = "Packaging Live Photo for \(item.filename)..."
                        }
                        let motionURL = stagingDir.appendingPathComponent("MOTION_\(item.filename)")
                        if (try? MotionPhotoBuilder.buildMotionPhoto(imageURL: stagedPrimaryURL, videoURL: companionURL, outputURL: motionURL)) != nil {
                            fileToPush = motionURL
                            isMotionPhoto = true
                            try? FileManager.default.removeItem(at: companionURL)
                        } else {
                            // If motion builder fails, also push companion video side-by-side
                            let companionRemoteName = companionURL.lastPathComponent
                            let companionRemotePath = "\(targetDir)/\(companionRemoteName)"
                            try await adbClient.push(localURL: companionURL, remotePath: companionRemotePath, serial: pixel.serial)
                            if let creationDate = item.creationDate {
                                await adbClient.setRemoteTimestamp(remotePath: companionRemotePath, date: creationDate, serial: pixel.serial)
                            }
                            Task.detached { [adb = self.adbClient, serial = pixel.serial] in
                                try? await adb.triggerMediaScan(remotePath: companionRemotePath, serial: serial)
                            }
                            try? FileManager.default.removeItem(at: companionURL)
                        }
                    }

                    // Push to Pixel
                    await MainActor.run {
                        self.progress.statusDescription = "Transferring \(item.filename) to Pixel..."
                    }

                    let remoteDest = "\(targetDir)/\(item.filename)"
                    try await adbClient.push(localURL: fileToPush, remotePath: remoteDest, serial: pixel.serial)

                    // Preserve original creation timestamp on Android filesystem so Google Photos sorts perfectly
                    if let creationDate = item.creationDate {
                        await adbClient.setRemoteTimestamp(remotePath: remoteDest, date: creationDate, serial: pixel.serial)
                    }

                    // Trigger Android MediaScanner asynchronously to avoid blocking the transfer pipeline
                    Task.detached { [adb = self.adbClient, serial = pixel.serial] in
                        try? await adb.triggerMediaScan(remotePath: remoteDest, serial: serial)
                    }

                    // Record into database
                    database.recordSynced(
                        fingerprint: item.fingerprint,
                        filename: item.filename,
                        fileSize: item.fileSize,
                        mediaType: item.mediaType.rawValue,
                        creationDate: item.creationDate,
                        pixelPath: remoteDest,
                        isMotionPhoto: isMotionPhoto
                    )

                    // Clean up Mac staging copy immediately to keep disk footprint minimal
                    let isolatedFolder = stagedPrimaryURL.deletingLastPathComponent()
                    if isolatedFolder != stagingDir && isolatedFolder.lastPathComponent.hasPrefix("asset_") {
                        try? FileManager.default.removeItem(at: isolatedFolder)
                    } else {
                        try? FileManager.default.removeItem(at: stagedPrimaryURL)
                        if fileToPush != stagedPrimaryURL {
                            try? FileManager.default.removeItem(at: fileToPush)
                        }
                        if let companion = stagedVideoURL {
                            try? FileManager.default.removeItem(at: companion)
                        }
                    }

                    overallTransferredBytes += item.fileSize

                    // Calculate rolling 15-second speed and dynamic ETA
                    let now = Date()
                    recentTransfers.append((date: now, bytes: item.fileSize))
                    let cutoff = now.addingTimeInterval(-15.0)
                    recentTransfers.removeAll(where: { $0.date < cutoff })

                    let recentBytes = recentTransfers.reduce(0) { $0 + $1.bytes }
                    let windowDuration = max(1.0, now.timeIntervalSince(recentTransfers.first?.date ?? now))
                    let rollingSpeed = Double(recentBytes) / windowDuration
                    let remainingBytes = max(0, totalBytes - overallTransferredBytes)
                    let eta = rollingSpeed > 1024 ? Double(remainingBytes) / rollingSpeed : nil

                    let bytesDone = overallTransferredBytes
                    let currentItem = item
                    await MainActor.run {
                        self.progress.bytesTransferred = bytesDone
                        self.progress.speedBytesPerSecond = rollingSpeed
                        self.progress.estimatedTimeRemainingSeconds = eta
                        self.syncedInSession.append(currentItem)
                        if !self.triageQueue.contains(where: { $0.id == currentItem.id }) {
                            self.triageQueue.append(currentItem)
                        }
                    }
                } catch {
                    // Item error isolation: record to skippedItems, clean staging, and continue seamlessly
                    print("⚠️ Skipped item \(item.filename) due to error: \(error.localizedDescription)")
                    let failedItem = item
                    let reason = error.localizedDescription
                    await MainActor.run {
                        let skipped = SkippedItem(id: failedItem.id, item: failedItem, reason: reason)
                        self.skippedItems.append(skipped)
                        self.skippedFailedItems.append(failedItem)
                        self.lastErrorMessage = "Skipped \(failedItem.filename): \(reason)"
                    }
                    let cleanId = item.id.prefix(12).replacingOccurrences(of: "/", with: "_")
                    if let subdirs = try? FileManager.default.contentsOfDirectory(at: stagingDir, includingPropertiesForKeys: nil) {
                        for sub in subdirs where sub.lastPathComponent.contains(cleanId) {
                            try? FileManager.default.removeItem(at: sub)
                        }
                    }
                    continue
                }
            }
        }

        // Auto-retry pass for skipped items if enabled and sync was not cancelled
        if autoRetrySkippedAtEnd && !skippedItems.isEmpty && !isCancelled {
            let retryItems = skippedItems.map { $0.item }
            await MainActor.run {
                self.progress.statusDescription = "Auto-retrying \(retryItems.count) skipped items..."
                self.skippedItems.removeAll()
                self.skippedFailedItems.removeAll()
            }

            for item in retryItems {
                if isCancelled { break }
                do {
                    var stagedPrimaryURL: URL
                    var stagedVideoURL: URL? = nil
                    var isMotionPhoto = false

                    if selectedSourceType == .icloudPhotos {
                        let timeout: TimeInterval = item.isVideo ? 300.0 : 120.0
                        let res = try await self.photoKitManager.downloadAssetWithRetry(id: item.id, to: stagingDir, timeout: timeout, maxRetries: 3)
                        stagedPrimaryURL = res.primaryURL
                        stagedVideoURL = res.companionVideoURL
                    } else {
                        stagedPrimaryURL = try await imageCaptureManager.downloadFile(named: item.filename, to: stagingDir)
                        if item.isLivePhoto && config.combineLivePhotos, let companionName = item.companionVideoName {
                            stagedVideoURL = try? await imageCaptureManager.downloadFile(named: companionName, to: stagingDir)
                        }
                    }

                    var fileToPush = stagedPrimaryURL
                    if item.isLivePhoto && config.combineLivePhotos, let companionURL = stagedVideoURL {
                        let motionURL = stagingDir.appendingPathComponent("MOTION_\(item.filename)")
                        if (try? MotionPhotoBuilder.buildMotionPhoto(imageURL: stagedPrimaryURL, videoURL: companionURL, outputURL: motionURL)) != nil {
                            fileToPush = motionURL
                            isMotionPhoto = true
                            try? FileManager.default.removeItem(at: companionURL)
                        } else {
                            let companionRemoteName = companionURL.lastPathComponent
                            let companionRemotePath = "\(targetDir)/\(companionRemoteName)"
                            try await adbClient.push(localURL: companionURL, remotePath: companionRemotePath, serial: pixel.serial)
                            if let creationDate = item.creationDate {
                                await adbClient.setRemoteTimestamp(remotePath: companionRemotePath, date: creationDate, serial: pixel.serial)
                            }
                            Task.detached { [adb = self.adbClient, serial = pixel.serial] in
                                try? await adb.triggerMediaScan(remotePath: companionRemotePath, serial: serial)
                            }
                            try? FileManager.default.removeItem(at: companionURL)
                        }
                    }

                    let remoteDest = "\(targetDir)/\(item.filename)"
                    try await adbClient.push(localURL: fileToPush, remotePath: remoteDest, serial: pixel.serial)
                    if let creationDate = item.creationDate {
                        await adbClient.setRemoteTimestamp(remotePath: remoteDest, date: creationDate, serial: pixel.serial)
                    }
                    Task.detached { [adb = self.adbClient, serial = pixel.serial] in
                        try? await adb.triggerMediaScan(remotePath: remoteDest, serial: serial)
                    }

                    database.recordSynced(
                        fingerprint: item.fingerprint,
                        filename: item.filename,
                        fileSize: item.fileSize,
                        mediaType: item.mediaType.rawValue,
                        creationDate: item.creationDate,
                        pixelPath: remoteDest,
                        isMotionPhoto: isMotionPhoto
                    )

                    let isolatedFolder = stagedPrimaryURL.deletingLastPathComponent()
                    if isolatedFolder != stagingDir && isolatedFolder.lastPathComponent.hasPrefix("asset_") {
                        try? FileManager.default.removeItem(at: isolatedFolder)
                    } else {
                        try? FileManager.default.removeItem(at: stagedPrimaryURL)
                    }

                    let currentItem = item
                    await MainActor.run {
                        self.syncedInSession.append(currentItem)
                        if !self.triageQueue.contains(where: { $0.id == currentItem.id }) {
                            self.triageQueue.append(currentItem)
                        }
                    }
                } catch {
                    let failedItem = item
                    let reason = error.localizedDescription
                    await MainActor.run {
                        let skipped = SkippedItem(id: failedItem.id, item: failedItem, reason: reason)
                        self.skippedItems.append(skipped)
                        self.skippedFailedItems.append(failedItem)
                    }
                }
            }
        }

        await MainActor.run {
            self.recalculatePendingQueue()
            self.state = isCancelled ? .cancelled : .completed
            self.progress.statusDescription = isCancelled ? "Sync cancelled." : "All media successfully transferred!"
        }
    }

    public func deleteSessionItemsFromiPhone() async throws {
        guard selectedSourceType == .usbIPhone else {
            // Protect cloud library from accidental deletion
            await MainActor.run {
                self.syncedInSession.removeAll()
            }
            return
        }
        let filenames = syncedInSession.map { $0.filename }
        try await imageCaptureManager.deleteFiles(named: filenames)
        for item in syncedInSession {
            database.markDeletedFromiPhone(fingerprint: item.fingerprint)
        }
        await MainActor.run {
            self.syncedInSession.removeAll()
        }
    }

    // MARK: - iCloud Swipe Triage & Cleanup

    public func populateTriageQueue() {
        let syncedSet = database.getAllSyncedFingerprints()
        if !syncedInSession.isEmpty {
            triageQueue = syncedInSession.filter { item in
                !markedForICloudDeletion.contains(where: { $0.id == item.id }) &&
                !markedToKeepInICloud.contains(where: { $0.id == item.id })
            }
        } else {
            triageQueue = allDiscoveredMedia.filter { item in
                syncedSet.contains(item.fingerprint) &&
                !markedForICloudDeletion.contains(where: { $0.id == item.id }) &&
                !markedToKeepInICloud.contains(where: { $0.id == item.id })
            }
        }
    }

    public func swipeKeep(item: MediaItem) {
        triageQueue.removeAll(where: { $0.id == item.id })
        markedToKeepInICloud.append(item)
    }

    public func swipeDelete(item: MediaItem) {
        triageQueue.removeAll(where: { $0.id == item.id })
        markedForICloudDeletion.append(item)
        totalICloudBytesFreed += item.fileSize
    }

    public func undoLastSwipe() {
        if let lastDeleted = markedForICloudDeletion.popLast() {
            triageQueue.insert(lastDeleted, at: 0)
            totalICloudBytesFreed = max(0, totalICloudBytesFreed - lastDeleted.fileSize)
        } else if let lastKept = markedToKeepInICloud.popLast() {
            triageQueue.insert(lastKept, at: 0)
        }
    }

    public func markAllSyncedForDeletion() {
        for item in triageQueue {
            markedForICloudDeletion.append(item)
            totalICloudBytesFreed += item.fileSize
        }
        triageQueue.removeAll()
    }

    public func purgeMarkedICloudAssets() async throws -> Int {
        let count = markedForICloudDeletion.count
        guard count > 0 else { return 0 }
        let ids = markedForICloudDeletion.map { $0.id }
        try await photoKitManager.deleteAssets(ids: ids)
        await MainActor.run {
            self.allDiscoveredMedia.removeAll(where: { item in ids.contains(item.id) })
            self.markedForICloudDeletion.removeAll()
            self.recalculatePendingQueue()
        }
        return count
    }

    public func resetSyncDatabase() {
        database.clearAll()
        recalculatePendingQueue()
    }

    public func retryFailedItems() {
        guard !skippedItems.isEmpty || !skippedFailedItems.isEmpty else { return }
        let toRetry = !skippedItems.isEmpty ? skippedItems.map { $0.item } : skippedFailedItems
        skippedItems.removeAll()
        skippedFailedItems.removeAll()
        pendingQueue = toRetry + pendingQueue
    }

    public func clearSkippedItems() {
        skippedItems.removeAll()
        skippedFailedItems.removeAll()
    }

    public func exportSkippedReport() -> String {
        var report = "# PixOS Skipped Items Report\n"
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .medium
        report += "Generated: \(df.string(from: Date()))\n"
        report += "Total Skipped: \(skippedItems.count)\n\n"
        report += "| Filename | Size | Failure Reason |\n"
        report += "| --- | --- | --- |\n"
        for item in skippedItems {
            let sizeStr = ByteCountFormatter.string(fromByteCount: item.item.fileSize, countStyle: .file)
            report += "| \(item.item.filename) | \(sizeStr) | \(item.reason) |\n"
        }
        return report
    }
}
