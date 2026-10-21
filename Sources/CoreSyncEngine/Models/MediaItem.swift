import Foundation

public enum MediaType: String, Codable, Sendable {
    case photo
    case video
    case livePhoto
    case screenshot
    case screenRecording
    case other
}

public enum MediaSourceType: String, CaseIterable, Identifiable, Sendable {
    case usbIPhone = "iPhone (USB Cable)"
    case icloudPhotos = "iCloud / Mac Photos"

    public var id: String { rawValue }

    public var shortTitle: String {
        switch self {
        case .usbIPhone: return "iPhone (USB)"
        case .icloudPhotos: return "iCloud Photos"
        }
    }

    public var iconName: String {
        switch self {
        case .usbIPhone: return "iphone.gen3"
        case .icloudPhotos: return "icloud.fill"
        }
    }
}

public struct MediaItem: Identifiable, Sendable, Equatable {
    public let id: String
    public let filename: String
    public let fileSize: Int64
    public let creationDate: Date?
    public let modificationDate: Date?
    public let mediaType: MediaType
    public let isLivePhoto: Bool
    public var companionVideoName: String?
    public var isSynced: Bool
    public var localStagedURL: URL?
    public var pixelPath: String?

    public init(
        id: String,
        filename: String,
        fileSize: Int64,
        creationDate: Date?,
        modificationDate: Date?,
        mediaType: MediaType,
        isLivePhoto: Bool,
        companionVideoName: String? = nil,
        isSynced: Bool = false,
        localStagedURL: URL? = nil,
        pixelPath: String? = nil
    ) {
        self.id = id
        self.filename = filename
        self.fileSize = fileSize
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.mediaType = mediaType
        self.isLivePhoto = isLivePhoto
        self.companionVideoName = companionVideoName
        self.isSynced = isSynced
        self.localStagedURL = localStagedURL
        self.pixelPath = pixelPath
    }

    public var fingerprint: String {
        let timestamp = creationDate?.timeIntervalSince1970 ?? 0
        return "\(filename)_\(fileSize)_\(Int(timestamp))"
    }

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}

public struct AndroidDevice: Identifiable, Sendable, Equatable {
    public let id: String
    public let serial: String
    public let model: String
    public let product: String
    public let isWireless: Bool
    public let isAuthorized: Bool

    public init(
        id: String,
        serial: String,
        model: String,
        product: String,
        isWireless: Bool,
        isAuthorized: Bool
    ) {
        self.id = id
        self.serial = serial
        self.model = model
        self.product = product
        self.isWireless = isWireless
        self.isAuthorized = isAuthorized
    }
}

public struct StorageInfo: Sendable, Equatable {
    public let totalBytes: Int64
    public let usedBytes: Int64
    public let freeBytes: Int64

    public init(totalBytes: Int64, usedBytes: Int64, freeBytes: Int64) {
        self.totalBytes = totalBytes
        self.usedBytes = usedBytes
        self.freeBytes = freeBytes
    }

    public var freePercentage: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(freeBytes) / Double(totalBytes)
    }

    public var formattedFree: String {
        ByteCountFormatter.string(fromByteCount: freeBytes, countStyle: .file)
    }

    public var formattedTotal: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }
}

public struct SyncConfiguration: Sendable, Equatable {
    public static let unlimitedBatchSize: Int64 = Int64.max

    public var batchSizeLimitBytes: Int64
    public var combineLivePhotos: Bool
    public var includeScreenshots: Bool
    public var includeVideos: Bool
    public var targetPixelPath: String
    public var customADBPath: String?
    public var safeFreeStorageThresholdBytes: Int64
    public var concurrentStreams: Int

    public init(
        batchSizeLimitBytes: Int64 = 5 * 1024 * 1024 * 1024, // 5 GB
        combineLivePhotos: Bool = true,
        includeScreenshots: Bool = true,
        includeVideos: Bool = true,
        targetPixelPath: String = "/sdcard/DCIM/iPhone",
        customADBPath: String? = nil,
        safeFreeStorageThresholdBytes: Int64 = 2 * 1024 * 1024 * 1024, // 2 GB
        concurrentStreams: Int = 4
    ) {
        self.batchSizeLimitBytes = batchSizeLimitBytes
        self.combineLivePhotos = combineLivePhotos
        self.includeScreenshots = includeScreenshots
        self.includeVideos = includeVideos
        self.targetPixelPath = targetPixelPath
        self.customADBPath = customADBPath
        self.safeFreeStorageThresholdBytes = safeFreeStorageThresholdBytes
        self.concurrentStreams = max(1, min(8, concurrentStreams))
    }
}

public struct SyncProgress: Sendable, Equatable {
    public var currentItem: String
    public var currentItemIndex: Int
    public var totalItems: Int
    public var bytesTransferred: Int64
    public var totalBytes: Int64
    public var currentBatchIndex: Int
    public var totalBatches: Int
    public var speedBytesPerSecond: Double
    public var statusDescription: String
    public var isPausedForStorage: Bool
    public var estimatedTimeRemainingSeconds: TimeInterval?

    public init(
        currentItem: String = "",
        currentItemIndex: Int = 0,
        totalItems: Int = 0,
        bytesTransferred: Int64 = 0,
        totalBytes: Int64 = 0,
        currentBatchIndex: Int = 0,
        totalBatches: Int = 0,
        speedBytesPerSecond: Double = 0,
        statusDescription: String = "Ready",
        isPausedForStorage: Bool = false,
        estimatedTimeRemainingSeconds: TimeInterval? = nil
    ) {
        self.currentItem = currentItem
        self.currentItemIndex = currentItemIndex
        self.totalItems = totalItems
        self.bytesTransferred = bytesTransferred
        self.totalBytes = totalBytes
        self.currentBatchIndex = currentBatchIndex
        self.totalBatches = totalBatches
        self.speedBytesPerSecond = speedBytesPerSecond
        self.statusDescription = statusDescription
        self.isPausedForStorage = isPausedForStorage
        self.estimatedTimeRemainingSeconds = estimatedTimeRemainingSeconds
    }

    public var fractionCompleted: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1.0, max(0.0, Double(bytesTransferred) / Double(totalBytes)))
    }

    public var formattedSpeed: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return "\(formatter.string(fromByteCount: Int64(speedBytesPerSecond)))/s"
    }

    public var formattedETA: String {
        guard let seconds = estimatedTimeRemainingSeconds, seconds > 0, seconds.isFinite else {
            return ""
        }
        let total = Int(seconds)
        let hrs = total / 3600
        let mins = (total % 3600) / 60
        if hrs > 0 {
            return "\(hrs)h \(mins)m remaining"
        } else {
            return "\(max(1, mins))m remaining"
        }
    }
}
