import SwiftUI
import CoreSyncEngine

public final class DashboardViewModel: ObservableObject {
    @Published public var showingOnboarding: Bool = false
    @Published public var showingWirelessModal: Bool = false
    @Published public var showingSwipeClean: Bool = false
    @Published public var showingSkippedModal: Bool = false
    @Published public var showingDeleteConfirmation: Bool = false
    @Published public var selectedFilter: String = "All"
    @Published public var copiedNotice: Bool = false
    @Published public var pairingVM: PairingViewModel = PairingViewModel()
    @Published public var swipeCleanVM: SwipeCleanViewModel = SwipeCleanViewModel()
    @Published public var onboardingVM: OnboardingViewModel = OnboardingViewModel()

    public init() {}
}

public struct MainDashboardView: View {
    @ObservedObject var orchestrator: SyncOrchestrator
    @StateObject private var vm: DashboardViewModel

    public init(orchestrator: SyncOrchestrator, vm: DashboardViewModel? = nil) {
        self.orchestrator = orchestrator
        self._vm = StateObject(wrappedValue: vm ?? DashboardViewModel())
    }

    public var body: some View {
        ZStack {
            // Liquid Glass Background
            VisualEffectView(material: .sidebar, blendingMode: .behindWindow)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top Header Bar
                headerBar
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                Divider()
                    .opacity(0.4)

                // Main Content Area
                ScrollView {
                    VStack(spacing: 20) {
                        // Device Status Badges
                        deviceStatusRow

                        // Storage & Sync Visualizer
                        storageCard

                        // Media Category Filters & Overwrite Control
                        mediaFilterCard

                        // Configuration Row
                        configurationCard

                        // Pending Queue / Media Table
                        mediaQueueCard

                        // Post-Sync Deletion Banner
                        if !orchestrator.syncedInSession.isEmpty && orchestrator.state == .completed {
                            deletionBanner
                        }
                    }
                    .padding(24)
                }

                Divider()
                    .opacity(0.4)

                // Bottom Action & Progress Bar
                bottomActionBar
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    .background(Color(NSColor.windowBackgroundColor).opacity(0.6))
            }

            // Modal Overlays
            if vm.showingOnboarding {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture { vm.showingOnboarding = false }

                OnboardingView(orchestrator: orchestrator, vm: vm.onboardingVM, onDismiss: { vm.showingOnboarding = false })
                    .background(VisualEffectView(material: .hudWindow, blendingMode: .withinWindow))
                    .cornerRadius(16)
                    .shadow(radius: 20)
                    .transition(.scale.combined(with: .opacity))
            }

            if vm.showingWirelessModal {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture { vm.showingWirelessModal = false }

                WirelessPairingView(orchestrator: orchestrator, vm: vm.pairingVM, onDismiss: { vm.showingWirelessModal = false })
                    .background(VisualEffectView(material: .hudWindow, blendingMode: .withinWindow))
                    .cornerRadius(16)
                    .shadow(radius: 20)
                    .transition(.scale.combined(with: .opacity))
            }

            if vm.showingSwipeClean {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture { vm.showingSwipeClean = false }

                ICloudSwipeCleanView(orchestrator: orchestrator, vm: vm.swipeCleanVM, onDismiss: { vm.showingSwipeClean = false })
                    .background(VisualEffectView(material: .hudWindow, blendingMode: .withinWindow))
                    .cornerRadius(16)
                    .shadow(radius: 20)
                    .transition(.scale.combined(with: .opacity))
            }

            if vm.showingSkippedModal {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture { vm.showingSkippedModal = false }

                SkippedItemsModalView(orchestrator: orchestrator, vm: vm, onDismiss: { vm.showingSkippedModal = false })
                    .background(VisualEffectView(material: .hudWindow, blendingMode: .withinWindow))
                    .cornerRadius(16)
                    .shadow(radius: 20)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.swap")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text("PixOS")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                        Text("OPEN SOURCE")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.15))
                            .foregroundColor(.blue)
                            .cornerRadius(4)
                    }
                    Text("iOS to Android (Pixel Unlimited Backup) Media Bridge")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            HStack(spacing: 10) {
                Button(action: {
                    orchestrator.populateTriageQueue()
                    vm.showingSwipeClean = true
                }) {
                    Label("iCloud Cleaner", systemImage: "hand.draw.fill")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .help("Open Tinder-like swipe deck to review and delete synced photos from iCloud")

                Button(action: { vm.showingWirelessModal = true }) {
                    Label("Wireless ADB", systemImage: "wifi")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)

                Button(action: { vm.showingOnboarding = true }) {
                    Label("Guide", systemImage: "questionmark.circle")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Device Status Row

    private var deviceStatusRow: some View {
        VStack(spacing: 12) {
            // Source Selector Bar
            HStack(spacing: 8) {
                Text("Source:")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)

                ForEach(MediaSourceType.allCases) { sourceType in
                    Button(action: {
                        orchestrator.selectSourceType(sourceType)
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: sourceType.iconName)
                            Text(sourceType.rawValue)
                                .font(.system(size: 12, weight: orchestrator.selectedSourceType == sourceType ? .bold : .medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(orchestrator.selectedSourceType == sourceType ? Color.blue.opacity(0.18) : Color.primary.opacity(0.04))
                        .foregroundColor(orchestrator.selectedSourceType == sourceType ? .blue : .primary)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                // Mac Storage safety indicator
                HStack(spacing: 4) {
                    Image(systemName: "internaldrive")
                        .font(.system(size: 10))
                    Text("Mac Free: \(ByteCountFormatter.string(fromByteCount: PhotoKitSourceManager.getMacFreeDiskBytes(), countStyle: .file))")
                        .font(.system(size: 10))
                }
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 4)

            HStack(spacing: 16) {
                // Source Card (iCloud or USB iPhone)
                if orchestrator.selectedSourceType == .icloudPhotos {
                    iCloudSourceCard
                } else {
                    iphoneSourceCard
                }

                // Google Pixel Device Card (Target Selector)
                pixelTargetCard
            }

            if orchestrator.selectedSourceType == .usbIPhone, let phone = orchestrator.connectedIPhone, phone.iCloudPhotosEnabled {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "icloud.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.blue)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("iCloud Photos Active ('Optimize iPhone Storage')")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Only \(phone.totalMediaCount) items are downloaded locally on iPhone flash. The rest reside in iCloud.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

                        Button(action: { orchestrator.selectSourceType(.icloudPhotos) }) {
                            HStack(spacing: 4) {
                                Image(systemName: "bolt.fill")
                                Text("Switch to iCloud Streaming Source")
                            }
                            .font(.system(size: 11, weight: .bold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                        .controlSize(.small)
                        .padding(.top, 2)
                    }
                    Spacer()
                }
                .padding(12)
                .background(Color.blue.opacity(0.08))
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.blue.opacity(0.2), lineWidth: 1))
            }

            if orchestrator.selectedSourceType == .icloudPhotos && orchestrator.isCatalogComplete && orchestrator.allDiscoveredMedia.isEmpty {
                iCloudSetupGuideCard
            }
        }
    }

    private var iCloudSetupGuideCard: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 22))
                .foregroundColor(.orange)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("0 Items in Mac Library — macOS iCloud Sync Required")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.primary)
                    Spacer()
                }

                Text("Apple's PhotoKit accesses your media via the macOS System Photo Library. If your Mac Photos app has never synced with your iCloud account, your Mac catalog is currently empty.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 6) {
                        Text("1.")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.blue)
                        Text("Open Photos app (Cmd+,) → **General** tab → Click **'Use as System Photo Library'** (until greyed out).")
                            .font(.system(size: 11))
                    }
                    HStack(alignment: .top, spacing: 6) {
                        Text("2.")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.blue)
                        Text("Photos → **iCloud** tab → Check **'[✓] iCloud Photos'** and select **'Optimize Mac Storage'** (zero disk bloat).")
                            .font(.system(size: 11))
                    }
                }
                .padding(.vertical, 2)

                HStack(spacing: 10) {
                    Button(action: { orchestrator.photoKitManager.openMacPhotos() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "photo.on.rectangle.angled")
                            Text("Open Mac Photos App")
                        }
                        .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .controlSize(.small)

                    Button(action: { orchestrator.photoKitManager.openPrivacySettings() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "lock.shield")
                            Text("Privacy Settings")
                        }
                        .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button(action: { orchestrator.refreshIPhone() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                            Text("Check Again")
                        }
                        .font(.system(size: 11))
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
                .padding(.top, 4)
            }
        }
        .padding(14)
        .background(Color.orange.opacity(0.08))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.3), lineWidth: 1))
    }

    private var iCloudSourceCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.blue.opacity(0.2), .purple.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 44, height: 44)
                Image(systemName: "icloud.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.blue)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("iCloud Photos")
                        .font(.system(size: 14, weight: .semibold))

                    let isAuth = (orchestrator.photoKitManager.authorizationStatus == .authorized || orchestrator.photoKitManager.authorizationStatus == .limited)
                    Circle()
                        .fill(isAuth ? Color.green : Color.orange)
                        .frame(width: 7, height: 7)
                }

                if orchestrator.photoKitManager.authorizationStatus == .authorized || orchestrator.photoKitManager.authorizationStatus == .limited {
                    if !orchestrator.isCatalogComplete {
                        HStack(spacing: 4) {
                            ProgressView().controlSize(.mini)
                            Text("Indexing iCloud catalog (\(orchestrator.photoKitManager.totalAssetCount) items)...")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text("\(orchestrator.allDiscoveredMedia.count) items ready to stream • Zero disk bloat")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                } else {
                    Button("Grant Photos Access") {
                        Task {
                            _ = await orchestrator.photoKitManager.requestAuthorization()
                            orchestrator.selectSourceType(.icloudPhotos)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }
            Spacer()

            Button(action: { orchestrator.refreshIPhone() }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Re-index iCloud Photos catalog")
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
        )
    }

    private var iphoneSourceCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(orchestrator.connectedIPhone != nil ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: "iphone.gen3")
                    .font(.system(size: 22))
                    .foregroundColor(orchestrator.connectedIPhone != nil ? .green : .orange)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if orchestrator.availableIPhones.count > 1 {
                        Menu {
                            ForEach(orchestrator.availableIPhones) { phone in
                                Button(action: { orchestrator.selectSourceIPhone(id: phone.id) }) {
                                    HStack {
                                        Text(phone.name)
                                        if phone.id == orchestrator.selectedIPhoneId {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(orchestrator.connectedIPhone?.name ?? "Source Device")
                                    .font(.system(size: 14, weight: .semibold))
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 10))
                            }
                        }
                        .menuStyle(.borderlessButton)
                    } else {
                        Text(orchestrator.connectedIPhone?.name ?? "iPhone (Not Connected)")
                            .font(.system(size: 14, weight: .semibold))
                    }

                    if let phone = orchestrator.connectedIPhone {
                        Circle()
                            .fill(phone.isLocked ? Color.orange : Color.green)
                            .frame(width: 7, height: 7)
                    }
                }

                if let phone = orchestrator.connectedIPhone {
                    if phone.isLocked {
                        HStack(spacing: 4) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 9))
                            Text("Passcode Locked • Unlock iPhone screen")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(.orange)
                    } else if !orchestrator.isCatalogComplete && phone.totalMediaCount == 0 {
                        HStack(spacing: 4) {
                            ProgressView().controlSize(.mini)
                            Text("Cataloging iPhone camera roll...")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text("\(phone.totalMediaCount) camera items • Ready\(phone.iCloudPhotosEnabled ? " (iCloud Optimized)" : "")")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("Plug in via USB & tap 'Trust This Computer'")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            Spacer()

            if orchestrator.connectedIPhone != nil {
                Button(action: { orchestrator.refreshIPhone() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Refresh iPhone connection and catalog")
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(orchestrator.connectedIPhone != nil ? Color.green.opacity(0.3) : Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private var pixelTargetCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(orchestrator.connectedPixel != nil ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: "candybarphone")
                    .font(.system(size: 22))
                    .foregroundColor(orchestrator.connectedPixel != nil ? .green : .red)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if orchestrator.availableAndroidDevices.count > 1 {
                        Menu {
                            ForEach(orchestrator.availableAndroidDevices) { device in
                                Button(action: { orchestrator.selectTargetPixel(serial: device.serial) }) {
                                    HStack {
                                        Text("\(device.model) (\(device.isWireless ? "Wi-Fi" : "USB")) [\(device.serial)]")
                                        if device.serial == orchestrator.selectedPixelSerial {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(orchestrator.connectedPixel?.model ?? "Target Device")
                                    .font(.system(size: 14, weight: .semibold))
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 10))
                            }
                        }
                        .menuStyle(.borderlessButton)
                    } else {
                        Text(orchestrator.connectedPixel?.model ?? "Pixel (Not Connected)")
                            .font(.system(size: 14, weight: .semibold))
                    }

                    if let pixel = orchestrator.connectedPixel {
                        Circle()
                            .fill(pixel.isAuthorized ? Color.green : Color.yellow)
                            .frame(width: 7, height: 7)
                        Text(pixel.isWireless ? "Wi-Fi" : "USB")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.primary.opacity(0.08))
                            .cornerRadius(3)
                    }
                }

                if let pixel = orchestrator.connectedPixel {
                    if pixel.isAuthorized {
                        Text("Free: \(orchestrator.pixelStorage?.formattedFree ?? "Checking...") • Free Unlimited Backup")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    } else {
                        Text("Unauthorized: Tap 'Allow USB Debugging' on phone")
                            .font(.system(size: 11))
                            .foregroundColor(.yellow)
                    }
                } else {
                    Text("Enable USB Debugging on Pixel")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(orchestrator.connectedPixel != nil ? Color.green.opacity(0.3) : Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    // MARK: - Storage Visualizer Card

    private var storageCard: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Transfer Pipeline")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Extracting from \(orchestrator.selectedSourceType == .icloudPhotos ? "iCloud / Mac Library" : "iPhone") → Google Motion Photo packaging → /sdcard/DCIM/iPhone/ (Auto-pruning Mac staging)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "infinity")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.blue)
                    Text("Unlimited Original Backup")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.blue)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.12))
                .cornerRadius(20)
            }

            // Metrics Bar
            let pendingBytes = orchestrator.pendingQueue.reduce(0) { $0 + $1.fileSize }
            let pendingStr = ByteCountFormatter.string(fromByteCount: pendingBytes, countStyle: .file)
            let usedFraction = orchestrator.pixelStorage?.freePercentage ?? 0

            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pending Sync")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(orchestrator.pendingQueue.count) items (\(pendingStr))")
                        .font(.title3.bold())
                }

                Divider()

                VStack(alignment: .leading, spacing: 2) {
                    Text("Pixel Free Storage")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(orchestrator.pixelStorage?.formattedFree ?? "--")
                        .font(.title3.bold())
                }

                Divider()

                VStack(alignment: .leading, spacing: 2) {
                    Text("Total Backed Up")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    let stats = orchestrator.database.getStats()
                    Text("\(stats.count) items (\(ByteCountFormatter.string(fromByteCount: stats.totalBytes, countStyle: .file)))")
                        .font(.title3.bold())
                }

                Spacer()
            }

            // Progress Bar of Pixel Storage
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Pixel Storage Health")
                        .font(.caption2.bold())
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(Int(usedFraction * 100))% free")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                ProgressView(value: 1.0 - usedFraction)
                    .tint(usedFraction < 0.15 ? .red : .blue)
            }
        }
        .padding(18)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    // MARK: - Media Category Filter & Overwrite Card

    private var mediaFilterCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header with Overwrite Mode Toggle
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "line.3.horizontal.decrease.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.blue)
                    Text("Media Category Filters")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Select which media to transfer")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Quick Presets
                HStack(spacing: 6) {
                    Button("All Media") {
                        orchestrator.config.includeLivePhotos = true
                        orchestrator.config.includePhotos = true
                        orchestrator.config.includeVideos = true
                        orchestrator.config.includeScreenshots = true
                        orchestrator.config.includeScreenRecordings = true
                        orchestrator.recalculatePendingQueue()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)

                    Button("Live Photos Only") {
                        orchestrator.config.includeLivePhotos = true
                        orchestrator.config.includePhotos = false
                        orchestrator.config.includeVideos = false
                        orchestrator.config.includeScreenshots = false
                        orchestrator.config.includeScreenRecordings = false
                        orchestrator.recalculatePendingQueue()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)

                    Button("Photos & Videos") {
                        orchestrator.config.includeLivePhotos = true
                        orchestrator.config.includePhotos = true
                        orchestrator.config.includeVideos = true
                        orchestrator.config.includeScreenshots = false
                        orchestrator.config.includeScreenRecordings = false
                        orchestrator.recalculatePendingQueue()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }

                Divider().frame(height: 16).padding(.horizontal, 4)

                // Overwrite Mode Toggle
                Toggle(isOn: Binding(
                    get: { orchestrator.config.overwriteMode },
                    set: { val in
                        orchestrator.config.overwriteMode = val
                        orchestrator.recalculatePendingQueue()
                    }
                )) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(orchestrator.config.overwriteMode ? .orange : .secondary)
                        Text("Overwrite Mode")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(orchestrator.config.overwriteMode ? .orange : .primary)
                    }
                }
                .toggleStyle(.checkbox)
                .help("When enabled, re-transfers and overwrites files on Pixel for active filtered categories without losing database history")
            }

            // Filter Chips Row
            HStack(spacing: 10) {
                // Live Photos Chip
                filterChip(
                    title: "Live Photos",
                    icon: "sparkles",
                    color: .yellow,
                    count: orchestrator.allDiscoveredMedia.filter { $0.isLivePhoto }.count,
                    bytes: orchestrator.allDiscoveredMedia.filter { $0.isLivePhoto }.reduce(0) { $0 + $1.fileSize },
                    isSelected: orchestrator.config.includeLivePhotos
                ) {
                    orchestrator.config.includeLivePhotos.toggle()
                    orchestrator.recalculatePendingQueue()
                }

                // Standard Photos Chip
                filterChip(
                    title: "Standard Photos",
                    icon: "photo",
                    color: .blue,
                    count: orchestrator.allDiscoveredMedia.filter { $0.isStandardPhoto }.count,
                    bytes: orchestrator.allDiscoveredMedia.filter { $0.isStandardPhoto }.reduce(0) { $0 + $1.fileSize },
                    isSelected: orchestrator.config.includePhotos
                ) {
                    orchestrator.config.includePhotos.toggle()
                    orchestrator.recalculatePendingQueue()
                }

                // Videos Chip
                filterChip(
                    title: "Videos",
                    icon: "video.fill",
                    color: .purple,
                    count: orchestrator.allDiscoveredMedia.filter { $0.mediaType == .video }.count,
                    bytes: orchestrator.allDiscoveredMedia.filter { $0.mediaType == .video }.reduce(0) { $0 + $1.fileSize },
                    isSelected: orchestrator.config.includeVideos
                ) {
                    orchestrator.config.includeVideos.toggle()
                    orchestrator.recalculatePendingQueue()
                }

                // Screenshots Chip
                filterChip(
                    title: "Screenshots",
                    icon: "camera.viewfinder",
                    color: .orange,
                    count: orchestrator.allDiscoveredMedia.filter { $0.mediaType == .screenshot }.count,
                    bytes: orchestrator.allDiscoveredMedia.filter { $0.mediaType == .screenshot }.reduce(0) { $0 + $1.fileSize },
                    isSelected: orchestrator.config.includeScreenshots
                ) {
                    orchestrator.config.includeScreenshots.toggle()
                    orchestrator.recalculatePendingQueue()
                }

                // Screen Recordings Chip
                filterChip(
                    title: "Recordings",
                    icon: "record.circle",
                    color: .red,
                    count: orchestrator.allDiscoveredMedia.filter { $0.mediaType == .screenRecording }.count,
                    bytes: orchestrator.allDiscoveredMedia.filter { $0.mediaType == .screenRecording }.reduce(0) { $0 + $1.fileSize },
                    isSelected: orchestrator.config.includeScreenRecordings
                ) {
                    orchestrator.config.includeScreenRecordings.toggle()
                    orchestrator.recalculatePendingQueue()
                }
            }

            // Sub-options & iCloud Storage Safety Callout
            HStack(spacing: 16) {
                // Strip motion option
                Toggle(isOn: Binding(
                    get: { orchestrator.config.stripMotionFromPhotos },
                    set: { val in
                        orchestrator.config.stripMotionFromPhotos = val
                        orchestrator.recalculatePendingQueue()
                    }
                )) {
                    Text("Strip Motion from Live Photos (Sync as static JPEG photos)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .toggleStyle(.checkbox)

                Spacer()

                // iCloud Safety Hint
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 11))
                    Text("Pixel backups in /sdcard/DCIM/iPhone/ are permanent. Deleting items from iCloud never deletes from Pixel.")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.green.opacity(0.08))
                .cornerRadius(6)
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(orchestrator.config.overwriteMode ? Color.orange.opacity(0.4) : Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func filterChip(
        title: String,
        icon: String,
        color: Color,
        count: Int,
        bytes: Int64,
        isSelected: Bool,
        onToggle: @escaping () -> Void
    ) -> some View {
        Button(action: onToggle) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? color : .secondary.opacity(0.4))
                    .font(.system(size: 12))

                Image(systemName: icon)
                    .foregroundColor(isSelected ? color : .secondary)
                    .font(.system(size: 11))

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                        .foregroundColor(isSelected ? .primary : .secondary)

                    HStack(spacing: 4) {
                        Text("\(count)")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        Text("•")
                            .font(.system(size: 7))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                            .font(.system(size: 9, design: .monospaced))
                    }
                    .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? color.opacity(0.12) : Color.primary.opacity(0.03))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? color.opacity(0.35) : Color.primary.opacity(0.05), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Configuration Card

    private var configurationCard: some View {
        HStack(spacing: 20) {
            // Batch Limit
            VStack(alignment: .leading, spacing: 6) {
                Text("Batch Size Limit")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)

                Picker("Batch Size", selection: $orchestrator.config.batchSizeLimitBytes) {
                    Text("2 GB").tag(Int64(2 * 1024 * 1024 * 1024))
                    Text("5 GB (Recommended)").tag(Int64(5 * 1024 * 1024 * 1024))
                    Text("10 GB").tag(Int64(10 * 1024 * 1024 * 1024))
                    Text("20 GB").tag(Int64(20 * 1024 * 1024 * 1024))
                    Text("Unlimited (All at Once)").tag(SyncConfiguration.unlimitedBatchSize)
                }
                .pickerStyle(.menu)
            }

            // Concurrency Streams
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Text("Parallel Streams (Download & USB)")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                    Text("(\(orchestrator.config.concurrentStreams)x)")
                        .font(.caption2.bold())
                        .foregroundColor(.blue)
                }

                HStack(spacing: 6) {
                    Picker("Preset", selection: Binding(
                        get: {
                            [1, 2, 4, 8, 16, 32, 64, 128].contains(orchestrator.config.concurrentStreams)
                                ? orchestrator.config.concurrentStreams
                                : -1
                        },
                        set: { val in
                            if val > 0 {
                                orchestrator.config.concurrentStreams = val
                            }
                        }
                    )) {
                        Text("1x").tag(1)
                        Text("2x").tag(2)
                        Text("4x (Default)").tag(4)
                        Text("8x (Fast)").tag(8)
                        Text("16x (Turbo)").tag(16)
                        Text("32x (Ultra)").tag(32)
                        Text("64x (Extreme)").tag(64)
                        Text("128x (Max)").tag(128)
                        Text("Custom...").tag(-1)
                    }
                    .pickerStyle(.menu)

                    TextField("Custom", value: $orchestrator.config.concurrentStreams, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 58)
                        .help("Enter custom number of parallel streams (e.g. 8, 16, 50)")
                }
            }

            Divider()

            // Live Photos Toggle
            Toggle(isOn: $orchestrator.config.combineLivePhotos) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Synthesize Motion Photos")
                        .font(.subheadline.bold())
                    Text("Combine Apple Live Photos into Google Motion Photos")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .toggleStyle(.checkbox)

            Spacer()
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.35))
        .cornerRadius(14)
    }

    // MARK: - Media Queue & Active Processing Dual Panes

    private var mediaQueueCard: some View {
        HStack(alignment: .top, spacing: 16) {
            // PANE 1: Currently Processing Items
            activeProcessingPane

            // PANE 2: Queued Media Items (Scrollable)
            queuedItemsPane
        }
    }

    // MARK: - Pane 1: Active Processing Items

    private var activeProcessingPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.horizontal.circle.fill")
                        .foregroundColor(orchestrator.state == .syncing ? .green : .secondary)
                        .font(.system(size: 14))

                    Text("Currently Processing")
                        .font(.system(size: 13, weight: .semibold))

                    if !orchestrator.activeProcessingItems.isEmpty {
                        Text("(\(orchestrator.activeProcessingItems.count))")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.blue)
                    }
                }

                Spacer()

                HStack(spacing: 8) {
                    Text("\(orchestrator.config.concurrentStreams)x Streams")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.06))
                        .cornerRadius(4)
                }
            }

            // Color Stage Legend
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Circle().fill(Color.blue).frame(width: 6, height: 6)
                    Text("Download").font(.system(size: 9)).foregroundColor(.secondary)
                }
                HStack(spacing: 4) {
                    Circle().fill(Color.orange).frame(width: 6, height: 6)
                    Text("Synthesis").font(.system(size: 9)).foregroundColor(.secondary)
                }
                HStack(spacing: 4) {
                    Circle().fill(Color.green).frame(width: 6, height: 6)
                    Text("USB Push").font(.system(size: 9)).foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.bottom, 2)

            Divider().opacity(0.3)

            if orchestrator.activeProcessingItems.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: orchestrator.state == .syncing ? "arrow.triangle.2.circlepath" : "tray")
                        .font(.system(size: 26))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text(orchestrator.state == .syncing ? "Prefetching next assets..." : "No Active Streams")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    Text(orchestrator.state == .syncing ? "Pipelined parallel stream engine active" : "Start sync to activate parallel streams.")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.7))
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(orchestrator.activeProcessingItems) { activeItem in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(spacing: 8) {
                                    Image(systemName: iconForMedia(activeItem.item.mediaType))
                                        .font(.system(size: 11))
                                        .foregroundColor(activeItem.item.isVideo ? .purple : .blue)
                                        .frame(width: 14)

                                    Text(activeItem.item.filename)
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .lineLimit(1)

                                    Spacer()

                                    // Stage Pill
                                    Text(activeItem.stage.badgeTitle)
                                        .font(.system(size: 8, weight: .bold))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1.5)
                                        .background(stageBackgroundColor(for: activeItem.stage))
                                        .foregroundColor(stageForegroundColor(for: activeItem.stage))
                                        .cornerRadius(4)

                                    Text(activeItem.item.formattedSize)
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }

                                // Colored Progress Bar
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(Color.primary.opacity(0.08))
                                            .frame(height: 5)

                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(stageGradient(for: activeItem.stage))
                                            .frame(width: max(8, geo.size.width * CGFloat(activeItem.progress)), height: 5)
                                            .animation(.linear(duration: 0.2), value: activeItem.progress)
                                    }
                                }
                                .frame(height: 5)

                                HStack {
                                    Text(activeItem.statusDetail)
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)

                                    Spacer()

                                    stageIcon(for: activeItem.stage)
                                        .font(.system(size: 9))
                                        .foregroundColor(stageForegroundColor(for: activeItem.stage))
                                }
                            }
                            .padding(8)
                            .background(Color(NSColor.controlBackgroundColor).opacity(0.45))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.primary.opacity(0.04), lineWidth: 1)
                            )
                        }
                    }
                    .padding(.trailing, 2)
                }
            }
        }
        .padding(14)
        .frame(height: 290)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    // MARK: - Pane 2: Queued Items (Scrollable)

    private var queuedItemsPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "list.bullet.rectangle.portrait.fill")
                        .foregroundColor(.blue)
                        .font(.system(size: 14))

                    Text("Queued Media")
                        .font(.system(size: 13, weight: .semibold))

                    Text("(\(orchestrator.pendingQueue.count))")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Spacer()

                HStack(spacing: 8) {
                    let totalQueuedBytes = orchestrator.pendingQueue.reduce(0) { $0 + $1.fileSize }
                    Text(ByteCountFormatter.string(fromByteCount: totalQueuedBytes, countStyle: .file))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)

                    Button(action: { orchestrator.recalculatePendingQueue() }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption2)
                    }
                    .buttonStyle(.borderless)
                }
            }

            Divider().opacity(0.3)

            if orchestrator.pendingQueue.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.green)
                    Text("Everything is Synced")
                        .font(.system(size: 13, weight: .semibold))
                    Text("No pending media waiting in queue.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(Array(orchestrator.pendingQueue.enumerated()), id: \.element.id) { index, item in
                            HStack(spacing: 8) {
                                Text("#\(index + 1)")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.secondary.opacity(0.7))
                                    .frame(width: 28, alignment: .leading)

                                Image(systemName: iconForMedia(item.mediaType))
                                    .font(.system(size: 11))
                                    .foregroundColor(.blue)
                                    .frame(width: 14)

                                Text(item.filename)
                                    .font(.system(size: 11, design: .monospaced))
                                    .lineLimit(1)

                                if item.isLivePhoto {
                                    Text("LIVE")
                                        .font(.system(size: 7, weight: .bold))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.yellow.opacity(0.2))
                                        .foregroundColor(.yellow)
                                        .cornerRadius(3)
                                } else if item.isVideo {
                                    Text("VIDEO")
                                        .font(.system(size: 7, weight: .bold))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.purple.opacity(0.2))
                                        .foregroundColor(.purple)
                                        .cornerRadius(3)
                                }

                                Spacer()

                                Text(item.formattedSize)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(Color.primary.opacity(0.02))
                            .cornerRadius(6)
                        }
                    }
                    .padding(.trailing, 2)
                }
            }
        }
        .padding(14)
        .frame(height: 290)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    // MARK: - Stage Visual Helpers

    private func stageBackgroundColor(for stage: TransferStage) -> Color {
        switch stage {
        case .downloading: return Color.blue.opacity(0.18)
        case .synthesizing: return Color.orange.opacity(0.18)
        case .transferring: return Color.green.opacity(0.18)
        case .completed: return Color.green.opacity(0.15)
        case .failed: return Color.red.opacity(0.15)
        case .queued: return Color.secondary.opacity(0.15)
        }
    }

    private func stageForegroundColor(for stage: TransferStage) -> Color {
        switch stage {
        case .downloading: return .blue
        case .synthesizing: return .orange
        case .transferring: return .green
        case .completed: return .green
        case .failed: return .red
        case .queued: return .secondary
        }
    }

    private func stageGradient(for stage: TransferStage) -> LinearGradient {
        switch stage {
        case .downloading:
            return LinearGradient(colors: [.blue, .cyan], startPoint: .leading, endPoint: .trailing)
        case .synthesizing:
            return LinearGradient(colors: [.yellow, .orange], startPoint: .leading, endPoint: .trailing)
        case .transferring:
            return LinearGradient(colors: [.green, .mint], startPoint: .leading, endPoint: .trailing)
        case .completed:
            return LinearGradient(colors: [.green, .mint], startPoint: .leading, endPoint: .trailing)
        case .failed:
            return LinearGradient(colors: [.red, .pink], startPoint: .leading, endPoint: .trailing)
        case .queued:
            return LinearGradient(colors: [.gray, .secondary], startPoint: .leading, endPoint: .trailing)
        }
    }

    @ViewBuilder
    private func stageIcon(for stage: TransferStage) -> some View {
        switch stage {
        case .downloading:
            Image(systemName: "icloud.and.arrow.down.fill")
        case .synthesizing:
            Image(systemName: "sparkles")
        case .transferring:
            Image(systemName: "bolt.horizontal.fill")
        case .completed:
            Image(systemName: "checkmark.circle.fill")
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
        case .queued:
            Image(systemName: "clock")
        }
    }

    private func iconForMedia(_ type: MediaType) -> String {
        switch type {
        case .photo: return "photo"
        case .video: return "video.fill"
        case .livePhoto: return "livephoto"
        case .screenshot: return "camera.viewfinder"
        case .screenRecording: return "record.circle"
        case .other: return "doc"
        }
    }

    // MARK: - Post-Sync Deletion Banner

    private var deletionBanner: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 28))
                .foregroundColor(.green)

            VStack(alignment: .leading, spacing: 2) {
                Text("Sync Complete: \(orchestrator.syncedInSession.count) Items Backed Up")
                    .font(.subheadline.bold())
                Text(orchestrator.selectedSourceType == .icloudPhotos
                    ? "Safe on Pixel & Google Photos. Launch Tinder Triage to review and delete from iCloud to reclaim storage."
                    : "All media has been pushed to your Pixel and will be uploaded to Google Photos at original quality.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if orchestrator.selectedSourceType == .icloudPhotos {
                Button(action: {
                    orchestrator.populateTriageQueue()
                    vm.showingSwipeClean = true
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "hand.draw.fill")
                        Text("iCloud Cleaner (Triage)")
                            .font(.caption.bold())
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
            } else {
                Button(action: {
                    Task {
                        try? await orchestrator.deleteSessionItemsFromiPhone()
                    }
                }) {
                    Text("Free up iPhone Storage")
                        .font(.caption.bold())
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding(14)
        .background(Color.green.opacity(0.1))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.green.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Bottom Action Bar

    private var bottomActionBar: some View {
        VStack(spacing: 10) {
            if orchestrator.state == .syncing {
                VStack(spacing: 6) {
                    HStack {
                        Text(orchestrator.progress.statusDescription)
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        let speedText = orchestrator.progress.formattedSpeed
                        let etaText = orchestrator.progress.formattedETA
                        let metrics = etaText.isEmpty ? speedText : "\(speedText) • \(etaText)"
                        Text("\(orchestrator.progress.currentItemIndex) / \(orchestrator.progress.totalItems) (\(metrics))")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    ProgressView(value: orchestrator.progress.fractionCompleted)
                        .tint(.blue)
                }
            }

            let skippedCount = max(orchestrator.skippedItems.count, orchestrator.skippedFailedItems.count)
            if skippedCount > 0 && orchestrator.state != .syncing {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("\(skippedCount) items skipped due to network/timeout.")
                        .font(.caption.bold())
                    Spacer()
                    Toggle("Auto-retry on finish", isOn: $orchestrator.autoRetrySkippedAtEnd)
                        .toggleStyle(.checkbox)
                        .font(.caption2)
                    Button("View Details") {
                        vm.showingSkippedModal = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    Button("Retry All (\(skippedCount))") {
                        orchestrator.retryFailedItems()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.small)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.12))
                .cornerRadius(8)
            }

            HStack {
                if let err = orchestrator.lastErrorMessage {
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.red)
                } else if orchestrator.state == .pausedForStorage {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                        Text("Paused: Free up space on Google Photos on Pixel to continue.")
                            .font(.caption.bold())
                            .foregroundColor(.yellow)
                    }
                } else if orchestrator.selectedSourceType == .usbIPhone && orchestrator.connectedIPhone?.isLocked == true {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundColor(.orange)
                        Text("iPhone is passcode locked. Unlock screen to access photos.")
                            .font(.caption.bold())
                            .foregroundColor(.orange)
                    }
                }

                Spacer()

                if orchestrator.state == .syncing {
                    Button("Cancel Sync", role: .cancel) {
                        orchestrator.cancelSync()
                    }
                    .buttonStyle(.bordered)
                } else {
                    let isLocked = (orchestrator.selectedSourceType == .usbIPhone && orchestrator.connectedIPhone?.isLocked == true)
                    let sourceReady = (orchestrator.selectedSourceType == .icloudPhotos)
                        ? (orchestrator.photoKitManager.authorizationStatus == .authorized || orchestrator.photoKitManager.authorizationStatus == .limited)
                        : (orchestrator.connectedIPhone != nil && !isLocked)
                    let canSync = sourceReady && (orchestrator.connectedPixel?.isAuthorized == true) && !orchestrator.pendingQueue.isEmpty

                    Button(action: {
                        Task {
                            try? await orchestrator.startSync()
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: isLocked ? "lock.fill" : "arrow.right.circle.fill")
                            Text(isLocked ? "Unlock iPhone to Sync" : "Start Sync to Pixel")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isLocked ? .orange : .blue)
                    .disabled(!canSync)
                }
            }
        }
    }
}

// MARK: - Skipped Items Modal

public struct SkippedItemsModalView: View {
    @ObservedObject var orchestrator: SyncOrchestrator
    @ObservedObject var vm: DashboardViewModel
    var onDismiss: () -> Void

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        let count = max(orchestrator.skippedItems.count, orchestrator.skippedFailedItems.count)
                        Text("Skipped Media Items (\(count))")
                            .font(.headline.bold())
                    }
                    Text("These photos/videos encountered iCloud network stalls or CloudKit timeouts.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(18)

            Divider()

            // List of Skipped Items
            if orchestrator.skippedItems.isEmpty && orchestrator.skippedFailedItems.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.green)
                    Text("No Skipped Items")
                        .font(.headline)
                    Text("All items were transferred or no skipped items remain.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        if !orchestrator.skippedItems.isEmpty {
                            ForEach(orchestrator.skippedItems) { item in
                                HStack(spacing: 12) {
                                    Image(systemName: item.item.isVideo ? "video.fill" : (item.item.isLivePhoto ? "livephoto" : "photo.fill"))
                                        .foregroundColor(item.item.isVideo ? .purple : .blue)
                                        .font(.title3)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(item.item.filename)
                                            .font(.subheadline.bold())
                                        Text(item.reason)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                            .lineLimit(2)
                                    }

                                    Spacer()

                                    Text(item.item.formattedSize)
                                        .font(.caption.monospaced())
                                        .foregroundColor(.secondary)
                                }
                                .padding(10)
                                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                                .cornerRadius(8)
                            }
                        } else {
                            ForEach(orchestrator.skippedFailedItems) { item in
                                HStack(spacing: 12) {
                                    Image(systemName: item.isVideo ? "video.fill" : (item.isLivePhoto ? "livephoto" : "photo.fill"))
                                        .foregroundColor(item.isVideo ? .purple : .blue)
                                        .font(.title3)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(item.filename)
                                            .font(.subheadline.bold())
                                        Text("iCloud streaming stall or timeout")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()

                                    Text(item.formattedSize)
                                        .font(.caption.monospaced())
                                        .foregroundColor(.secondary)
                                }
                                .padding(10)
                                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                                .cornerRadius(8)
                            }
                        }
                    }
                    .padding(16)
                }
                .frame(maxHeight: 300)
            }

            Divider()

            // Footer Actions
            HStack {
                Toggle("Auto-retry on batch completion", isOn: $orchestrator.autoRetrySkippedAtEnd)
                    .font(.caption)

                Spacer()

                Button(vm.copiedNotice ? "Copied!" : "Copy Report") {
                    let report = orchestrator.exportSkippedReport()
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report, forType: .string)
                    vm.copiedNotice = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        vm.copiedNotice = false
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                let count = max(orchestrator.skippedItems.count, orchestrator.skippedFailedItems.count)
                Button("Retry All (\(count))") {
                    orchestrator.retryFailedItems()
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .controlSize(.small)
                .disabled(count == 0)
            }
            .padding(16)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.4))
        }
        .frame(width: 580)
    }
}
