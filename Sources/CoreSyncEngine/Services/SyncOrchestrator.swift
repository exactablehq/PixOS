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
    public let adbClient: ADBClient
    public let database: SyncDatabase
    @Published public var config: SyncConfiguration

    @Published public var state: SyncState = .idle
    @Published public var progress: SyncProgress = SyncProgress()
    @Published public var connectedIPhone: ConnectedIPhone? = nil
    @Published public var connectedPixel: AndroidDevice? = nil
    @Published public var pixelStorage: StorageInfo? = nil
    @Published public var allDiscoveredMedia: [MediaItem] = []
    @Published public var pendingQueue: [MediaItem] = []
    @Published public var syncedInSession: [MediaItem] = []
    @Published public var lastErrorMessage: String? = nil

    private var isCancelled = false
    private var timer: Timer?

    public init(
        customADBPath: String? = nil,
        customDBPath: String? = nil,
        config: SyncConfiguration = SyncConfiguration()
    ) {
        self.config = config
        self.imageCaptureManager = ImageCaptureManager()
        self.adbClient = ADBClient(customPath: customADBPath ?? config.customADBPath)
        self.database = SyncDatabase(customPath: customDBPath)

        setupBindings()
    }

    private func setupBindings() {
        imageCaptureManager.onDeviceListChanged = { [weak self] phones in
            DispatchQueue.main.async {
                self?.connectedIPhone = phones.first
            }
        }

        imageCaptureManager.onMediaItemsLoaded = { [weak self] items in
            DispatchQueue.main.async {
                self?.allDiscoveredMedia = items
                self?.recalculatePendingQueue()
            }
        }
    }

    public func startMonitoring() {
        imageCaptureManager.startBrowsing()
        pollADB()
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.pollADB()
        }
    }

    public func stopMonitoring() {
        imageCaptureManager.stopBrowsing()
        timer?.invalidate()
        timer = nil
    }

    public func pollADB() {
        Task {
            do {
                let devices = try await adbClient.listDevices()
                let pixel = devices.first(where: { $0.isAuthorized }) ?? devices.first
                var storage: StorageInfo? = nil
                if let serial = pixel?.serial, pixel?.isAuthorized == true {
                    storage = try? await adbClient.getStorage(serial: serial)
                }
                let finalPixel = pixel
                let finalStorage = storage
                await MainActor.run {
                    self.connectedPixel = finalPixel
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
        guard connectedIPhone != nil else {
            throw NSError(
                domain: "PixOS.Sync",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "No iPhone connected via USB. Please unlock phone and trust computer."]
            )
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
        let startTime = Date()

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

            // Process each item in batch
            for item in batch {
                if isCancelled { break }
                itemCounter += 1

                let currentItemNum = itemCounter
                let currentItemName = item.filename
                await MainActor.run {
                    self.progress.currentItem = currentItemName
                    self.progress.currentItemIndex = currentItemNum
                    self.progress.statusDescription = "Staging \(currentItemName)..."
                }

                // Download primary file to staging
                let stagedPrimaryURL = try await imageCaptureManager.downloadFile(named: item.filename, to: stagingDir)
                var fileToPush = stagedPrimaryURL
                var isMotionPhoto = false

                // Handle Live Photo combination
                if item.isLivePhoto && config.combineLivePhotos, let companionName = item.companionVideoName {
                    await MainActor.run {
                        self.progress.statusDescription = "Packaging Live Photo for \(item.filename)..."
                    }
                    if let stagedVideoURL = try? await imageCaptureManager.downloadFile(named: companionName, to: stagingDir) {
                        let motionURL = stagingDir.appendingPathComponent("MOTION_\(item.filename)")
                        if (try? MotionPhotoBuilder.buildMotionPhoto(imageURL: stagedPrimaryURL, videoURL: stagedVideoURL, outputURL: motionURL)) != nil {
                            fileToPush = motionURL
                            isMotionPhoto = true
                            try? FileManager.default.removeItem(at: stagedVideoURL)
                        } else {
                            // If motion builder fails, also push companion video side-by-side
                            try await adbClient.push(localURL: stagedVideoURL, remotePath: "\(targetDir)/\(companionName)", serial: pixel.serial)
                            try? await adbClient.triggerMediaScan(remotePath: "\(targetDir)/\(companionName)", serial: pixel.serial)
                            try? FileManager.default.removeItem(at: stagedVideoURL)
                        }
                    }
                }

                // Push to Pixel
                await MainActor.run {
                    self.progress.statusDescription = "Transferring \(item.filename) to Pixel..."
                }

                let remoteDest = "\(targetDir)/\(item.filename)"
                try await adbClient.push(localURL: fileToPush, remotePath: remoteDest, serial: pixel.serial)

                // Trigger Android MediaScanner
                try await adbClient.triggerMediaScan(remotePath: remoteDest, serial: pixel.serial)

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

                // Clean up Mac staging copy
                try? FileManager.default.removeItem(at: stagedPrimaryURL)
                if fileToPush != stagedPrimaryURL {
                    try? FileManager.default.removeItem(at: fileToPush)
                }

                overallTransferredBytes += item.fileSize
                let elapsed = Date().timeIntervalSince(startTime)
                let speed = elapsed > 0 ? Double(overallTransferredBytes) / elapsed : 0

                let bytesDone = overallTransferredBytes
                let currentItem = item
                await MainActor.run {
                    self.progress.bytesTransferred = bytesDone
                    self.progress.speedBytesPerSecond = speed
                    self.syncedInSession.append(currentItem)
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
        let filenames = syncedInSession.map { $0.filename }
        try await imageCaptureManager.deleteFiles(named: filenames)
        for item in syncedInSession {
            database.markDeletedFromiPhone(fingerprint: item.fingerprint)
        }
        await MainActor.run {
            self.syncedInSession.removeAll()
        }
    }
}
