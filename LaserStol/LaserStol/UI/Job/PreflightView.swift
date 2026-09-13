import SwiftUI

struct PreflightView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        VStack(spacing: 0) {
            Text("Лазерная гравировка и резка")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.mute)
                .padding(.top, 16)
                .padding(.bottom, 10)

            HStack(alignment: .top, spacing: 36) {
                previewColumn
                checksColumn
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 18)

            HStack {
                Spacer()
                Button {
                    app.sheet = nil
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark")
                        Text("Отмена")
                    }
                }
                .buttonStyle(CompactButtonStyle())

                Button {
                    app.confirmStart()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                        Text("Начать")
                    }
                }
                .buttonStyle(CompactButtonStyle(prominent: true))
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 22)
        }
        .frame(width: 860, height: 540)
        .background(Theme.cream)
    }

    private var previewColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Превью траектории")
                .font(.system(size: 20, weight: .semibold))
            Text("Как лазер обработает ваш объект")
                .font(.system(size: 12))
                .foregroundColor(Theme.mute)

            TrajectoryPreview(document: app.document)
                .frame(width: 360, height: 280)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Theme.woodLight)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Theme.dashCut.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                )

            HStack(spacing: 16) {
                legend(Theme.dashCut, "Рез (контур)", dashed: true)
                legend(Theme.burnDot, "Гравировка (прожиг)", dashed: false)
            }
            .padding(.top, 4)
        }
    }

    private var checksColumn: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Проверка перед запуском")
                .font(.system(size: 20, weight: .semibold))
            Text("Проверьте все параметры для безопасной работы")
                .font(.system(size: 12))
                .foregroundColor(Theme.mute)

            checkRow(
                icon: "scope",
                title: "Лазер на месте",
                subtitle: app.machine.connection.isReady
                    ? "Лазерная головка готова к работе"
                    : "Сначала подключите станок или макет",
                on: app.machine.connection.isReady
            )
            checkRow(
                icon: "checkmark.shield",
                title: "Объект в пределах стола",
                subtitle: app.document.itemsFitBed()
                    ? "Все контуры внутри 400×400 мм"
                    : "Часть объектов выходит за край стола",
                on: app.document.itemsFitBed()
            )

            StrengthSlider(
                title: "Мощность",
                labels: ProcessStrength.allCases.map(\.powerTitle),
                value: Binding(
                    get: { app.document.job.power },
                    set: {
                        app.document.job.power = $0
                        app.lastJob = app.buildJob(scope: app.pendingScope)
                    }
                )
            )
            StrengthSlider(
                title: "Скорость",
                labels: ProcessStrength.allCases.map(\.speedTitle),
                value: Binding(
                    get: { app.document.job.speed },
                    set: {
                        app.document.job.speed = $0
                        app.lastJob = app.buildJob(scope: app.pendingScope)
                    }
                )
            )

            if let job = app.lastJob {
                Text("Оценка времени: \(TimeEstimator.formatDuration(job.estimatedSeconds))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.ink)
                Text("Строк G-code: \(job.lineCount)")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.mute)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func checkRow(icon: String, title: String, subtitle: String, on: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(Theme.terracotta)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(subtitle).font(.system(size: 10)).foregroundColor(Theme.mute)
            }
            Spacer()
            Circle()
                .fill(on ? Theme.good : Theme.line)
                .frame(width: 22, height: 14)
                .overlay(
                    Circle()
                        .fill(Color.white)
                        .frame(width: 10, height: 10)
                        .offset(x: on ? 4 : -4)
                )
                .animation(.easeInOut(duration: 0.15), value: on)
        }
    }

    private func legend(_ color: Color, _ title: String, dashed: Bool) -> some View {
        HStack(spacing: 6) {
            if dashed {
                HStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { _ in
                        Capsule().fill(color).frame(width: 6, height: 2)
                    }
                }
            } else {
                Circle().fill(color).frame(width: 8, height: 8)
            }
            Text(title)
                .font(.system(size: 10))
                .foregroundColor(Theme.mute)
        }
    }
}

struct TrajectoryPreview: View {
    var document: ProjectDocument

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                let bedW = document.bedWidthMM
                let bedH = document.bedHeightMM
                func map(_ p: MMPoint) -> CGPoint {
                    CGPoint(
                        x: CGFloat(p.x / bedW) * size.width,
                        y: size.height - CGFloat(p.y / bedH) * size.height
                    )
                }
                for item in document.items {
                    guard let layer = document.layer(id: item.layerID), layer.isVisible else { continue }
                    var path = Path()
                    switch item.content {
                    case .shape(let shape):
                        let r = item.transform.bounds
                        let rect = CGRect(
                            x: map(r.origin).x,
                            y: map(MMPoint(x: r.minX, y: r.maxY)).y,
                            width: CGFloat(r.width / bedW) * size.width,
                            height: CGFloat(r.height / bedH) * size.height
                        )
                        if shape.kind == .oval || shape.kind == .tagOval {
                            path.addEllipse(in: rect)
                        } else {
                            path.addRoundedRect(in: rect, cornerSize: CGSize(width: 8, height: 8))
                        }
                    case .freehand(let stroke):
                        let pts = JobBuilder.transformed(stroke.points, item.transform, normalized: false)
                        if let first = pts.first {
                            path.move(to: map(first))
                            for p in pts.dropFirst() { path.addLine(to: map(p)) }
                            if stroke.closed { path.closeSubpath() }
                        }
                    default:
                        let r = item.transform.axisAlignedBounds
                        let rect = CGRect(
                            x: map(r.origin).x,
                            y: map(MMPoint(x: r.minX, y: r.maxY)).y,
                            width: CGFloat(r.width / bedW) * size.width,
                            height: CGFloat(r.height / bedH) * size.height
                        )
                        path.addRoundedRect(in: rect, cornerSize: CGSize(width: 4, height: 4))
                    }
                    if layer.kind == .cut {
                        context.stroke(path, with: .color(Theme.dashCut), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    } else {
                        context.fill(path, with: .color(Theme.burnDot.opacity(0.35)))
                        context.stroke(path, with: .color(Theme.burnDot), lineWidth: 1)
                    }
                }
            }
        }
    }
}
