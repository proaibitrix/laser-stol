import Foundation

/// Заготовка библиотеки монограмм: несколько декоративных знаков и букв.
/// Позже сюда можно подставить настоящие SVG-контуры.
struct MonogramSymbol: Identifiable, Equatable {
    var id: String
    var title: String
    var letters: String
    /// Нормированный контур в квадрате 0…1 (ломаные). Пусто — рисуем глиф.
    var strokes: [[MMPoint]]
}

enum MonogramLibrary {
    static let all: [MonogramSymbol] = {
        var symbols: [MonogramSymbol] = [
            MonogramSymbol(
                id: "av-ligature",
                title: "AV",
                letters: "AV",
                strokes: ligatureAV()
            ),
            MonogramSymbol(
                id: "ampersand",
                title: "&",
                letters: "&",
                strokes: []
            )
        ]
        let alphabet = Array("АБВГДЕЖЗИКЛМНОПРСТУФХЧШЭЮЯABCDEFGHIJKLMNOPQRSTUVWXYZ")
        for ch in alphabet {
            symbols.append(
                MonogramSymbol(
                    id: "letter-\(ch)",
                    title: String(ch),
                    letters: String(ch),
                    strokes: []
                )
            )
        }
        return symbols
    }()

    static func symbol(id: String) -> MonogramSymbol? {
        all.first(where: { $0.id == id })
    }

    /// Декоративная связка AV в духе макета.
    private static func ligatureAV() -> [[MMPoint]] {
        let a: [MMPoint] = [
            MMPoint(x: 0.18, y: 0.18),
            MMPoint(x: 0.32, y: 0.82),
            MMPoint(x: 0.42, y: 0.82),
            MMPoint(x: 0.28, y: 0.18)
        ]
        let aCross: [MMPoint] = [
            MMPoint(x: 0.22, y: 0.42),
            MMPoint(x: 0.40, y: 0.42)
        ]
        let flourish: [MMPoint] = [
            MMPoint(x: 0.12, y: 0.22),
            MMPoint(x: 0.06, y: 0.12),
            MMPoint(x: 0.16, y: 0.08),
            MMPoint(x: 0.22, y: 0.16)
        ]
        let v: [MMPoint] = [
            MMPoint(x: 0.48, y: 0.80),
            MMPoint(x: 0.66, y: 0.18),
            MMPoint(x: 0.74, y: 0.18),
            MMPoint(x: 0.88, y: 0.80)
        ]
        let vFlourish: [MMPoint] = [
            MMPoint(x: 0.78, y: 0.22),
            MMPoint(x: 0.90, y: 0.10),
            MMPoint(x: 0.96, y: 0.20)
        ]
        return [a, aCross, flourish, v, vFlourish]
    }
}
