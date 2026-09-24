import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var runner: ProgramRunner
    @EnvironmentObject private var setup: SetupManager
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
            if showLog {
                Divider()
                logView
            } else {
                Spacer(minLength: 0)
            }
            Divider()
            statusBar
        }
        .toolbar { toolbar }
        .confirmationDialog("Visszaállítod a Windows környezetet?", isPresented: $confirmReset) {
            Button("Visszaállítás", role: .destructive) { setup.resetWindows() }
        } message: {
            Text("Minden futó Windows program leáll, és a C: meghajtó tartalma (a telepített programokkal együtt) a Kukába kerül. Utána egy új, tiszta környezet jön létre.")
        }
    }

    // MARK: - Drop zone

    private var dropZone: some View {
        VStack(spacing: 10) {
            Image(systemName: dropTargeted ? "arrow.down.app.fill" : "arrow.down.app")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(dropTargeted ? Color.accentColor : .secondary)
            Text("Húzd ide a Windows vagy DOS programot")
                .font(.title3.weight(.semibold))
            Text(".exe, .com, .msi vagy .bat — vagy kattints a kiválasztáshoz")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 170)
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
