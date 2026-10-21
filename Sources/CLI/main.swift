import Foundation
import CoreSyncEngine

let banner = """
\u{001B}[36m
  ____  _      ___  ____  
 |  _ \\(_)_  _/ _ \\/ ___| 
 | |_) | \\ \\/ / | | \\___ \\ 
 |  __/| |>  <| |_| |___) |
 |_|   |_/_/\\_\\\\___/|____/ 
\u{001B}[0m
\u{001B}[1mPixOS\u{001B}[0m - Seamless iOS to Android (Pixel Unlimited Backup) Media Bridge
Copyright (c) 2026 Exactable | MIT License
"""

func printHelp() {
    print(banner)
    print("""
\u{001B}[1mUSAGE:\u{001B}[0m
    pixos <command> [options]

\u{001B}[1mCOMMANDS:\u{001B}[0m
    \u{001B}[32mstatus\u{001B}[0m                  Display connected iPhone, Pixel, storage info & sync stats
    \u{001B}[32mdevices\u{001B}[0m                 List all available source (iOS) and target (Android) devices
    \u{001B}[32msync\u{001B}[0m                    Start automated extraction and transfer to Pixel
    \u{001B}[32mconnect-wireless <ip>\u{001B}[0m   Connect to Pixel over local Wi-Fi (Wireless ADB)
    \u{001B}[32mhistory\u{001B}[0m                 View past sync statistics and database records
    \u{001B}[32mhelp\u{001B}[0m                    Show this help guide

\u{001B}[1mSYNC OPTIONS:\u{001B}[0m
    --batch-size <GB>       Batch limit in GB (default: 5)
    --unlimited             Transfer everything at once without batching
    --source <id/name>      Select specific iPhone/iPad as source
    --target <serial>       Select specific Android device as target
    --no-motion-photos      Do not merge Live Photos into Google Motion Photos
    --exclude-screenshots   Skip screenshots and screen recordings
    --exclude-videos        Skip standalone video files
    --pixel-path <path>     Destination folder on Pixel (default: /sdcard/DCIM/iPhone)
    --dry-run               Scan and calculate pending media without transferring
    --delete-after          Prompt to remove backed-up media from iPhone after sync
""")
}

