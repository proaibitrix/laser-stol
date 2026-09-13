import Foundation

enum LayerKind: String, Codable, CaseIterable, Identifiable {
    case burn = "prozhig"
    case cut = "rez"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .burn: return "Прожиг"
        case .cut: return "Рез"
        }
    }

    var shortTitle: String {
        title
    }
}

struct LaserLayer: Identifiable, Codable, Equatable {
    var id: UUID
    var kind: LayerKind
    var name: String
    var isVisible: Bool
    var powerPercent: Double
    var speedMMPerMin: Double

    init(
        id: UUID = UUID(),
        kind: LayerKind,
        name: String? = nil,
        isVisible: Bool = true,
        powerPercent: Double? = nil,
        speedMMPerMin: Double? = nil
    ) {
        self.id = id
        self.kind = kind
        self.name = name ?? kind.title
        self.isVisible = isVisible
        self.powerPercent = powerPercent ?? (kind == .burn ? 45 : 80)
        self.speedMMPerMin = speedMMPerMin ?? (kind == .burn ? 1200 : 400)
    }

    static func defaultPair() -> [LaserLayer] {
        [
            LaserLayer(kind: .burn),
            LaserLayer(kind: .cut)
        ]
    }
}
