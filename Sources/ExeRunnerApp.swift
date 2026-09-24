import SwiftUI
import AppKit

@main
struct ExeRunnerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var runner = ProgramRunner.shared
    @StateObject private var setup = SetupManager.shared
    @StateObject private var updater = Updater.shared

    var body: some Scene {
        Window("EXEKI", id: "main") {
            RootView()
                .environmentObject(runner)
                .environmentObject(setup)
                .frame(minWidth: 620, minHeight: 460)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Megnyitás…") { runner.chooseAndRun() }
                    .keyboardShortcut("o")
                    .disabled(setup.step != .ready)
            }
            CommandGroup(after: .appInfo) {
                Button("Frissítések keresése…") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
                Button("Licencek és forráskód") { openLicenses() }
            }
        }
    }

    private func openLicenses() {
        if let url = Bundle.main.url(forResource: "Licencek", withExtension: "txt") {
            NSWorkspace.shared.open(url)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var setup: SetupManager

    var body: some View {
        Group {
            if setup.step == .ready {
                ContentView()
            } else {
                SetupView()
            }
        }
        .onAppear { setup.startOnce() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Finder double-click, "Open With" and drops onto the Dock icon all arrive here.
    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated {
            SetupManager.shared.open(urls)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
