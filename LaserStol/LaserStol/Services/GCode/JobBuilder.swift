import Foundation

enum JobBuilder {
    static func build(
        document: ProjectDocument,
        settings: JobSettings,
        pixelsForItem: (DesignItem) -> PixelBuffer?,
        options: GCodeOptions = GCodeOptions()
    ) -> GeneratedJob {
        var lines = GCodeGenerator.header(options: options)
        var burnMM = 0.0
        var cutMM = 0.0

        let material = MaterialPreset.preset(id: settings.materialID)

        switch settings.scope {
        case .framePreview:
            let bounds = document.allItemsBounds() ?? document.bedRect.inset(by: 10)
            lines = GCodeGenerator.framePreview(bounds: bounds, options: options)
            let assembled = lines.joined(separator: "\n") + "\n"
            let dist = TimeEstimator.distances(in: assembled)
            return GeneratedJob(
                gcode: assembled,
                lineCount: lines.count,
                burnDistanceMM: 0,
                cutDistanceMM: 0,
                travelDistanceMM: dist.travelMM,
                estimatedSeconds: TimeEstimator.estimateSeconds(distances: dist, burnFeed: 1, cutFeed: 1),
                bounds: bounds
            )
        case .burnLayer, .cutLayer, .wholeSheet:
            break
        }

        let includeBurn = settings.scope == .burnLayer || settings.scope == .wholeSheet
        let includeCut = settings.scope == .cutLayer || settings.scope == .wholeSheet

        var burnItemCount = 0
        var burnImageCount = 0
        var burnTextCount = 0
        var errors: [String] = []

        if includeBurn {
            let burnCandidates = burnItems(from: document)
            if !burnCandidates.isEmpty {
                let layer = document.layer(kind: .burn)
                let (power, speed) = GCodeGenerator.applyStrength(
                    power: (layer?.powerPercent ?? 0) > 0 ? (layer?.powerPercent ?? material.burnPowerPercent) : material.burnPowerPercent,
                    speed: (layer?.speedMMPerMin ?? 0) > 0 ? (layer?.speedMMPerMin ?? material.burnSpeedMMPerMin) : material.burnSpeedMMPerMin,
                    settings: settings
                )
                lines.append("; Слой Прожиг  S~\(GCodeGenerator.spindle(power, max: options.maxSpindle))  F\(Int(speed))")
                for item in burnCandidates {
                    countBurnContent(item, items: &burnItemCount, images: &burnImageCount, texts: &burnTextCount)
                    let chunk = burnLines(
                        item: item,
                        power: power,
                        speed: speed,
                        pixels: pixelsForItem(item),
                        options: options,
                        errors: &errors
                    )
                    lines.append(contentsOf: chunk)
                    burnMM += polylineLength(from: chunk)
                }
            }
        }

        if includeCut, let layer = document.layer(kind: .cut), layer.isVisible {
            let (power, speed) = GCodeGenerator.applyStrength(
                power: layer.powerPercent > 0 ? layer.powerPercent : material.cutPowerPercent,
                speed: layer.speedMMPerMin > 0 ? layer.speedMMPerMin : material.cutSpeedMMPerMin,
                settings: settings
            )
            lines.append("; Слой Рез  S~\(GCodeGenerator.spindle(power, max: options.maxSpindle))  F\(Int(speed))")
            for item in document.items(on: layer.id) {
                let chunk = cutLines(item: item, power: power, speed: speed, options: options)
                lines.append(contentsOf: chunk)
                cutMM += polylineLength(from: chunk)
            }
        }

        lines.append(contentsOf: GCodeGenerator.footer())
        let assembled = lines.joined(separator: "\n") + "\n"
        let dist = TimeEstimator.distances(in: assembled)
        let seconds = TimeEstimator.estimateSeconds(
            distances: dist,
            burnFeed: max(200.0, material.burnSpeedMMPerMin * settings.speed.speedMultiplier),
            cutFeed: max(80.0, material.cutSpeedMMPerMin * settings.speed.speedMultiplier)
        )
        return GeneratedJob(
            gcode: assembled,
            lineCount: lines.count,
            burnDistanceMM: dist.burnMM,
            cutDistanceMM: dist.cutMM,
            travelDistanceMM: dist.travelMM,
            estimatedSeconds: seconds,
            bounds: document.allItemsBounds(),
            burnItemCount: burnItemCount,
            burnImageCount: burnImageCount,
            burnTextCount: burnTextCount,
            errors: errors
        )
    }

