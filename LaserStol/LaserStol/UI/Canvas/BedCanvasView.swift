import AppKit

final class BedCanvasView: NSView {
    weak var app: AppState? {
        didSet { needsDisplay = true }
    }

    private enum DragKind {
        case move
        case scale(handle: Int)
        case rotate
        case draw
    }

    private var drag: DragKind?
    private var dragStart: MMPoint = .zero
    private var original: [UUID: ItemTransform] = [:]

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.cornerRadius = 18
        layer?.masksToBounds = true
        window?.isMovableByWindowBackground = false
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let app = app else {
            Theme.nsCream.setFill()
            dirtyRect.fill()
            return
        }
        Theme.nsCream.setFill()
        bounds.fill()

        let bed = bedRect()
        drawWood(in: bed)

        let doc = app.document
        for item in doc.items {
            guard let layer = doc.layer(id: item.layerID), layer.isVisible else { continue }
            drawItem(item, layer: layer, selected: app.selectedIDs.contains(item.id))
        }

        if app.tool == .contour, app.contourDraft.count >= 1 {
            drawDraft(app.contourDraft)
        }

        if let id = app.selectedIDs.first, let item = doc.item(id: id) {
            drawSelection(item)
        }
    }

    // MARK: - Mapping

    private func bedRect() -> NSRect {
        guard let app = app else { return bounds.insetBy(dx: 24, dy: 24) }
        let inset: CGFloat = 8
        let available = bounds.insetBy(dx: inset, dy: inset)
        let aspect = CGFloat(app.document.bedWidthMM / max(app.document.bedHeightMM, 1.0))
        var w = available.width
        var h = w / aspect
        if h > available.height {
            h = available.height
            w = h * aspect
        }
        return NSRect(
            x: available.midX - w / 2,
            y: available.midY - h / 2,
            width: w,
            height: h
        )
    }

    private func viewPoint(from mm: MMPoint) -> NSPoint {
        guard let app = app else { return .zero }
        let bed = bedRect()
        let x = bed.minX + CGFloat(mm.x / app.document.bedWidthMM) * bed.width
        let y = bed.minY + CGFloat(mm.y / app.document.bedHeightMM) * bed.height
        return NSPoint(x: x, y: y)
    }

    private func mmPoint(from view: NSPoint) -> MMPoint {
        guard let app = app else { return .zero }
        let bed = bedRect()
        let x = Double((view.x - bed.minX) / max(bed.width, 1 as CGFloat)) * app.document.bedWidthMM
        let y = Double((view.y - bed.minY) / max(bed.height, 1 as CGFloat)) * app.document.bedHeightMM
        return MMPoint(x: x, y: y)
    }

    private func scaleMMPerPoint() -> Double {
        guard let app = app else { return 1 }
        return app.document.bedWidthMM / Double(max(bedRect().width, 1 as CGFloat))
    }

    // MARK: - Drawing

    private func drawWood(in rect: NSRect) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
        Theme.nsWoodLight.setFill()
        path.fill()

        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        Theme.nsWoodMid.withAlphaComponent(0.18).setStroke()
        var y = rect.minY
        var i = 0
        while y < rect.maxY {
            let grain = NSBezierPath()
            grain.move(to: NSPoint(x: rect.minX, y: y))
            grain.curve(
                to: NSPoint(x: rect.maxX, y: y + 2),
                controlPoint1: NSPoint(x: rect.midX - 40, y: y + CGFloat((i % 3) * 2 - 2)),
                controlPoint2: NSPoint(x: rect.midX + 30, y: y + 3)
            )
            grain.lineWidth = 1
            grain.stroke()
            y += 7
            i += 1
        }
        NSGraphicsContext.restoreGraphicsState()

        Theme.nsTerracotta.withAlphaComponent(0.18).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private func drawItem(_ item: DesignItem, layer: LaserLayer, selected: Bool) {
        switch item.content {
        case .image(let payload):
            drawImageItem(item, payload: payload)
        case .text(let text):
            let image = ImageProcessor.renderText(text, size: NSSize(width: 320, height: 180))
            drawNSImage(image, item: item, threshold: item.threshold, invert: item.invert)
        case .monogram(let mono):
            if let symbol = MonogramLibrary.symbol(id: mono.symbolID), !symbol.strokes.isEmpty {
                drawMonogramStrokes(symbol, item: item, cut: layer.kind == .cut)
            } else if let symbol = MonogramLibrary.symbol(id: mono.symbolID) {
                let image = ImageProcessor.renderMonogram(symbol, size: NSSize(width: 260, height: 260))
                drawNSImage(image, item: item, threshold: 0.55, invert: false)
            }
        case .shape(let shape):
            drawShape(item, shape: shape, layer: layer)
        case .freehand(let path):
            drawFreehand(item, path: path, layer: layer)
        }
        if layer.kind == .cut {
            strokeBoundsDashed(item.transform.axisAlignedBounds)
        }
    }

    private func drawImageItem(_ item: DesignItem, payload: ImagePayload) {
        guard let image = NSImage(data: payload.pngData) else { return }
        drawNSImage(image, item: item, threshold: payload.threshold, invert: payload.invert)
    }

    private func drawNSImage(_ image: NSImage, item: DesignItem, threshold: Double, invert: Bool) {
        let buffer = ImageProcessor.pixelBuffer(image: image, maxEdge: 180)
        let preview: NSImage
        if let buffer = buffer {
            preview = ImageProcessor.previewImage(from: buffer, threshold: threshold, invert: invert)
        } else {
            preview = image
        }
        let bounds = item.transform.bounds
        let r = nsRect(from: bounds)
        NSGraphicsContext.saveGraphicsState()
        let t = NSAffineTransform()
        t.translateX(by: r.midX, yBy: r.midY)
        t.rotate(byDegrees: CGFloat(item.transform.rotationDegrees))
        t.scaleX(by: item.transform.flipHorizontal ? -1 : 1, yBy: item.transform.flipVertical ? -1 : 1)
        t.concat()
        let dest = NSRect(x: -r.width / 2, y: -r.height / 2, width: r.width, height: r.height)
        preview.draw(in: dest, from: .zero, operation: .sourceOver, fraction: 0.92)
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawShape(_ item: DesignItem, shape: ShapePayload, layer: LaserLayer) {
        let r = nsRect(from: item.transform.bounds)
        let path: NSBezierPath
        switch shape.kind {
        case .rectangle, .tagRectangle:
            path = NSBezierPath(roundedRect: r, xRadius: CGFloat(shape.cornerRadiusMM / scaleMMPerPoint()), yRadius: CGFloat(shape.cornerRadiusMM / scaleMMPerPoint()))
        case .oval, .tagOval:
            path = NSBezierPath(ovalIn: r)
        }
        if layer.kind == .burn {
            Theme.nsWoodMid.withAlphaComponent(0.35).setFill()
            path.fill()
        }
        Theme.nsTerracotta.setStroke()
        path.lineWidth = 1.1
        if layer.kind == .cut {
            let dashes: [CGFloat] = [4, 3]
            path.setLineDash(dashes, count: 2, phase: 0)
        }
        path.stroke()
        if shape.hangHole {
            let holeC = GCodeGenerator.tagHoleCenter(rect: item.transform.bounds)
            let holeR = GCodeGenerator.tagHoleRadius(rect: item.transform.bounds)
            let c = viewPoint(from: holeC)
            let rr = CGFloat(holeR / scaleMMPerPoint())
            let hole = NSBezierPath(ovalIn: NSRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2))
            hole.lineWidth = 1
            hole.setLineDash([3, 2], count: 2, phase: 0)
            Theme.nsTerracotta.setStroke()
            hole.stroke()
        }
    }

    private func drawFreehand(_ item: DesignItem, path: FreehandPayload, layer: LaserLayer) {
        let pts = JobBuilder.transformed(path.points, item.transform, normalized: false)
        guard let first = pts.first else { return }
        let bezier = NSBezierPath()
        bezier.move(to: viewPoint(from: first))
        for p in pts.dropFirst() { bezier.line(to: viewPoint(from: p)) }
        if path.closed { bezier.close() }
        bezier.lineWidth = 1.2
        bezier.lineJoinStyle = .round
        bezier.lineCapStyle = .round
        if layer.kind == .cut {
            bezier.setLineDash([4, 3], count: 2, phase: 0)
            Theme.nsTerracotta.setStroke()
        } else {
            Theme.nsInk.setStroke()
        }
        bezier.stroke()
    }

    private func drawMonogramStrokes(_ symbol: MonogramSymbol, item: DesignItem, cut: Bool) {
        for stroke in symbol.strokes {
            let pts = JobBuilder.transformed(stroke, item.transform, normalized: true)
            guard let first = pts.first else { continue }
            let bezier = NSBezierPath()
            bezier.move(to: viewPoint(from: first))
            for p in pts.dropFirst() { bezier.line(to: viewPoint(from: p)) }
            bezier.lineWidth = 1.4
            bezier.lineCapStyle = .round
            Theme.nsInk.setStroke()
            bezier.stroke()
        }
    }

    private func strokeBoundsDashed(_ rect: MMRect) {
        let r = nsRect(from: rect)
        let path = NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6)
        path.setLineDash([3, 3], count: 2, phase: 0)
        path.lineWidth = 0.8
        Theme.nsTerracotta.withAlphaComponent(0.55).setStroke()
        path.stroke()
    }

    private func drawDraft(_ points: [MMPoint]) {
        guard let first = points.first else { return }
        let path = NSBezierPath()
        path.move(to: viewPoint(from: first))
        for p in points.dropFirst() { path.line(to: viewPoint(from: p)) }
        path.lineWidth = 1.2
        path.setLineDash([4, 3], count: 2, phase: 0)
        Theme.nsTerracotta.setStroke()
        path.stroke()
    }

    private func drawSelection(_ item: DesignItem) {
        let r = nsRect(from: item.transform.axisAlignedBounds)
        let box = NSBezierPath(rect: r)
        Theme.nsTerracotta.withAlphaComponent(0.35).setStroke()
        box.lineWidth = 0.8
        box.stroke()
        for p in handlePoints(r) {
            drawHandle(at: p)
        }
        let rot = NSPoint(x: r.midX, y: r.minY - 18)
        NSColor.white.setFill()
        Theme.nsTerracotta.setStroke()
        let knob = NSBezierPath(ovalIn: NSRect(x: rot.x - 4, y: rot.y - 4, width: 8, height: 8))
        knob.fill()
        knob.stroke()
        let line = NSBezierPath()
        line.move(to: NSPoint(x: r.midX, y: r.minY))
        line.line(to: rot)
        line.lineWidth = 0.8
        Theme.nsTerracotta.withAlphaComponent(0.5).setStroke()
        line.stroke()
    }

    private func handlePoints(_ r: NSRect) -> [NSPoint] {
        [
            NSPoint(x: r.minX, y: r.minY),
            NSPoint(x: r.maxX, y: r.minY),
            NSPoint(x: r.minX, y: r.maxY),
            NSPoint(x: r.maxX, y: r.maxY)
        ]
    }

    private func drawHandle(at p: NSPoint) {
        let r = NSRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7)
        NSColor.white.setFill()
        Theme.nsTerracotta.setStroke()
        let path = NSBezierPath(rect: r)
        path.fill()
        path.lineWidth = 1
        path.stroke()
    }

    private func nsRect(from mm: MMRect) -> NSRect {
        let a = viewPoint(from: mm.origin)
        let b = viewPoint(from: MMPoint(x: mm.maxX, y: mm.maxY))
        return NSRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let app = app else { return }
        let loc = convert(event.locationInWindow, from: nil)
        let mm = mmPoint(from: loc)
        var shouldTrack = false

        if app.tool == .contour {
            drag = .draw
            app.contourDraft = [mm]
            needsDisplay = true
            shouldTrack = true
        } else if let id = app.selectedIDs.first, let item = app.document.item(id: id) {
            let r = nsRect(from: item.transform.axisAlignedBounds)
            let rot = NSPoint(x: r.midX, y: r.minY - 18)
            if hypot(loc.x - rot.x, loc.y - rot.y) < 10 {
                beginDrag(.rotate, mm: mm)
                shouldTrack = true
            } else if let handle = handleIndex(at: loc, in: r) {
                beginDrag(.scale(handle: handle), mm: mm)
                shouldTrack = true
            } else if let hit = hitItem(at: mm) {
                app.select(hit.id, additive: event.modifierFlags.contains(.shift))
                beginDrag(.move, mm: mm)
                shouldTrack = true
            } else {
                app.select(nil)
            }
        } else if let hit = hitItem(at: mm) {
            app.select(hit.id, additive: event.modifierFlags.contains(.shift))
            beginDrag(.move, mm: mm)
            shouldTrack = true
        } else {
            app.select(nil)
        }

        needsDisplay = true
        if shouldTrack {
            trackUntilMouseUp()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let app = app, let drag = drag else { return }
        let loc = convert(event.locationInWindow, from: nil)
        let mm = mmPoint(from: loc)
        switch drag {
        case .draw:
            if let last = app.contourDraft.last, last.distance(to: mm) > 0.4 {
                app.contourDraft.append(mm)
            }
        case .move:
            let dx = mm.x - dragStart.x
            let dy = mm.y - dragStart.y
            for id in app.selectedIDs {
                guard var item = app.document.item(id: id), let orig = original[id] else { continue }
                item.transform = orig.applying(dx: dx, dy: dy)
                app.updateItem(item)
            }
        case .scale(let handle):
            guard let id = app.selectedIDs.first, var item = app.document.item(id: id), let orig = original[id] else { return }
            let sx: Double = (handle == 0 || handle == 2) ? -1 : 1
            let sy: Double = (handle == 0 || handle == 1) ? -1 : 1
            let dw = (mm.x - dragStart.x) * sx
            let dh = (mm.y - dragStart.y) * sy
            item.transform.width = max(4.0, orig.width + dw)
            item.transform.height = max(4.0, orig.height + dh)
            app.updateItem(item)
        case .rotate:
            guard let id = app.selectedIDs.first, var item = app.document.item(id: id) else { return }
            let c = item.transform.center
            let a1 = atan2(dragStart.y - c.y, dragStart.x - c.x)
            let a2 = atan2(mm.y - c.y, mm.x - c.x)
            if let orig = original[id] {
                item.transform.rotationDegrees = ItemTransform.normalizedAngle(orig.rotationDegrees + (a2 - a1) * 180 / Double.pi)
                app.updateItem(item)
            }
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if app?.tool == .contour {
            app?.finishContour()
        }
        drag = nil
        original = [:]
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 {
            app?.deleteSelection()
            needsDisplay = true
        } else {
            super.keyDown(with: event)
        }
    }

    private func beginDrag(_ kind: DragKind, mm: MMPoint) {
        drag = kind
        dragStart = mm
        original = [:]
        for item in app?.selectedItems ?? [] {
            original[item.id] = item.transform
        }
    }

    /// Забираем drag в tracking loop, чтобы AppKit не утащил окно и SwiftUI не съел события.
    private func trackUntilMouseUp() {
        guard let window = window else { return }
        while true {
            guard let next = window.nextEvent(
                matching: [.leftMouseDragged, .leftMouseUp],
                until: Date.distantFuture,
                inMode: .eventTracking,
                dequeue: true
            ) else { break }
            if next.type == .leftMouseUp {
                mouseUp(with: next)
                break
            }
            mouseDragged(with: next)
        }
    }

    private func handleIndex(at loc: NSPoint, in r: NSRect) -> Int? {
        for (index, p) in handlePoints(r).enumerated() {
            if hypot(loc.x - p.x, loc.y - p.y) < 9 {
                return index
            }
        }
        return nil
    }

    private func hitItem(at mm: MMPoint) -> DesignItem? {
        guard let app = app else { return nil }
        let slop = 2.0
        return app.document.items.reversed().first { item in
            guard let layer = app.document.layer(id: item.layerID), layer.isVisible else { return false }
            return item.transform.axisAlignedBounds.inset(by: -slop).contains(mm)
        }
    }
}
