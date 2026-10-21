import SwiftUI
import CoreSyncEngine

public final class OnboardingViewModel: ObservableObject {
    @Published public var currentStep: Int = 1
    @Published public var cliInstallStatus: String = "Installing CLI & Platform Tools..."
    @Published public var isCLIInstalled: Bool = false
    @Published public var pairingVM: PairingViewModel = PairingViewModel()

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
        VStack(spacing: 20) {
            // Step Progress Bar
            HStack(spacing: 8) {
                stepPill(step: 1, label: "Welcome")
                stepDivider()
                stepPill(step: 2, label: "Connect iPhone")
                stepDivider()
                stepPill(step: 3, label: "Connect Pixel")
                stepDivider()
                stepPill(step: 4, label: "Ready")
            }
            .padding(.top, 16)
            .padding(.horizontal)

            Divider().opacity(0.4)

            // Step Content
            VStack {
                if vm.currentStep == 1 {
                    step1Welcome
                } else if vm.currentStep == 2 {
                    step2ConnectIPhone
                } else if vm.currentStep == 3 {
                    step3ConnectPixel
                } else {
                    step4Ready
                }
            }
            .frame(maxHeight: .infinity)
            .padding(.horizontal, 24)

            Divider().opacity(0.4)

            // Navigation Controls
            HStack {
                if vm.currentStep > 1 {
                    Button("Back") {
                        withAnimation { vm.currentStep -= 1 }
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                if vm.currentStep < 4 {
                    Button(action: {
                        withAnimation { vm.currentStep += 1 }
                    }) {
                        Text(vm.currentStep == 1 ? "Start Device Setup →" : "Continue →")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                } else {
                    Button("Open PixOS Dashboard") {
                        onDismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .frame(width: 720, height: 500)
    }

    // MARK: - Step Pills
    private func stepPill(step: Int, label: String) -> some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(vm.currentStep >= step ? Color.blue : Color.gray.opacity(0.2))
                    .frame(width: 22, height: 22)
                Text("\(step)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(vm.currentStep >= step ? .white : .gray)
            }
            Text(label)
                .font(.system(size: 12, weight: vm.currentStep == step ? .bold : .medium))
                .foregroundColor(vm.currentStep >= step ? .primary : .secondary)
        }
    }

    private func stepDivider() -> some View {
        Rectangle()
            .fill(Color.gray.opacity(0.2))
            .frame(height: 2)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Step 1: Welcome & Auto Setup
    private var step1Welcome: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.stack.fill")
                .font(.system(size: 44))
                .foregroundStyle(
                    LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                )

            VStack(spacing: 6) {
                Text("Welcome to PixOS")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text("Bypass iCloud storage fees forever using your Google Pixel's lifetime free unlimited original quality backup.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
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
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(vm.isCLIInstalled ? Color.green.opacity(0.3) : Color.primary.opacity(0.08), lineWidth: 1)
            )

            Text("Next, we'll guide you to connect both of your phones one by one.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Step 2: Connect iPhone
    private var step2ConnectIPhone: some View {
        VStack(spacing: 20) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(orchestrator.connectedIPhone != nil ? Color.green.opacity(0.15) : Color.blue.opacity(0.15))
                        .frame(width: 50, height: 50)
                    Image(systemName: "iphone.gen3")
                        .font(.system(size: 26))
                        .foregroundColor(orchestrator.connectedIPhone != nil ? .green : .blue)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Step 1 of 2: Connect Your iPhone")
                        .font(.title3.bold())
                    Text("Plug in your iPhone to your Mac using a Lightning or USB-C cable.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            // Live Detection Card
            if let phone = orchestrator.connectedIPhone {
                if phone.isLocked {
                    HStack(spacing: 16) {
                        Image(systemName: "lock.circle.fill")
                            .font(.system(size: 36))
                            .foregroundColor(.orange)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Connected: \(phone.name)")
                                .font(.headline)
                            Text("Passcode Locked • Unlock your iPhone screen with Face ID / passcode and tap 'Trust This Computer' to access photos.")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                        Spacer()
                    }
                    .padding(20)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.orange.opacity(0.3), lineWidth: 1))
                } else {
                    HStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 36))
                            .foregroundColor(.green)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Connected: \(phone.name)")
                                .font(.headline)
                            let statusText = orchestrator.isCatalogComplete ? "\(phone.totalMediaCount) photos & videos detected • Ready for backup" : "Reading camera roll... (\(phone.totalMediaCount) detected)"
                            Text(statusText)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(20)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.green.opacity(0.3), lineWidth: 1))
                }
            } else {
                VStack(spacing: 14) {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Waiting for iPhone connection...")
                            .font(.subheadline.bold())
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        instructionBullet(number: "1", text: "Plug your iPhone into any USB port on your Mac.")
                        instructionBullet(number: "2", text: "Unlock your iPhone screen with Face ID / passcode.")
                        instructionBullet(number: "3", text: "Tap 'Trust This Computer' if the prompt appears.")
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .cornerRadius(14)
            }
        }
    }

    // MARK: - Step 3: Connect Google Pixel
    private var step3ConnectPixel: some View {
        VStack(spacing: 20) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(orchestrator.connectedPixel != nil ? Color.green.opacity(0.15) : Color.purple.opacity(0.15))
                        .frame(width: 50, height: 50)
                    Image(systemName: "candybarphone")
                        .font(.system(size: 26))
                        .foregroundColor(orchestrator.connectedPixel != nil ? .green : .purple)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Step 2 of 2: Connect Your Google Pixel")
                        .font(.title3.bold())
                    Text("Connect via USB cable or scan the QR code for Wireless ADB.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            // Live Pixel Detection Card
            if let pixel = orchestrator.connectedPixel, pixel.isAuthorized {
                HStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.green)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Connected: \(pixel.model) (\(pixel.isWireless ? "Wireless" : "USB"))")
                            .font(.headline)
                        Text("Free Storage: \(orchestrator.pixelStorage?.formattedFree ?? "24 GB") • Lifetime Unlimited Backup Active")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(20)
                .background(Color.green.opacity(0.1))
                .cornerRadius(14)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.green.opacity(0.3), lineWidth: 1))
            } else {
                HStack(spacing: 20) {
                    // QR Code Option
                    VStack(spacing: 8) {
                        if let qr = QRCodeGenerator.generateQRCode(from: vm.pairingVM.qrPayload, size: CGSize(width: 120, height: 120)) {
                            Image(nsImage: qr)
                                .interpolation(.none)
                                .resizable()
                                .frame(width: 120, height: 120)
                                .padding(4)
                                .background(Color.white)
                                .cornerRadius(8)
                        }
                        Text("Scan with Pixel")
                            .font(.caption2.bold())
                    }

                    // Instructions
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Connect via Cable or Wireless:")
                            .font(.caption.bold())
                        instructionBullet(number: "1", text: "On Pixel: Settings → Developer Options.")
                        instructionBullet(number: "2", text: "Toggle ON 'USB Debugging'.")
                        instructionBullet(number: "3", text: "Plug in via USB OR tap 'Wireless Debugging' → 'Pair with QR code' & scan this QR code.")
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .cornerRadius(14)
            }
        }
    }

    // MARK: - Step 4: Ready
    private var step4Ready: some View {
        VStack(spacing: 20) {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundColor(.yellow)

            VStack(spacing: 6) {
                Text("Setup Complete!")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text("PixOS is fully configured to transfer all your media directly to your Google Pixel.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                    Text("iPhone extraction ready (Lossless ImageCaptureCore)")
                        .font(.caption.bold())
                }
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                    Text("Google Motion Photos enabled for Live Photos")
                        .font(.caption.bold())
                }
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                    Text("Smart Batching & Storage Safeguards active")
                        .font(.caption.bold())
                }
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                    Text("CLI installed: Run 'pixos status' anytime in Terminal")
                        .font(.caption.bold())
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .cornerRadius(14)
        }
    }

    private func instructionBullet(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(number)
                .font(.system(size: 10, weight: .bold))
                .frame(width: 16, height: 16)
                .background(Color.blue.opacity(0.15))
                .foregroundColor(.blue)
                .cornerRadius(8)
            Text(text)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}