    /// Все видимые объекты прожига: слой Прожиг + «осиротевшие» картинки/текст/монограммы.
    static func burnItems(from document: ProjectDocument) -> [DesignItem] {
        let visibleBurnIDs = Set(document.layers.filter { $0.kind == .burn && $0.isVisible }.map(\.id))
        let cutIDs = Set(document.layers.filter { $0.kind == .cut }.map(\.id))
        let knownIDs = Set(document.layers.map(\.id))
        return document.items.filter { item in
            if visibleBurnIDs.contains(item.layerID) {
                return true
            }
            switch item.content {
            case .image, .text, .monogram:
                if cutIDs.contains(item.layerID) { return false }
                return !knownIDs.contains(item.layerID)
            default:
                return false
            }
        }
    }

    private static func countBurnContent(
        _ item: DesignItem,
        items: inout Int,
        images: inout Int,
        texts: inout Int
    ) {
        switch item.content {
        case .image:
            items += 1
            images += 1
        case .text, .monogram:
            items += 1
            texts += 1
        case .shape:
            items += 1
        case .freehand:
            break
        }
    }

    private static func burnLines(
        item: DesignItem,
        power: Double,
        speed: Double,
        pixels: PixelBuffer?,
        options: GCodeOptions,
        errors: inout [String]
    ) -> [String] {
        switch item.content {
        case .image, .text, .monogram:
            if let error = rasterFailure(item: item, pixels: pixels) {
                errors.append(error)
                return []
            }
            guard var buffer = pixels else { return [] }
            if item.transform.flipHorizontal { buffer = buffer.flippedHorizontally() }
            if item.transform.flipVertical { buffer = buffer.flippedVertically() }
            let bounds = item.transform.bounds
            let mmPerPixel = bounds.width / Double(max(buffer.width, 1))
            let chunk = GCodeGenerator.raster(
                buffer: buffer,
                origin: bounds.origin,
                mmPerPixel: mmPerPixel,
                powerPercent: power,
                feedMMPerMin: speed,
                threshold: item.effectiveThreshold,
                invert: item.effectiveInvert,
                options: options
            )
            if !hasBurnMove(chunk) {
                errors.append("«\(itemLabel(item))»: G-code прожига пуст")
                return []
            }
            return chunk
        case .shape(let shape):
            if shape.kind == .rectangle || shape.kind == .tagRectangle {
                return GCodeGenerator.rasterFilledRect(
                    rect: item.transform.bounds,
                    powerPercent: power,
                    feedMMPerMin: speed,
                    mmPerPixel: options.rasterMMPerPixel,
                    options: options
                )
            }
            return GCodeGenerator.rasterFilledOval(
                rect: item.transform.bounds,
                powerPercent: power,
                feedMMPerMin: speed,
                mmPerPixel: options.rasterMMPerPixel,
                options: options
            )
        case .freehand:
            return []
        }
    }

    private static func rasterFailure(item: DesignItem, pixels: PixelBuffer?) -> String? {
        let kind: String
        switch item.content {
        case .image: kind = "изображение"
        case .text: kind = "текст"
        case .monogram: kind = "монограмма"
        default: return nil
        }
        let name = itemLabel(item)
        guard let pixels = pixels else {
            return "«\(name)»: нет растра — \(kind) не декодировалось"
        }
        if pixels.width < 1 || pixels.height < 1 {
            return "«\(name)»: пустой растр"
        }
        let count = pixels.burnPixelCount(threshold: item.effectiveThreshold, invert: item.effectiveInvert)
        if count == 0 {
            return "«\(name)»: после порога нет точек прожига (проверьте контраст или инверсию)"
        }
        return nil
    }

    private static func itemLabel(_ item: DesignItem) -> String {
        let trimmed = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "без имени" : trimmed
    }

