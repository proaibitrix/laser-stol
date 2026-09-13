import SwiftUI

struct RunningJobView: View {
    @EnvironmentObject private var app: AppState

    private var percent: Int {
        Int((app.machine.progress * 100).rounded())
    }

    var body: some View {
        VStack(spacing: 22) {
            Text("Идёт работа")
                .font(.system(size: 26, weight: .semibold))
                .foregroundColor(Theme.ink)
                .padding(.top, 8)

            HStack(spacing: 22) {
                ZStack {
                    Circle()
                        .stroke(Theme.line, lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: CGFloat(app.machine.progress))
                        .stroke(Theme.progress, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(percent)%")
                        .font(.system(size: 16, weight: .semibold))
                }
                .frame(width: 86, height: 86)

                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: app.machine.progress)
                        .progressViewStyle(LinearProgressViewStyle(tint: Theme.progress))
                        .frame(width: 280)
                    Text(app.machine.statusCaption.isEmpty ? "Вырезаю контур…" : app.machine.statusCaption)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.mute)
                }
            }

            HeadSilhouette()
                .frame(height: 120)
                .padding(.horizontal, 36)

            HStack(spacing: 16) {
                Button {
                    if app.machine.phase == .paused {
                        app.machine.resume()
                    } else {
                        app.machine.pause()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: app.machine.phase == .paused ? "play.fill" : "pause.fill")
                        Text(app.machine.phase == .paused ? "Дальше" : "Пауза")
                    }
                    .frame(width: 130, height: 36)
                }
                .buttonStyle(CompactButtonStyle())

                Button {
                    app.machine.stop()
                    app.sheet = nil
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "stop.fill")
                        Text("Стоп")
                    }
                    .frame(width: 130, height: 36)
                    .foregroundColor(.white)
                    .background(Capsule().fill(Theme.stop))
                }
                .buttonStyle(.plain)
            }

            if app.machine.phase == .finished {
                Button("Готово") { app.sheet = nil }
                    .buttonStyle(CompactButtonStyle(prominent: true))
            }

            HStack(spacing: 6) {
                Image(systemName: "leaf.circle")
                    .foregroundColor(Theme.progress)
                Text("Можно отойти, приложение само напишет когда готово")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.mute)
            }
            .padding(.bottom, 8)
        }
        .padding(28)
        .frame(width: 560, height: 460)
        .background(Theme.cream)
    }

}

struct HeadSilhouette: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Theme.line, lineWidth: 1)
                    )
                Path { path in
                    let x0 = w * 0.34
                    let y0 = h * 0.22
                    path.move(to: CGPoint(x: x0, y: y0 + h * 0.18))
                    path.addQuadCurve(
                        to: CGPoint(x: x0 + w * 0.22, y: y0),
                        control: CGPoint(x: x0 + w * 0.04, y: y0 - h * 0.04)
                    )
                    path.addQuadCurve(
                        to: CGPoint(x: x0 + w * 0.30, y: y0 + h * 0.42),
                        control: CGPoint(x: x0 + w * 0.36, y: y0 + h * 0.10)
                    )
                    path.addQuadCurve(
                        to: CGPoint(x: x0 + w * 0.16, y: y0 + h * 0.58),
                        control: CGPoint(x: x0 + w * 0.32, y: y0 + h * 0.62)
                    )
                    path.addLine(to: CGPoint(x: x0, y: y0 + h * 0.50))
                    path.closeSubpath()
                }
                .stroke(Theme.ink.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

                Path { path in
                    path.move(to: CGPoint(x: w * 0.62, y: h * 0.58))
                    path.addLine(to: CGPoint(x: w * 0.70, y: h * 0.64))
                }
                .stroke(Theme.ink.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

                Circle()
                    .fill(Theme.ink.opacity(0.7))
                    .frame(width: 7, height: 7)
                    .position(x: w * 0.70, y: h * 0.64)
            }
        }
    }
}
