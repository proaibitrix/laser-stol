import Foundation

struct ProjectDocument: Codable, Equatable {
    var version: Int
    var bedWidthMM: Double
    var bedHeightMM: Double
    var layers: [LaserLayer]
    var items: [DesignItem]
    var materialID: String
    var job: JobSettings
    var updatedAt: Date

    static let currentVersion = 1
    static let defaultBedMM: Double = 400

    init(
        version: Int = ProjectDocument.currentVersion,
        bedWidthMM: Double = ProjectDocument.defaultBedMM,
        bedHeightMM: Double = ProjectDocument.defaultBedMM,
        layers: [LaserLayer] = LaserLayer.defaultPair(),
        items: [DesignItem] = [],
        materialID: String = "plywood-3",
        job: JobSettings = JobSettings(),
        updatedAt: Date = Date()
    ) {
        self.version = version
        self.bedWidthMM = bedWidthMM
        self.bedHeightMM = bedHeightMM
        self.layers = layers
        self.items = items
        self.materialID = materialID
        self.job = job
        self.updatedAt = updatedAt
    }

    var bedRect: MMRect {
        MMRect(origin: .zero, size: MMSize(width: bedWidthMM, height: bedHeightMM))
    }

    func layer(id: UUID) -> LaserLayer? {
        layers.first(where: { $0.id == id })
    }

    func layer(kind: LayerKind) -> LaserLayer? {
        layers.first(where: { $0.kind == kind })
    }

    mutating func ensureDefaultLayers() {
        if layer(kind: .burn) == nil {
            layers.insert(LaserLayer(kind: .burn), at: 0)
        }
        if layer(kind: .cut) == nil {
            layers.append(LaserLayer(kind: .cut))
        }
    }

    func items(on layerID: UUID) -> [DesignItem] {
        items.filter { $0.layerID == layerID }
    }

    func item(id: UUID) -> DesignItem? {
        items.first(where: { $0.id == id })
    }

    mutating func upsert(_ item: DesignItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.append(item)
        }
        updatedAt = Date()
    }

    mutating func removeItems(ids: Set<UUID>) {
        items.removeAll { ids.contains($0.id) }
        updatedAt = Date()
    }

    func combinedBounds(of ids: [UUID]) -> MMRect? {
        let selected = items.filter { ids.contains($0.id) }
        guard let first = selected.first else { return nil }
        return selected.dropFirst().reduce(first.transform.axisAlignedBounds) { $0.union($1.transform.axisAlignedBounds) }
    }

    func allItemsBounds() -> MMRect? {
        guard let first = items.first else { return nil }
        return items.dropFirst().reduce(first.transform.axisAlignedBounds) { $0.union($1.transform.axisAlignedBounds) }
    }

    func itemsFitBed() -> Bool {
        guard let bounds = allItemsBounds() else { return true }
        let margin = 0.4
        return bounds.minX >= -margin
            && bounds.minY >= -margin
            && bounds.maxX <= bedWidthMM + margin
            && bounds.maxY <= bedHeightMM + margin
    }

    mutating func applyMaterial(_ preset: MaterialPreset) {
        materialID = preset.id
        job.materialID = preset.id
        for index in layers.indices {
            switch layers[index].kind {
            case .burn:
                layers[index].powerPercent = preset.burnPowerPercent
                layers[index].speedMMPerMin = preset.burnSpeedMMPerMin
            case .cut:
                layers[index].powerPercent = preset.cutPowerPercent
                layers[index].speedMMPerMin = preset.cutSpeedMMPerMin
            }
        }
        updatedAt = Date()
    }
}
