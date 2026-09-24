import AppKit

enum SetupStep: Equatable {
    case checking
    case moveToApplications
    case needsRosetta
    case installingRosetta
    /// `isUpdate` when an older engine is replaced after an app update.
    case downloading(Double, isUpdate: Bool)
    case preparingWindows
    case ready
    case failed(String)
}

/// Walks a fresh Mac through everything needed before the first EXE can run.
@MainActor
final class SetupManager: ObservableObject {
    static let shared = SetupManager()

    @Published private(set) var step: SetupStep = .checking
    private var started = false
    private var skippedMove = false
    private var pendingFiles: [URL] = []

    /// Files opened from Finder before setup finished are run once it is done.
    func open(_ urls: [URL]) {
        if step == .ready {
            urls.forEach(ProgramRunner.shared.run)
        } else {
            pendingFiles += urls
        }
    }

    func startOnce() {
        guard !started else { return }
        started = true
        if let preview = ProcessInfo.processInfo.environment["EXEKI_PREVIEW_STEP"] {
            step = Self.previewStep(preview)
            return
        }
        retry()
    }

    func retry() {
        Task { await advance() }
    }

    func skipMove() {
        skippedMove = true
        retry()
    }

    func moveToApplications() {
        do {
            try AppLocation.moveToApplicationsAndRelaunch()
        } catch {
            step = .failed("Nem sikerült áthelyezni: \(error.localizedDescription). Húzd át kézzel az Alkalmazások mappába.")
        }
    }

    func installRosetta() {
        step = .installingRosetta
        Task {
            do {
                if try await Rosetta.install() {
                    await advance()
                } else {
                    step = .needsRosetta
                }
            } catch {
                step = .failed(error.localizedDescription)
            }
        }
    }

    /// Wipes the Windows environment and builds a fresh one (the "fix everything" button).
    func resetWindows() {
        ProgramRunner.shared.stopAll()
        step = .preparingWindows
        Task {
            try? await Task.sleep(for: .seconds(2))
            try? FileManager.default.trashItem(at: AppPaths.prefix, resultingItemURL: nil)
            await advance()
        }
    }

    private func advance() async {
        step = .checking
        if !skippedMove && AppLocation.needsMove {
            step = .moveToApplications
            return
        }
        if Rosetta.isNeeded && !Rosetta.isInstalled {
            step = .needsRosetta
            return
        }
        do {
            let wine = Engine.wine
            if !wine.isInstalled {
                let isUpdate = wine.needsUpdate
                step = .downloading(0, isUpdate: isUpdate)
                try await wine.install { progress in
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            SetupManager.shared.step = .downloading(progress, isUpdate: isUpdate)
                        }
                    }
                }
            }
            if !FileManager.default.fileExists(atPath: AppPaths.prefixReadyMarker.path) {
                step = .preparingWindows
                try await ProgramRunner.shared.initializePrefix()
            }
            step = .ready
            let files = pendingFiles
            pendingFiles = []
            files.forEach(ProgramRunner.shared.run)
        } catch {
            step = .failed(error.localizedDescription)
        }
    }

    private static func previewStep(_ name: String) -> SetupStep {
        switch name {
        case "move": .moveToApplications
        case "rosetta": .needsRosetta
        case "rosetta-installing": .installingRosetta
        case "download": .downloading(0.42, isUpdate: false)
        case "update": .downloading(0.42, isUpdate: true)
        case "windows": .preparingWindows
        case "failed": .failed(SetupError.download("The Internet connection appears to be offline.").localizedDescription)
        default: .checking
        }
    }
}
