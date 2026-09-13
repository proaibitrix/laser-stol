import SwiftUI

struct RunningJobView: View {
    @EnvironmentObject private var app: AppState

    private var percent: Int {
        Int((app.machine.progress * 100).rounded())
    }

    private var isDemo: Bool { app.machine.isDemo }

    private var titleText: String {
        switch app.machine.phase {
        case .demoFinished: return "Демо завершено"
        case .finished: return "Готово"
        case .failed: return "Ошибка"
        case .cancelled: return "Остановлено"
        default: return isDemo ? "Демо-прогон" : "Идёт работа"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 18) {
                    Text(titleText)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(Theme.ink)
                        .padding(.top, 8)

                    if isDemo {
                        Text("Макет GRBL — станок не подключён, лазер не двигается.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Theme.mute)
                            .multilineTextAlignment(.center)
                    }

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
                                .foregroundColor(Theme.ink)
                        }
                        .frame(width: 86, height: 86)

                        VStack(alignment: .leading, spacing: 8) {
                            ProgressView(value: app.machine.progress)
                                .progressViewStyle(LinearProgressViewStyle(tint: Theme.progress))
                                .frame(width: 260)
                            Text(statusLine)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Theme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    HeadSilhouette()
                        .frame(height: 110)
                        .padding(.horizontal, 24)

                    if case .failed(let message) = app.machine.phase {
                        Text(message)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Theme.stop)
                            .multilineTextAlignment(.center)
                    }

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
                        .disabled(app.machine.phase == .finished || app.machine.phase == .demoFinished || isTerminal)

                        Button {
                            app.machine.stop()
                            app.sheet = nil
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "stop.fill")
                                Text("Стоп")
                                    .foregroundColor(Color(red: 1, green: 1, blue: 1))
                            }
                            .frame(width: 130, height: 36)
                            .foregroundColor(Color(red: 1, green: 1, blue: 1))
                            .background(Capsule().fill(Theme.stop))
                        }
                        .buttonStyle(.plain)
                    }

                    if app.machine.phase == .finished || app.machine.phase == .demoFinished || isTerminal {
                        Button(app.machine.phase == .demoFinished ? "Закрыть демо" : "Закрыть") {
                            app.sheet = nil
                        }
                        .buttonStyle(CompactButtonStyle(prominent: true))
                    }

                    HStack(spacing: 6) {
                        Image(systemName: isDemo ? "exclamationmark.circle" : "leaf.circle")
                            .foregroundColor(isDemo ? Theme.terracotta : Theme.progress)
                        Text(footerNote)
                            .font(.system(size: 11))
                            .foregroundColor(Theme.mute)
                    }
                    .padding(.bottom, 8)
                }
                .padding(24)
            }
        }
        .frame(minWidth: 480, idealWidth: 560, maxWidth: 640, minHeight: 400, idealHeight: 500)
        .creamSurface()
        .background(Theme.cream)
    }

    private var isTerminal: Bool {
        switch app.machine.phase {
        case .failed, .cancelled: return true
        default: return false
        }
    }

    private var statusLine: String {
        if app.machine.statusCaption.isEmpty {
            return isDemo ? "Демо: считаю строки…" : "Вырезаю контур…"
        }
        return app.machine.statusCaption
    }

    private var footerNote: String {
        if isDemo {
            return "Это прогон интерфейса. Для реза подключите последовательный порт."
        }
        return "Можно отойти, приложение само напишет когда готово"
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
