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
    \u{001B}[32msync\u{001B}[0m                    Start automated extraction and transfer to Pixel
    \u{001B}[32mconnect-wireless <ip>\u{001B}[0m   Connect to Pixel over local Wi-Fi (Wireless ADB)
    \u{001B}[32mhistory\u{001B}[0m                 View past sync statistics and database records
    \u{001B}[32mhelp\u{001B}[0m                    Show this help guide

\u{001B}[1mSYNC OPTIONS:\u{001B}[0m
    --batch-size <GB>       Batch limit in GB (default: 5)
    --no-motion-photos      Do not merge Live Photos into Google Motion Photos
    --exclude-screenshots   Skip screenshots and screen recordings
    --exclude-videos        Skip standalone video files
    --pixel-path <path>     Destination folder on Pixel (default: /sdcard/DCIM/iPhone)
    --dry-run               Scan and calculate pending media without transferring
    --delete-after          Prompt to remove backed-up media from iPhone after sync
""")
}

func formatBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
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
        print("\u{001B}[1m🔍 Scanning for connected devices...\u{001B}[0m\n")

        orchestrator.startMonitoring()
        try? await Task.sleep(nanoseconds: 1_500_000_000)

        print("\u{001B}[1m--- [iPhone (Source)] ---\u{001B}[0m")
        if let phone = orchestrator.connectedIPhone {
            print("  Status:     \u{001B}[32mConnected (USB)\u{001B}[0m")
            print("  Name:       \(phone.name)")
            print("  Media:      \(phone.totalMediaCount) items detected")
            print("  Lock State: \(phone.isLocked ? "\u{001B}[33mLocked (Please unlock device)\u{001B}[0m" : "Unlocked")")
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

        if let bIndex = args.firstIndex(of: "--batch-size"), bIndex + 1 < args.count, let gb = Int64(args[bIndex + 1]) {
            config.batchSizeLimitBytes = gb * 1024 * 1024 * 1024
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

        print("🔍 Connecting to devices (waiting up to 3 seconds)...")
        try? await Task.sleep(nanoseconds: 2_000_000_000)

        guard let _ = orchestrator.connectedIPhone else {
            print("\u{001B}[31mError:\u{001B}[0m iPhone not detected. Connect via USB and unlock phone.")
            return
        }
        guard let pixel = orchestrator.connectedPixel, pixel.isAuthorized else {
            print("\u{001B}[31mError:\u{001B}[0m Google Pixel not detected or unauthorized. Check USB debugging.")
            return
        }

        orchestrator.recalculatePendingQueue()
        let pending = orchestrator.pendingQueue
        let totalBytes = pending.reduce(0) { $0 + $1.fileSize }

        print("\n\u{001B}[1mSync Plan:\u{001B}[0m")
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
