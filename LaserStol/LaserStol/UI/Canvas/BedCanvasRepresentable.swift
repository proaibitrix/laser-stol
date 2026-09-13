import SwiftUI

struct BedCanvasRepresentable: NSViewRepresentable {
    @EnvironmentObject var app: AppState

    func makeNSView(context: Context) -> BedCanvasView {
        let view = BedCanvasView()
        view.app = app
        return view
    }

    func updateNSView(_ nsView: BedCanvasView, context: Context) {
        nsView.app = app
        nsView.needsDisplay = true
    }
}
