import AppKit
import CryptoKit

/// A third-party runtime downloaded on demand and pinned to one checksum-verified version.
/// Shipping an app update with a new `version` makes existing installs download the new engine.
struct Engine {
    enum Format { case tarball, diskImage }

    /// Folder name under Application Support, also the key of the local-archive override.
    let id: String
    let displayName: String
    let version: String
    let fileName: String
    let upstreamURL: URL
    let size: Int64
    let sha256: String
    let format: Format
    /// The .app inside the archive.
    let bundleName: String
    /// Executable path relative to the bundle.
    let executablePath: String

    static let wine = Engine(
        id: "Wine",
        displayName: "Windows-futtató motor",
        version: "11.17",
        fileName: "wine-devel-11.17-osx64.tar.xz",
        upstreamURL: URL(string: "https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.17/wine-devel-11.17-osx64.tar.xz")!,
        size: 191_290_556,
        sha256: "c2b3a8274dbc594deaa64e40469b607cbc4aa8ef5656dec4c5f6f3dac0da770c",
        format: .tarball,
        bundleName: "Wine Devel.app",
        executablePath: "Contents/Resources/wine/bin/wine")

    static let dosbox = Engine(
        id: "DOSBox",
        displayName: "DOS-motor",
        version: "0.83.0",
        fileName: "dosbox-staging-macOS-v0.83.0.dmg",
        upstreamURL: URL(string: "https://github.com/dosbox-staging/dosbox-staging/releases/download/v0.83.0/dosbox-staging-macOS-v0.83.0.dmg")!,
        size: 44_531_761,
        sha256: "d8a771adfb8010fa6b5f7fb5351abfba659273ad01c89f03675a92bdbdae8167",
        format: .diskImage,
        bundleName: "DOSBox Staging.app",
        executablePath: "Contents/MacOS/dosbox")

    var root: URL { AppPaths.support.appendingPathComponent(id) }
    var executable: URL { root.appendingPathComponent(bundleName).appendingPathComponent(executablePath) }
    private var versionMarker: URL { root.appendingPathComponent(".version") }

