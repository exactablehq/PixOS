import Foundation

public enum ADBError: LocalizedError, Sendable {
    case adbNotFound
    case commandFailed(command: String, exitCode: Int32, stderr: String)
    case deviceNotFound
    case deviceUnauthorized
    case pushFailed(path: String, reason: String)
    case fileVerificationFailed(expected: Int64, actual: Int64)
    case wirelessConnectionFailed(reason: String)

    public var errorDescription: String? {
        switch self {
        case .adbNotFound:
            return "ADB executable not found. Please ensure Android SDK platform-tools or Bundled ADB is installed."
        case .commandFailed(let cmd, let code, let err):
            return "ADB command '\(cmd)' failed with code \(code): \(err)"
        case .deviceNotFound:
            return "No Android / Google Pixel device detected via ADB."
        case .deviceUnauthorized:
            return "Pixel is connected but unauthorized. Please unlock the phone and tap 'Allow USB Debugging'."
        case .pushFailed(let path, let reason):
            return "Failed to push '\(path)' to Pixel: \(reason)"
        case .fileVerificationFailed(let exp, let act):
            return "File verification mismatch: expected \(exp) bytes, found \(act) bytes on device."
        case .wirelessConnectionFailed(let reason):
            return "Failed to connect to Pixel over Wi-Fi: \(reason)"
        }
    }
}

public final class ADBClient: Sendable {
    public let adbPath: String?

    public init(customPath: String? = nil) {
        self.adbPath = BundledADB.resolveADBPath(customPath: customPath)
    }

    public var isAvailable: Bool {
        adbPath != nil
    }

    private static func shellQuote(_ path: String) -> String {
        let escaped = path.replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    public func run(arguments: [String], timeout: TimeInterval = 60) async throws -> (stdout: String, stderr: String, exitCode: Int32) {
        guard let adb = adbPath else {
            throw ADBError.adbNotFound
        }

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: adb)
            process.arguments = arguments

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
                return
            }

            // Watchdog timer to kill hanging ADB process if timeout is exceeded
            let timeoutWorkItem = DispatchWorkItem {
                if process.isRunning {
                    process.terminate()
                }
            }
            DispatchQueue.global(qos: .background).asyncAfter(
                deadline: .now() + timeout,
                execute: timeoutWorkItem
            )

