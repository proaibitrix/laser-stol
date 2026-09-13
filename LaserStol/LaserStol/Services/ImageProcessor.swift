import Foundation
import AppKit
import CoreGraphics

enum ImageProcessor {
    static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    static func nsImage(from data: Data) -> NSImage? {
        NSImage(data: data)
    }

    static func loadImage(url: URL) -> (NSImage, Data)? {
        guard let image = NSImage(contentsOf: url) else { return nil }
        if let png = pngData(from: image) {
            return (image, png)
        }
        return nil
    }

    /// Растеризация в RGBA8, затем порог. Прозрачность PNG сохраняется.
    static func pixelBuffer(
        pngData: Data,
        maxEdge: Int = 400,
        threshold: Double,
        invert: Bool
    ) -> PixelBuffer? {
        guard let image = NSImage(data: pngData) else { return nil }
        return pixelBuffer(image: image, maxEdge: maxEdge)
    }

    static func pixelBuffer(image: NSImage, maxEdge: Int = 400) -> PixelBuffer? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(1, Double(maxEdge) / max(size.width, size.height))
        let w = max(1, Int((size.width * scale).rounded()))
        let h = max(1, Int((size.height * scale).rounded()))
        return rasterize(image, width: w, height: h)
    }

    static func rasterize(_ image: NSImage, width: Int, height: Int) -> PixelBuffer? {
        let bytesPerRow = width * 4
        var rgba = [UInt8](repeating: 0, count: height * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &rgba,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.clear(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.interpolationQuality = .high

        var rect = CGRect(x: 0, y: 0, width: width, height: height)
        if let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) {
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        } else if let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let cg = rep.cgImage {
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        } else {
            return nil
        }

        // Снять премультиплирование для порога.
        for i in 0..<(width * height) {
            let o = i * 4
            let a = rgba[o + 3]
            if a == 0 {
                rgba[o] = 0
                rgba[o + 1] = 0
                rgba[o + 2] = 0
            } else if a < 255 {
                rgba[o] = UInt8(min(255, Int(rgba[o]) * 255 / Int(a)))
                rgba[o + 1] = UInt8(min(255, Int(rgba[o + 1]) * 255 / Int(a)))
                rgba[o + 2] = UInt8(min(255, Int(rgba[o + 2]) * 255 / Int(a)))
            }
        }
        return ThresholdProcessor.fromRGBA(width: width, height: height, rgba: rgba)
    }

    static func previewImage(from buffer: PixelBuffer, threshold: Double, invert: Bool) -> NSImage {
        var rgba = [UInt8](repeating: 0, count: buffer.width * buffer.height * 4)
        for y in 0..<buffer.height {
            for x in 0..<buffer.width {
                let i = buffer.index(x, y)
                let o = i * 4
                if !buffer.opaque[i] {
                    rgba[o + 3] = 0
                    continue
                }
                let burn = buffer.shouldBurn(x: x, y: y, threshold: threshold, invert: invert)
                let v: UInt8 = burn ? 70 : 235
                rgba[o] = v
                rgba[o + 1] = v
                rgba[o + 2] = v
                rgba[o + 3] = 255
            }
        }
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &rgba,
            width: buffer.width,
            height: buffer.height,
            bitsPerComponent: 8,
            bytesPerRow: buffer.width * 4,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let cg = ctx.makeImage() else {
            return NSImage(size: NSSize(width: buffer.width, height: buffer.height))
        }
        return NSImage(cgImage: cg, size: NSSize(width: buffer.width, height: buffer.height))
    }

    static func renderText(_ payload: TextPayload, size: NSSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.clear.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        let font = NSFont(name: payload.fontName, size: payload.fontSizePT)
            ?? NSFont.systemFont(ofSize: payload.fontSizePT)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black
        ]
        let text = payload.text as NSString
        let textSize = text.size(withAttributes: attrs)
        let origin = NSPoint(
            x: (size.width - textSize.width) / 2,
            y: (size.height - textSize.height) / 2
        )
        text.draw(at: origin, withAttributes: attrs)
        image.unlockFocus()
        return image
    }

    static func renderMonogram(_ symbol: MonogramSymbol, size: NSSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.clear.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        NSColor.black.setStroke()
        if symbol.strokes.isEmpty {
            let font = NSFont(name: "Times New Roman", size: min(size.width, size.height) * 0.72)
                ?? NSFont.systemFont(ofSize: min(size.width, size.height) * 0.72)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.black
            ]
            let text = symbol.letters as NSString
            let textSize = text.size(withAttributes: attrs)
            text.draw(
                at: NSPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2),
                withAttributes: attrs
            )
        } else {
            for stroke in symbol.strokes {
                guard let first = stroke.first else { continue }
                let path = NSBezierPath()
                path.move(to: NSPoint(x: first.x * size.width, y: first.y * size.height))
                for p in stroke.dropFirst() {
                    path.line(to: NSPoint(x: p.x * size.width, y: p.y * size.height))
                }
                path.lineWidth = max(1.2, min(size.width, size.height) * 0.03)
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                path.stroke()
            }
        }
        image.unlockFocus()
        return image
    }

    static func defaultItemSize(for image: NSImage, bed: Double) -> MMSize {
        let maxSide = min(80, bed * 0.35)
        let w = max(image.size.width, 1)
        let h = max(image.size.height, 1)
        let scale = maxSide / max(w, h)
        return MMSize(width: w * scale, height: h * scale)
    }
}
