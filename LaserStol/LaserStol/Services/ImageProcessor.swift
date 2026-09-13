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
        guard let image = NSImage(data: data) else { return nil }
        normalizeSize(image)
        return image
    }

    static func loadImage(url: URL) -> (NSImage, Data)? {
        guard let image = NSImage(contentsOf: url) else { return nil }
        normalizeSize(image)
        if let png = pngData(from: image) {
            return (image, png)
        }
        return nil
    }

    /// Реальный пиксельный размер: `NSImage.size` у PNG/JPEG часто 0×0,
    /// пока не прочитаны `representations`.
    static func pixelSize(of image: NSImage) -> (Int, Int)? {
        var bestW = 0
        var bestH = 0
        for rep in image.representations {
            let w = rep.pixelsWide
            let h = rep.pixelsHigh
            if w > bestW && h > 0 {
                bestW = w
                bestH = h
            }
        }
        if bestW > 0, bestH > 0 {
            return (bestW, bestH)
        }
        let w = Int(round(image.size.width))
        let h = Int(round(image.size.height))
        if w > 0, h > 0 {
            return (w, h)
        }
        return nil
    }

    static func normalizeSize(_ image: NSImage) {
        if let (w, h) = pixelSize(of: image) {
            image.size = NSSize(width: w, height: h)
        }
    }

    static func cgImage(from image: NSImage) -> CGImage? {
        normalizeSize(image)
        var proposed = CGRect(origin: .zero, size: image.size)
        if proposed.width < 1 || proposed.height < 1, let (w, h) = pixelSize(of: image) {
            proposed = CGRect(x: 0, y: 0, width: w, height: h)
        }
        if proposed.width >= 1, proposed.height >= 1,
           let cg = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil) {
            return cg
        }
        for rep in image.representations {
            if let bitmap = rep as? NSBitmapImageRep, let cg = bitmap.cgImage {
                return cg
            }
        }
        if let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let cg = rep.cgImage {
            return cg
        }
        return nil
    }

    /// Растеризация в RGBA8, затем порог. Прозрачность PNG сохраняется.
    static func pixelBuffer(
        pngData: Data,
        maxEdge: Int = 400,
        threshold: Double = 0.52,
        invert: Bool = false
    ) -> PixelBuffer? {
        if let rep = NSBitmapImageRep(data: pngData),
           rep.pixelsWide > 0,
           rep.pixelsHigh > 0 {
            let scaled = scaledSize(width: rep.pixelsWide, height: rep.pixelsHigh, maxEdge: maxEdge)
            if let cg = rep.cgImage {
                return rasterize(cgImage: cg, width: scaled.0, height: scaled.1)
            }
        }
        guard let image = nsImage(from: pngData) else { return nil }
        return pixelBuffer(image: image, maxEdge: maxEdge)
    }

    static func pixelBuffer(image: NSImage, maxEdge: Int = 400) -> PixelBuffer? {
        normalizeSize(image)
        guard let (pw, ph) = pixelSize(of: image) else { return nil }
        let scaled = scaledSize(width: pw, height: ph, maxEdge: maxEdge)
        return rasterize(image, width: scaled.0, height: scaled.1)
    }

    static func rasterize(_ image: NSImage, width: Int, height: Int) -> PixelBuffer? {
        if let cg = cgImage(from: image) {
            return rasterize(cgImage: cg, width: width, height: height)
        }
        return rasterizeByDrawing(image, width: width, height: height)
    }

    static func rasterize(cgImage: CGImage, width: Int, height: Int) -> PixelBuffer? {
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

        let pixelRect = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(pixelRect)
        ctx.interpolationQuality = .high
        ctx.draw(cgImage, in: pixelRect)
        unpremultiply(&rgba, pixelCount: width * height)
        return ThresholdProcessor.fromRGBA(width: width, height: height, rgba: rgba)
    }

    /// Запасной путь: `draw(in:)` работает даже когда `cgImage` недоступен.
    static func rasterizeByDrawing(_ image: NSImage, width: Int, height: Int) -> PixelBuffer? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: width * 4,
            bitsPerPixel: 32
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
            NSGraphicsContext.restoreGraphicsState()
            return nil
        }
        NSGraphicsContext.current = ctx
        let rect = NSRect(x: 0, y: 0, width: width, height: height)
        NSColor.white.setFill()
        NSBezierPath.fill(rect)
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()

        guard let data = rep.bitmapData else { return nil }
        let rgba = Array(UnsafeBufferPointer(start: data, count: width * height * 4))
        return ThresholdProcessor.fromRGBA(width: width, height: height, rgba: rgba)
    }

    private static func scaledSize(width: Int, height: Int, maxEdge: Int) -> (Int, Int) {
        let longEdge = Double(max(width, height))
        let scale = min(1.0, Double(maxEdge) / max(1.0, longEdge))
        let w = max(1, Int((Double(width) * scale).rounded()))
        let h = max(1, Int((Double(height) * scale).rounded()))
        return (w, h)
    }

    private static func unpremultiply(_ rgba: inout [UInt8], pixelCount: Int) {
        for i in 0..<pixelCount {
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
    }

    static func previewImage(from buffer: PixelBuffer, threshold: Double = 0.52, invert: Bool = false) -> NSImage {
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
            return NSImage(size: NSSize(width: CGFloat(buffer.width), height: CGFloat(buffer.height)))
        }
        return NSImage(cgImage: cg, size: NSSize(width: CGFloat(buffer.width), height: CGFloat(buffer.height)))
    }

    static func renderText(_ payload: TextPayload, size: NSSize) -> NSImage {
        let w = max(1, Int(size.width.rounded()))
        let h = max(1, Int(size.height.rounded()))
        if let image = renderIntoBitmap(width: w, height: h, draw: { rect in
            let font = NSFont(name: payload.fontName, size: CGFloat(payload.fontSizePT))
                ?? NSFont.systemFont(ofSize: CGFloat(payload.fontSizePT))
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.black
            ]
            let text = payload.text as NSString
            let textSize = text.size(withAttributes: attrs)
            text.draw(
                at: NSPoint(
                    x: (rect.width - textSize.width) / 2,
                    y: (rect.height - textSize.height) / 2
                ),
                withAttributes: attrs
            )
        }) {
            return image
        }
        return renderTextLockFocus(payload, size: size)
    }

    static func renderMonogram(_ symbol: MonogramSymbol, size: NSSize) -> NSImage {
        let w = max(1, Int(size.width.rounded()))
        let h = max(1, Int(size.height.rounded()))
        if let image = renderIntoBitmap(width: w, height: h, draw: { rect in
            drawMonogram(symbol, in: rect)
        }) {
            return image
        }
        return renderMonogramLockFocus(symbol, size: size)
    }

    private static func renderIntoBitmap(width: Int, height: Int, draw: (NSRect) -> Void) -> NSImage? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: width * 4,
            bitsPerPixel: 32
        ) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
            NSGraphicsContext.restoreGraphicsState()
            return nil
        }
        NSGraphicsContext.current = ctx
        let rect = NSRect(x: 0, y: 0, width: width, height: height)
        NSColor.clear.setFill()
        NSBezierPath.fill(rect)
        draw(rect)
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(rep)
        return image
    }

    private static func drawMonogram(_ symbol: MonogramSymbol, in size: NSRect) {
        NSColor.black.setStroke()
        if symbol.strokes.isEmpty {
            let edge = min(size.width, size.height)
            let font = NSFont(name: "Times New Roman", size: edge * CGFloat(0.72))
                ?? NSFont.systemFont(ofSize: edge * CGFloat(0.72))
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
                path.move(to: NSPoint(x: CGFloat(first.x) * size.width, y: CGFloat(first.y) * size.height))
                for p in stroke.dropFirst() {
                    path.line(to: NSPoint(x: CGFloat(p.x) * size.width, y: CGFloat(p.y) * size.height))
                }
                path.lineWidth = CGFloat(max(1.2, Double(min(size.width, size.height)) * 0.03))
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                path.stroke()
            }
        }
    }

    private static func renderTextLockFocus(_ payload: TextPayload, size: NSSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.clear.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        let font = NSFont(name: payload.fontName, size: CGFloat(payload.fontSizePT))
            ?? NSFont.systemFont(ofSize: CGFloat(payload.fontSizePT))
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black
        ]
        let text = payload.text as NSString
        let textSize = text.size(withAttributes: attrs)
        text.draw(
            at: NSPoint(
                x: (size.width - textSize.width) / 2,
                y: (size.height - textSize.height) / 2
            ),
            withAttributes: attrs
        )
        image.unlockFocus()
        return image
    }

    private static func renderMonogramLockFocus(_ symbol: MonogramSymbol, size: NSSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.clear.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        drawMonogram(symbol, in: NSRect(origin: .zero, size: size))
        image.unlockFocus()
        return image
    }

    static func defaultItemSize(for image: NSImage, bed: Double) -> MMSize {
        let maxSide = min(80.0, bed * 0.35)
        let dims = pixelSize(of: image)
        let w = max(Double(dims?.0 ?? Int(image.size.width)), 1.0)
        let h = max(Double(dims?.1 ?? Int(image.size.height)), 1.0)
        let scale = maxSide / max(w, h)
        return MMSize(width: w * scale, height: h * scale)
    }
}
