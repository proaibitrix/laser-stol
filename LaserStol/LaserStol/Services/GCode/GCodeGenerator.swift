import Foundation

struct GCodeOptions: Equatable {
    var maxSpindle: Int
    var rasterMMPerPixel: Double
    var travelFeed: Double
    var headerComment: String

    init(
        maxSpindle: Int = 1000,
        rasterMMPerPixel: Double = 0.2,
        travelFeed: Double = 3000,
        headerComment: String = "LaserStol / GRBL 1.1"
    ) {
        self.maxSpindle = maxSpindle
        self.rasterMMPerPixel = rasterMMPerPixel
        self.travelFeed = travelFeed
        self.headerComment = headerComment
    }
}

struct GeneratedJob: Equatable {
    var gcode: String
    var lineCount: Int
    var burnDistanceMM: Double
    var cutDistanceMM: Double
    var travelDistanceMM: Double
    var estimatedSeconds: Double
    var bounds: MMRect?
}

enum GCodeGenerator {
    static func header(options: GCodeOptions = GCodeOptions()) -> [String] {
        [
            "; \(options.headerComment)",
            "G90",
            "G21",
            "G94",
            "M5",
            "G0 F\(fmt(options.travelFeed))"
        ]
    }

    static func footer() -> [String] {
        [
            "M5",
            "G0 X0 Y0",
            "M5"
        ]
    }

    static func spindle(_ percent: Double, max: Int) -> Int {
        let clamped = min(1, max(0, percent / 100))
        return Int((clamped * Double(max)).rounded())
    }

    static func contour(
        points: [MMPoint],
        closed: Bool,
        powerPercent: Double,
        feedMMPerMin: Double,
        options: GCodeOptions = GCodeOptions()
    ) -> [String] {
        guard let first = points.first, points.count >= 2 else { return [] }
        let s = spindle(powerPercent, max: options.maxSpindle)
        var lines: [String] = []
        lines.append("G0 X\(fmt(first.x)) Y\(fmt(first.y))")
        lines.append("M4 S\(s)")
        lines.append("G1 F\(fmt(feedMMPerMin))")
        for p in points.dropFirst() {
            lines.append("G1 X\(fmt(p.x)) Y\(fmt(p.y))")
        }
        if closed {
            lines.append("G1 X\(fmt(first.x)) Y\(fmt(first.y))")
        }
        lines.append("M5")
        return lines
    }

    static func rectangleContour(
        rect: MMRect,
        powerPercent: Double,
        feedMMPerMin: Double,
        cornerRadius: Double = 0,
        options: GCodeOptions = GCodeOptions()
    ) -> [String] {
        let pts = roundedRectPoints(rect, radius: cornerRadius)
        return contour(points: pts, closed: true, powerPercent: powerPercent, feedMMPerMin: feedMMPerMin, options: options)
    }

    static func ovalContour(
        rect: MMRect,
        powerPercent: Double,
        feedMMPerMin: Double,
        segments: Int = 72,
        options: GCodeOptions = GCodeOptions()
    ) -> [String] {
        let pts = ovalPoints(rect, segments: segments)
        return contour(points: pts, closed: true, powerPercent: powerPercent, feedMMPerMin: feedMMPerMin, options: options)
    }

    static func circleContour(
        center: MMPoint,
        radius: Double,
        powerPercent: Double,
        feedMMPerMin: Double,
        options: GCodeOptions = GCodeOptions()
    ) -> [String] {
        let rect = MMRect(
            origin: MMPoint(x: center.x - radius, y: center.y - radius),
            size: MMSize(width: radius * 2, height: radius * 2)
        )
        return ovalContour(rect: rect, powerPercent: powerPercent, feedMMPerMin: feedMMPerMin, options: options)
    }

    static func framePreview(bounds: MMRect, feedMMPerMin: Double = 2500, options: GCodeOptions = GCodeOptions()) -> [String] {
        let pts = [
            MMPoint(x: bounds.minX, y: bounds.minY),
            MMPoint(x: bounds.maxX, y: bounds.minY),
            MMPoint(x: bounds.maxX, y: bounds.maxY),
            MMPoint(x: bounds.minX, y: bounds.maxY),
            MMPoint(x: bounds.minX, y: bounds.minY)
        ]
        var lines = header(options: options)
        lines.append("; Frame preview — лазер выключен")
        lines.append("M5")
        if let first = pts.first {
            lines.append("G0 X\(fmt(first.x)) Y\(fmt(first.y))")
        }
        lines.append("G0 F\(fmt(feedMMPerMin))")
        for p in pts.dropFirst() {
            lines.append("G0 X\(fmt(p.x)) Y\(fmt(p.y))")
        }
        lines.append(contentsOf: footer())
        return lines
    }

