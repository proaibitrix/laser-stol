import XCTest
import AppKit
@testable import LaserStol

final class GeometryTests: XCTestCase {
    func testTileGridOffsets() {
        let pts = TileGridMath.offsets(columns: 3, rows: 2, itemWidth: 10, itemHeight: 8, gapMM: 2)
        XCTAssertEqual(pts.count, 6)
        XCTAssertEqual(pts[0], MMPoint(x: 0, y: 0))
        XCTAssertEqual(pts[1], MMPoint(x: 12, y: 0))
        XCTAssertEqual(pts[3], MMPoint(x: 0, y: 10))
    }

    func testTileTotalSize() {
        let size = TileGridMath.totalSize(columns: 5, rows: 5, itemWidth: 48, itemHeight: 48, gapMM: 10)
        XCTAssertEqual(size.width, 5 * 48 + 4 * 10, accuracy: 0.001)
        XCTAssertEqual(size.height, 5 * 48 + 4 * 10, accuracy: 0.001)
    }

    func testPathSimplifierKeepsEnds() {
        let pts = [
            MMPoint(x: 0, y: 0),
            MMPoint(x: 1, y: 0.01),
            MMPoint(x: 2, y: 0),
            MMPoint(x: 10, y: 0)
        ]
        let simple = PathSimplifier.douglasPeucker(pts, tolerance: 0.5)
        XCTAssertEqual(simple.first, pts.first)
        XCTAssertEqual(simple.last, pts.last)
        XCTAssertLessThan(simple.count, pts.count)
    }

    func testRotatedBoundsGrows() {
        var t = ItemTransform(centerX: 50, centerY: 50, width: 20, height: 10)
        t.rotationDegrees = 90
        XCTAssertEqual(t.axisAlignedBounds.width, 10, accuracy: 0.01)
        XCTAssertEqual(t.axisAlignedBounds.height, 20, accuracy: 0.01)
    }
}

final class PixelTests: XCTestCase {
    func testThresholdBurnsDarkPixels() {
        let rgba: [UInt8] = [
            10, 10, 10, 255,
            250, 250, 250, 255,
            0, 0, 0, 0,
            40, 40, 40, 255
        ]
        let buffer = ThresholdProcessor.fromRGBA(width: 2, height: 2, rgba: rgba)
        XCTAssertTrue(buffer.shouldBurn(x: 0, y: 0, threshold: 0.5, invert: false))
        XCTAssertFalse(buffer.shouldBurn(x: 1, y: 0, threshold: 0.5, invert: false))
        XCTAssertFalse(buffer.shouldBurn(x: 0, y: 1, threshold: 0.5, invert: false), "прозрачный не жжём")
        XCTAssertTrue(buffer.shouldBurn(x: 1, y: 0, threshold: 0.5, invert: true))
    }

    func testLuminanceFormula() {
        XCTAssertEqual(ThresholdProcessor.luminance(r: 255, g: 255, b: 255), 255)
        XCTAssertEqual(ThresholdProcessor.luminance(r: 0, g: 0, b: 0), 0)
        XCTAssertGreaterThan(ThresholdProcessor.luminance(r: 0, g: 255, b: 0), ThresholdProcessor.luminance(r: 0, g: 0, b: 255))
    }

    func testFlipHorizontal() {
        var lum: [UInt8] = [0, 255, 0, 255]
        var opq = [Bool](repeating: true, count: 4)
        let buffer = PixelBuffer(width: 2, height: 2, luminance: lum, opaque: opq).flippedHorizontally()
        XCTAssertEqual(buffer.luminance[0], 255)
        XCTAssertEqual(buffer.luminance[1], 0)
    }
}

