import Foundation
import Photos
import AppKit

public enum PhotoKitError: LocalizedError, Sendable {
    case notAuthorized
    case assetNotFound
    case resourceNotFound
    case writeFailed(String)

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

    public override init() {
        super.init()
        self.authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if self.authorizationStatus == .authorized || self.authorizationStatus == .limited {
            PHPhotoLibrary.shared().register(self)
            self.isRegisteredObserver = true
        }
    }

    deinit {
        if isRegisteredObserver {
            PHPhotoLibrary.shared().unregisterChangeObserver(self)
        }
    }

    public func photoLibraryDidChange(_ changeInstance: PHChange) {
        // Automatically re-index when iCloud Photos syncs new assets into the system library
        DispatchQueue.main.async { [weak self] in
            self?.startCataloging()
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
        catalogTask?.cancel()
        catalogTask = Task.detached(priority: .userInitiated) { [weak self] in
            await self?.catalogLibrary()
        }
    }

    public func stopCataloging() {
        catalogTask?.cancel()
        catalogTask = nil
    }

    private func catalogLibrary() async {
        await MainActor.run {
            self.isCatalogComplete = false
            self.catalogedMediaItems.removeAll()
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
                self.onCatalogCompleted?()
            }
            return
        }

        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.includeHiddenAssets = false
        // Fetch all media items without restrictive source-type filters

        let fetchResult = PHAsset.fetchAssets(with: fetchOptions)
        let total = fetchResult.count

        await MainActor.run {
            self.totalAssetCount = total
        }

        var items: [MediaItem] = []
        items.reserveCapacity(min(total, 5000))
        var lastBatchDispatch = Date()

        for i in 0..<total {
            if Task.isCancelled { break }
            let asset = fetchResult.object(at: i)

            let item = makeMediaItem(from: asset)
            items.append(item)

            // Stream updates to UI in batches of 200 or every 0.5s so 80,000 items don't freeze the main thread
            if items.count % 250 == 0 || Date().timeIntervalSince(lastBatchDispatch) > 0.5 {
                let currentBatch = items
                await MainActor.run {
                    self.catalogedMediaItems = currentBatch
                    self.onMediaItemsLoaded?(currentBatch)
                }
                lastBatchDispatch = Date()
                // Yield to allow UI updates and prevent saturating GCD
                await Task.yield()
            }
        }

        let finalItems = items
        await MainActor.run {
            self.catalogedMediaItems = finalItems
            self.isCatalogComplete = true
            self.onMediaItemsLoaded?(finalItems)
            self.onCatalogCompleted?()
        }
    }

