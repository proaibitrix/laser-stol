import SwiftUI

struct TextToolSheet: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Текст")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(Theme.ink)
            TextField("Надпись", text: $app.draftText)
                .textFieldStyle(.roundedBorder)
                .foregroundColor(Theme.ink)
                .frame(width: 320)
            Text("Будет выжжена как чёрно-белый рисунок на слое «Прожиг».")
                .font(.system(size: 11))
                .foregroundColor(Theme.mute)
            HStack {
                Spacer()
                Button("Отмена") { app.sheet = nil }
                    .buttonStyle(CompactButtonStyle())
                Button("Добавить") { app.addText(app.draftText) }
                    .buttonStyle(CompactButtonStyle(prominent: true))
            }
        }
        .padding(24)
        .frame(minWidth: 380, minHeight: 200)
        .creamSurface()
        .background(Theme.cream)
    }
}
