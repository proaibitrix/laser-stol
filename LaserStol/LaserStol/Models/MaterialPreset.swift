import Foundation

struct MaterialPreset: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var burnPowerPercent: Double
    var burnSpeedMMPerMin: Double
    var cutPowerPercent: Double
    var cutSpeedMMPerMin: Double
    var note: String

    static let builtIn: [MaterialPreset] = [
        MaterialPreset(
            id: "plywood-3",
            name: "Фанера 3 мм",
            burnPowerPercent: 40,
            burnSpeedMMPerMin: 1400,
            cutPowerPercent: 85,
            cutSpeedMMPerMin: 380,
            note: "Домашний диод, один проход реза"
        ),
        MaterialPreset(
            id: "plywood-5",
            name: "Фанера 5 мм",
            burnPowerPercent: 45,
            burnSpeedMMPerMin: 1200,
            cutPowerPercent: 100,
            cutSpeedMMPerMin: 220,
            note: "Возможно два прохода реза"
        ),
        MaterialPreset(
            id: "cardboard",
            name: "Картон",
            burnPowerPercent: 25,
            burnSpeedMMPerMin: 2000,
            cutPowerPercent: 55,
            cutSpeedMMPerMin: 700,
            note: "Низкая мощность, чтобы не поджечь"
        ),
        MaterialPreset(
            id: "paper",
            name: "Бумага",
            burnPowerPercent: 12,
            burnSpeedMMPerMin: 2800,
            cutPowerPercent: 28,
            cutSpeedMMPerMin: 1200,
            note: "Очень слабо и быстро"
        ),
        MaterialPreset(
            id: "leather",
            name: "Кожа",
            burnPowerPercent: 35,
            burnSpeedMMPerMin: 900,
            cutPowerPercent: 70,
            cutSpeedMMPerMin: 350,
            note: "Пахнет — проветривать"
        ),
        MaterialPreset(
            id: "acrylic",
            name: "Оргстекло",
            burnPowerPercent: 30,
            burnSpeedMMPerMin: 1100,
            cutPowerPercent: 90,
            cutSpeedMMPerMin: 180,
            note: "Диод режет тонкое; толстое — только гравировка"
        )
    ]

    static func preset(id: String) -> MaterialPreset {
        builtIn.first(where: { $0.id == id }) ?? builtIn[0]
    }
}

enum ProcessStrength: Int, Codable, CaseIterable, Identifiable {
    case weak = 0
    case medium = 1
    case strong = 2

    var id: Int { rawValue }

    var powerTitle: String {
        switch self {
        case .weak: return "Слабая"
        case .medium: return "Средняя"
        case .strong: return "Сильная"
        }
    }

    var speedTitle: String {
        switch self {
        case .weak: return "Низкая"
        case .medium: return "Средняя"
        case .strong: return "Сильная"
        }
    }

    /// Множитель мощности: слабая / средняя / сильная.
    var powerMultiplier: Double {
        switch self {
        case .weak: return 0.55
        case .medium: return 1.0
        case .strong: return 1.25
        }
    }

    /// Множитель скорости: «сильная» скорость — быстрее, слабее прожиг.
    var speedMultiplier: Double {
        switch self {
        case .weak: return 0.65
        case .medium: return 1.0
        case .strong: return 1.45
        }
    }
}

enum JobScope: String, Codable, Equatable {
    case burnLayer
    case cutLayer
    case wholeSheet
    case framePreview
}

struct JobSettings: Codable, Equatable {
    var power: ProcessStrength
    var speed: ProcessStrength
    var scope: JobScope
    var materialID: String

    init(
        power: ProcessStrength = .medium,
        speed: ProcessStrength = .medium,
        scope: JobScope = .wholeSheet,
        materialID: String = "plywood-3"
    ) {
        self.power = power
        self.speed = speed
        self.scope = scope
        self.materialID = materialID
    }
}
