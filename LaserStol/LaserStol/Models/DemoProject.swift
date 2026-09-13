import Foundation

enum DemoProject {
    /// Одна маленькая буква в углу — подсказка, а не заготовка листа.
    static func make() -> ProjectDocument {
        var doc = ProjectDocument()
        doc.ensureDefaultLayers()
        guard let burn = doc.layer(kind: .burn) else { return doc }

        let letter = "A"
        let size: Double = 22
        let inset: Double = 18
        let cx = inset + size / 2
        let cy = inset + size / 2

        doc.upsert(DesignItem(
            layerID: burn.id,
            name: letter,
            transform: ItemTransform(centerX: cx, centerY: cy, width: size, height: size),
            content: .text(TextPayload(text: letter, fontName: "Times New Roman", fontSizePT: 48)),
            threshold: 0.6
        ))
        return doc
    }

    /// Старый стартовый лист: сетка 5×5 букв + контуры. Такие автосохранения
    /// при открытии заменяем на одну подсказку, чтобы стол не был занят.
    static func looksLikeLegacyLetterGrid(_ document: ProjectDocument) -> Bool {
        let texts = document.items.compactMap { item -> String? in
            if case .text(let payload) = item.content { return payload.text }
            return nil
        }
        let cutHints = document.items.filter { item in
            if case .shape = item.content { return item.name.hasPrefix("Контур ") }
            return false
        }
        return document.items.count == 50
            && texts.count == 25
            && cutHints.count == 25
            && texts.sorted() == legacyLetters.sorted()
    }

    private static let legacyLetters = [
        "A", "M", "K", "R", "D",
        "V", "Y", "S", "Q", "L",
        "V", "R", "E", "N", "R",
        "B", "B", "E", "S", "T",
        "N", "P", "G", "T", "H"
    ]
}
