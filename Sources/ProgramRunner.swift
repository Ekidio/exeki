import AppKit
import UniformTypeIdentifiers

struct LogLine: Identifiable {
    enum Kind { case info, output, error }
    let id: Int
    let text: String
    let kind: Kind
}

struct RunningProgram: Identifiable {
    let id = UUID()
    let name: String
    let isDOS: Bool
    let process: Process
    let started = Date()
}

/// Progress of an engine being downloaded on demand (the DOS engine on first use).
struct EngineDownload: Equatable {
    let title: String
    let fraction: Double
}

/// A short, human message shown above the log.
struct Notice: Equatable {
    enum Kind { case info, error }
    let kind: Kind
    let text: String
}

/// Collects raw pipe data and hands back complete lines.
private final class LineBuffer {
    private var data = Data()

    func feed(_ chunk: Data) -> [String] {
        data.append(chunk)
        var lines: [String] = []
        while let nl = data.firstIndex(of: 0x0A) {
            lines.append(Self.decode(data[data.startIndex..<nl]))
            data.removeSubrange(data.startIndex...nl)
        }
        return lines
    }

    func flush() -> [String] {
        defer { data.removeAll() }
        return data.isEmpty ? [] : [Self.decode(data)]
    }

    private static func decode(_ bytes: Data) -> String {
        let s = String(decoding: bytes, as: UTF8.self)
        return s.hasSuffix("\r") ? String(s.dropLast()) : s
    }
}

@MainActor
final class ProgramRunner: ObservableObject {
    static let shared = ProgramRunner()

    static let supportedTypes: [UTType] = [
        UTType("com.microsoft.windows-executable") ?? .executable,
        UTType("com.microsoft.msi-installer") ?? .data,
        UTType("com.microsoft.bat") ?? .data,
        UTType(filenameExtension: "com") ?? .data,
    ]

    @Published private(set) var log: [LogLine] = []
    @Published private(set) var running: [RunningProgram] = []
    @Published private(set) var recent: [URL] = []
    @Published var notice: Notice?
    @Published private(set) var engineDownload: EngineDownload?
    @Published var verbose: Bool {
        didSet { UserDefaults.standard.set(verbose, forKey: "verbose") }
    }

    private var nextLogID = 0
    private let maxLogLines = 5000
    /// Recent output lines per program (Wine reports some errors on stdout), used to explain why it failed.
    private var outputTails: [UUID: [String]] = [:]

    private init() {
        verbose = UserDefaults.standard.bool(forKey: "verbose")
        recent = (UserDefaults.standard.stringArray(forKey: "recent") ?? [])
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    // MARK: - Windows environment

    func initializePrefix() async throws {
        try FileManager.default.createDirectory(at: AppPaths.prefix, withIntermediateDirectories: true)
        var env = environment()
        // Skip the Wine Mono / Gecko installer dialogs on first setup; Wine offers them later if a program needs them.
        env["WINEDLLOVERRIDES"] = "mscoree,mshtml="
        let result = try await Shell.run(Engine.wine.executable, ["wineboot", "--init"], environment: env)
        guard result.status == 0 else { throw SetupError.windows(result.status) }
        FileManager.default.createFile(atPath: AppPaths.prefixReadyMarker.path, contents: nil)
        info("Windows környezet kész: \(AppPaths.prefix.path)")
    }

    // MARK: - Running programs

    func chooseAndRun() {
        chooseAndRun(forceEngine: nil)
    }

    /// Picks the right engine from the file's header: Wine for Windows programs, DOSBox for DOS ones.
    func run(_ url: URL) {
        let name = url.lastPathComponent
        switch ProgramKind.detect(url) {
        case .windows:
            runWithWine(url)
        case .dos:
            runWithDOS(url)
        case .windows16:
            show(.error, "„\(name)” egy régi, Windows 3.1-es (16 bites) program. Ezt sajnos egyik motor sem tudja futtatni.")
        case .windowsARM:
            show(.error, "„\(name)” ARM-os Windowsra készült. Keresd a program „x64” vagy „x86” változatát.")
        case .notAProgram:
            show(.error, "„\(name)” nem futtatható program. .exe, .com, .msi és .bat fájlokat tudok indítani.")
        }
    }

    func runWithWine(_ url: URL) {
        let windowsPath = "Z:" + url.path.replacingOccurrences(of: "/", with: "\\")
        let args: [String]
        switch url.pathExtension.lowercased() {
        case "msi": args = ["msiexec", "/i", windowsPath]
        case "bat", "cmd": args = ["cmd", "/c", windowsPath]
        default: args = [url.path]
        }
        remember(url)
        launch(Engine.wine.executable, args, name: url.lastPathComponent, isDOS: false,
               directory: url.deletingLastPathComponent())
    }

    /// DOSBox mounts the program's folder as C:, runs it, and quits when it exits.
    func runWithDOS(_ url: URL) {
        remember(url)
        let dosbox = Engine.dosbox
        guard dosbox.isInstalled else {
            installDOSEngine(thenRun: url)
            return
        }
        launch(dosbox.executable, [url.path], name: url.lastPathComponent, isDOS: true,
               directory: url.deletingLastPathComponent(), dosEnvironment: true)
    }

    func chooseAndRun(forceEngine: ProgramKind?) {
        let panel = NSOpenPanel()
        panel.message = forceEngine == .dos ? "Válaszd ki a DOS programot" : "Válaszd ki a futtatandó Windows programot"
        panel.allowedContentTypes = Self.supportedTypes
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            switch forceEngine {
            case .dos: runWithDOS(url)
            case .windows: runWithWine(url)
            default: run(url)
            }
        }
    }

