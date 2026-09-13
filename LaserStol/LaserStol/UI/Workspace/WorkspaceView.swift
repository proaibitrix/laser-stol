import SwiftUI

struct WorkspaceView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        VStack(spacing: 0) {
            TitleBar()
            Divider().opacity(0.15)
            HStack(spacing: 0) {
                ToolRail()
                    .frame(width: 92)
                BedCanvasRepresentable()
                    .padding(18)
                if app.showLayers {
                    LayersPanel()
                        .frame(width: 220)
                        .padding(.trailing, 16)
                        .padding(.vertical, 18)
                }
            }
            Divider().opacity(0.15)
            BottomBar()
        }
        .background(Theme.cream)
    }
}

struct TitleBar: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        ZStack {
            HStack {
                Color.clear.frame(width: 68, height: 12)
                Spacer()
                ConnectionChip()
                    .padding(.trailing, 16)
            }
            VStack(spacing: 2) {
                Text("Лазерный стол")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.ink)
                Text(String(format: "%.0f × %.0f мм", app.document.bedWidthMM, app.document.bedHeightMM))
                    .font(.system(size: 10))
                    .foregroundColor(Theme.mute)
            }
        }
        .frame(height: 46)
        .padding(.top, 8)
    }
}

struct ConnectionChip: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        Button {
            app.showConnectionPopover.toggle()
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(app.machine.connection.isReady
                          ? (app.machine.isDemo ? Theme.terracotta : Theme.good)
                          : Theme.mute)
                    .frame(width: 7, height: 7)
                Text(app.machine.connectionLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.ink)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Theme.card))
            .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $app.showConnectionPopover, arrowEdge: .bottom) {
            ConnectionPopover()
                .environmentObject(app)
        }
    }
}

struct ConnectionPopover: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Связь со станком")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.ink)
            Text(app.machine.isDemo
                 ? "Сейчас макет GRBL: лазер не двигается."
                 : "Канал: последовательный порт.")
                .font(.system(size: 11))
                .foregroundColor(Theme.mute)
            Picker("Канал", selection: $app.machine.transportKind) {
                ForEach(TransportKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.radioGroup)

            if app.machine.transportKind == .serial {
                if app.machine.availablePorts.isEmpty {
                    Text("Порты не найдены. Подключите USB-UART и нажмите «Обновить».")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.mute)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Picker("Порт", selection: $app.machine.selectedPortPath) {
                        ForEach(app.machine.availablePorts) { port in
                            Text(port.name).tag(port.path)
                        }
                    }
                }
                Button("Обновить список") { app.machine.refreshPorts() }
            }

            HStack {
                Button("Подключить") {
                    app.machine.connect(kind: app.machine.transportKind)
                    app.showConnectionPopover = false
                }
                Button("Отключить") {
                    app.machine.disconnect()
                }
            }
            if let err = app.machine.lastError {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.stop)
            }
        }
        .padding(16)
        .frame(width: 300)
        .creamSurface()
        .background(Theme.cream)
    }
}
