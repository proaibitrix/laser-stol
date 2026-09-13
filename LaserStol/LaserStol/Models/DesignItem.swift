import Foundation

enum ShapeKind: String, Codable, CaseIterable {
    case rectangle
    case oval
    case tagRectangle
    case tagOval
}

enum DesignContent: Codable, Equatable {
    case image(ImagePayload)
    case text(TextPayload)
    case shape(ShapePayload)
    case freehand(FreehandPayload)
    case monogram(MonogramPayload)

    enum CodingKeys: String, CodingKey {
        case type
        case image
        case text
        case shape
        case freehand
        case monogram
    }

    enum Kind: String, Codable {
        case image, text, shape, freehand, monogram
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(Kind.self, forKey: .type)
        switch type {
        case .image:
            self = .image(try container.decode(ImagePayload.self, forKey: .image))
        case .text:
            self = .text(try container.decode(TextPayload.self, forKey: .text))
        case .shape:
            self = .shape(try container.decode(ShapePayload.self, forKey: .shape))
        case .freehand:
            self = .freehand(try container.decode(FreehandPayload.self, forKey: .freehand))
        case .monogram:
            self = .monogram(try container.decode(MonogramPayload.self, forKey: .monogram))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .image(let payload):
            try container.encode(Kind.image, forKey: .type)
            try container.encode(payload, forKey: .image)
        case .text(let payload):
            try container.encode(Kind.text, forKey: .type)
            try container.encode(payload, forKey: .text)
        case .shape(let payload):
            try container.encode(Kind.shape, forKey: .type)
            try container.encode(payload, forKey: .shape)
        case .freehand(let payload):
            try container.encode(Kind.freehand, forKey: .type)
            try container.encode(payload, forKey: .freehand)
        case .monogram(let payload):
            try container.encode(Kind.monogram, forKey: .type)
            try container.encode(payload, forKey: .monogram)
        }
    }

    var prefersCutLayer: Bool {
        switch self {
        case .freehand, .shape:
            return true
        case .image, .text, .monogram:
            return false
        }
    }
}

struct ImagePayload: Codable, Equatable {
    var pngData: Data
    var originalName: String
    var threshold: Double
    var invert: Bool

    init(pngData: Data, originalName: String, threshold: Double = 0.52, invert: Bool = false) {
        self.pngData = pngData
        self.originalName = originalName
        self.threshold = threshold
        self.invert = invert
    }
}

struct TextPayload: Codable, Equatable {
    var text: String
    var fontName: String
    var fontSizePT: Double

    init(text: String, fontName: String = "Times New Roman", fontSizePT: Double = 48) {
        self.text = text
        self.fontName = fontName
        self.fontSizePT = fontSizePT
    }
}

struct ShapePayload: Codable, Equatable {
    var kind: ShapeKind
    var cornerRadiusMM: Double
    var hangHole: Bool

    init(kind: ShapeKind, cornerRadiusMM: Double = 3, hangHole: Bool = false) {
        self.kind = kind
        self.cornerRadiusMM = cornerRadiusMM
        self.hangHole = hangHole
    }
}

struct FreehandPayload: Codable, Equatable {
    var points: [MMPoint]
    var closed: Bool

    init(points: [MMPoint], closed: Bool = false) {
        self.points = points
        self.closed = closed
    }
}

struct MonogramPayload: Codable, Equatable {
    var symbolID: String
    var letters: String

    init(symbolID: String, letters: String) {
        self.symbolID = symbolID
        self.letters = letters
    }
}

struct DesignItem: Identifiable, Codable, Equatable {
    var id: UUID
    var layerID: UUID
    var name: String
    var transform: ItemTransform
    var content: DesignContent
    var threshold: Double
    var invert: Bool

    init(
        id: UUID = UUID(),
        layerID: UUID,
        name: String,
        transform: ItemTransform,
        content: DesignContent,
        threshold: Double = 0.52,
        invert: Bool = false
    ) {
        self.id = id
        self.layerID = layerID
        self.name = name
        self.transform = transform
        self.content = content
        self.threshold = threshold
        self.invert = invert
    }

    var effectiveThreshold: Double {
        if case .image(let image) = content {
            return image.threshold
        }
        return threshold
    }

    var effectiveInvert: Bool {
        if case .image(let image) = content {
            return image.invert
        }
        return invert
    }

    mutating func setThreshold(_ value: Double) {
        threshold = min(1, max(0, value))
        if case .image(var image) = content {
            image.threshold = threshold
            content = .image(image)
        }
    }

    mutating func setInvert(_ value: Bool) {
        invert = value
        if case .image(var image) = content {
            image.invert = value
            content = .image(image)
        }
    }

    func duplicated(offset: MMPoint) -> DesignItem {
        var copy = self
        copy.id = UUID()
        copy.transform.translate(dx: offset.x, dy: offset.y)
        return copy
    }
}