final class GCodeTests: XCTestCase {
    func testRectangleContourClosed() {
        let rect = MMRect(origin: MMPoint(x: 10, y: 20), size: MMSize(width: 30, height: 15))
        let lines = GCodeGenerator.rectangleContour(rect: rect, powerPercent: 80, feedMMPerMin: 400)
        XCTAssertTrue(lines.contains(where: { $0.hasPrefix("M4") }))
        XCTAssertTrue(lines.contains("M5"))
        XCTAssertTrue(lines.contains(where: { $0.contains("X10.000") }))
    }

    func testRasterEmitsBurns() {
        let buffer = PixelBuffer.filled(width: 8, height: 2, value: 0)
        let lines = GCodeGenerator.raster(
            buffer: buffer,
            origin: MMPoint(x: 0, y: 0),
            mmPerPixel: 1,
            powerPercent: 40,
            feedMMPerMin: 1200,
            threshold: 0.5,
            invert: false
        )
        XCTAssertTrue(lines.contains(where: { $0.hasPrefix("M4") }))
        XCTAssertTrue(lines.contains(where: { $0.hasPrefix("G1") }))
    }

    func testFramePreviewLaserOff() {
        let lines = GCodeGenerator.framePreview(
            bounds: MMRect(origin: .zero, size: MMSize(width: 40, height: 20))
        )
        XCTAssertFalse(lines.contains(where: { $0.hasPrefix("M3") }))
        XCTAssertFalse(lines.contains(where: { $0.hasPrefix("M4") }))
        XCTAssertTrue(lines.contains(where: { $0 == "M5" }))
    }

    func testSpindleClamp() {
        XCTAssertEqual(GCodeGenerator.spindle(0, max: 1000), 0)
        XCTAssertEqual(GCodeGenerator.spindle(50, max: 1000), 500)
        XCTAssertEqual(GCodeGenerator.spindle(200, max: 1000), 1000)
    }

    func testTimeEstimatePositive() {
        let gcode = """
        G90
        G0 X0 Y0
        M4 S500
        G1 F1000
        G1 X100 Y0
        M5
        G0 X0 Y0
        """
        let seconds = TimeEstimator.estimateSeconds(gcode: gcode, burnFeed: 1000, cutFeed: 400)
        XCTAssertGreaterThan(seconds, 4)
        XCTAssertLessThan(seconds, 20)
        XCTAssertFalse(TimeEstimator.formatDuration(seconds).isEmpty)
    }

    func testParseWord() {
        XCTAssertEqual(TimeEstimator.parseWord("G1 X12.5 Y-3 F800", "X"), 12.5)
        XCTAssertEqual(TimeEstimator.parseWord("G1 X12.5 Y-3 F800", "Y"), -3)
        XCTAssertEqual(TimeEstimator.parseWord("M4 S750", "S"), 750)
    }
}

final class DocumentTests: XCTestCase {
    func testRoundTrip() throws {
        var doc = ProjectDocument()
        doc.ensureDefaultLayers()
        let layerID = doc.layer(kind: .cut)!.id
        doc.upsert(DesignItem(
            layerID: layerID,
            name: "тест",
            transform: ItemTransform(centerX: 20, centerY: 30, width: 10, height: 8),
            content: .shape(ShapePayload(kind: .oval))
        ))
        let data = try JSONEncoder().encode(doc)
        let decoded = try JSONDecoder().decode(ProjectDocument.self, from: data)
        XCTAssertEqual(decoded.items.count, 1)
        XCTAssertEqual(decoded.items[0].name, "тест")
    }

    func testItemsFitBed() {
        var doc = ProjectDocument()
        doc.ensureDefaultLayers()
        let id = doc.layer(kind: .burn)!.id
        doc.upsert(DesignItem(
            layerID: id,
            name: "out",
            transform: ItemTransform(centerX: 500, centerY: 200, width: 40, height: 40),
            content: .shape(ShapePayload(kind: .rectangle))
        ))
        XCTAssertFalse(doc.itemsFitBed())
    }

    func testDemoFitsBed() {
        let demo = DemoProject.make()
        XCTAssertGreaterThan(demo.items.count, 10)
        XCTAssertTrue(demo.itemsFitBed())
        XCTAssertEqual(demo.layers.count, 2)
    }

