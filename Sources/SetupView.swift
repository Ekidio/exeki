import SwiftUI

/// First-launch screen: one clear message and at most one button per step.
struct SetupView: View {
    @EnvironmentObject private var setup: SetupManager

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            content
                .frame(maxWidth: 440)
                .multilineTextAlignment(.center)
            Spacer()
            if showsStepCounter {
                Text("Az első indításkor egyszer kell elvégezni, utána azonnal indul.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.2), value: setup.step)
    }

    @ViewBuilder
    private var content: some View {
        switch setup.step {
        case .checking, .ready:
            ProgressView()
                .controlSize(.small)

        case .moveToApplications:
            title("Tedd az Alkalmazások közé")
            message("Az EXEKI most a Letöltések mappából vagy a telepítő lemezről fut. Egy kattintással áthelyezem a helyére.")
            Button("Áthelyezés az Alkalmazások mappába") { setup.moveToApplications() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            Button("Most nem") { setup.skipMove() }
                .buttonStyle(.link)

        case .needsRosetta:
            title("Még egy Apple kiegészítő kell")
            message("A Windows programokhoz az Apple ingyenes Rosetta kiegészítője szükséges. A telepítéshez a Mac jelszavát kéri a rendszer.")
            Button("Rosetta telepítése") { setup.installRosetta() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

        case .installingRosetta:
            title("Rosetta telepítése…")
            message("Ez 1–2 percig tarthat.")
            ProgressView().controlSize(.small)

        case .downloading(let fraction, let isUpdate):
            title(isUpdate ? "Windows-futtató motor frissítése" : "Windows-futtató motor letöltése")
            ProgressView(value: fraction)
                .frame(width: 320)
            message("\(Int(fraction * 100))%  ·  kb. \(Int(Double(Engine.wine.size) / 1_000_000)) MB")

        case .preparingWindows:
            title("Windows környezet előkészítése…")
            message("Létrehozom a virtuális C: meghajtót. Ez 1–2 percig tarthat.")
            ProgressView().controlSize(.small)

        case .failed(let error):
            title("Valami nem sikerült")
            message(error)
            Button("Újrapróbálás") { setup.retry() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }

    private var showsStepCounter: Bool {
        switch setup.step {
        case .downloading, .preparingWindows: true
        default: false
        }
    }

    private func title(_ text: String) -> some View {
        Text(text).font(.title2.weight(.semibold))
    }

    private func message(_ text: String) -> some View {
        Text(text).foregroundStyle(.secondary)
    }
}
