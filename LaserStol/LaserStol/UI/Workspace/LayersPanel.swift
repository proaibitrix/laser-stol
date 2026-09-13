import SwiftUI

struct LayersPanel: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Слои")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.ink)

            ForEach(app.document.layers) { layer in
                layerRow(layer)
            }

            ItemInspector()

            Spacer()

            VStack(spacing: 8) {
                Button {
                    addLayerHint()
                } label: {
                    Label("слой", systemImage: "plus")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(CompactButtonStyle())

                Button {
                    app.sheet = .tileGrid
                } label: {
                    Label("Размножить сеткой", systemImage: "square.grid.3x3")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(CompactButtonStyle())
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.card)
                .shadow(color: Color.black.opacity(0.04), radius: 10, y: 2)
        )
    }

    private func layerRow(_ layer: LaserLayer) -> some View {
        HStack(spacing: 8) {
            Button {
                toggleVisibility(layer)
            } label: {
                Image(systemName: layer.isVisible ? "eye" : "eye.slash")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.mute)
            }
            .buttonStyle(.plain)

            Text(layer.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.ink)

            Spacer()

            if layer.kind == .cut {
                dashedIcon
            } else {
                Capsule()
                    .fill(Theme.ink.opacity(0.55))
                    .frame(width: 18, height: 2)
            }
        }
        .padding(.vertical, 6)
    }

    private var dashedIcon: some View {
        HStack(spacing: 2) {
            ForEach(0..<4, id: \.self) { _ in
                Capsule().fill(Theme.ink.opacity(0.45)).frame(width: 4, height: 2)
            }
        }
    }

    private func toggleVisibility(_ layer: LaserLayer) {
        guard let index = app.document.layers.firstIndex(where: { $0.id == layer.id }) else { return }
        app.document.layers[index].isVisible.toggle()
    }

    private func addLayerHint() {
        // v1: фиксированная пара Прожиг/Рез — повторное нажатие просто показывает панель.
        app.showLayers = true
    }
}

struct ItemInspector: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        if let item = app.primarySelection {
            VStack(alignment: .leading, spacing: 8) {
                Text(item.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.ink)
                    .lineLimit(1)

                Text("Порог ч/б")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.mute)
                Slider(
                    value: Binding(
                        get: { item.effectiveThreshold },
                        set: { app.setThreshold($0) }
                    ),
                    in: 0.08...0.92
                )
                .accentColor(Theme.terracotta)

                HStack(spacing: 6) {
                    mini("Инверт", action: app.invertSelection)
                    mini("↔︎") { app.flipSelection(horizontal: true) }
                    mini("↕︎") { app.flipSelection(horizontal: false) }
                    mini("90°") { app.rotateSelection(degrees: 90) }
                }

                Picker("Материал", selection: Binding(
                    get: { app.document.materialID },
                    set: { id in
                        app.applyMaterial(MaterialPreset.preset(id: id))
                    }
                )) {
                    ForEach(MaterialPreset.builtIn) { preset in
                        Text(preset.name).tag(preset.id)
                    }
                }
                .font(.system(size: 11))
            }
            .padding(.top, 8)
        } else {
            Text("Выберите объект на столе")
                .font(.system(size: 11))
                .foregroundColor(Theme.mute)
                .padding(.top, 6)
        }
    }

    private func mini(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(Theme.ink)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Capsule().fill(Theme.creamDeep))
            .buttonStyle(.plain)
    }
}