    /// Растр: чёрные горизонтальные пробеги, двунаправленно.
    /// `origin` — левый нижний угол изображения в мм.
    static func raster(
        buffer: PixelBuffer,
        origin: MMPoint,
        mmPerPixel: Double,
        powerPercent: Double,
        feedMMPerMin: Double,
        threshold: Double,
        invert: Bool,
        options: GCodeOptions = GCodeOptions()
    ) -> [String] {
        let s = spindle(powerPercent, max: options.maxSpindle)
        var lines: [String] = []
        var laserOn = false

        func ensureOff() {
            if laserOn {
                lines.append("M5")
                laserOn = false
            }
        }

        for row in 0..<buffer.height {
            let yMM = origin.y + (Double(buffer.height - 1 - row) + 0.5) * mmPerPixel
            let rtl = row % 2 == 1
            let xs: [Int] = rtl
                ? Array(stride(from: buffer.width - 1, through: 0, by: -1))
                : Array(stride(from: 0, through: buffer.width - 1, by: 1))
            var runStart: Int?
            var lastX: Int?

            func flushRun(endX: Int) {
                guard let startX = runStart else { return }
                let x0 = (min(startX, endX) + 0.5) * mmPerPixel + origin.x
                let x1 = (max(startX, endX) + 0.5) * mmPerPixel + origin.x
                let from = rtl ? x1 : x0
                let to = rtl ? x0 : x1
                if !laserOn {
                    lines.append("G0 X\(fmt(from)) Y\(fmt(yMM))")
                    lines.append("M4 S\(s)")
                    lines.append("G1 F\(fmt(feedMMPerMin))")
                    laserOn = true
                }
                lines.append("G1 X\(fmt(to)) Y\(fmt(yMM))")
                runStart = nil
            }

            for x in xs {
                let burn = buffer.shouldBurn(x: x, y: row, threshold: threshold, invert: invert)
                if burn {
                    if runStart == nil { runStart = x }
                    lastX = x
                } else if let last = lastX, runStart != nil {
                    flushRun(endX: last)
                    lastX = nil
                    ensureOff()
                }
            }
            if let last = lastX, runStart != nil {
                flushRun(endX: last)
            }
            ensureOff()
        }
        ensureOff()
        return lines
    }

    static func roundedRectPoints(_ rect: MMRect, radius: Double, segmentsPerCorner: Int = 6) -> [MMPoint] {
        let r = min(max(0, radius), min(rect.width, rect.height) / 2)
        if r < 0.05 {
            return [
                MMPoint(x: rect.minX, y: rect.minY),
                MMPoint(x: rect.maxX, y: rect.minY),
                MMPoint(x: rect.maxX, y: rect.maxY),
                MMPoint(x: rect.minX, y: rect.maxY)
            ]
        }
        var pts: [MMPoint] = []
        func arc(cx: Double, cy: Double, start: Double, end: Double) {
            for i in 0...segmentsPerCorner {
                let t = start + (end - start) * Double(i) / Double(segmentsPerCorner)
                pts.append(MMPoint(x: cx + cos(t) * r, y: cy + sin(t) * r))
            }
        }
        arc(cx: rect.maxX - r, cy: rect.minY + r, start: -Double.pi / 2, end: 0)
        arc(cx: rect.maxX - r, cy: rect.maxY - r, start: 0, end: Double.pi / 2)
        arc(cx: rect.minX + r, cy: rect.maxY - r, start: Double.pi / 2, end: Double.pi)
        arc(cx: rect.minX + r, cy: rect.minY + r, start: Double.pi, end: 3 * Double.pi / 2)
        return pts
    }

    static func ovalPoints(_ rect: MMRect, segments: Int) -> [MMPoint] {
        let n = max(12, segments)
        let cx = rect.midX
        let cy = rect.midY
        let rx = rect.width / 2
        let ry = rect.height / 2
        return (0..<n).map { i in
            let t = Double(i) / Double(n) * 2 * Double.pi
            return MMPoint(x: cx + cos(t) * rx, y: cy + sin(t) * ry)
        }
    }

    static func tagHoleCenter(rect: MMRect) -> MMPoint {
        MMPoint(x: rect.midX, y: rect.maxY - min(6, rect.height * 0.18))
    }

    static func tagHoleRadius(rect: MMRect) -> Double {
        min(2.2, min(rect.width, rect.height) * 0.08)
    }

    static func applyStrength(power: Double, speed: Double, settings: JobSettings) -> (Double, Double) {
        let p = min(100, power * settings.power.powerMultiplier)
        let s = max(60, speed * settings.speed.speedMultiplier)
        return (p, s)
    }

    static func fmt(_ value: Double) -> String {
        String(format: "%.3f", value)
    }
}
