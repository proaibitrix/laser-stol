import SwiftUI

struct BottomBar: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        HStack(spacing: 10) {
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
            .padding(.leading, 18)

            Spacer()

            barButton(icon: "flame", title: "Выжечь слой") {
                app.beginJob(scope: .burnLayer)
            }
            barButton(icon: "scissors", title: "Вырезать слой") {
                app.beginJob(scope: .cutLayer)
            }
            barButton(icon: "eye", title: "Превью") {
                app.beginJob(scope: .framePreview)
            }
            Button {
                app.beginJob(scope: .wholeSheet)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9))
                    Text("Старт всего листа")
                }
            }
            .buttonStyle(CompactButtonStyle(prominent: true))
            .padding(.trailing, 16)
        }
        .frame(height: 54)
        .background(Theme.cream)
    }

    private func barButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(title)
            }
        }
        .buttonStyle(CompactButtonStyle())
    }
}
