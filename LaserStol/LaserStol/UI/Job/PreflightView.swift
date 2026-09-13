import SwiftUI

struct PreflightView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Лазерная гравировка и резка")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.mute)
                        .frame(maxWidth: .infinity)

                    HStack(alignment: .top, spacing: 28) {
                        previewColumn
                        checksColumn
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 16)
                .padding(.bottom, 12)
            }
            footer
        }
        .frame(minWidth: 720, idealWidth: 840, maxWidth: 920, minHeight: 480, idealHeight: 580)
        .creamSurface()
        .background(Theme.cream)
    }

    private var previewColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Превью траектории")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(Theme.ink)
            Text("Как лазер обработает ваш объект")
                .font(.system(size: 12))
                .foregroundColor(Theme.mute)

            TrajectoryPreview(document: app.document)
                .frame(minWidth: 280, minHeight: 220)
                .frame(height: 240)
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
        .frame(minWidth: 300)
    }

    private var checksColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Проверка перед запуском")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(Theme.ink)
            Text("Проверьте все параметры для безопасной работы")
                .font(.system(size: 12))
                .foregroundColor(Theme.mute)

            if app.machine.isDemo {
                demoBanner
            }

            checkRow(
                icon: "scope",
                title: "Лазер на месте",
                subtitle: app.machine.isDemo
                    ? "Макет: головка не проверяется"
                    : (app.machine.connection.isReady
                        ? "Канал станка открыт"
                        : "Сначала выберите порт и подключите"),
                on: app.machine.connection.isReady && !app.machine.isDemo
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
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.ink)
                Text("Строк G-code: \(job.lineCount)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.mute)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var demoBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Демо без станка")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.ink)
            Text("Подключён Mock GRBL. «Начать» прогонит G-code только в приложении — лазер не поедет. Для реального реза: связь → последовательный порт.")
                .font(.system(size: 11))
                .foregroundColor(Theme.mute)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.terracottaSoft))
    }

    private var footer: some View {
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
                    Text(app.machine.isDemo ? "Начать демо" : "Начать")
                }
            }
            .buttonStyle(CompactButtonStyle(prominent: true))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(Theme.cream)
    }

    private func checkRow(icon: String, title: String, subtitle: String, on: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(Theme.terracotta)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.ink)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(Theme.mute)
            }
            Spacer()
            Circle()
                .fill(on ? Theme.good : Theme.line)
                .frame(width: 22, height: 14)
                .overlay(
                    Circle()
                        .fill(Color(red: 1, green: 1, blue: 1))
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
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Theme.ink)
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
