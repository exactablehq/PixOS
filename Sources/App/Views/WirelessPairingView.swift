import SwiftUI
import CoreSyncEngine
import AppKit

public final class PairingViewModel: ObservableObject {
    @Published public var selectedTab: Int = 0 // 0: QR Code, 1: Pairing Code, 2: Direct IP
    @Published public var ipAddress: String = ""
    @Published public var pairingPort: String = ""
    @Published public var connectPort: String = "5555"
    @Published public var pairingCode: String = ""
    @Published public var isConnecting: Bool = false
    @Published public var statusMessage: String? = nil
    @Published public var isSuccess: Bool = false

    public let qrPassword = String(Int.random(in: 100000...999999))
    public let hostName = Host.current().localizedName ?? "Mac"

    public var qrPayload: String {
        "WIFI:T:ADB;S:PixOS-\(hostName);P:\(qrPassword);;"
    }

    public init() {}
}

public struct WirelessPairingView: View {
    let orchestrator: SyncOrchestrator
    @ObservedObject var vm: PairingViewModel
    var onDismiss: () -> Void

    public init(orchestrator: SyncOrchestrator, vm: PairingViewModel, onDismiss: @escaping () -> Void) {
        self.orchestrator = orchestrator
        self.vm = vm
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "wifi")
                    .font(.system(size: 26))
                    .foregroundColor(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Wireless ADB Connection")
                        .font(.title3.bold())
                    Text("Pair your Google Pixel without keeping it tethered via USB cable.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            // Tab Selector
            Picker("Mode", selection: $vm.selectedTab) {
                Text("Scan QR Code").tag(0)
                Text("6-Digit Pairing Code").tag(1)
                Text("Direct IP:Port").tag(2)
            }
            .pickerStyle(.segmented)

            // Tab Content
            if vm.selectedTab == 0 {
                qrCodeTab
            } else if vm.selectedTab == 1 {
                pairingCodeTab
            } else {
                directIPTab
            }

            if let msg = vm.statusMessage {
                HStack {
                    Image(systemName: vm.isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(vm.isSuccess ? .green : .red)
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(vm.isSuccess ? .green : .red)
                }
            }

            // Bottom Buttons
            HStack {
                Button("Close") {
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                if vm.selectedTab != 0 {
                    Button(action: performPairOrConnect) {
                        if vm.isConnecting {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(vm.selectedTab == 1 ? "Pair & Connect" : "Connect")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(vm.ipAddress.isEmpty || vm.isConnecting)
                }
            }
        }
        .padding(24)
        .frame(width: 500)
    }

    // MARK: - QR Code Tab
    private var qrCodeTab: some View {
        VStack(spacing: 14) {
            if let qrImage = QRCodeGenerator.generateQRCode(from: vm.qrPayload, size: CGSize(width: 170, height: 170)) {
                Image(nsImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 170, height: 170)
                    .padding(8)
                    .background(Color.white)
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.15), radius: 8)
            }

            VStack(spacing: 4) {
                Text("How to scan from your Google Pixel:")
                    .font(.caption.bold())
                Text("1. Open Settings → System → Developer Options\n2. Tap Wireless Debugging (toggle ON)\n3. Tap 'Pair device with QR code' & scan this screen")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
    }

    // MARK: - Pairing Code Tab
    private var pairingCodeTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("On your Pixel, tap 'Pair device with pairing code':")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("IP Address")
                        .font(.caption2.bold())
                    TextField("192.168.1.150", text: $vm.ipAddress)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Pairing Port")
                        .font(.caption2.bold())
                    TextField("e.g. 37891", text: $vm.pairingPort)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("6-Digit Wi-Fi Pairing Code")
                    .font(.caption2.bold())
                TextField("e.g. 849201", text: $vm.pairingCode)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(12)
    }

    // MARK: - Direct IP Tab
    private var directIPTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connect directly to an already paired device or standard ADB port:")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Device IP Address")
                        .font(.caption2.bold())
                    TextField("192.168.1.150", text: $vm.ipAddress)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Port")
                        .font(.caption2.bold())
                    TextField("5555", text: $vm.connectPort)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(12)
    }

    private func performPairOrConnect() {
        vm.isConnecting = true
        vm.statusMessage = nil

        Task {
            do {
                if vm.selectedTab == 1 {
                    // Pair code tab
                    let port = Int(vm.pairingPort) ?? 5555
                    let paired = try await orchestrator.adbClient.pairWireless(ip: vm.ipAddress, port: port, code: vm.pairingCode)
                    if paired {
                        _ = try? await orchestrator.adbClient.connectWireless(ip: vm.ipAddress, port: 5555)
                        await MainActor.run {
                            self.vm.isConnecting = false
                            self.vm.isSuccess = true
                            self.vm.statusMessage = "Pairing successful & connected!"
                            self.orchestrator.pollADB()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                self.onDismiss()
                            }
                        }
                    } else {
                        await MainActor.run {
                            self.vm.isConnecting = false
                            self.vm.isSuccess = false
                            self.vm.statusMessage = "Pairing failed. Check pairing code and port."
                        }
                    }
                } else {
                    // Direct connect
                    let port = Int(vm.connectPort) ?? 5555
                    let connected = try await orchestrator.adbClient.connectWireless(ip: vm.ipAddress, port: port)
                    await MainActor.run {
                        self.vm.isConnecting = false
                        self.vm.isSuccess = connected
                        self.vm.statusMessage = connected ? "Connected successfully!" : "Could not reach device."
                        if connected {
                            self.orchestrator.pollADB()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                self.onDismiss()
                            }
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.vm.isConnecting = false
                    self.vm.isSuccess = false
                    self.vm.statusMessage = error.localizedDescription
                }
            }
        }
    }
}