    func testJobBuilderWholeSheet() {
        let demo = DemoProject.make()
        let stub = PixelBuffer.filled(width: 8, height: 8, value: 0)
        let job = JobBuilder.build(document: demo, settings: JobSettings(), pixelsForItem: { item in
            switch item.content {
            case .text, .image, .monogram: return stub
            default: return nil
            }
        })
        XCTAssertTrue(job.errors.isEmpty)
        XCTAssertTrue(job.gcode.contains("G90"))
        XCTAssertTrue(job.gcode.contains("Слой Рез") || job.gcode.contains("G1"))
        XCTAssertGreaterThan(job.lineCount, 20)
        XCTAssertGreaterThan(job.estimatedSeconds, 0)
        XCTAssertEqual(job.burnTextCount, 25)
        XCTAssertTrue(job.preflightSummary.contains("Прожиг: 25 объектов"))
        XCTAssertTrue(job.preflightSummary.contains("текст: 25"))
    }

    func testJobBuilderBurnsImportedImage() {
        var doc = ProjectDocument()
        doc.ensureDefaultLayers()
        let png = TestImages.blackSquarePNG()
        doc.upsert(DesignItem(
            layerID: doc.layer(kind: .burn)!.id,
            name: "фото",
            transform: ItemTransform(centerX: 50, centerY: 50, width: 20, height: 20),
            content: .image(ImagePayload(pngData: png, originalName: "shot.png"))
        ))
        let job = JobBuilder.build(
            document: doc,
            settings: JobSettings(scope: .burnLayer),
            pixelsForItem: { item in
                if case .image(let payload) = item.content {
                    return ImageProcessor.pixelBuffer(pngData: payload.pngData, maxEdge: 32)
                }
                return nil
            }
        )
        XCTAssertTrue(job.errors.isEmpty, job.errors.joined(separator: "; "))
        XCTAssertEqual(job.burnItemCount, 1)
        XCTAssertEqual(job.burnImageCount, 1)
        XCTAssertEqual(job.burnTextCount, 0)
        XCTAssertTrue(job.gcode.contains("G1"))
        XCTAssertTrue(job.preflightSummary.contains("изображений: 1"))
    }

    func testJobBuilderBurnsUserText() {
        var doc = ProjectDocument()
        doc.ensureDefaultLayers()
        doc.upsert(DesignItem(
            layerID: doc.layer(kind: .burn)!.id,
            name: "Привет",
            transform: ItemTransform(centerX: 80, centerY: 80, width: 40, height: 22),
            content: .text(TextPayload(text: "Привет"))
        ))
        let job = JobBuilder.build(
            document: doc,
            settings: JobSettings(scope: .burnLayer),
            pixelsForItem: { item in
                if case .text(let payload) = item.content {
                    let ns = ImageProcessor.renderText(payload, size: NSSize(width: 200, height: 100))
                    return ImageProcessor.pixelBuffer(image: ns, maxEdge: 80)
                }
                return nil
            }
        )
        XCTAssertTrue(job.errors.isEmpty, job.errors.joined(separator: "; "))
        XCTAssertEqual(job.burnTextCount, 1)
        XCTAssertTrue(job.gcode.contains("G1"))
        XCTAssertTrue(job.preflightSummary.contains("текст: 1"))
    }

    func testJobBuilderIncludesOrphanImage() {
        var doc = ProjectDocument()
        doc.ensureDefaultLayers()
        let png = TestImages.blackSquarePNG()
        doc.upsert(DesignItem(
            layerID: UUID(),
            name: "сирота",
            transform: ItemTransform(centerX: 40, centerY: 40, width: 16, height: 16),
            content: .image(ImagePayload(pngData: png, originalName: "orphan.png"))
        ))
        let job = JobBuilder.build(
            document: doc,
            settings: JobSettings(scope: .burnLayer),
            pixelsForItem: { item in
                if case .image(let payload) = item.content {
                    return ImageProcessor.pixelBuffer(pngData: payload.pngData, maxEdge: 24)
                }
                return nil
            }
        )
        XCTAssertEqual(job.burnImageCount, 1)
        XCTAssertTrue(job.errors.isEmpty, job.errors.joined(separator: "; "))
        XCTAssertTrue(job.gcode.contains("G1"))
    }

