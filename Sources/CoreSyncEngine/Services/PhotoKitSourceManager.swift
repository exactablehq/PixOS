import Foundation
import Photos
import AppKit

public enum PhotoKitError: LocalizedError, Sendable {
    case notAuthorized
    case assetNotFound
    case resourceNotFound
    case writeFailed(String)
    case downloadTimedOut

    public var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Photos Library access not granted. Please allow PixOS access in System Settings > Privacy & Security > Photos."
        case .assetNotFound:
            return "Asset not found in Photos library."
        case .resourceNotFound:
            return "Could not find valid photo or video resource for asset."
        case .writeFailed(let message):
            return "Failed to download asset from iCloud/Photos: \(message)"
        case .downloadTimedOut:
            return "iCloud download timed out (exceeded 60s without response from Apple servers)."
        }
    }
}

public final class PhotoKitSourceManager: NSObject, ObservableObject, PHPhotoLibraryChangeObserver, @unchecked Sendable {
    @Published public var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @Published public var isCatalogComplete: Bool = false
    @Published public var totalAssetCount: Int = 0
    @Published public var catalogedMediaItems: [MediaItem] = []

    public var onMediaItemsLoaded: (([MediaItem]) -> Void)?
    public var onCatalogCompleted: (() -> Void)?

    private var catalogTask: Task<Void, Never>?
    private var isRegisteredObserver: Bool = false
    private var isCatalogingInProgress: Bool = false
    private var hasPendingChange: Bool = false
    private var debounceTimer: DispatchWorkItem?

    public override init() {
        super.init()
        self.authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if self.authorizationStatus == .authorized || self.authorizationStatus == .limited {
            PHPhotoLibrary.shared().register(self)
            self.isRegisteredObserver = true
        }
    }

    deinit {
        debounceTimer?.cancel()
        if isRegisteredObserver {
            PHPhotoLibrary.shared().unregisterChangeObserver(self)
        }
    }

