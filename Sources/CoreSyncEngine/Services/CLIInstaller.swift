import Foundation

public struct CLIInstaller: Sendable {
    public static func isCLIInstalled() -> Bool {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let paths = [
            "/usr/local/bin/pixos",
            "\(home)/.local/bin/pixos"
        ]
        return paths.contains { fm.isExecutableFile(atPath: $0) }
    }

    public static func installCLITools() -> (success: Bool, message: String) {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let userLocalBin = "\(home)/.local/bin"

        // Locate bundled binaries
        var sourcePixosURL: URL? = nil
        var sourceAdbURL: URL? = nil

        // 1. App Bundle Resources
        if let resourceURL = Bundle.main.resourceURL {
            let p = resourceURL.appendingPathComponent("bin/pixos")
            let a = resourceURL.appendingPathComponent("bin/adb")
            if fm.fileExists(atPath: p.path) { sourcePixosURL = p }
            if fm.fileExists(atPath: a.path) { sourceAdbURL = a }
        }

        // 2. Relative bin / build directory
        let searchPaths = [
            "./.build/release/pixos",
            "../.build/release/pixos",
            "./bin/pixos"
        ]
        if sourcePixosURL == nil {
            for p in searchPaths {
                if fm.fileExists(atPath: p) {
                    sourcePixosURL = URL(fileURLWithPath: p)
                    break
                }
            }
        }

        if sourceAdbURL == nil {
            if let resolvedADB = BundledADB.resolveADBPath() {
                sourceAdbURL = URL(fileURLWithPath: resolvedADB)
            }
        }

        guard let pixosSrc = sourcePixosURL else {
            return (false, "Could not locate bundled 'pixos' binary to install.")
        }

        // Try installing to /usr/local/bin first if writable
        let usrLocalBin = "/usr/local/bin"
        var targetDir = usrLocalBin

        if fm.isWritableFile(atPath: usrLocalBin) {
            targetDir = usrLocalBin
        } else {
            // Check ~/.local/bin
            try? fm.createDirectory(atPath: userLocalBin, withIntermediateDirectories: true)
            targetDir = userLocalBin
        }

        do {
            let destPixos = "\(targetDir)/pixos"
            if fm.fileExists(atPath: destPixos) {
                try? fm.removeItem(atPath: destPixos)
            }
            try fm.copyItem(at: pixosSrc, to: URL(fileURLWithPath: destPixos))
            _ = try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destPixos)

            if let adbSrc = sourceAdbURL {
                let destAdb = "\(targetDir)/adb"
                if !fm.fileExists(atPath: destAdb) {
                    try? fm.copyItem(at: adbSrc, to: URL(fileURLWithPath: destAdb))
                    _ = try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destAdb)
                }
            }

            // Ensure ~/.local/bin is in user's PATH if installed there
            if targetDir == userLocalBin {
                ensurePathConfigured(home: home, localBin: userLocalBin)
            }

            return (true, "Installed 'pixos' and 'adb' to \(targetDir)")
        } catch {
            return (false, "Failed to copy binaries: \(error.localizedDescription)")
        }
    }

    private static func ensurePathConfigured(home: String, localBin: String) {
        let zshrc = URL(fileURLWithPath: "\(home)/.zshrc")
        if let content = try? String(contentsOf: zshrc, encoding: .utf8) {
            if !content.contains(".local/bin") {
                let appendText = "\n# Added by PixOS\nexport PATH=\"$HOME/.local/bin:$PATH\"\n"
                if let data = appendText.data(using: .utf8), let handle = try? FileHandle(forWritingTo: zshrc) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            }
        }
    }
}
