import Foundation
import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

enum WorkspaceTool: String, CaseIterable, Identifiable {
    case select
    case open
    case text
    case shapes
    case monogram
    case contour

    var id: String { rawValue }
}

enum ActiveSheet: Identifiable, Equatable {
    case newTag
    case text
    case monogram
    case tileGrid
    case preflight
    case running

    var id: String {
        switch self {
        case .newTag: return "newTag"
        case .text: return "text"
        case .monogram: return "monogram"
        case .tileGrid: return "tileGrid"
        case .preflight: return "preflight"
        case .running: return "running"
        }
    }
}

final class AppState: ObservableObject {
    @Published var document: ProjectDocument {
        didSet { scheduleAutosave() }
    }
    @Published var selectedIDs: Set<UUID> = []
    @Published var tool: WorkspaceTool = .select
    @Published var sheet: ActiveSheet?
    @Published var showLayers: Bool = true
    @Published var draftTag = TagDraft()
    @Published var draftText = "Монограмма"
    @Published var tileColumns: Int = 5
    @Published var tileRows: Int = 5
    @Published var tileGapMM: Double = 6
    @Published var lastJob: GeneratedJob?
    @Published var pendingScope: JobScope = .wholeSheet
    @Published var contourDraft: [MMPoint] = []
    @Published var showConnectionPopover = false

    @Published var machine = GRBLController()
    private var autosave: AnyCancellable?
    private var machineBag = Set<AnyCancellable>()