    private func installDOSEngine(thenRun url: URL) {
        guard engineDownload == nil else {
            show(.info, "A DOS-motor letöltése folyamatban, utána indítsd újra: \(url.lastPathComponent)")
            return
        }
        let dosbox = Engine.dosbox
        let title = dosbox.needsUpdate ? "DOS-motor frissítése" : "DOS-motor letöltése (csak az első DOS programnál)"
        engineDownload = EngineDownload(title: title, fraction: 0)
        Task {
            do {
                try await dosbox.install { fraction in
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            ProgramRunner.shared.engineDownload = EngineDownload(title: title, fraction: fraction)
                        }
                    }
                }
                engineDownload = nil
                info("DOS-motor telepítve: DOSBox Staging \(dosbox.version)")
                runWithDOS(url)
            } catch {
                engineDownload = nil
                show(.error, error.localizedDescription)
            }
        }
    }

    func runTool(_ tool: String) {
        launch(Engine.wine.executable, [tool], name: tool, isDOS: false, directory: nil)
    }

    func stop(_ program: RunningProgram) {
        info("Leállítás: \(program.name)")
        program.process.terminate()
    }

    /// Kills every Windows process in the environment, including ones started outside this app.
    func stopAll() {
        let server = Process()
        server.executableURL = Engine.wine.executable.deletingLastPathComponent().appendingPathComponent("wineserver")
        server.arguments = ["-k"]
        server.environment = environment()
        try? server.run()
        running.forEach { $0.process.terminate() }
    }

    /// Makes this app open .exe/.msi/.bat files on double-click in Finder.
    func makeDefaultHandler() {
        let app = Bundle.main.bundleURL
        for type in Self.supportedTypes {
            NSWorkspace.shared.setDefaultApplication(at: app, toOpen: type) { error in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        if let error {
                            ProgramRunner.shared.show(.error, "Nem sikerült beállítani: \(error.localizedDescription)")
                        } else {
                            ProgramRunner.shared.show(.info, "Kész: dupla kattintásra mostantól az EXEKI nyitja meg a Windows programokat.")
                        }
                    }
                }
            }
        }
    }

    func openDriveC() {
        NSWorkspace.shared.open(AppPaths.prefix.appendingPathComponent("drive_c"))
    }

    func clearLog() {
        log.removeAll()
    }

    private func launch(_ executable: URL, _ args: [String], name: String, isDOS: Bool, directory: URL?,
                        dosEnvironment: Bool = false) {
        let process = Process()
        process.executableURL = executable
        process.arguments = args
        process.environment = dosEnvironment ? ProcessInfo.processInfo.environment : environment()
        if let directory { process.currentDirectoryURL = directory }

        let program = RunningProgram(name: name, isDOS: isDOS, process: process)
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        // Lets the exit handler wait until the last output lines have been logged.
        let drained = DispatchGroup()
        Self.stream(out.fileHandleForReading, kind: .output, program: program.id, drained: drained)
        Self.stream(err.fileHandleForReading, kind: .error, program: program.id, drained: drained)

        process.terminationHandler = { proc in
            let status = proc.terminationStatus
            let signaled = proc.terminationReason == .uncaughtSignal
            // A lingering child (e.g. wineserver) can keep the pipes open, so don't wait forever.
            _ = drained.wait(timeout: .now() + 1)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    ProgramRunner.shared.finished(program.id, status: status, signaled: signaled)
                }
            }
        }

        do {
            try process.run()
            running.append(program)
            notice = nil
            info("▶ Indítás: \(name)")
        } catch {
            show(.error, "Nem sikerült elindítani: \(name). \(error.localizedDescription)")
        }
    }

    private func finished(_ id: UUID, status: Int32, signaled: Bool) {
        guard let index = running.firstIndex(where: { $0.id == id }) else { return }
        let program = running.remove(at: index)
        let tail = outputTails.removeValue(forKey: id) ?? []
        if signaled {
            info("■ Leállítva: \(program.name)")
        } else if status == 0 {
            info("■ Befejeződött: \(program.name)")
        } else {
            append(["■ Kilépett: \(program.name) (kód: \(status))"], .error)
            show(.error, program.isDOS
                 ? "„\(program.name)” hibával leállt (kód: \(status)). A részleteket a Naplóban találod."
                 : Self.explain(program.name, status: status, errors: tail))
        }
    }

    /// Turns Wine's last words into something a non-technical user can act on.
    private static func explain(_ name: String, status: Int32, errors: [String]) -> String {
        let text = errors.joined(separator: "\n").lowercased()
        if text.contains("bad exe format") || text.contains("bad format") || text.contains("not a valid") {
            return "„\(name)” nem indítható: a fájl sérült, vagy nem ilyen Windows programot tudok futtatni."
        }
        if text.contains("16-bit") || text.contains("winevdm") {
            return "„\(name)” egy régi 16 bites (DOS / Windows 3.1) program, ezt nem tudom futtatni."
        }
        if text.contains("mscoree") || text.contains(".net") {
            return "„\(name)” .NET-et igényel. Indítsd el újra, és ha a Wine felajánlja a „Wine Mono” telepítését, fogadd el."
        }
        if text.contains("vcruntime") || text.contains("msvcp") {
            return "„\(name)” a Microsoft Visual C++ csomagot igényli. Töltsd le a vc_redist.x64.exe fájlt a Microsofttól, és futtasd itt."
        }
        return "„\(name)” hibával leállt (kód: \(status)). A részleteket a Naplóban találod."
    }

    private func environment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = AppPaths.prefix.path
        if !verbose {
            env["WINEDEBUG"] = "-all"
            env["MVK_CONFIG_LOG_LEVEL"] = "0"
        }
        return env
    }

    private func remember(_ url: URL) {
        recent.removeAll { $0 == url }
        recent.insert(url, at: 0)
        recent = Array(recent.prefix(8))
        UserDefaults.standard.set(recent.map(\.path), forKey: "recent")
    }

    // MARK: - Log

    private nonisolated static func stream(_ handle: FileHandle, kind: LogLine.Kind, program: UUID?,
                                           drained: DispatchGroup) {
        let buffer = LineBuffer()
        drained.enter()
        handle.readabilityHandler = { h in
            let chunk = h.availableData
            let lines: [String]
            let finished = chunk.isEmpty
            if finished {
                h.readabilityHandler = nil
                lines = buffer.flush()
            } else {
                lines = buffer.feed(chunk)
            }
            defer { if finished { drained.leave() } }
            guard !lines.isEmpty else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let runner = ProgramRunner.shared
                    runner.append(lines, kind)
                    if let program {
                        runner.outputTails[program, default: []].append(contentsOf: lines)
                        runner.outputTails[program] = runner.outputTails[program].map { Array($0.suffix(30)) }
                    }
                }
            }
        }
    }

    private func show(_ kind: Notice.Kind, _ text: String) {
        notice = Notice(kind: kind, text: text)
        append([text], kind == .error ? .error : .info)
    }

    private func info(_ text: String) {
        append([text], .info)
    }

    private func append(_ lines: [String], _ kind: LogLine.Kind) {
        for text in lines {
            log.append(LogLine(id: nextLogID, text: text, kind: kind))
            nextLogID += 1
        }
        if log.count > maxLogLines {
            log.removeFirst(log.count - maxLogLines)
        }
    }
}