    public func photoLibraryDidChange(_ changeInstance: PHChange) {
        // Automatically re-index when iCloud Photos syncs new assets into the system library,
        // debounced to prevent rapid background iCloud sync commit storms from restarting scans.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.debounceTimer?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                if self.isCatalogingInProgress {
                    self.hasPendingChange = true
                } else {
                    self.startCataloging()
                }
            }
            self.debounceTimer = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: workItem)
        }
    }

    public func updateAuthorizationStatus() {
        self.authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if (self.authorizationStatus == .authorized || self.authorizationStatus == .limited) && !isRegisteredObserver {
            PHPhotoLibrary.shared().register(self)
            self.isRegisteredObserver = true
        }
    }

    public func requestAuthorization() async -> Bool {
        let status = await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                continuation.resume(returning: newStatus)
            }
        }
        await MainActor.run {
            self.authorizationStatus = status
            if (status == .authorized || status == .limited) && !self.isRegisteredObserver {
                PHPhotoLibrary.shared().register(self)
                self.isRegisteredObserver = true
            }
        }
        return status == .authorized || status == .limited
    }

    public func openMacPhotos() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Photos.app"))
    }

    public func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos") {
            NSWorkspace.shared.open(url)
        }
    }

    public func startCataloging() {
        if isCatalogingInProgress {
            hasPendingChange = true
            return
        }
        isCatalogingInProgress = true
        hasPendingChange = false

        catalogTask = Task.detached(priority: .userInitiated) { [weak self] in
            await self?.catalogLibrary()
        }
    }

    public func stopCataloging() {
        debounceTimer?.cancel()
        catalogTask?.cancel()
        catalogTask = nil
        isCatalogingInProgress = false
        hasPendingChange = false
    }

    private func catalogLibrary() async {
        await MainActor.run {
            self.isCatalogComplete = false
            // Note: Keep existing catalogedMediaItems in place to prevent UI flickering or reset to 0
        }

        var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            status = await withCheckedContinuation { continuation in
                PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                    continuation.resume(returning: newStatus)
                }
            }
            let updatedStatus = status
            await MainActor.run {
                self.authorizationStatus = updatedStatus
                if (updatedStatus == .authorized || updatedStatus == .limited) && !self.isRegisteredObserver {
                    PHPhotoLibrary.shared().register(self)
                    self.isRegisteredObserver = true
                }
            }
        }

        guard status == .authorized || status == .limited else {
            let finalStatus = status
            await MainActor.run {
                self.authorizationStatus = finalStatus
                self.isCatalogComplete = true
                self.isCatalogingInProgress = false
                self.onCatalogCompleted?()
            }
            return
        }

        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.includeHiddenAssets = false

        let fetchResult = PHAsset.fetchAssets(with: fetchOptions)
        let total = fetchResult.count

        await MainActor.run {
            self.totalAssetCount = total
        }

        var items: [MediaItem] = []
        items.reserveCapacity(total)
        var lastBatchDispatch = Date()

        for i in 0..<total {
            if Task.isCancelled { break }
            let asset = fetchResult.object(at: i)

            let item = makeMediaItem(from: asset)
            items.append(item)

            // Stream updates to UI in batches of 500 or every 0.5s so UI stays responsive
            if items.count % 500 == 0 || Date().timeIntervalSince(lastBatchDispatch) > 0.5 {
                let currentBatch = items
                await MainActor.run {
                    self.catalogedMediaItems = currentBatch
                    self.onMediaItemsLoaded?(currentBatch)
                }
                lastBatchDispatch = Date()
                await Task.yield()
            }
        }

        let finalItems = items
        await MainActor.run {
            self.catalogedMediaItems = finalItems
            self.isCatalogComplete = true
            self.isCatalogingInProgress = false
            self.onMediaItemsLoaded?(finalItems)
            self.onCatalogCompleted?()

            if self.hasPendingChange {
                self.hasPendingChange = false
                self.startCataloging()
            }
        }
    }

    private func makeMediaItem(from asset: PHAsset) -> MediaItem {
        let id = asset.localIdentifier
        let creationDate = asset.creationDate
        let modificationDate = asset.modificationDate

        let isLiveSubtype = asset.mediaSubtypes.contains(.photoLive)
        let isScreenshot = asset.mediaSubtypes.contains(.photoScreenshot)
        let isScreenRecording = asset.mediaSubtypes.contains(PHAssetMediaSubtype(rawValue: 1 << 19))
        let isVideo = asset.mediaType == .video

        // Fast in-memory metadata extraction without expensive IPC PHAssetResource calls
        let baseFilename = asset.value(forKey: "filename") as? String

        let mediaType: MediaType
        var companionFilename: String? = nil
        let isLive: Bool

        if isLiveSubtype {
            isLive = true
            mediaType = .livePhoto
        } else if isScreenshot {
            isLive = false
            mediaType = .screenshot
        } else if isScreenRecording {
            isLive = false
            mediaType = .screenRecording
        } else if isVideo {
            isLive = false
            mediaType = .video
        } else {
            isLive = false
            mediaType = .photo
        }

        let ext = isVideo ? "MOV" : (isLive ? "HEIC" : "JPG")
        let cleanId = id.prefix(8).replacingOccurrences(of: "/", with: "_")
        let finalFilename = baseFilename ?? "IMG_\(cleanId).\(ext)"

        if isLive {
            let base = (finalFilename as NSString).deletingPathExtension
            companionFilename = "\(base).MOV"
        }

        // Fast, deterministic file size calculation
        let totalBytes: Int64
        if isVideo {
            let durationSec = max(1.0, asset.duration)
            totalBytes = Int64(durationSec * 2_500_000) // ~2.5 MB/sec
        } else if isLive {
            let pixels = max(1, asset.pixelWidth * asset.pixelHeight)
            let photoBytes = Int64(max(1_500_000, pixels / 4))
            let videoBytes: Int64 = 3_000_000
            totalBytes = photoBytes + videoBytes
        } else {
            let pixels = max(1, asset.pixelWidth * asset.pixelHeight)
            totalBytes = Int64(max(1_500_000, pixels / 4))
        }

        return MediaItem(
            id: id,
            filename: finalFilename,
            fileSize: totalBytes,
            creationDate: creationDate,
            modificationDate: modificationDate,
            mediaType: mediaType,
            isLivePhoto: isLive,
            companionVideoName: companionFilename
        )
    }

    final class ActivityTracker: @unchecked Sendable {
        private let lock = NSLock()
        private var _lastActivity: Date = Date()

        var lastActivity: Date {
            lock.lock()
            defer { lock.unlock() }
            return _lastActivity
        }

        func recordActivity() {
            lock.lock()
            _lastActivity = Date()
            lock.unlock()
        }
    }

    /// Downloads the asset directly from iCloud / Photo Library to the local staging folder.
    /// If the item is in iCloud, `isNetworkAccessAllowed = true` triggers Apple's background iCloud streaming download.
    /// Prioritizes current adjusted/edited media if present, falling back to original camera capture.
    public func downloadAsset(
        id: String,
        to stagingDir: URL,
        timeout: TimeInterval = 120.0,
        onProgress: ((Double) -> Void)? = nil
    ) async throws -> (primaryURL: URL, companionVideoURL: URL?) {
        let tracker = ActivityTracker()

        return try await withThrowingTaskGroup(of: (URL, URL?).self) { group in
            group.addTask {
                try await self.performDownload(id: id, to: stagingDir) { progress in
                    tracker.recordActivity()
                    onProgress?(progress)
                }
            }

            // Stall Watchdog: Only times out if zero bytes / progress have arrived for `timeout` seconds
            group.addTask {
                while !Task.isCancelled {
                    try await Task.sleep(nanoseconds: 2_000_000_000) // check every 2 seconds
                    let idle = Date().timeIntervalSince(tracker.lastActivity)
                    if idle >= timeout {
                        throw PhotoKitError.downloadTimedOut
                    }
                }
                throw CancellationError()
            }

            guard let firstCompleted = try await group.next() else {
                throw PhotoKitError.downloadTimedOut
            }
            group.cancelAll()
            return firstCompleted
        }
    }

    /// Retries downloading up to maxRetries attempts with exponential backoff
    public func downloadAssetWithRetry(
        id: String,
        to stagingDir: URL,
        timeout: TimeInterval = 120.0,
        maxRetries: Int = 3,
        onProgress: ((Double) -> Void)? = nil
    ) async throws -> (primaryURL: URL, companionVideoURL: URL?) {
        var lastError: Error = PhotoKitError.resourceNotFound
        for attempt in 1...maxRetries {
            do {
                return try await downloadAsset(id: id, to: stagingDir, timeout: timeout, onProgress: onProgress)
            } catch {
                lastError = error
                if attempt < maxRetries {
                    let backoff = Double(attempt * 2)
                    try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
                }
            }
        }
        throw lastError
    }

    private func performDownload(
        id: String,
        to stagingDir: URL,
        onProgress: ((Double) -> Void)? = nil
    ) async throws -> (primaryURL: URL, companionVideoURL: URL?) {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
        guard let asset = fetch.firstObject else {
            throw PhotoKitError.assetNotFound
        }

        let resources = PHAssetResource.assetResources(for: asset)
        guard !resources.isEmpty else {
            throw PhotoKitError.resourceNotFound
        }

        let isLive = asset.mediaSubtypes.contains(.photoLive)
        let resourceManager = PHAssetResourceManager.default()

        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true // Downloads full resolution original from iCloud
        options.progressHandler = { progress in
            onProgress?(progress)
        }

        // Create an isolated subfolder per download to prevent multi-stream filename collisions
        let cleanId = id.prefix(12).replacingOccurrences(of: "/", with: "_")
        let isolatedDir = stagingDir.appendingPathComponent("asset_\(cleanId)_\(UUID().uuidString.prefix(6))")
        try FileManager.default.createDirectory(at: isolatedDir, withIntermediateDirectories: true)

        // Determine candidate resources for primary file with graceful fallback
        var primaryCandidates: [PHAssetResource] = []
        if isLive {
            if let edited = resources.first(where: { $0.type == .fullSizePhoto }) {
                primaryCandidates.append(edited)
            }
            if let original = resources.first(where: { $0.type == .photo }) {
                primaryCandidates.append(original)
            }
        } else if asset.mediaType == .video {
            if let edited = resources.first(where: { $0.type == .fullSizeVideo }) {
                primaryCandidates.append(edited)
            }
            if let original = resources.first(where: { $0.type == .video }) {
                primaryCandidates.append(original)
            }
        } else {
            if let edited = resources.first(where: { $0.type == .fullSizePhoto }) {
                primaryCandidates.append(edited)
            }
            if let original = resources.first(where: { $0.type == .photo }) {
                primaryCandidates.append(original)
            }
        }

        if primaryCandidates.isEmpty {
            if let anyRes = resources.first {
                primaryCandidates.append(anyRes)
            } else {
                throw PhotoKitError.resourceNotFound
            }
        }

        var downloadedPrimaryURL: URL?
        var lastWriteError: Error?

        for candidate in primaryCandidates {
            let candidateFilename = candidate.originalFilename
            let destURL = isolatedDir.appendingPathComponent(candidateFilename)
            try? FileManager.default.removeItem(at: destURL)

            do {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    resourceManager.writeData(for: candidate, toFile: destURL, options: options) { error in
                        if let error = error {
                            continuation.resume(throwing: PhotoKitError.writeFailed(error.localizedDescription))
                        } else {
                            continuation.resume()
                        }
                    }
                }
                downloadedPrimaryURL = destURL
                lastWriteError = nil
                break
            } catch {
                lastWriteError = error
                try? FileManager.default.removeItem(at: destURL)
            }
        }

        guard let primaryDestURL = downloadedPrimaryURL else {
            try? FileManager.default.removeItem(at: isolatedDir)
            throw lastWriteError ?? PhotoKitError.writeFailed("All resource candidates failed to download from iCloud")
        }

        // Preserve original filesystem creation and modification dates on the staged file
        if let creationDate = asset.creationDate {
            var attrs: [FileAttributeKey: Any] = [.creationDate: creationDate]
            attrs[.modificationDate] = asset.modificationDate ?? creationDate
            try? FileManager.default.setAttributes(attrs, ofItemAtPath: primaryDestURL.path)
        }

        // Handle companion live photo video with fallback
        var companionDestURL: URL? = nil
        if isLive {
            var companionCandidates: [PHAssetResource] = []
            if let editedComp = resources.first(where: { $0.type == .fullSizePairedVideo }) {
                companionCandidates.append(editedComp)
            }
            if let origComp = resources.first(where: { $0.type == .pairedVideo }) {
                companionCandidates.append(origComp)
            }

            for compRes in companionCandidates {
                let compFilename = compRes.originalFilename
                let compURL = isolatedDir.appendingPathComponent(compFilename)
                try? FileManager.default.removeItem(at: compURL)

                let compOptions = PHAssetResourceRequestOptions()
                compOptions.isNetworkAccessAllowed = true
                compOptions.progressHandler = { progress in
                    onProgress?(progress)
                }

                do {
                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                        resourceManager.writeData(for: compRes, toFile: compURL, options: compOptions) { error in
                            if let error = error {
                                continuation.resume(throwing: PhotoKitError.writeFailed(error.localizedDescription))
                            } else {
                                continuation.resume()
                            }
                        }
                    }

                    if let creationDate = asset.creationDate {
                        var attrs: [FileAttributeKey: Any] = [.creationDate: creationDate]
                        attrs[.modificationDate] = asset.modificationDate ?? creationDate
                        try? FileManager.default.setAttributes(attrs, ofItemAtPath: compURL.path)
                    }

                    companionDestURL = compURL
                    break
                } catch {
                    try? FileManager.default.removeItem(at: compURL)
                }
            }
        }

        return (primaryDestURL, companionDestURL)
    }

    /// Fast thumbnail generation for swipe triage UI
    public func loadThumbnailImage(for id: String, targetSize: CGSize = CGSize(width: 500, height: 500)) async -> NSImage? {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
        guard let asset = fetch.firstObject else { return nil }

        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast

        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    /// Deletes assets from iCloud Photo Library.
    /// This frees up iCloud cloud storage and prompts the user with macOS's native confirmation dialog.
    public func deleteAssets(ids: [String]) async throws {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        guard fetch.count > 0 else { return }

        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(fetch)
        }
    }

    /// Returns available free bytes on Mac startup volume
    public static func getMacFreeDiskBytes() -> Int64 {
        let home = FileManager.default.homeDirectoryForCurrentUser
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: home.path),
           let freeSize = attrs[.systemFreeSize] as? NSNumber {
            return freeSize.int64Value
        }
        return 0
    }

    /// Cleans up any leftover staging files to protect Mac SSD space
    public static func cleanStagingDirectory() {
        let stagingDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".pixos/staging", isDirectory: true)
        if let items = try? FileManager.default.contentsOfDirectory(at: stagingDir, includingPropertiesForKeys: nil) {
            for item in items {
                try? FileManager.default.removeItem(at: item)
            }
        }
    }
}
