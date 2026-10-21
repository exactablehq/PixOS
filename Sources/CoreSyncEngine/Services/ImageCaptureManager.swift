import Foundation
import ImageCaptureCore
import UniformTypeIdentifiers

public struct ConnectedIPhone: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let isLocked: Bool
    public let hasOpenSession: Bool
    public let totalMediaCount: Int
    public let batteryLevel: Int

    public init(
        id: String,
        name: String,
        isLocked: Bool,
        hasOpenSession: Bool,
        totalMediaCount: Int,
        batteryLevel: Int
    ) {
        self.id = id
        self.name = name
        self.isLocked = isLocked
        self.hasOpenSession = hasOpenSession
        self.totalMediaCount = totalMediaCount
        self.batteryLevel = batteryLevel
    }
}

public final class ImageCaptureManager: NSObject, @unchecked Sendable, ICDeviceBrowserDelegate, ICCameraDeviceDelegate, ICCameraDeviceDownloadDelegate {
    private let browser: ICDeviceBrowser
    public private(set) var activeCamera: ICCameraDevice?
    public var onDeviceListChanged: (([ConnectedIPhone]) -> Void)?
    public var onMediaItemsLoaded: (([MediaItem]) -> Void)?

    private var cachedMediaFiles: [String: ICCameraFile] = [:]
    public private(set) var discoveredCameras: [ICCameraDevice] = []
    private var downloadContinuation: CheckedContinuation<URL, Error>?
    private var currentDownloadDestination: URL?
    private let syncQueue = DispatchQueue(label: "com.exactable.pixos.imagecapture")

    public override init() {
        self.browser = ICDeviceBrowser()
        super.init()
        self.browser.delegate = self
        let rawMask = ICDeviceTypeMask.camera.rawValue | ICDeviceLocationTypeMask.local.rawValue | ICDeviceLocationTypeMask.shared.rawValue
        self.browser.browsedDeviceTypeMask = ICDeviceTypeMask(rawValue: rawMask) ?? .camera
    }

    public func startBrowsing() {
        browser.start()
    }

    public func stopBrowsing() {
        browser.stop()
    }

    public func selectCamera(id: String) {
        syncQueue.sync {
            if let selected = discoveredCameras.first(where: { ($0.uuidString ?? $0.name) == id }) {
                if activeCamera != selected {
                    activeCamera = selected
                    if !selected.hasOpenSession {
                        selected.requestOpenSession()
                    } else {
                        processCameraFiles(camera: selected)
                    }
                }
            }
        }
        notifyDeviceChanged()
    }

    // MARK: - ICDeviceBrowserDelegate