    init(document: ProjectDocument = ProjectDocument()) {
        if let saved = ProjectStore.load(), !saved.items.isEmpty {
            self.document = saved
        } else if document.items.isEmpty {
            self.document = DemoProject.make()
        } else {
            self.document = document
            self.document.ensureDefaultLayers()
        }
        machine.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &machineBag)
        machine.connect(kind: .mock)
    }

    var selectedItems: [DesignItem] {
        document.items.filter { selectedIDs.contains($0.id) }
    }

    var primarySelection: DesignItem? {
        selectedItems.first
    }

    func select(_ id: UUID?, additive: Bool = false) {
        guard let id = id else {
            selectedIDs.removeAll()
            return
        }
        if additive {
            if selectedIDs.contains(id) { selectedIDs.remove(id) }
            else { selectedIDs.insert(id) }
        } else {
            selectedIDs = [id]
        }
    }

    func updateItem(_ item: DesignItem) {
        document.upsert(item)
    }

    func deleteSelection() {
        document.removeItems(ids: selectedIDs)
        selectedIDs.removeAll()
    }

    func layerID(for kind: LayerKind) -> UUID {
        document.ensureDefaultLayers()
        return document.layer(kind: kind)?.id ?? document.layers[0].id
    }

    func openImportPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        var types: [UTType] = [.png, .jpeg]
        if let svg = UTType(filenameExtension: "svg") {
            types.append(svg)
        }
        panel.allowedContentTypes = types
        panel.title = "Открыть изображение"
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            self?.importURLs(panel.urls)
        }
    }

    func importURLs(_ urls: [URL]) {
        for url in urls {
            let ext = url.pathExtension.lowercased()
            if ext == "svg" {
                importSVG(url)
            } else {
                importRaster(url)
            }
        }
    }

    private func importRaster(_ url: URL) {
        guard let (image, png) = ImageProcessor.loadImage(url: url) else { return }
        let size = ImageProcessor.defaultItemSize(for: image, bed: document.bedWidthMM)
        let item = DesignItem(
            layerID: layerID(for: .burn),
            name: url.lastPathComponent,
            transform: ItemTransform(
                centerX: document.bedWidthMM / 2,
                centerY: document.bedHeightMM / 2,
                width: size.width,
                height: size.height
            ),
            content: .image(ImagePayload(pngData: png, originalName: url.lastPathComponent))
        )
        document.upsert(item)
        selectedIDs = [item.id]
    }

    private func importSVG(_ url: URL) {
        let imported = SVGImporter.importPaths(url: url)
        guard !imported.isEmpty else { return }
        let allPoints = imported.flatMap(\.points)
        guard let minX = allPoints.map(\.x).min(),
              let minY = allPoints.map(\.y).min(),
              let maxX = allPoints.map(\.x).max(),
              let maxY = allPoints.map(\.y).max() else { return }
        let srcW = max(1.0, maxX - minX)
        let srcH = max(1.0, maxY - minY)
        let target = min(90.0, document.bedWidthMM * 0.3)
        let scale = target / max(srcW, srcH)
        let cx = document.bedWidthMM / 2
        let cy = document.bedHeightMM / 2
        for (index, path) in imported.enumerated() {
            let local = path.points.map { p -> MMPoint in
                MMPoint(
                    x: (p.x - minX - srcW / 2) * scale,
                    y: (p.y - minY - srcH / 2) * scale
                )
            }
            let item = DesignItem(
                layerID: layerID(for: .cut),
                name: "SVG \(index + 1)",
                transform: ItemTransform(centerX: cx, centerY: cy, width: srcW * scale, height: srcH * scale),
                content: .freehand(FreehandPayload(points: local, closed: path.closed))
            )
            document.upsert(item)
            selectedIDs = [item.id]
        }
    }

    func addTag(from draft: TagDraft) {
        document.ensureDefaultLayers()
        let kind: ShapeKind = {
            switch draft.shape {
            case .rectangle: return .tagRectangle
            case .oval: return .tagOval
            case .custom: return .tagRectangle
            }
        }()
        let item = DesignItem(
            layerID: layerID(for: .cut),
            name: "Бирка",
            transform: ItemTransform(
                centerX: document.bedWidthMM / 2,
                centerY: document.bedHeightMM / 2,
                width: draft.widthMM,
                height: draft.heightMM
            ),
            content: .shape(ShapePayload(kind: kind, cornerRadiusMM: draft.shape == .oval ? 0 : 4, hangHole: true))
        )
        document.upsert(item)
        selectedIDs = [item.id]
        sheet = nil
    }

    func addText(_ text: String) {
        let payload = TextPayload(text: text)
        let image = ImageProcessor.renderText(payload, size: NSSize(width: 400, height: 220))
        let png = ImageProcessor.pngData(from: image) ?? Data()
        let item = DesignItem(
            layerID: layerID(for: .burn),
            name: text,
            transform: ItemTransform(
                centerX: document.bedWidthMM / 2,
                centerY: document.bedHeightMM / 2,
                width: 70,
                height: 38
            ),
            content: .image(ImagePayload(pngData: png, originalName: text))
        )
        document.upsert(item)
        selectedIDs = [item.id]
        sheet = nil
    }

    func addMonogram(_ symbol: MonogramSymbol) {
        document.ensureDefaultLayers()
        if symbol.strokes.isEmpty {
            let image = ImageProcessor.renderMonogram(symbol, size: NSSize(width: 360, height: 360))
            let png = ImageProcessor.pngData(from: image) ?? Data()
            let item = DesignItem(
                layerID: layerID(for: .burn),
                name: "Монограмма \(symbol.title)",
                transform: ItemTransform(
                    centerX: document.bedWidthMM / 2,
                    centerY: document.bedHeightMM / 2,
                    width: 60,
                    height: 60
                ),
                content: .image(ImagePayload(pngData: png, originalName: symbol.title))
            )
            document.upsert(item)
            selectedIDs = [item.id]
        } else {
            let item = DesignItem(
                layerID: layerID(for: .cut),
                name: "Монограмма \(symbol.title)",
                transform: ItemTransform(
                    centerX: document.bedWidthMM / 2,
                    centerY: document.bedHeightMM / 2,
                    width: 70,
                    height: 46
                ),
                content: .monogram(MonogramPayload(symbolID: symbol.id, letters: symbol.letters))
            )
            document.upsert(item)
            selectedIDs = [item.id]
        }
        sheet = nil
    }

    func finishContour() {
        let simplified = PathSimplifier.douglasPeucker(contourDraft, tolerance: 0.35)
        contourDraft = []
        tool = .select
        guard simplified.count >= 2 else { return }
        let minX = simplified.map(\.x).min() ?? 0
        let minY = simplified.map(\.y).min() ?? 0
        let maxX = simplified.map(\.x).max() ?? 0
        let maxY = simplified.map(\.y).max() ?? 0
        let cx = (minX + maxX) / 2
        let cy = (minY + maxY) / 2
        let local = simplified.map { MMPoint(x: $0.x - cx, y: $0.y - cy) }
        let item = DesignItem(
            layerID: layerID(for: .cut),
            name: "Контур",
            transform: ItemTransform(centerX: cx, centerY: cy, width: max(1.0, maxX - minX), height: max(1.0, maxY - minY)),
            content: .freehand(FreehandPayload(points: local, closed: true))
        )
        document.upsert(item)
        selectedIDs = [item.id]
    }

    func applyTileGrid() {
        let targets = selectedItems.isEmpty ? document.items : selectedItems
        guard let first = targets.first else { return }
        let offsets = TileGridMath.offsets(
            columns: tileColumns,
            rows: tileRows,
            itemWidth: first.transform.width,
            itemHeight: first.transform.height,
            gapMM: tileGapMM
        )
        let groupBounds = TileGridMath.totalSize(
            columns: tileColumns,
            rows: tileRows,
            itemWidth: first.transform.width,
            itemHeight: first.transform.height,
            gapMM: tileGapMM
        )
        let startX = (document.bedWidthMM - groupBounds.width) / 2 + first.transform.width / 2
        let startY = (document.bedHeightMM - groupBounds.height) / 2 + first.transform.height / 2
        var newItems: [DesignItem] = []
        for (index, offset) in offsets.enumerated() {
            for source in targets {
                var copy = source.duplicated(offset: .zero)
                copy.transform.centerX = startX + offset.x + (source.transform.centerX - first.transform.centerX)
                copy.transform.centerY = startY + offset.y + (source.transform.centerY - first.transform.centerY)
                if index == 0 {
                    // заменяем исходники первой клеткой
                    copy.id = source.id
                }
                newItems.append(copy)
            }
        }
        if !selectedItems.isEmpty {
            document.removeItems(ids: selectedIDs)
        } else {
            document.items.removeAll()
        }
        for item in newItems {
            document.upsert(item)
        }
        selectedIDs = Set(newItems.map(\.id))
        sheet = nil
    }

    func applyMaterial(_ preset: MaterialPreset) {
        document.applyMaterial(preset)
    }

    func beginJob(scope: JobScope) {
        pendingScope = scope
        document.job.scope = scope
        lastJob = buildJob(scope: scope)
        sheet = .preflight
    }

    func buildJob(scope: JobScope) -> GeneratedJob {
        var settings = document.job
        settings.scope = scope
        settings.materialID = document.materialID
        return JobBuilder.build(document: document, settings: settings, pixelsForItem: { item in
            self.pixels(for: item)
        })
    }

    func pixels(for item: DesignItem) -> PixelBuffer? {
        switch item.content {
        case .image(let image):
            return ImageProcessor.pixelBuffer(
                pngData: image.pngData,
                maxEdge: 220,
                threshold: image.threshold,
                invert: image.invert
            )
        case .text(let text):
            let ns = ImageProcessor.renderText(text, size: NSSize(width: 240, height: 240))
            return ImageProcessor.pixelBuffer(image: ns, maxEdge: 72)
        case .monogram(let mono):
            guard let symbol = MonogramLibrary.symbol(id: mono.symbolID) else { return nil }
            let ns = ImageProcessor.renderMonogram(symbol, size: NSSize(width: 260, height: 260))
            return ImageProcessor.pixelBuffer(image: ns, maxEdge: 96)
        default:
            return nil
        }
    }

    func confirmStart() {
        guard let job = lastJob else { return }
        sheet = .running
        machine.run(job: job)
    }

    func flipSelection(horizontal: Bool) {
        for id in selectedIDs {
            guard var item = document.item(id: id) else { continue }
            if horizontal { item.transform.flipHorizontal.toggle() }
            else { item.transform.flipVertical.toggle() }
            document.upsert(item)
        }
    }

    func rotateSelection(degrees: Double) {
        for id in selectedIDs {
            guard var item = document.item(id: id) else { continue }
            item.transform.rotateBy(degrees: degrees)
            document.upsert(item)
        }
    }

    func invertSelection() {
        for id in selectedIDs {
            guard var item = document.item(id: id) else { continue }
            item.setInvert(!item.effectiveInvert)
            document.upsert(item)
        }
    }

    func setThreshold(_ value: Double) {
        for id in selectedIDs {
            guard var item = document.item(id: id) else { continue }
            item.setThreshold(value)
            document.upsert(item)
        }
    }

    private func scheduleAutosave() {
        autosave?.cancel()
        autosave = Just(document)
            .delay(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { ProjectStore.autosave($0) }
    }
}

struct TagDraft: Equatable {
    enum Shape: String, CaseIterable, Identifiable {
        case rectangle
        case oval
        case custom
        var id: String { rawValue }
    }

    var shape: Shape = .rectangle
    var widthMM: Double = 50
    var heightMM: Double = 30
}
