import SwiftUI
import CoreSyncEngine

public final class PairingViewModel: ObservableObject {
    @Published public var ipAddress: String = ""
    @Published public var port: String = "5555"
    @Published public var isConnecting = false
    @Published public var statusMessage: String? = nil
    @Published public var isSuccess: Bool = false

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
            HStack(spacing: 12) {
                Image(systemName: "wifi")
                    .font(.system(size: 28))
                    .foregroundColor(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connect Pixel over Wi-Fi")
                        .font(.title3.bold())
                    Text("Wireless ADB allows transfers without keeping the Pixel plugged in via cable.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Pixel IP Address")
                        .font(.caption.bold())
                    TextField("e.g. 192.168.1.150", text: $vm.ipAddress)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Port (Default: 5555)")
                        .font(.caption.bold())
                    TextField("5555", text: $vm.port)
                        .textFieldStyle(.roundedBorder)
                }

                Text("How to find Pixel IP: On your Pixel, go to Settings → About Phone → Status → IP Address. Make sure 'Wireless debugging' or 'ADB over network' is enabled in Developer Options.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .cornerRadius(12)

            if let msg = vm.statusMessage {
                HStack {
                    Image(systemName: vm.isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(vm.isSuccess ? .green : .red)
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(vm.isSuccess ? .green : .red)
                }
            }

            HStack {
                Button("Cancel") {
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(action: connect) {
                    if vm.isConnecting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Connect Device")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(vm.ipAddress.isEmpty || vm.isConnecting)
            }
        }
        .padding()
        .frame(width: 440)
    }

    private func connect() {
        guard !vm.ipAddress.isEmpty else { return }
        vm.isConnecting = true
        vm.statusMessage = nil

        let portNum = Int(vm.port) ?? 5555
        Task {
            do {
                let success = try await orchestrator.adbClient.connectWireless(ip: vm.ipAddress, port: portNum)
                await MainActor.run {
                    self.vm.isConnecting = false
                    if success {
                        self.vm.isSuccess = true
                        self.vm.statusMessage = "Connected successfully!"
                        self.orchestrator.pollADB()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                            self.onDismiss()
                        }
                    } else {
                        self.vm.isSuccess = false
                        self.vm.statusMessage = "Could not verify connection. Check IP and port."
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