    public func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        if let camera = device as? ICCameraDevice {
            camera.delegate = self
            syncQueue.sync {
                if !discoveredCameras.contains(where: { $0 == camera }) {
                    discoveredCameras.append(camera)
                }
            }
            if activeCamera == nil {
                activeCamera = camera
                if !camera.hasOpenSession {
                    camera.requestOpenSession()
                }
            }
            notifyDeviceChanged()
        }
    }

    public func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
        if let camera = device as? ICCameraDevice {
            syncQueue.sync {
                discoveredCameras.removeAll(where: { $0 == camera })
            }
            if device == activeCamera {
                activeCamera = discoveredCameras.first
                if let next = activeCamera, !next.hasOpenSession {
                    next.requestOpenSession()
                }
            }
            notifyDeviceChanged()
        }
    }

    // MARK: - ICDeviceDelegate

    public func didRemove(_ device: ICDevice) {
        if let camera = device as? ICCameraDevice {
            syncQueue.sync {
                discoveredCameras.removeAll(where: { $0 == camera })
            }
            if device == activeCamera {
                activeCamera = discoveredCameras.first
                if let next = activeCamera, !next.hasOpenSession {
                    next.requestOpenSession()
                }
            }
            notifyDeviceChanged()
        }
    }

    public func deviceDidBecomeReady(_ device: ICDevice) {
        if let camera = device as? ICCameraDevice {
            activeCamera = camera
            processCameraFiles(camera: camera)
            notifyDeviceChanged()
        }
    }

    public func device(_ device: ICDevice, didOpenSessionWithError error: Error?) {
        if error == nil, let camera = device as? ICCameraDevice {
            activeCamera = camera
            processCameraFiles(camera: camera)
            notifyDeviceChanged()
        }
    }

    public func device(_ device: ICDevice, didCloseSessionWithError error: Error?) {
        if device == activeCamera {
            activeCamera = nil
        }
        notifyDeviceChanged()
    }

    public func deviceDidChangeName(_ device: ICDevice) {
        notifyDeviceChanged()
    }

    public func deviceDidChangeSharingState(_ device: ICDevice) {}

    // MARK: - ICCameraDeviceDelegate

    public func cameraDevice(_ camera: ICCameraDevice, didAdd items: [ICCameraItem]) {
        processCameraFiles(camera: camera)
    }

    public func cameraDevice(_ camera: ICCameraDevice, didRemove items: [ICCameraItem]) {
        processCameraFiles(camera: camera)
    }

    public func cameraDevice(_ camera: ICCameraDevice, didRenameItems items: [ICCameraItem]) {
        processCameraFiles(camera: camera)
    }

    public func cameraDeviceDidChangeCapability(_ camera: ICCameraDevice) {}

    public func cameraDevice(_ camera: ICCameraDevice, didReceiveThumbnail thumbnail: CGImage?, for item: ICCameraItem, error: Error?) {}

    public func cameraDevice(_ camera: ICCameraDevice, didReceiveMetadata metadata: [AnyHashable : Any]?, for item: ICCameraItem, error: Error?) {}

    public func cameraDevice(_ camera: ICCameraDevice, didReceivePTPEvent eventData: Data) {}

    public func deviceDidBecomeReady(withCompleteContentCatalog device: ICCameraDevice) {
        activeCamera = device
        processCameraFiles(camera: device)
        notifyDeviceChanged()
    }

    public func cameraDeviceDidRemoveAccessRestriction(_ device: ICDevice) {
        if let camera = device as? ICCameraDevice {
            processCameraFiles(camera: camera)
            notifyDeviceChanged()
        }
    }

    public func cameraDeviceDidEnableAccessRestriction(_ device: ICDevice) {
        notifyDeviceChanged()
    }

    // MARK: - Processing Media Items

    private func processCameraFiles(camera: ICCameraDevice) {
        guard let files = camera.mediaFiles as? [ICCameraFile] else { return }

        syncQueue.sync {
            cachedMediaFiles.removeAll()
            for file in files {
                if let name = file.name {
                    cachedMediaFiles[name] = file
                }
            }
        }

        var items: [MediaItem] = []
        var pairedVideos = Set<String>()

        // Pass 1: Identify live photo pairs
        for file in files {
            guard let name = file.name else { continue }
            let ext = (name as NSString).pathExtension.lowercased()
            let base = (name as NSString).deletingPathExtension

            if ext == "heic" || ext == "jpg" || ext == "jpeg" {
                let candidateMov1 = "\(base).MOV"
                let candidateMov2 = "\(base).mov"
                let exists1 = syncQueue.sync { cachedMediaFiles[candidateMov1] != nil }
                let exists2 = syncQueue.sync { cachedMediaFiles[candidateMov2] != nil }

                if exists1 {
                    pairedVideos.insert(candidateMov1)
                } else if exists2 {
                    pairedVideos.insert(candidateMov2)
                }
            }
        }

        // Pass 2: Build MediaItems
        for file in files {
            guard let name = file.name else { continue }
            let ext = (name as NSString).pathExtension.lowercased()
            let base = (name as NSString).deletingPathExtension
            let fileSize = file.fileSize
            let creationDate = file.creationDate
            let modDate = file.modificationDate

            var mediaType: MediaType = .photo
            var isLivePhoto = false
            var companionVideo: String? = nil

            if ext == "heic" || ext == "jpg" || ext == "jpeg" || ext == "png" || ext == "dng" {
                let candidateMov1 = "\(base).MOV"
                let candidateMov2 = "\(base).mov"
                if pairedVideos.contains(candidateMov1) {
                    isLivePhoto = true
                    mediaType = .livePhoto
                    companionVideo = candidateMov1
                } else if pairedVideos.contains(candidateMov2) {
                    isLivePhoto = true
                    mediaType = .livePhoto
                    companionVideo = candidateMov2
                } else if ext == "png" && name.contains("Screenshot") {
                    mediaType = .screenshot
                } else {
                    mediaType = .photo
                }
            } else if ext == "mov" || ext == "mp4" {
                if pairedVideos.contains(name) {
                    continue
                }
                if name.contains("ScreenRecording") || name.contains("RPReplay") {
                    mediaType = .screenRecording
                } else {
                    mediaType = .video
                }
            } else {
                mediaType = .other
            }

            let item = MediaItem(
                id: "\(name)_\(fileSize)",
                filename: name,
                fileSize: fileSize,
                creationDate: creationDate,
                modificationDate: modDate,
                mediaType: mediaType,
                isLivePhoto: isLivePhoto,
                companionVideoName: companionVideo
            )
            items.append(item)
        }

        onMediaItemsLoaded?(items)
    }

    private func notifyDeviceChanged() {
        let cameras: [ICCameraDevice] = syncQueue.sync {
            var list = discoveredCameras
            if let active = activeCamera, !list.contains(where: { $0 == active }) {
                list.append(active)
            }
            return list
        }

        guard !cameras.isEmpty else {
            onDeviceListChanged?([])
            return
        }

        let phones = cameras.map { camera in
            ConnectedIPhone(
                id: camera.uuidString ?? camera.name ?? "iPhone",
                name: camera.name ?? "iPhone",
                isLocked: camera.isLocked,
                hasOpenSession: camera.hasOpenSession,
                totalMediaCount: camera.mediaFiles?.count ?? 0,
                batteryLevel: camera.batteryLevel
            )
        }
        onDeviceListChanged?(phones)
    }

    // MARK: - Downloading

    public func downloadFile(named filename: String, to destinationFolder: URL) async throws -> URL {
        let (camera, file): (ICCameraDevice, ICCameraFile) = try syncQueue.sync {
            guard let cam = activeCamera, let f = cachedMediaFiles[filename] else {
                throw NSError(
                    domain: "PixOS.ImageCapture",
                    code: 404,
                    userInfo: [NSLocalizedDescriptionKey: "File '\(filename)' not found on iPhone."]
                )
            }
            return (cam, f)
        }

        let options: [ICDownloadOption: Any] = [
            .downloadsDirectoryURL: destinationFolder,
            .overwrite: true,
            .saveAsFilename: filename
        ]

        return try await withCheckedThrowingContinuation { continuation in
            self.downloadContinuation = continuation
            self.currentDownloadDestination = destinationFolder.appendingPathComponent(filename)

            camera.requestDownloadFile(
                file,
                options: options,
                downloadDelegate: self,
                didDownloadSelector: #selector(didDownloadFile(file:error:options:contextInfo:)),
                contextInfo: nil
            )
        }
    }

    @objc private func didDownloadFile(file: ICCameraFile, error: Error?, options: [String: Any], contextInfo: UnsafeMutableRawPointer?) {
        if let error = error {
            downloadContinuation?.resume(throwing: error)
        } else if let dest = currentDownloadDestination {
            downloadContinuation?.resume(returning: dest)
        } else {
            let fallback = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(file.name ?? "download")
            downloadContinuation?.resume(returning: fallback)
        }
        downloadContinuation = nil
        currentDownloadDestination = nil
    }

    // MARK: - Deletion

    public func deleteFiles(named filenames: [String]) async throws {
        let (camera, itemsToDelete): (ICCameraDevice, [ICCameraItem]) = try syncQueue.sync {
            guard let cam = activeCamera else {
                throw NSError(domain: "PixOS.ImageCapture", code: 400, userInfo: [NSLocalizedDescriptionKey: "No active camera"])
            }
            var items: [ICCameraItem] = []
            for name in filenames {
                if let f = cachedMediaFiles[name] {
                    items.append(f)
                }
            }
            return (cam, items)
        }

        guard !itemsToDelete.isEmpty else { return }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            camera.requestDeleteFiles(
                itemsToDelete,
                deleteFailed: { _ in },
                completion: { results, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            )
        }
    }
}