    private func makeMediaItem(from asset: PHAsset) -> MediaItem {
        let id = asset.localIdentifier
        let creationDate = asset.creationDate
        let modificationDate = asset.modificationDate

        let resources = PHAssetResource.assetResources(for: asset)

        var primaryFilename: String?
        var companionFilename: String?
        var totalBytes: Int64 = 0
        var isLive = false

        let isLiveSubtype = asset.mediaSubtypes.contains(.photoLive)

        if isLiveSubtype {
            isLive = true
            let photoRes = resources.first(where: { $0.type == .photo || $0.type == .fullSizePhoto })
            let videoRes = resources.first(where: { $0.type == .pairedVideo || $0.type == .fullSizePairedVideo })

            primaryFilename = photoRes?.originalFilename
            companionFilename = videoRes?.originalFilename

            let photoSize = (photoRes?.value(forKey: "fileSize") as? NSNumber)?.int64Value ?? 0
            let videoSize = (videoRes?.value(forKey: "fileSize") as? NSNumber)?.int64Value ?? 0
            totalBytes = photoSize + videoSize
        } else if asset.mediaType == .video {
            let videoRes = resources.first(where: { $0.type == .video || $0.type == .fullSizeVideo })
            primaryFilename = videoRes?.originalFilename
            totalBytes = (videoRes?.value(forKey: "fileSize") as? NSNumber)?.int64Value ?? 0
        } else {
            let photoRes = resources.first(where: { $0.type == .photo || $0.type == .fullSizePhoto }) ?? resources.first
            primaryFilename = photoRes?.originalFilename
            totalBytes = (photoRes?.value(forKey: "fileSize") as? NSNumber)?.int64Value ?? 0
        }

        // Fallback filename if resource originalFilename is empty
        let ext: String
        if asset.mediaType == .video {
            ext = "MOV"
        } else {
            ext = "HEIC"
        }
        let cleanId = id.prefix(8).replacingOccurrences(of: "/", with: "_")
        let finalFilename = primaryFilename ?? "IMG_\(cleanId).\(ext)"

        // Fallback estimate if fileSize metadata is 0
        if totalBytes == 0 {
            if asset.mediaType == .video {
                let durationSec = max(1.0, asset.duration)
                totalBytes = Int64(durationSec * 2_500_000) // ~2.5 MB/s
            } else {
                let pixels = max(1, asset.pixelWidth * asset.pixelHeight)
                totalBytes = Int64(max(1_500_000, pixels / 4)) // ~2-4 MB estimate
            }
        }

        let mediaType: MediaType
        if isLive {
            mediaType = .livePhoto
        } else if asset.mediaSubtypes.contains(.photoScreenshot) {
            mediaType = .screenshot
        } else if asset.mediaSubtypes.contains(PHAssetMediaSubtype(rawValue: 1 << 19)) {
            mediaType = .screenRecording
        } else if asset.mediaType == .video {
            mediaType = .video
        } else {
            mediaType = .photo
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

    /// Downloads the asset directly from iCloud / Photo Library to the local staging folder.
    /// If the item is in iCloud, `isNetworkAccessAllowed = true` triggers Apple's background iCloud streaming download.
    public func downloadAsset(
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

        // Determine primary and companion resources
        let primaryResource: PHAssetResource
        var companionResource: PHAssetResource? = nil

        if isLive {
            guard let photo = resources.first(where: { $0.type == .photo || $0.type == .fullSizePhoto }) else {
                throw PhotoKitError.resourceNotFound
            }
            primaryResource = photo
            companionResource = resources.first(where: { $0.type == .pairedVideo || $0.type == .fullSizePairedVideo })
        } else if asset.mediaType == .video {
            guard let video = resources.first(where: { $0.type == .video || $0.type == .fullSizeVideo }) ?? resources.first else {
                throw PhotoKitError.resourceNotFound
            }
            primaryResource = video
        } else {
            guard let photo = resources.first(where: { $0.type == .photo || $0.type == .fullSizePhoto }) ?? resources.first else {
                throw PhotoKitError.resourceNotFound
            }
            primaryResource = photo
        }

        let primaryFilename = primaryResource.originalFilename
        let primaryDestURL = stagingDir.appendingPathComponent(primaryFilename)
        try? FileManager.default.removeItem(at: primaryDestURL)

        // Write primary file (streams from iCloud if needed)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            resourceManager.writeData(for: primaryResource, toFile: primaryDestURL, options: options) { error in
                if let error = error {
                    continuation.resume(throwing: PhotoKitError.writeFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            }
        }

        var companionDestURL: URL? = nil
        if let comp = companionResource {
            let compFilename = comp.originalFilename
            let compURL = stagingDir.appendingPathComponent(compFilename)
            try? FileManager.default.removeItem(at: compURL)

            let compOptions = PHAssetResourceRequestOptions()
            compOptions.isNetworkAccessAllowed = true

            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                resourceManager.writeData(for: comp, toFile: compURL, options: compOptions) { error in
                    if let error = error {
                        continuation.resume(throwing: PhotoKitError.writeFailed(error.localizedDescription))
                    } else {
                        continuation.resume()
                    }
                }
            }
            companionDestURL = compURL
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
