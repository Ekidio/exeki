import AppKit

/// Where the app keeps its engines and Windows environment.
enum AppPaths {
    static let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("EXEKI")
    /// The Windows environment ("bottle"); its drive_c is the C: drive.
    static let prefix = support.appendingPathComponent("Windows")
    static let prefixReadyMarker = prefix.appendingPathComponent(".exerunner-ready")
}

enum Rosetta {
    static var isNeeded: Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }

    static var isInstalled: Bool {
        let probe = Process()
        probe.executableURL = URL(fileURLWithPath: "/usr/bin/arch")
        probe.arguments = ["-x86_64", "/usr/bin/true"]
        probe.standardOutput = FileHandle.nullDevice
        probe.standardError = FileHandle.nullDevice
        do {
            try probe.run()
            probe.waitUntilExit()
            return probe.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Shows the system password prompt, then installs Rosetta. Returns false if the user cancelled.
    static func install() async throws -> Bool {
        let script = """
            do shell script "/usr/sbin/softwareupdate --install-rosetta --agree-to-license" \
            with prompt "Az EXEKI telepíteni szeretné az Apple Rosetta kiegészítőt." \
            with administrator privileges
            """
        let result = try await Shell.run(URL(fileURLWithPath: "/usr/bin/osascript"), ["-e", script], captureErrors: true)
        if result.status == 0 { return true }
        if result.errors.contains("-128") { return false }
        throw SetupError.rosetta(result.errors.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

/// Detects when the app runs from Downloads or the disk image, where macOS
/// runs it from a hidden read-only copy ("App Translocation").
enum AppLocation {
    static var isTranslocated: Bool { Bundle.main.bundlePath.contains("/AppTranslocation/") }
    static var isOnDiskImage: Bool { originalURL.path.hasPrefix("/Volumes/") }
    static var needsMove: Bool { isTranslocated || isOnDiskImage }

    static var originalURL: URL {
        let url = Bundle.main.bundleURL
        guard url.path.contains("/AppTranslocation/"),
              let handle = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY),
              let symbol = dlsym(handle, "SecTranslocateCreateOriginalPathForURL")
        else { return url }
        typealias Fn = @convention(c) (CFURL, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFURL>?
        let original = unsafeBitCast(symbol, to: Fn.self)(url as CFURL, nil)?.takeRetainedValue()
        return (original as URL?) ?? url
    }

    /// Copies the app into /Applications (or ~/Applications), relaunches it from there and quits.
    static func moveToApplicationsAndRelaunch() throws {
        let fm = FileManager.default
        let source = originalURL
        var folder = URL(fileURLWithPath: "/Applications")
        if !fm.isWritableFile(atPath: folder.path) {
            folder = fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let destination = folder.appendingPathComponent(source.lastPathComponent)
        if fm.fileExists(atPath: destination.path) {
            try fm.trashItem(at: destination, resultingItemURL: nil)
        }
        try fm.copyItem(at: Bundle.main.bundleURL, to: destination)
        // The user has already approved this app in Gatekeeper; don't make them do it twice for the copy.
        Shell.removeQuarantine(destination)
        if !source.path.hasPrefix("/Volumes/") {
            try? fm.trashItem(at: source, resultingItemURL: nil)
        }
        // Same bundle ID as this running copy, so explicitly ask for a new instance; otherwise
        // LaunchServices just re-activates us and nothing is left running after we quit.
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: destination, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}

enum SetupError: LocalizedError {
    case download(String)
    case corrupted
    case extract
    case windows(Int32)
    case rosetta(String)

    var errorDescription: String? {
        switch self {
        case .download(let detail):
            "A letöltés nem sikerült. Ellenőrizd az internetkapcsolatot. Ha tűzfalprogramot használsz (pl. LuLu vagy Little Snitch), engedélyezd benne az EXEKI-t. (\(detail))"
        case .corrupted:
            "A letöltött fájl sérült. Próbáld újra."
        case .extract:
            "A kicsomagolás nem sikerült. Van elég szabad hely a Macen (kb. 1 GB)?"
        case .windows(let code):
            "Nem sikerült előkészíteni a Windows környezetet (kód: \(code))."
        case .rosetta(let detail):
            "Nem sikerült telepíteni a Rosettát. \(detail)"
        }
    }
}

enum Shell {
    struct Result {
        let status: Int32
        let errors: String
    }

    static func run(_ executable: URL, _ args: [String], environment: [String: String]? = nil,
                    captureErrors: Bool = false) async throws -> Result {
        let process = Process()
        process.executableURL = executable
        process.arguments = args
        if let environment { process.environment = environment }
        process.standardOutput = FileHandle.nullDevice
        let errPipe = captureErrors ? Pipe() : nil
        process.standardError = errPipe ?? FileHandle.nullDevice
        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { proc in
                let data = errPipe?.fileHandleForReading.readDataToEndOfFile() ?? Data()
                continuation.resume(returning: Result(status: proc.terminationStatus,
                                                      errors: String(decoding: data, as: UTF8.self)))
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    @discardableResult
    static func runSync(_ executable: URL, _ args: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = executable
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    static func removeQuarantine(_ url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        process.arguments = ["-dr", "com.apple.quarantine", url.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }
}
