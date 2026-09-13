import SwiftUI

struct ToolRail: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        VStack(spacing: 6) {
            QuietIconButton(systemName: "folder", title: "Открыть", selected: false) {
                app.openImportPanel()
            }
            QuietIconButton(systemName: "textformat", title: "Текст", selected: app.sheet == .text) {
                app.sheet = .text
            }
            QuietIconButton(systemName: "circle.dotted", title: "Фигуры", selected: app.sheet == .newTag) {
                app.sheet = .newTag
            }
            QuietIconButton(systemName: "snowflake", title: "Монограмма", selected: app.sheet == .monogram) {
                app.sheet = .monogram
            }
            QuietIconButton(
                systemName: "pencil.and.outline",
                title: "Контур",
                selected: app.tool == .contour
            ) {
                app.tool = app.tool == .contour ? .select : .contour
                app.contourDraft = []
            }
            Spacer()
        }
        .padding(.top, 12)
        .padding(.horizontal, 8)
        .background(Theme.cream)
    }
}
