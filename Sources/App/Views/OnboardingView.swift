import SwiftUI
import CoreSyncEngine

public final class OnboardingViewModel: ObservableObject {
    @Published public var currentStep: Int = 1
    @Published public var cliInstallStatus: String = "Installing CLI & Platform Tools..."
    @Published public var isCLIInstalled: Bool = false
    @Published public var pairingVM: PairingViewModel = PairingViewModel()
    @Published public var databaseResetMessage: String? = nil

    public init() {
        performCLIInstall()
    }

    public func performCLIInstall() {
        let result = CLIInstaller.installCLITools()
        self.isCLIInstalled = result.success
        self.cliInstallStatus = result.success 
            ? "✔ 'pixos' CLI & Platform Tools automatically installed to system."
            : result.message
    }
}

public struct OnboardingView: View {
    @ObservedObject var orchestrator: SyncOrchestrator
    @ObservedObject var vm: OnboardingViewModel
    var onDismiss: () -> Void

    public init(orchestrator: SyncOrchestrator? = nil, vm: OnboardingViewModel? = nil, onDismiss: @escaping () -> Void = {}) {
        self.orchestrator = orchestrator ?? SyncOrchestrator()
        self.vm = vm ?? OnboardingViewModel()
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 16) {
            // Header Tabs
            HStack(spacing: 6) {
                stepTab(step: 1, label: "Overview", icon: "sparkles")
                stepTab(step: 2, label: "iCloud Setup", icon: "icloud.fill")
                stepTab(step: 3, label: "iPhone (USB)", icon: "iphone.gen3")
                stepTab(step: 4, label: "Google Pixel", icon: "candybarphone")
                stepTab(step: 5, label: "Metadata & Cleaner", icon: "hand.draw.fill")

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close Guide")
            }
            .padding(.top, 16)
            .padding(.horizontal, 20)

            Divider().opacity(0.3)

            // Step Content
            ScrollView {
                VStack {
                    switch vm.currentStep {
                    case 1: step1Overview
                    case 2: step2ICloudSetup
                    case 3: step3IPhoneSetup
                    case 4: step4PixelSetup
                    case 5: step5MetadataAndCleaner
                    default: step1Overview
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 8)
            }
            .frame(maxHeight: .infinity)

            Divider().opacity(0.3)

            // Navigation Controls
            HStack {
                if vm.currentStep > 1 {
                    Button(action: { withAnimation { vm.currentStep -= 1 } }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                if vm.currentStep < 5 {
                    Button(action: { withAnimation { vm.currentStep += 1 } }) {
                        HStack(spacing: 4) {
                            Text("Next Step")
                            Image(systemName: "chevron.right")
                        }
                        .font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                } else {
                    Button("Done — Back to Dashboard") {
                        onDismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .frame(width: 780, height: 560)
    }

    // MARK: - Step Tabs
    private func stepTab(step: Int, label: String, icon: String) -> some View {
        Button(action: { withAnimation { vm.currentStep = step } }) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(label)
                    .font(.system(size: 12, weight: vm.currentStep == step ? .bold : .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(vm.currentStep == step ? Color.blue.opacity(0.18) : Color.primary.opacity(0.04))
            .foregroundColor(vm.currentStep == step ? .blue : .secondary)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 1: Overview & Auto Setup
    private var step1Overview: some View {
        VStack(spacing: 18) {
            Image(systemName: "infinity")
                .font(.system(size: 42, weight: .bold))
                .foregroundStyle(
                    LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                )

            VStack(spacing: 6) {
                Text("PixOS v1.6.0 Master Guide")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text("Bypass iCloud storage fees forever using Google Pixel's lifetime free unlimited original quality backup.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Automatic Platform Tools & CLI Setup Status
            HStack(spacing: 12) {
                Image(systemName: vm.isCLIInstalled ? "checkmark.circle.fill" : "gearshape.2.fill")
                    .foregroundColor(vm.isCLIInstalled ? .green : .blue)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Automated System Setup")
                        .font(.caption.bold())
                    Text(vm.cliInstallStatus)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(vm.isCLIInstalled ? Color.green.opacity(0.3) : Color.primary.opacity(0.08), lineWidth: 1)
            )

            // Architecture Highlights
            VStack(alignment: .leading, spacing: 10) {
                featureRow(icon: "icloud.and.arrow.down", title: "Dual-Source Pipeline", description: "Source directly from iCloud Photos CDN on demand, or plug your iPhone in via USB.")
                featureRow(icon: "internaldrive", title: "Zero-Disk-Bloat Micro-Staging", description: "Streams each file, packages it, pushes to Pixel, and immediately deletes it from your Mac SSD.")
                featureRow(icon: "photo.badge.checkmark", title: "100% Lossless Metadata & Edits", description: "Preserves EXIF, edits, Live Photo Google Motion Photos, and original timestamps on Android.")
                featureRow(icon: "hand.draw", title: "Tinder-Style iCloud Cleaner", description: "Swipe right to keep or left to purge from iCloud, reclaiming paid cloud storage once backed up to Pixel.")
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
            .cornerRadius(14)
        }
    }

    // MARK: - Step 2: iCloud Photos Setup
    private var step2ICloudSetup: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "icloud.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Setting Up Direct iCloud Streaming")
                        .font(.title3.bold())
                    Text("How to connect your Mac to your 80,000+ iCloud photos without filling your Mac SSD.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                guideStepCard(
                    number: "1",
                    title: "Set as 'System Photo Library' (Mandatory for macOS)",
                    body: "Apple's cloud daemon strictly requires your Photos library to be the System Photo Library.\n• Open Photos app → Press Cmd+, (Photos > Settings)\n• In General tab: Click 'Use as System Photo Library' (until it becomes greyed out)."
                )

                guideStepCard(
                    number: "2",
                    title: "Enable iCloud Photos with 'Optimize Mac Storage'",
                    body: "• In Photos Settings, click the iCloud tab.\n• Check [✓] iCloud Photos.\n• CRUCIAL: Choose 'Optimize Mac Storage' (NOT Download Originals).\nThis downloads only lightweight metadata/thumbnails (~megabytes), while PixOS streams full originals on demand!"
                )

                guideStepCard(
                    number: "3",
                    title: "Grant macOS Privacy & Security Permissions",
                    body: "• Open System Settings > Privacy & Security > Photos.\n• Ensure PixOS has 'Full Access' enabled."
                )

                guideStepCard(
                    number: "4",
                    title: "Live Cloud Indexing",
                    body: "macOS will display 'Syncing with iCloud...' at the bottom of the Photos library. PixOS monitors this live and automatically picks up new photos as they arrive in real time."
                )
            }

            HStack(spacing: 12) {
                Button(action: { orchestrator.photoKitManager.openMacPhotos() }) {
                    Label("Open Mac Photos App", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button(action: { orchestrator.photoKitManager.openPrivacySettings() }) {
                    Label("Privacy & Security Settings", systemImage: "lock.shield")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Step 3: iPhone USB Setup
    private var step3IPhoneSetup: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "iphone.gen3")
                    .font(.system(size: 24))
                    .foregroundColor(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("iPhone Direct USB Connection")
                        .font(.title3.bold())
                    Text("Fast hardware-level extraction using native ImageCaptureCore over USB cable.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                guideStepCard(
                    number: "1",
                    title: "Cable Connection & Screen Unlock",
                    body: "• Plug your iPhone into any USB-C / USB-A port on your Mac using a verified cable.\n• Unlock your iPhone screen using Face ID, Touch ID, or Passcode."
                )

                guideStepCard(
                    number: "2",
                    title: "Tap 'Trust This Computer'",
                    body: "• If prompted on your iPhone screen, tap 'Trust This Computer' and enter your device passcode.\n• PixOS communicates directly with iOS hardware (zero drivers, zero jailbreak needed)."
                )

                guideStepCard(
                    number: "3",
                    title: "Understanding 'Optimize iPhone Storage'",
                    body: "If your iPhone has 'Optimize iPhone Storage' turned on in iOS Settings > Photos, full resolution originals reside in iCloud while only low-res thumbnails stay on phone flash.\n• If PixOS shows only a small number of items, switch source to 'iCloud / Mac Photos' to stream the full 80,000+ library directly!"
                )
            }
        }
    }

    // MARK: - Step 4: Google Pixel Setup
    private var step4PixelSetup: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "candybarphone")
                    .font(.system(size: 24))
                    .foregroundColor(.purple)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Google Pixel Setup (USB & Wireless ADB)")
                        .font(.title3.bold())
                    Text("Prepare your Pixel for automated photo ingestion and unlimited original backup.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                guideStepCard(
                    number: "1",
                    title: "Enable Developer Options & USB Debugging",
                    body: "• On your Pixel: Go to Settings > About phone → Tap 'Build number' 7 times.\n• Go to Settings > System > Developer options.\n• Turn ON 'USB Debugging'."
                )

                guideStepCard(
                    number: "2",
                    title: "Connect via USB or Wireless ADB",
                    body: "• USB: Plug Pixel into Mac. Tap 'Always allow from this computer' on Pixel screen.\n• Wireless ADB: Click 'Wireless ADB' in PixOS header and scan the QR code with your Pixel's Developer Options > Wireless Debugging screen."
                )

                guideStepCard(
                    number: "3",
                    title: "Where Photos Go & Google Photos Backup",
                    body: "• PixOS pushes all photos to /sdcard/DCIM/iPhone/ on your Pixel.\n• Triggers Android's MediaScanner so photos appear instantly in Google Photos.\n• Google Photos automatically backs them up at 100% original quality for free forever (OG Pixel)."
                )
            }
        }
    }

    // MARK: - Step 5: Metadata & Cleaner
    private var step5MetadataAndCleaner: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "hand.draw.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Metadata Preservation & iCloud Cleaner")
                        .font(.title3.bold())
                    Text("Zero data loss, Google Motion Photos, and reclaiming paid cloud storage.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                guideStepCard(
                    number: "1",
                    title: "100% Edits & EXIF Preservation",
                    body: "• PixOS prioritizes full-resolution edited/adjusted versions (crops, filters, portrait depth).\n• All EXIF metadata (camera, lens, GPS coordinates, ISO, shutter speed) is preserved untouched.\n• Timestamps are synced to Android via 'touch -t', ensuring chronologically perfect sorting in Google Photos."
                )

                guideStepCard(
                    number: "2",
                    title: "Apple Live Photos → Google Motion Photos",
                    body: "• Live Photos contain a still photo + 3-second companion MOV.\n• PixOS injects official Google Camera XMP metadata (Camera:MotionPhoto=1) and multiplexes both into a single Google Motion Photo that animates natively in Google Photos."
                )

                guideStepCard(
                    number: "3",
                    title: "Tinder-Style iCloud Swipe Triage",
                    body: "• Once media is safely backed up to your Pixel, open 'iCloud Cleaner'.\n• Swipe Right (or → key / K): Keep in iCloud.\n• Swipe Left (or ← key / D): Purge from iCloud to reclaim storage.\n• Undo (Cmd+Z / Z): Instant rollback.\n• Batched Apple Confirmation: Triggers macOS security prompt only once for the entire batch."
                )
            }

            // Database Reset Option
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Database Management")
                        .font(.caption.bold())
                    Text(vm.databaseResetMessage ?? "Want to start over as if no items were synced? Reset sync history below.")
                        .font(.caption2)
                        .foregroundColor(vm.databaseResetMessage != nil ? .green : .secondary)
                }
                Spacer()
                Button(vm.databaseResetMessage != nil ? "Cleared ✔" : "Reset Sync History") {
                    orchestrator.resetSyncDatabase()
                    vm.databaseResetMessage = "✔ All records cleared! Database is clean (0 items synced)."
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(12)
            .background(vm.databaseResetMessage != nil ? Color.green.opacity(0.08) : Color.red.opacity(0.06))
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(vm.databaseResetMessage != nil ? Color.green.opacity(0.3) : Color.red.opacity(0.2), lineWidth: 1))
        }
    }

    // MARK: - Helpers
    private func guideStepCard(number: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 22, height: 22)
                .background(Color.blue)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                Text(body)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
        .cornerRadius(10)
    }

    private func featureRow(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .font(.system(size: 14))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                Text(description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
    }
}
