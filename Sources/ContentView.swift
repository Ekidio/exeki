import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var runner: ProgramRunner
    @EnvironmentObject private var setup: SetupManager
    @ObservedObject private var library = ProgramLibrary.shared
    @AppStorage("showLog") private var showLog = false
    @State private var dropTargeted = false
    @State private var confirmReset = false

    var body: some View {
        VStack(spacing: 0) {
            dropZone
                .padding(16)
            if let download = runner.engineDownload {
                engineDownloadRow(download)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
            if let notice = runner.notice {
                noticeBanner(notice)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
            if !runner.running.isEmpty {
                runningList
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
            if !library.programs.isEmpty {
                programsSection
                    .frame(maxHeight: showLog ? 190 : .infinity)
            }
            if showLog {
                Divider()
                logView
            } else if library.programs.isEmpty {
                Text("A telepített programjaid itt fognak megjelenni.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            statusBar
        }
        .toolbar { toolbar }
        .onAppear { library.refresh() }
        .confirmationDialog("Visszaállítod a Windows környezetet?", isPresented: $confirmReset) {
            Button("Visszaállítás", role: .destructive) { setup.resetWindows() }
        } message: {
            Text("Minden futó Windows program leáll, és a C: meghajtó tartalma (a telepített programokkal együtt) a Kukába kerül. Utána egy új, tiszta környezet jön létre.")
        }
    }

    // MARK: - Drop zone

    private var dropZone: some View {
        let compact = !library.programs.isEmpty
        return VStack(spacing: compact ? 6 : 10) {
            Image(systemName: dropTargeted ? "arrow.down.app.fill" : "arrow.down.app")
                .font(.system(size: compact ? 28 : 42, weight: .light))
                .foregroundStyle(dropTargeted ? Color.accentColor : .secondary)
            Text("Húzd ide a Windows vagy DOS programot")
                .font(compact ? .headline : .title3.weight(.semibold))
            Text(".exe, .com, .msi vagy .bat — vagy kattints a kiválasztáshoz")
                .font(compact ? .caption : .callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: compact ? 110 : 170)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(dropTargeted ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .foregroundStyle(dropTargeted ? Color.accentColor : Color.secondary.opacity(0.4))
        )
        .contentShape(Rectangle())
        .onTapGesture { runner.chooseAndRun() }
        .dropDestination(for: URL.self) { urls, _ in
            urls.forEach(runner.run)
            return !urls.isEmpty
        } isTargeted: { dropTargeted = $0 }
        .animation(.easeOut(duration: 0.15), value: dropTargeted)
    }

    private func engineDownloadRow(_ download: EngineDownload) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(download.title)
                Spacer()
                Text("\(Int(download.fraction * 100))%")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: download.fraction)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.08)))
    }

    private func noticeBanner(_ notice: Notice) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: notice.kind == .error ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(notice.kind == .error ? Color.orange : Color.green)
            Text(notice.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            if notice.kind == .error && !showLog {
                Button("Napló") { showLog = true }
                    .buttonStyle(.link)
            }
            Button {
                runner.notice = nil
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill((notice.kind == .error ? Color.orange : Color.green).opacity(0.12))
        )
    }

    // MARK: - Installed programs

    private var programsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Programjaim")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 4)], spacing: 4) {
                    ForEach(library.programs) { program in
                        ProgramTile(
                            program: program,
                            icon: library.icon(for: program),
                            isRunning: runner.running.contains {
                                $0.name == program.name || $0.name == program.exe.lastPathComponent
                            },
                            onRun: { runner.runInstalled(program) },
                            onReveal: { NSWorkspace.shared.activateFileViewerSelecting([program.exe]) },
                            onRemove: { library.remove(program) })
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
    }

    // MARK: - Running programs

    private var runningList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Fut")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(runner.running) { program in
                HStack {
                    ProgressView().controlSize(.small)
                    Text(program.name).lineLimit(1).truncationMode(.middle)
                    if program.isDOS {
                        Text("DOS")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.secondary.opacity(0.15)))
                    }
                    Text(program.started, style: .timer)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Leállítás") { runner.stop(program) }
                        .controlSize(.small)
                }
            }
        }
    }

    // MARK: - Log

    private var logView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(runner.log) { line in
                        Text(line.text)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(color(for: line.kind))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(line.id)
                    }
                }
                .padding(10)
                .textSelection(.enabled)
            }
            .overlay {
                if runner.log.isEmpty {
                    Text("A programok kimenete itt jelenik meg")
                        .foregroundStyle(.tertiary)
                }
            }
            .onChange(of: runner.log.last?.id) { _, id in
                if let id { proxy.scrollTo(id, anchor: .bottom) }
            }
            .onAppear {
                if let id = runner.log.last?.id { proxy.scrollTo(id, anchor: .bottom) }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func color(for kind: LogLine.Kind) -> Color {
        switch kind {
        case .info: .accentColor
        case .output: .primary
        case .error: .orange
        }
    }

    private var statusBar: some View {
        HStack(spacing: 6) {
            Button {
                showLog.toggle()
            } label: {
                Label(showLog ? "Napló elrejtése" : "Napló", systemImage: "text.alignleft")
            }
            .buttonStyle(.borderless)
            Spacer()
            Circle()
                .fill(Color.green)
                .frame(width: 7, height: 7)
            Text("Kész")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button { runner.chooseAndRun() } label: {
                Label("Megnyitás", systemImage: "folder")
            }
            .help("Program kiválasztása és futtatása")

            Menu {
                if runner.recent.isEmpty {
                    Text("Még nincs")
                }
                ForEach(runner.recent, id: \.self) { url in
                    Button(url.lastPathComponent) { runner.run(url) }
                }
            } label: {
                Label("Legutóbbiak", systemImage: "clock.arrow.circlepath")
            }
            .help("Legutóbb futtatott programok")

            Button { runner.openDriveC() } label: {
                Label("C: meghajtó", systemImage: "internaldrive")
            }
            .help("A virtuális C: meghajtó megnyitása a Finderben — itt vannak a telepített programok")

            Button { runner.stopAll() } label: {
                Label("Mindent leállít", systemImage: "stop.circle")
            }
            .help("Minden futó program leállítása")

            Menu {
                Button("Program hozzáadása a listához…") { library.chooseAndPin() }
                if library.hiddenCount > 0 {
                    Button("Elrejtett programok visszahozása (\(library.hiddenCount))") { library.showHidden() }
                }
                Divider()
                Button("Legyen ez az .exe fájlok megnyitója") { runner.makeDefaultHandler() }
                Divider()
                Button("Futtatás a DOS-motorral…") { runner.chooseAndRun(forceEngine: .dos) }
                Button("Futtatás a Windows-motorral…") { runner.chooseAndRun(forceEngine: .windows) }
                Divider()
                Button("Wine beállítások (winecfg)") { runner.runTool("winecfg") }
                Button("Windows parancssor") { runner.runTool("wineconsole") }
                Button("Rendszerleíró-szerkesztő") { runner.runTool("regedit") }
                Divider()
                Toggle("Részletes Wine napló", isOn: $runner.verbose)
                Button("Napló törlése") { runner.clearLog() }
                Divider()
                Button("Windows környezet visszaállítása…") { confirmReset = true }
            } label: {
                Label("Továbbiak", systemImage: "ellipsis.circle")
            }
        }
    }
}

/// One program in the "Programjaim" grid: its own icon and name; a click starts it.
private struct ProgramTile: View {
    let program: InstalledProgram
    let icon: NSImage
    let isRunning: Bool
    let onRun: () -> Void
    let onReveal: () -> Void
    let onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        // A real Button (not a tap gesture) so VoiceOver and the keyboard can start programs too.
        Button(action: onRun) {
            VStack(spacing: 6) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 48, height: 48)
                Text(program.name)
                    .font(.callout)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(height: 34, alignment: .top)
            }
            .frame(width: 104)
            .padding(.vertical, 10)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(hovering ? Color.secondary.opacity(0.12) : Color.clear)
            )
            .overlay(alignment: .topTrailing) {
                if isRunning {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                        .padding(8)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("\(program.name) indítása")
        .accessibilityLabel(isRunning ? "\(program.name), fut" : program.name)
        .contextMenu {
            Button("Indítás", action: onRun)
            Button("Megjelenítés a Finderben", action: onReveal)
            Divider()
            Button(program.isPinned ? "Eltávolítás a listából" : "Elrejtés a listából", action: onRemove)
        }
    }
}
