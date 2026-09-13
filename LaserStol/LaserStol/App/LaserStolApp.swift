import SwiftUI

@main
struct LaserStolApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .frame(minWidth: 1080, minHeight: 700)
        }
        .windowStyle(HiddenTitleBarWindowStyle())
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Новая бирка…") { appState.sheet = .newTag }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Открыть изображение…") { appState.openImportPanel() }
                    .keyboardShortcut("o", modifiers: .command)
            }
            CommandMenu("Станок") {
                Button("Подключить макет GRBL") { appState.machine.connect(kind: .mock) }
                Button("Обновить порты") { appState.machine.refreshPorts() }
                Divider()
                Button("Превью рамки") { appState.beginJob(scope: .framePreview) }
                    .keyboardShortcut("p", modifiers: .command)
                Button("Старт всего листа") { appState.beginJob(scope: .wholeSheet) }
                    .keyboardShortcut(.return, modifiers: .command)
            }
            CommandMenu("Объект") {
                Button("Отразить по горизонтали") { appState.flipSelection(horizontal: true) }
                Button("Отразить по вертикали") { appState.flipSelection(horizontal: false) }
                Button("Повернуть на 90°") { appState.rotateSelection(degrees: 90) }
                Button("Инвертировать") { appState.invertSelection() }
                Divider()
                Button("Удалить") { appState.deleteSelection() }
                    .keyboardShortcut(.delete, modifiers: [])
            }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        WorkspaceView()
            .background(Theme.cream.ignoresSafeArea())
            .background(WindowAccessor { window in
                window.title = "Лазерный стол"
                window.titleVisibility = .hidden
                window.titlebarAppearsTransparent = true
                window.isMovableByWindowBackground = true
                window.backgroundColor = Theme.nsCream
                window.toolbarStyle = .unifiedCompact
            })
            .sheet(item: $app.sheet) { sheet in
                sheetHost(sheet)
            }
    }

    @ViewBuilder
    private func sheetHost(_ sheet: ActiveSheet) -> some View {
        switch sheet {
        case .newTag:
            NewTagWizard()
                .environmentObject(app)
        case .text:
            TextToolSheet()
                .environmentObject(app)
        case .monogram:
            MonogramPicker()
                .environmentObject(app)
        case .tileGrid:
            TileGridSheet()
                .environmentObject(app)
        case .preflight:
            PreflightView()
                .environmentObject(app)
        case .running:
            RunningJobView()
                .environmentObject(app)
        }
    }
}