    private static func hasBurnMove(_ lines: [String]) -> Bool {
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("G1") || trimmed.hasPrefix("G01") {
                return true
            }
        }
        return false
    }

    private static func cutLines(
        item: DesignItem,
        power: Double,
        speed: Double,
        options: GCodeOptions
    ) -> [String] {
        switch item.content {
        case .freehand(let path):
            let pts = transformed(path.points, item.transform, normalized: false)
            return GCodeGenerator.contour(points: pts, closed: path.closed, powerPercent: power, feedMMPerMin: speed, options: options)
        case .shape(let shape):
            return shapeCut(shape, transform: item.transform, power: power, speed: speed, options: options)
        case .monogram(let mono):
            guard let symbol = MonogramLibrary.symbol(id: mono.symbolID) else { return [] }
            var lines: [String] = []
            for stroke in symbol.strokes {
                let pts = transformed(stroke, item.transform, normalized: true)
                lines.append(contentsOf: GCodeGenerator.contour(points: pts, closed: false, powerPercent: power, feedMMPerMin: speed, options: options))
            }
            return lines
        case .image, .text:
            return GCodeGenerator.rectangleContour(
                rect: item.transform.bounds,
                powerPercent: power,
                feedMMPerMin: speed,
                options: options
            )
        }
    }

    private static func shapeCut(
        _ shape: ShapePayload,
        transform: ItemTransform,
        power: Double,
        speed: Double,
        options: GCodeOptions
    ) -> [String] {
        let rect = transform.bounds
        var lines: [String] = []
        switch shape.kind {
        case .rectangle, .tagRectangle:
            lines.append(contentsOf: GCodeGenerator.rectangleContour(
                rect: rect,
                powerPercent: power,
                feedMMPerMin: speed,
                cornerRadius: shape.cornerRadiusMM,
                options: options
            ))
        case .oval, .tagOval:
            lines.append(contentsOf: GCodeGenerator.ovalContour(
                rect: rect,
                powerPercent: power,
                feedMMPerMin: speed,
                options: options
            ))
        }
        if shape.hangHole {
            let holeR = GCodeGenerator.tagHoleRadius(rect: rect)
            let holeC = GCodeGenerator.tagHoleCenter(rect: rect)
            lines.append(contentsOf: GCodeGenerator.circleContour(
                center: holeC,
                radius: holeR,
                powerPercent: power,
                feedMMPerMin: speed,
                options: options
            ))
        }
        return lines
    }

    /// Точки в локальных мм (freehand) или 0…1 (монограмма).
    static func transformed(_ points: [MMPoint], _ transform: ItemTransform, normalized: Bool) -> [MMPoint] {
        let rad = transform.rotationDegrees * Double.pi / 180
        let cosA = cos(rad)
        let sinA = sin(rad)
        return points.map { p in
            var lx: Double
            var ly: Double
            if normalized {
                lx = (p.x - 0.5) * transform.width
                ly = (p.y - 0.5) * transform.height
            } else {
                lx = p.x
                ly = p.y
            }
            if transform.flipHorizontal { lx = -lx }
            if transform.flipVertical { ly = -ly }
            let rx = lx * cosA - ly * sinA
            let ry = lx * sinA + ly * cosA
            return MMPoint(x: transform.centerX + rx, y: transform.centerY + ry)
        }
    }

    private static func polylineLength(from lines: [String]) -> Double {
        TimeEstimator.distances(in: lines.joined(separator: "\n")).cutMM
            + TimeEstimator.distances(in: lines.joined(separator: "\n")).burnMM
    }
}

extension GCodeGenerator {
    static func rasterFilledRect(
        rect: MMRect,
        powerPercent: Double,
        feedMMPerMin: Double,
        mmPerPixel: Double,
        options: GCodeOptions = GCodeOptions()
    ) -> [String] {
        let w = max(1, Int((rect.width / mmPerPixel).rounded()))
        let h = max(1, Int((rect.height / mmPerPixel).rounded()))
        let buffer = PixelBuffer.filled(width: w, height: h, value: 0)
        return raster(
            buffer: buffer,
            origin: rect.origin,
            mmPerPixel: mmPerPixel,
            powerPercent: powerPercent,
            feedMMPerMin: feedMMPerMin,
            threshold: 0.5,
            invert: false,
            options: options
        )
    }

    static func rasterFilledOval(
        rect: MMRect,
        powerPercent: Double,
        feedMMPerMin: Double,
        mmPerPixel: Double,
        options: GCodeOptions = GCodeOptions()
    ) -> [String] {
        let w = max(1, Int((rect.width / mmPerPixel).rounded()))
        let h = max(1, Int((rect.height / mmPerPixel).rounded()))
        var lum = [UInt8](repeating: 255, count: w * h)
        let opq = [Bool](repeating: true, count: w * h)
        let cx = Double(w) / 2
        let cy = Double(h) / 2
        let rx = max(0.5, Double(w) / 2 - 0.5)
        let ry = max(0.5, Double(h) / 2 - 0.5)
        for y in 0..<h {
            for x in 0..<w {
                let nx = (Double(x) + 0.5 - cx) / rx
                let ny = (Double(y) + 0.5 - cy) / ry
                if nx * nx + ny * ny <= 1 {
                    lum[y * w + x] = 0
                }
            }
        }
        let buffer = PixelBuffer(width: w, height: h, luminance: lum, opaque: opq)
        return raster(
            buffer: buffer,
            origin: rect.origin,
            mmPerPixel: mmPerPixel,
            powerPercent: powerPercent,
            feedMMPerMin: feedMMPerMin,
            threshold: 0.5,
            invert: false,
            options: options
        )
    }
}
