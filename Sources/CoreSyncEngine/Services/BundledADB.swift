import Foundation

public struct BundledADB: Sendable {
    public static func resolveADBPath(customPath: String? = nil) -> String? {
        let fm = FileManager.default

        // 1. Check custom path if provided
        if let custom = customPath, !custom.isEmpty {
            if fm.isExecutableFile(atPath: custom) {
                return custom
            }
        }

        // 2. Check App Bundle Resources
        if let resourceURL = Bundle.main.resourceURL {
            let bundledBin = resourceURL.appendingPathComponent("bin/adb").path
            if fm.fileExists(atPath: bundledBin) {
                _ = try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bundledBin)
                if fm.isExecutableFile(atPath: bundledBin) {
                    return bundledBin
                }
            }
        }

        // 3. Check relative bin/adb in current working directory / repo root
        let relativePaths = [
            "./bin/adb",
            "../bin/adb",
            "Resources/bin/adb"
        ]
        for rel in relativePaths {
            let fullPath = URL(fileURLWithPath: rel).path
            if fm.fileExists(atPath: fullPath) {
                _ = try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fullPath)
                if fm.isExecutableFile(atPath: fullPath) {
                    return fullPath
                }
            }
        }

        // 4. Check standard macOS Android Studio SDK location
        let homeDir = fm.homeDirectoryForCurrentUser.path
        let sdkPath = "\(homeDir)/Library/Android/sdk/platform-tools/adb"
        if fm.isExecutableFile(atPath: sdkPath) {
            return sdkPath
        }

        // 5. Check Homebrew and common Unix paths
        let standardPaths = [
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb",
            "/usr/bin/adb"
        ]
        for path in standardPaths {
            if fm.isExecutableFile(atPath: path) {
                return path
            }
        }

        // 6. Check PATH via 'which adb'
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["adb"]
        process.standardOutput = pipe
        try? process.run()
        process.waitUntilExit()

        if process.terminationStatus == 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !output.isEmpty {
                if fm.isExecutableFile(atPath: output) {
                    return output
                }
            }
        }

        return nil
    }
}