    var installedVersion: String? {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { return nil }
        return (try? String(contentsOf: versionMarker, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isInstalled: Bool { installedVersion == version }
    /// An older version is present, so installing it now is an update.
    var needsUpdate: Bool { FileManager.default.isExecutableFile(atPath: executable.path) && !isInstalled }

    /// Tried in order: the project's own GitHub mirror first (so a third party deleting its
    /// files can never break installs — this is what killed Whisky), then the upstream release.
    var downloadURLs: [URL] {
        if let override = UserDefaults.standard.string(forKey: "\(id)ArchiveURL").flatMap(URL.init(string:)) {
            return [override]
        }
        var urls: [URL] = []
        if let repo = Bundle.main.object(forInfoDictionaryKey: "EXEKIGitHubRepo") as? String, !repo.isEmpty,
           let mirror = URL(string: "https://github.com/\(repo)/releases/download/engines/\(fileName)") {
            urls.append(mirror)
        }
        urls.append(upstreamURL)
        return urls
    }

    /// Downloads, verifies and unpacks the engine, replacing any older version.
    func install(progress: @escaping @Sendable (Double) -> Void) async throws {
        var lastError: Error = SetupError.download("nincs letöltési cím")
        for url in downloadURLs {
            do {
                let archive = try await Downloader(expectedSize: size).download(url, progress: progress)
                defer { try? FileManager.default.removeItem(at: archive) }
                try await verify(archive)
                try await unpack(archive)
                return
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private func verify(_ file: URL) async throws {
        let size = size, sha256 = sha256
        let ok = try await Task.detached(priority: .userInitiated) { () throws -> Bool in
            let handle = try FileHandle(forReadingFrom: file)
            defer { try? handle.close() }
            var hasher = SHA256()
            var total: Int64 = 0
            while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty {
                hasher.update(data: chunk)
                total += Int64(chunk.count)
            }
            let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
            return total == size && digest == sha256
        }.value
        if !ok { throw SetupError.corrupted }
    }

    private func unpack(_ archive: URL) async throws {
        let fm = FileManager.default
        let staging = AppPaths.support.appendingPathComponent("\(id).partial")
        try? fm.removeItem(at: staging)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            switch format {
            case .tarball:
                let result = try await Shell.run(URL(fileURLWithPath: "/usr/bin/tar"), ["-xf", archive.path, "-C", staging.path])
                guard result.status == 0 else { throw SetupError.extract }
            case .diskImage:
                try await copyBundle(fromDiskImage: archive, to: staging)
            }
            guard fm.fileExists(atPath: staging.appendingPathComponent(bundleName).path) else { throw SetupError.extract }
            Shell.removeQuarantine(staging)
            try version.write(to: staging.appendingPathComponent(".version"), atomically: true, encoding: .utf8)
            try? fm.removeItem(at: root)
            try fm.moveItem(at: staging, to: root)
        } catch {
            try? fm.removeItem(at: staging)
            throw error is SetupError ? error : SetupError.extract
        }
    }

    private func copyBundle(fromDiskImage image: URL, to folder: URL) async throws {
        let mountPoint = FileManager.default.temporaryDirectory.appendingPathComponent("mnt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)
        let hdiutil = URL(fileURLWithPath: "/usr/bin/hdiutil")
        let attach = try await Shell.run(hdiutil, ["attach", image.path, "-nobrowse", "-readonly", "-noverify",
                                                   "-mountpoint", mountPoint.path])
        guard attach.status == 0 else { throw SetupError.extract }
        defer {
            _ = try? Shell.runSync(hdiutil, ["detach", mountPoint.path, "-force"])
            try? FileManager.default.removeItem(at: mountPoint)
        }
        try FileManager.default.copyItem(at: mountPoint.appendingPathComponent(bundleName),
                                         to: folder.appendingPathComponent(bundleName))
    }
}

/// One-shot file download with progress reporting.
final class Downloader: NSObject, URLSessionDownloadDelegate {
    private let expectedSize: Int64
    private var continuation: CheckedContinuation<URL, Error>?
    private var onProgress: ((Double) -> Void)?
    private var lastReported = -1.0
    private var session: URLSession?

    init(expectedSize: Int64) {
        self.expectedSize = expectedSize
    }

    func download(_ url: URL, progress: @escaping (Double) -> Void) async throws -> URL {
        onProgress = progress
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let config = URLSessionConfiguration.default
            // Fail with a helpful message instead of hanging forever (offline, or a firewall like LuLu holding the connection).
            config.timeoutIntervalForRequest = 30
            let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
            self.session = session
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64,
                    totalBytesWritten written: Int64, totalBytesExpectedToWrite expected: Int64) {
        let total = expected > 0 ? expected : expectedSize
        let fraction = min(1, Double(written) / Double(total))
        if fraction - lastReported >= 0.005 {
            lastReported = fraction
            onProgress?(fraction)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            finish(.failure(SetupError.download("HTTP \(http.statusCode)")))
            return
        }
        // The temporary file is deleted when this method returns, so move it first.
        let name = downloadTask.originalRequest?.url?.lastPathComponent ?? "download"
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(name)")
        do {
            try FileManager.default.moveItem(at: location, to: destination)
            finish(.success(destination))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            finish(.failure(SetupError.download(error.localizedDescription)))
        }
    }

    private func finish(_ result: Result<URL, Error>) {
        continuation?.resume(with: result)
        continuation = nil
        session?.finishTasksAndInvalidate()
    }
}

/// What kind of program a file is, read from its executable header.
enum ProgramKind: Equatable {
    case windows          // 32/64-bit Windows (PE), plus .msi and .bat
    case dos              // DOS .com/.exe, including DOS-extender games (LE/LX)
    case windows16        // Windows 3.x (NE)
    case windowsARM       // Windows on ARM builds, which Wine on macOS can't run
    case notAProgram

    static func detect(_ url: URL) -> ProgramKind {
        switch url.pathExtension.lowercased() {
        case "msi", "bat", "cmd": return .windows
        case "com": return .dos
        case "exe": break
        default: return .notAProgram
        }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return .notAProgram }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 64), header.count >= 2 else { return .notAProgram }
        let magic = String(decoding: header.prefix(2), as: UTF8.self)
        guard magic == "MZ" || magic == "ZM" else { return .notAProgram }
        guard header.count >= 64 else { return .dos }

        // e_lfanew points at the "new" header; plain DOS programs have garbage or nothing there.
        let offset = UInt64(header[60]) | UInt64(header[61]) << 8 | UInt64(header[62]) << 16 | UInt64(header[63]) << 24
        guard offset >= 64, (try? handle.seek(toOffset: offset)) != nil,
              let next = try? handle.read(upToCount: 6), next.count >= 2
        else { return .dos }

        switch String(decoding: next.prefix(2), as: UTF8.self) {
        case "PE" where next.count == 6 && next[2] == 0 && next[3] == 0:
            let machine = UInt16(next[4]) | UInt16(next[5]) << 8
            return machine == 0xAA64 || machine == 0x01C4 ? .windowsARM : .windows
        case "NE": return .windows16
        default: return .dos
        }
    }
}