    func testJobBuilderErrorsWhenImageHasNoPixels() {
        var doc = ProjectDocument()
        doc.ensureDefaultLayers()
        doc.upsert(DesignItem(
            layerID: doc.layer(kind: .burn)!.id,
            name: "пустое",
            transform: ItemTransform(centerX: 50, centerY: 50, width: 20, height: 20),
            content: .image(ImagePayload(pngData: Data(), originalName: "empty.png"))
        ))
        let job = JobBuilder.build(
            document: doc,
            settings: JobSettings(scope: .burnLayer),
            pixelsForItem: { _ in nil }
        )
        XCTAssertFalse(job.canStart)
        XCTAssertEqual(job.errors.count, 1)
        XCTAssertTrue(job.errors[0].contains("пустое"))
        XCTAssertFalse(job.gcode.contains("G1"))
    }

    func testJobBuilderErrorsWhenRasterIsWhite() {
        var doc = ProjectDocument()
        doc.ensureDefaultLayers()
        doc.upsert(DesignItem(
            layerID: doc.layer(kind: .burn)!.id,
            name: "светлое",
            transform: ItemTransform(centerX: 50, centerY: 50, width: 20, height: 20),
            content: .image(ImagePayload(pngData: Data([0x00]), originalName: "white.png"))
        ))
        let white = PixelBuffer.filled(width: 8, height: 8, value: 255)
        let job = JobBuilder.build(
            document: doc,
            settings: JobSettings(scope: .burnLayer),
            pixelsForItem: { _ in white }
        )
        XCTAssertFalse(job.canStart)
        XCTAssertTrue(job.errors[0].contains("светлое"))
        XCTAssertTrue(job.errors[0].contains("нет точек прожига"))
    }

    func testPixelBufferIgnoresZeroNSImageSize() {
        let png = TestImages.blackSquarePNG()
        let image = NSImage(data: png)!
        image.size = .zero
        let buffer = ImageProcessor.pixelBuffer(image: image, maxEdge: 32)
        XCTAssertNotNil(buffer)
        XCTAssertGreaterThan(buffer!.burnPixelCount(threshold: 0.5, invert: false), 0)
    }

    func testPixelBufferFromPNGData() {
        let png = TestImages.blackSquarePNG()
        let buffer = ImageProcessor.pixelBuffer(pngData: png, maxEdge: 32)
        XCTAssertNotNil(buffer)
        XCTAssertGreaterThan(buffer!.burnPixelCount(threshold: 0.5, invert: false), 0)
    }
}

enum TestImages {
    static func blackSquarePNG() -> Data {
        let width = 16
        let height = 16
        let rep = NSBitmapImageRep(
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
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.black.setFill()
        NSBezierPath.fill(NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])!
    }
}

final class SVGTests: XCTestCase {
    func testParseRectAndPath() {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg">
          <rect x="1" y="2" width="10" height="5"/>
          <path d="M0 0 L10 0 L10 10 Z"/>
        </svg>
        """
        let paths = SVGImporter.importPaths(data: Data(svg.utf8))
        XCTAssertGreaterThanOrEqual(paths.count, 2)
        XCTAssertTrue(paths.contains(where: { $0.closed }))
    }
}

final class StrengthTests: XCTestCase {
    func testMultipliers() {
        XCTAssertLessThan(ProcessStrength.weak.powerMultiplier, ProcessStrength.medium.powerMultiplier)
        XCTAssertGreaterThan(ProcessStrength.strong.speedMultiplier, ProcessStrength.medium.speedMultiplier)
    }
}
