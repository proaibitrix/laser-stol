import Foundation

/// Серое изображение: 0 — чёрный (жечь), 255 — белый (пропуск).
/// Прозрачные пиксели помечаются отдельно и не прожигаются.
struct PixelBuffer: Equatable {
    var width: Int
    var height: Int
    var luminance: [UInt8]
    var opaque: [Bool]

    init(width: Int, height: Int, luminance: [UInt8], opaque: [Bool]) {
        precondition(luminance.count == width * height)
        precondition(opaque.count == width * height)
        self.width = width
        self.height = height
        self.luminance = luminance
        self.opaque = opaque
    }

    static func filled(width: Int, height: Int, value: UInt8 = 255) -> PixelBuffer {
        PixelBuffer(
            width: width,
            height: height,
            luminance: [UInt8](repeating: value, count: width * height),
            opaque: [Bool](repeating: true, count: width * height)
        )
    }

    func index(_ x: Int, _ y: Int) -> Int { y * width + x }

    func shouldBurn(x: Int, y: Int, threshold: Double, invert: Bool) -> Bool {
        let i = index(x, y)
        guard opaque[i] else { return false }
        let t = UInt8(min(255, max(0, Int((threshold * 255).rounded()))))
        let isDark = luminance[i] < t
        return invert ? !isDark : isDark
    }

    func flippedHorizontally() -> PixelBuffer {
        var lum = [UInt8](repeating: 0, count: luminance.count)
        var opq = [Bool](repeating: false, count: opaque.count)
        for y in 0..<height {
            for x in 0..<width {
                let src = index(width - 1 - x, y)
                let dst = index(x, y)
                lum[dst] = luminance[src]
                opq[dst] = opaque[src]
            }
        }
        return PixelBuffer(width: width, height: height, luminance: lum, opaque: opq)
    }

    func flippedVertically() -> PixelBuffer {
        var lum = [UInt8](repeating: 0, count: luminance.count)
        var opq = [Bool](repeating: false, count: opaque.count)
        for y in 0..<height {
            for x in 0..<width {
                let src = index(x, height - 1 - y)
                let dst = index(x, y)
                lum[dst] = luminance[src]
                opq[dst] = opaque[src]
            }
        }
        return PixelBuffer(width: width, height: height, luminance: lum, opaque: opq)
    }

    func inverted() -> PixelBuffer {
        let lum = luminance.map { 255 &- $0 }
        return PixelBuffer(width: width, height: height, luminance: lum, opaque: opaque)
    }
}

enum ThresholdProcessor {
    static func luminance(r: UInt8, g: UInt8, b: UInt8) -> UInt8 {
        let y = 0.299 * Double(r) + 0.587 * Double(g) + 0.114 * Double(b)
        return UInt8(min(255, max(0, Int(y.rounded()))))
    }

    /// RGBA8 (не премультипл.) → буфер. Альфа ниже `alphaCutoff` считается прозрачной.
    static func fromRGBA(
        width: Int,
        height: Int,
        rgba: [UInt8],
        alphaCutoff: UInt8 = 16
    ) -> PixelBuffer {
        precondition(rgba.count == width * height * 4)
        var lum = [UInt8](repeating: 255, count: width * height)
        var opq = [Bool](repeating: false, count: width * height)
        for i in 0..<(width * height) {
            let o = i * 4
            let a = rgba[o + 3]
            if a < alphaCutoff {
                lum[i] = 255
                opq[i] = false
            } else {
                lum[i] = luminance(r: rgba[o], g: rgba[o + 1], b: rgba[o + 2])
                opq[i] = true
            }
        }
        return PixelBuffer(width: width, height: height, luminance: lum, opaque: opq)
    }
}
