import SwiftUI
import CoreSyncEngine

public final class DashboardViewModel: ObservableObject {
    @Published public var showingOnboarding: Bool = false
    @Published public var showingWirelessModal: Bool = false
    @Published public var showingDeleteConfirmation: Bool = false
    @Published public var selectedFilter: String = "All"
    @Published public var pairingVM: PairingViewModel = PairingViewModel()

    public init() {}
}

public struct MainDashboardView: View {
    @ObservedObject var orchestrator: SyncOrchestrator
    @ObservedObject var vm: DashboardViewModel

    public init(orchestrator: SyncOrchestrator, vm: DashboardViewModel? = nil) {
        self.orchestrator = orchestrator
        self.vm = vm ?? DashboardViewModel()
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

                OnboardingView(orchestrator: orchestrator, onDismiss: { vm.showingOnboarding = false })
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
        HStack(spacing: 16) {
            // iPhone Device Card
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
                        Text(orchestrator.connectedIPhone?.name ?? "iPhone (Not Connected)")
                            .font(.system(size: 14, weight: .semibold))
                        if orchestrator.connectedIPhone != nil {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 7, height: 7)
                        }
                    }

                    if let phone = orchestrator.connectedIPhone {
                        Text("\(phone.totalMediaCount) camera items • \(phone.isLocked ? "Locked" : "Unlocked")")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    } else {
                        Text("Plug in via USB & tap 'Trust This Computer'")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(orchestrator.connectedIPhone != nil ? Color.green.opacity(0.3) : Color.primary.opacity(0.06), lineWidth: 1)
            )

            // Google Pixel Device Card
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
                        Text(orchestrator.connectedPixel?.model ?? "Pixel (Not Connected)")
                            .font(.system(size: 14, weight: .semibold))
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
                Spacer()
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(orchestrator.connectedPixel != nil ? Color.green.opacity(0.3) : Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
    }

    // MARK: - Storage Visualizer Card

    private var storageCard: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Transfer Pipeline")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Extracting from iPhone → Google Motion Photo packaging → /sdcard/DCIM/iPhone/")
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

            Divider()

            // Live Photos Toggle
            Toggle(isOn: $orchestrator.config.combineLivePhotos) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Combine Live Photos")
                        .font(.subheadline.bold())
                    Text("Synthesize Google Motion Photos")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .toggleStyle(.checkbox)

            Divider()

            // Screenshots Toggle
            Toggle(isOn: $orchestrator.config.includeScreenshots) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Screenshots")
                        .font(.subheadline.bold())
                    Text("Include PNG screenshots")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .toggleStyle(.checkbox)
            .onChange(of: orchestrator.config.includeScreenshots) {
                orchestrator.recalculatePendingQueue()
            }

            Divider()

            // Videos Toggle
            Toggle(isOn: $orchestrator.config.includeVideos) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Videos")
                        .font(.subheadline.bold())
                    Text("Include 4K/HDR videos")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .toggleStyle(.checkbox)
            .onChange(of: orchestrator.config.includeVideos) {
                orchestrator.recalculatePendingQueue()
            }

            Spacer()
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.35))
        .cornerRadius(14)
    }

    // MARK: - Media Queue Card

    private var mediaQueueCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Pending Media Queue (\(orchestrator.pendingQueue.count))")
                    .font(.system(size: 14, weight: .semibold))

                Spacer()

                HStack(spacing: 8) {
                    Button(action: { orchestrator.recalculatePendingQueue() }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
            }

            if orchestrator.pendingQueue.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.green)
                    Text("Everything is Synced")
                        .font(.headline)
                    Text("No pending photos or videos found on your iPhone.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else {
                VStack(spacing: 6) {
                    ForEach(orchestrator.pendingQueue.prefix(6)) { item in
                        HStack(spacing: 12) {
                            Image(systemName: iconForMedia(item.mediaType))
                                .foregroundColor(.blue)
                                .frame(width: 20)

                            Text(item.filename)
                                .font(.system(size: 12, weight: .medium, design: .monospaced))

                            if item.isLivePhoto {
                                Text("LIVE")
                                    .font(.system(size: 8, weight: .bold))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.yellow.opacity(0.2))
                                    .foregroundColor(.yellow)
                                    .cornerRadius(3)
                            }

                            Spacer()

                            Text(item.formattedSize)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(Color.primary.opacity(0.02))
                        .cornerRadius(6)
                    }

                    if orchestrator.pendingQueue.count > 6 {
                        Text("+ \(orchestrator.pendingQueue.count - 6) more items in queue")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
                }
            }
        }
        .padding(18)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
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
                Text("All media has been pushed to your Pixel and will be uploaded to Google Photos at original quality.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

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
                        Text("\(orchestrator.progress.currentItemIndex) / \(orchestrator.progress.totalItems) (\(orchestrator.progress.formattedSpeed))")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    ProgressView(value: orchestrator.progress.fractionCompleted)
                        .tint(.blue)
                }
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
                }

                Spacer()

                if orchestrator.state == .syncing {
                    Button("Cancel Sync", role: .cancel) {
                        orchestrator.cancelSync()
                    }
                    .buttonStyle(.bordered)
                } else {
                    let canSync = (orchestrator.connectedIPhone != nil && orchestrator.connectedPixel?.isAuthorized == true && !orchestrator.pendingQueue.isEmpty)

                    Button(action: {
                        Task {
                            try? await orchestrator.startSync()
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.right.circle.fill")
                            Text("Start Sync to Pixel")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .disabled(!canSync)
                }
            }
        }
    }
}
