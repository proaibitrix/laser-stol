import SwiftUI

struct TileGridSheet: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Размножить сеткой")
                .font(.system(size: 20, weight: .semibold))
            Text("Копии выбранных объектов раскладываются по листу 400×400 мм с зазором.")
                .font(.system(size: 12))
                .foregroundColor(Theme.mute)

            stepper("Столбцы", intValue: $app.tileColumns, range: 1...12)
            stepper("Строки", intValue: $app.tileRows, range: 1...12)
            HStack {
                Text("Зазор")
                    .frame(width: 80, alignment: .leading)
                Slider(value: $app.tileGapMM, in: 0...20)
                    .accentColor(Theme.terracotta)
                Text(String(format: "%.1f мм", app.tileGapMM))
                    .font(.system(size: 11))
                    .foregroundColor(Theme.mute)
                    .frame(width: 64, alignment: .trailing)
            }

            if let first = app.selectedItems.first ?? app.document.items.first {
                let size = TileGridMath.totalSize(
                    columns: app.tileColumns,
                    rows: app.tileRows,
                    itemWidth: first.transform.width,
                    itemHeight: first.transform.height,
                    gapMM: app.tileGapMM
                )
                Text(String(format: "Займёт примерно %.0f × %.0f мм", size.width, size.height))
                    .font(.system(size: 11))
                    .foregroundColor(size.width > app.document.bedWidthMM || size.height > app.document.bedHeightMM ? Theme.stop : Theme.mute)
            }

            HStack {
                Spacer()
                Button("Отмена") { app.sheet = nil }
                    .buttonStyle(CompactButtonStyle())
                Button("Размножить") { app.applyTileGrid() }
                    .buttonStyle(CompactButtonStyle(prominent: true))
            }
        }
        .padding(24)
        .frame(width: 460)
        .background(Theme.cream)
    }

    private func stepper(_ title: String, intValue: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack {
            Text(title).frame(width: 80, alignment: .leading)
            Stepper(value: intValue, in: range) {
                Text("\(intValue.wrappedValue)")
                    .frame(width: 28)
            }
        }
        .font(.system(size: 13))
    }
}