            DispatchQueue.global(qos: .userInitiated).async {
                // Concurrently drain stdout and stderr to prevent pipe buffer deadlock
                var outData = Data()
                var errData = Data()
                let group = DispatchGroup()

                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }

                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }

                process.waitUntilExit()
                group.wait()
                timeoutWorkItem.cancel()

                let stdout = String(data: outData, encoding: .utf8) ?? ""
                let stderr = String(data: errData, encoding: .utf8) ?? ""
                continuation.resume(returning: (stdout, stderr, process.terminationStatus))
            }
        }
    }

    public func listDevices() async throws -> [AndroidDevice] {
        let (stdout, _, exitCode) = try await run(arguments: ["devices", "-l"])
        guard exitCode == 0 else { return [] }

        var devices: [AndroidDevice] = []
        let lines = stdout.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.starts(with: "List of devices") || trimmed.starts(with: "*") {
                continue
            }

            let parts = trimmed.split(separator: " ").map(String.init)
            guard parts.count >= 2 else { continue }

            let serial = parts[0]
            let status = parts[1]
            let isAuthorized = (status == "device")
            let isWireless = serial.contains(":")

            var model = "Pixel"
            var product = "Pixel"

            for part in parts {
                if part.starts(with: "model:") {
                    model = String(part.dropFirst("model:".count))
                } else if part.starts(with: "product:") {
                    product = String(part.dropFirst("product:".count))
                }
            }

            devices.append(AndroidDevice(
                id: serial,
                serial: serial,
                model: model,
                product: product,
                isWireless: isWireless,
                isAuthorized: isAuthorized
            ))
        }

        return devices
    }

    public func getStorage(serial: String? = nil) async throws -> StorageInfo {
        var args = ["shell", "df", "-k", "/sdcard"]
        if let serial = serial {
            args = ["-s", serial] + args
        }

        let (stdout, stderr, exitCode) = try await run(arguments: args)
        guard exitCode == 0 else {
            throw ADBError.commandFailed(command: "df -k /sdcard", exitCode: exitCode, stderr: stderr)
        }

        let lines = stdout.components(separatedBy: .newlines)
        for line in lines.dropFirst() {
            let tokens = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            if tokens.count >= 4 {
                if let total1k = Int64(tokens[1]),
                   let used1k = Int64(tokens[2]),
                   let free1k = Int64(tokens[3]) {
                    return StorageInfo(
                        totalBytes: total1k * 1024,
                        usedBytes: used1k * 1024,
                        freeBytes: free1k * 1024
                    )
                }
            }
        }

        return StorageInfo(totalBytes: 0, usedBytes: 0, freeBytes: 0)
    }

    public func createDirectory(remotePath: String, serial: String? = nil) async throws {
        var args = ["shell", "mkdir", "-p", ADBClient.shellQuote(remotePath)]
        if let serial = serial {
            args = ["-s", serial] + args
        }
        let (_, stderr, exitCode) = try await run(arguments: args)
        guard exitCode == 0 else {
            throw ADBError.commandFailed(command: "mkdir -p \(remotePath)", exitCode: exitCode, stderr: stderr)
        }
    }

    public func push(localURL: URL, remotePath: String, serial: String? = nil) async throws {
        var args = ["push", localURL.path, remotePath]
        if let serial = serial {
            args = ["-s", serial] + args
        }

        let (_, stderr, exitCode) = try await run(arguments: args, timeout: 300)
        guard exitCode == 0 else {
            throw ADBError.pushFailed(path: localURL.lastPathComponent, reason: stderr)
        }
    }

    public func verifyFileSize(remotePath: String, expectedBytes: Int64, serial: String? = nil) async throws -> Bool {
        var args = ["shell", "stat", "-c", "%s", ADBClient.shellQuote(remotePath)]
        if let serial = serial {
            args = ["-s", serial] + args
        }

        let (stdout, _, exitCode) = try await run(arguments: args)
        if exitCode == 0 {
            let cleaned = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if let size = Int64(cleaned) {
                return size == expectedBytes
            }
        }

        // Fallback to ls -nl if stat is not present
        var lsArgs = ["shell", "ls", "-nl", ADBClient.shellQuote(remotePath)]
        if let serial = serial {
            lsArgs = ["-s", serial] + lsArgs
        }
        let (lsOut, _, lsCode) = try await run(arguments: lsArgs)
        if lsCode == 0 {
            let tokens = lsOut.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            if tokens.count >= 5, let size = Int64(tokens[4]) {
                return size == expectedBytes
            }
        }

        return false
    }

    public func triggerMediaScan(remotePath: String, serial: String? = nil) async throws {
        let encodedPath = remotePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? remotePath
        var args = [
            "shell", "am", "broadcast",
            "-a", "android.intent.action.MEDIA_SCANNER_SCAN_FILE",
            "-d", "file://\(encodedPath)"
        ]
        if let serial = serial {
            args = ["-s", serial] + args
        }
        _ = try? await run(arguments: args)
    }

    public func setRemoteTimestamp(remotePath: String, date: Date, serial: String? = nil) async {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyyMMddHHmm.ss"
        let timestampStr = formatter.string(from: date)

        var args = ["shell", "touch", "-t", timestampStr, ADBClient.shellQuote(remotePath)]
        if let serial = serial {
            args = ["-s", serial] + args
        }
        _ = try? await run(arguments: args)
    }

    public func connectWireless(ip: String, port: Int = 5555) async throws -> Bool {
        let (stdout, stderr, exitCode) = try await run(arguments: ["connect", "\(ip):\(port)"])
        guard exitCode == 0 else {
            throw ADBError.wirelessConnectionFailed(reason: stderr)
        }
        return stdout.contains("connected to")
    }

    public func pairWireless(ip: String, port: Int, code: String) async throws -> Bool {
        let (stdout, stderr, exitCode) = try await run(arguments: ["pair", "\(ip):\(port)", code])
        guard exitCode == 0 else {
            throw ADBError.wirelessConnectionFailed(reason: stderr.isEmpty ? stdout : stderr)
        }
        return stdout.lowercased().contains("successfully paired") || stdout.lowercased().contains("paired to")
    }

    public func enableTcpip(port: Int = 5555, serial: String? = nil) async throws -> Bool {
        var args = ["tcpip", "\(port)"]
        if let serial = serial {
            args = ["-s", serial] + args
        }
        let (_, _, exitCode) = try await run(arguments: args)
        return exitCode == 0
    }
}