func formatBytes(_ bytes: Int64) -> String {
    if bytes >= SyncConfiguration.unlimitedBatchSize {
        return "Unlimited (All at once)"
    }
    return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

func main() async {
    let args = CommandLine.arguments.dropFirst().map { String($0) }
    guard let command = args.first else {
        printHelp()
        return
    }

    let orchestrator = SyncOrchestrator()

    switch command.lowercased() {
    case "status":
        print(banner)
        print("\u{001B}[1m🔍 Scanning for connected devices & reading camera roll...\u{001B}[0m\n")

        orchestrator.startMonitoring()
        _ = await orchestrator.waitForMedia(timeout: 3.5)

        print("\u{001B}[1m--- [iPhone (Source)] ---\u{001B}[0m")
        if let phone = orchestrator.connectedIPhone {
            print("  Status:     \u{001B}[32mConnected (USB)\u{001B}[0m")
            print("  Name:       \(phone.name)")
            let catalogStatus = orchestrator.isCatalogComplete ? "Catalog complete" : "Indexing..."
            print("  Media:      \(phone.totalMediaCount) items detected (\(catalogStatus))")
            print("  Lock State: \(phone.isLocked ? "\u{001B}[33mPasscode Locked (Please unlock device screen)\u{001B}[0m" : "\u{001B}[32mUnlocked & Ready\u{001B}[0m")")
            if phone.iCloudPhotosEnabled {
                print("  iCloud:     \u{001B}[33mOptimize iPhone Storage Active\u{001B}[0m (Only locally cached media is accessible over USB)")
            }
            if !orchestrator.allDiscoveredMedia.isEmpty {
                print("  Sample Media in Local Camera Roll:")
                for item in orchestrator.allDiscoveredMedia.prefix(5) {
                    print("    • \(item.filename) (\(item.formattedSize), \(item.mediaType.rawValue))")
                }
            }
        } else {
            print("  Status:     \u{001B}[31mNot Detected\u{001B}[0m (Plug in iPhone via USB and tap 'Trust This Computer')")
        }

        print("\n\u{001B}[1m--- [Google Pixel (Destination)] ---\u{001B}[0m")
        if let pixel = orchestrator.connectedPixel {
            let connType = pixel.isWireless ? "Wireless ADB" : "USB"
            print("  Status:     \u{001B}[32mConnected (\(connType))\u{001B}[0m")
            print("  Model:      \(pixel.model) (\(pixel.product))")
            print("  Serial:     \(pixel.serial)")
            print("  Authorized: \(pixel.isAuthorized ? "Yes" : "\u{001B}[33mUnauthorized (Allow USB Debugging on phone)\u{001B}[0m")")

            if let storage = orchestrator.pixelStorage {
                print("  Storage:    \(storage.formattedFree) free / \(storage.formattedTotal) total")
            }
        } else {
            print("  Status:     \u{001B}[31mNot Detected\u{001B}[0m (Enable USB Debugging on Pixel and connect via USB or Wi-Fi)")
        }

        print("\n\u{001B}[1m--- [Sync State & History] ---\u{001B}[0m")
        let stats = orchestrator.database.getStats()
        print("  Total Media Synced: \(stats.count) items (\(formatBytes(stats.totalBytes)))")
        if let lastDate = stats.lastSyncDate {
            let df = DateFormatter()
            df.dateStyle = .medium
            df.timeStyle = .short
            print("  Last Sync:          \(df.string(from: lastDate))")
        }
        print()

    case "devices":
        print(banner)
        print("\u{001B}[1m🔍 Scanning for connected devices & reading camera roll...\u{001B}[0m\n")
        orchestrator.startMonitoring()
        _ = await orchestrator.waitForMedia(timeout: 3.5)

        print("\u{001B}[1m--- [Available Source Devices (iOS)] ---\u{001B}[0m")
        if orchestrator.availableIPhones.isEmpty {
            print("  No iOS devices found. Plug in via USB and unlock screen.")
        } else {
            for (idx, phone) in orchestrator.availableIPhones.enumerated() {
                let isSelected = phone.id == orchestrator.selectedIPhoneId ? " \u{001B}[32m(Selected)\u{001B}[0m" : ""
                let lockStatus = phone.isLocked ? "\u{001B}[33mPasscode Locked\u{001B}[0m" : "\u{001B}[32mUnlocked\u{001B}[0m"
                print("  [\(idx + 1)] \(phone.name) [ID: \(phone.id)]\(isSelected)")
                print("      \(phone.totalMediaCount) camera items • \(lockStatus)")
            }
        }

        print("\n\u{001B}[1m--- [Available Target Devices (Android)] ---\u{001B}[0m")
        if orchestrator.availableAndroidDevices.isEmpty {
            print("  No Android devices found via ADB. Check USB debugging.")
        } else {
            for (idx, device) in orchestrator.availableAndroidDevices.enumerated() {
                let isSelected = device.serial == orchestrator.selectedPixelSerial ? " \u{001B}[32m(Selected)\u{001B}[0m" : ""
                let conn = device.isWireless ? "Wireless" : "USB"
                print("  [\(idx + 1)] \(device.model) (\(conn)) [Serial: \(device.serial)]\(isSelected)")
            }
        }
        print()

    case "connect-wireless":
        guard args.count >= 2 else {
            print("\u{001B}[31mError:\u{001B}[0m Please provide device IP. Example: pixos connect-wireless 192.168.1.150")
            return
        }
        let ip = args[1]
        let port = (args.count >= 3 ? Int(args[2]) : nil) ?? 5555
        print("Connecting to Google Pixel at \(ip):\(port)...")
        do {
            let success = try await orchestrator.adbClient.connectWireless(ip: ip, port: port)
            if success {
                print("\u{001B}[32mSuccessfully connected wirelessly to Pixel!\u{001B}[0m")
            } else {
                print("\u{001B}[33mADB output received, but connection not confirmed. Please check device IP.\u{001B}[0m")
            }
        } catch {
            print("\u{001B}[31mFailed to connect:\u{001B}[0m \(error.localizedDescription)")
        }

    case "history":
        let stats = orchestrator.database.getStats()
        print(banner)
        print("\u{001B}[1mSync History & Database Records\u{001B}[0m")
        print("----------------------------------------")
        print("Total Items Backed Up: \(stats.count)")
        print("Total Data Transferred: \(formatBytes(stats.totalBytes))")
        if let lastDate = stats.lastSyncDate {
            let df = DateFormatter()
            df.dateStyle = .medium
            df.timeStyle = .short
            print("Last Backup Session:    \(df.string(from: lastDate))")
        }
        print("Local Database:         ~/.pixos/sync_state.db")
        print("----------------------------------------\n")

    case "sync":
        print(banner)
        var config = SyncConfiguration()

        if args.contains("--unlimited") {
            config.batchSizeLimitBytes = SyncConfiguration.unlimitedBatchSize
        } else if let bIndex = args.firstIndex(of: "--batch-size"), bIndex + 1 < args.count {
            let val = args[bIndex + 1].lowercased()
            if val == "unlimited" || val == "all" || val == "0" {
                config.batchSizeLimitBytes = SyncConfiguration.unlimitedBatchSize
            } else if let gb = Int64(val) {
                config.batchSizeLimitBytes = gb * 1024 * 1024 * 1024
            }
        }
        if args.contains("--no-motion-photos") {
            config.combineLivePhotos = false
        }
        if args.contains("--exclude-screenshots") {
            config.includeScreenshots = false
        }
        if args.contains("--exclude-videos") {
            config.includeVideos = false
        }
        if let pIndex = args.firstIndex(of: "--pixel-path"), pIndex + 1 < args.count {
            config.targetPixelPath = args[pIndex + 1]
        }

        let isDryRun = args.contains("--dry-run")
        let shouldPromptDelete = args.contains("--delete-after")

        orchestrator.config = config
        orchestrator.startMonitoring()

        print("🔍 Connecting to devices and waiting for iPhone photo catalog...")
        _ = await orchestrator.waitForMedia(timeout: 3.5)

        if let sIndex = args.firstIndex(of: "--source"), sIndex + 1 < args.count {
            let targetSource = args[sIndex + 1]
            if let match = orchestrator.availableIPhones.first(where: { $0.id == targetSource || $0.name.lowercased().contains(targetSource.lowercased()) }) {
                orchestrator.selectSourceIPhone(id: match.id)
            }
        }

        if let tIndex = args.firstIndex(of: "--target"), tIndex + 1 < args.count {
            let targetSerial = args[tIndex + 1]
            orchestrator.selectTargetPixel(serial: targetSerial)
        }

        let isICloud = args.contains("--icloud") || (args.firstIndex(of: "--source").map { args[$0 + 1].lowercased() == "icloud" } ?? false)
        if isICloud {
            orchestrator.selectSourceType(.icloudPhotos)
        } else {
            orchestrator.selectSourceType(.usbIPhone)
        }

        if !isICloud {
            guard var phone = orchestrator.connectedIPhone else {
                print("\u{001B}[31mError:\u{001B}[0m iPhone not detected. Connect via USB or pass '--icloud' to stream from iCloud.")
                return
            }

            if phone.isLocked {
                print("\n\u{001B}[33m🔒 iPhone is Passcode Locked\u{001B}[0m")
                print("👉 Please unlock your iPhone screen with Face ID / Passcode and tap 'Trust This Computer' if prompted.")
                print("⏳ Waiting up to 20 seconds for unlock...")

                var unlocked = false
                for _ in 0..<40 {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    if let p = orchestrator.connectedIPhone, !p.isLocked {
                        unlocked = true
                        phone = p
                        break
                    }
                }

                if !unlocked {
                    print("\u{001B}[31mError:\u{001B}[0m iPhone remained locked. Unlock screen and try again.")
                    return
                }

                print("\u{001B}[32m✔ iPhone unlocked! Reading full media catalog...\u{001B}[0m")
                _ = await orchestrator.waitForMedia(timeout: 5.0)
            }
        } else {
            print("☁️ Connecting to iCloud / Mac Photos Library...")
            let status = orchestrator.photoKitManager.authorizationStatus
            if status != .authorized && status != .limited {
                let granted = await orchestrator.photoKitManager.requestAuthorization()
                if !granted {
                    print("\u{001B}[31mError:\u{001B}[0m Photos permission not granted. Grant access in System Settings > Privacy & Security > Photos.")
                    return
                }
            }
            orchestrator.photoKitManager.startCataloging()
            for _ in 0..<20 {
                try? await Task.sleep(nanoseconds: 200_000_000)
                if orchestrator.isCatalogComplete || !orchestrator.allDiscoveredMedia.isEmpty {
                    break
                }
            }
        }

        guard let pixel = orchestrator.connectedPixel, pixel.isAuthorized else {
            print("\u{001B}[31mError:\u{001B}[0m Google Pixel not detected or unauthorized. Check USB debugging.")
            return
        }

        orchestrator.recalculatePendingQueue()
        let pending = orchestrator.pendingQueue
        let totalBytes = pending.reduce(0) { $0 + $1.fileSize }

        let sourceName = orchestrator.selectedSourceType == .icloudPhotos ? "iCloud / Mac Photos Library" : (orchestrator.connectedIPhone?.name ?? "iPhone")
        print("\n\u{001B}[1mSync Plan:\u{001B}[0m")
        print("  Source:              \(sourceName)")
        print("  Target Device:       \(pixel.model) (\(pixel.isWireless ? "Wi-Fi" : "USB")) [\(pixel.serial)]")
        print("  Pending Media:       \(pending.count) items (\(formatBytes(totalBytes)))")
        print("  Pixel Target:        \(config.targetPixelPath)")
        print("  Batch Limit:         \(formatBytes(config.batchSizeLimitBytes))")
        print("  Motion Photos:       \(config.combineLivePhotos ? "Enabled" : "Disabled")")
        print("  Include Screenshots: \(config.includeScreenshots ? "Yes" : "No")")

        if isDryRun {
            print("\n\u{001B}[33m[Dry Run]\u{001B}[0m No files transferred.")
            return
        }

        guard !pending.isEmpty else {
            print("\n\u{001B}[32mAll photos and videos are already synced! Everything is up to date.\u{001B}[0m\n")
            return
        }

        print("\n🚀 Starting sync...\n")
        do {
            try await orchestrator.startSync()
            print("\n\u{001B}[32m✔ Sync complete!\u{001B}[0m Transferred \(orchestrator.syncedInSession.count) items to Pixel.")

            if shouldPromptDelete && !orchestrator.syncedInSession.isEmpty {
                print("\n\u{001B}[33mWould you like to delete the \(orchestrator.syncedInSession.count) backed-up items from your iPhone to free up space? (y/N):\u{001B}[0m ", terminator: "")
                fflush(stdout)
                if let response = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), response == "y" || response == "yes" {
                    print("Deleting backed-up items from iPhone...")
                    try await orchestrator.deleteSessionItemsFromiPhone()
                    print("\u{001B}[32m✔ Deleted from iPhone successfully!\u{001B}[0m")
                } else {
                    print("iPhone untouched.")
                }
            }
        } catch {
            print("\n\u{001B}[31mSync failed:\u{001B}[0m \(error.localizedDescription)")
        }

    default:
        printHelp()
    }
}

await main()
