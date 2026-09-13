import Foundation
import CoreGraphics

/// Точка в миллиметрах рабочего стола. Начало — левый нижний угол, ось Y вверх (как у GRBL).
struct MMPoint: Codable, Equatable {
    var x: Double
    var y: Double

    static let zero = MMPoint(x: 0, y: 0)

    var cgPoint: CGPoint { CGPoint(x: CGFloat(x), y: CGFloat(y)) }

    func offset(dx: Double, dy: Double) -> MMPoint {
        MMPoint(x: x + dx, y: y + dy)
    }

    func distance(to other: MMPoint) -> Double {
        let dx = x - other.x
        let dy = y - other.y
        return sqrt(dx * dx + dy * dy)
    }
}

struct MMSize: Codable, Equatable {
    var width: Double
    var height: Double

    static let zero = MMSize(width: 0, height: 0)
}

struct MMRect: Codable, Equatable {
    var origin: MMPoint
    var size: MMSize

    var minX: Double { origin.x }
    var minY: Double { origin.y }
    var maxX: Double { origin.x + size.width }
    var maxY: Double { origin.y + size.height }
    var midX: Double { origin.x + size.width / 2 }
    var midY: Double { origin.y + size.height / 2 }
    var width: Double { size.width }
    var height: Double { size.height }

    static let zero = MMRect(origin: .zero, size: .zero)

    func inset(by d: Double) -> MMRect {
        MMRect(
            origin: MMPoint(x: origin.x + d, y: origin.y + d),
            size: MMSize(width: size.width - d * 2, height: size.height - d * 2)
        )
    }

    func contains(_ p: MMPoint) -> Bool {
        p.x >= minX && p.x <= maxX && p.y >= minY && p.y <= maxY
    }

    func union(_ other: MMRect) -> MMRect {
        let minX = min(self.minX, other.minX)
        let minY = min(self.minY, other.minY)
        let maxX = max(self.maxX, other.maxX)
        let maxY = max(self.maxY, other.maxY)
        return MMRect(
            origin: MMPoint(x: minX, y: minY),
            size: MMSize(width: maxX - minX, height: maxY - minY)
        )
    }
}

/// Положение объекта: центр, размер, поворот и отражения.
struct ItemTransform: Codable, Equatable {
    var centerX: Double
    var centerY: Double
    var width: Double
    var height: Double
    var rotationDegrees: Double
    var flipHorizontal: Bool
    var flipVertical: Bool

    init(
        centerX: Double,
        centerY: Double,
        width: Double,
        height: Double,
        rotationDegrees: Double = 0,
        flipHorizontal: Bool = false,
        flipVertical: Bool = false
    ) {
        self.centerX = centerX
        self.centerY = centerY
        self.width = width
        self.height = height
        self.rotationDegrees = rotationDegrees
        self.flipHorizontal = flipHorizontal
        self.flipVertical = flipVertical
    }

    var bounds: MMRect {
        MMRect(
            origin: MMPoint(x: centerX - width / 2, y: centerY - height / 2),
            size: MMSize(width: width, height: height)
        )
    }

    var center: MMPoint {
        get { MMPoint(x: centerX, y: centerY) }
        set {
            centerX = newValue.x
            centerY = newValue.y
        }
    }

    mutating func translate(dx: Double, dy: Double) {
        centerX += dx
        centerY += dy
    }

    mutating func rotateBy(degrees: Double) {
        rotationDegrees = Self.normalizedAngle(rotationDegrees + degrees)
    }

    func applying(dx: Double, dy: Double) -> ItemTransform {
        var copy = self
        copy.translate(dx: dx, dy: dy)
        return copy
    }

    /// Осе-выровненный bounding box с учётом поворота (для проверки стола и рамки).
    var axisAlignedBounds: MMRect {
        let rad = rotationDegrees * Double.pi / 180
        let c = abs(cos(rad))
        let s = abs(sin(rad))
        let w = width * c + height * s
        let h = width * s + height * c
        return MMRect(
            origin: MMPoint(x: centerX - w / 2, y: centerY - h / 2),
            size: MMSize(width: w, height: h)
        )
    }

    static func normalizedAngle(_ degrees: Double) -> Double {
        var a = degrees.truncatingRemainder(dividingBy: 360)
        if a > 180 { a -= 360 }
        if a < -180 { a += 360 }
        return a
    }
}

enum PathSimplifier {
    /// Упрощение ломаной (Дуглас–Пекер), порог в миллиметрах.
    static func douglasPeucker(_ points: [MMPoint], tolerance: Double) -> [MMPoint] {
        guard points.count > 2 else { return points }
        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true
        simplify(points, 0, points.count - 1, tolerance, &keep)
        return zip(points, keep).compactMap { $0.1 ? $0.0 : nil }
    }

    private static func simplify(_ pts: [MMPoint], _ start: Int, _ end: Int, _ eps: Double, _ keep: inout [Bool]) {
        guard end > start + 1 else { return }
        var maxDist = 0.0
        var index = start
        for i in (start + 1)..<end {
            let d = perpendicularDistance(pts[i], a: pts[start], b: pts[end])
            if d > maxDist {
                maxDist = d
                index = i
            }
        }
        if maxDist > eps {
            keep[index] = true
            simplify(pts, start, index, eps, &keep)
            simplify(pts, index, end, eps, &keep)
        }
    }

    private static func perpendicularDistance(_ p: MMPoint, a: MMPoint, b: MMPoint) -> Double {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lenSq = dx * dx + dy * dy
        if lenSq < 1e-12 {
            return p.distance(to: a)
        }
        let t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / lenSq
        let proj = MMPoint(x: a.x + t * dx, y: a.y + t * dy)
        return p.distance(to: proj)
    }
}

enum TileGridMath {
    /// Раскладка копий по сетке. Возвращает смещения центров относительно исходного.
    static func offsets(
        columns: Int,
        rows: Int,
        itemWidth: Double,
        itemHeight: Double,
        gapMM: Double
    ) -> [MMPoint] {
        let cols = max(1, columns)
        let rws = max(1, rows)
        let stepX = itemWidth + gapMM
        let stepY = itemHeight + gapMM
        var result: [MMPoint] = []
        result.reserveCapacity(cols * rws)
        let originX = 0.0
        let originY = 0.0
        for row in 0..<rws {
            for col in 0..<cols {
                result.append(MMPoint(x: originX + Double(col) * stepX, y: originY + Double(row) * stepY))
            }
        }
        return result
    }

    static func totalSize(
        columns: Int,
        rows: Int,
        itemWidth: Double,
        itemHeight: Double,
        gapMM: Double
    ) -> MMSize {
        let cols = max(1, columns)
        let rws = max(1, rows)
        return MMSize(
            width: Double(cols) * itemWidth + Double(max(0, cols - 1)) * gapMM,
            height: Double(rws) * itemHeight + Double(max(0, rws - 1)) * gapMM
        )
    }
}
