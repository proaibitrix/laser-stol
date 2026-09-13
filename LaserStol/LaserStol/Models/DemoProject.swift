import Foundation

enum DemoProject {
    /// Стартовый лист в духе макета: сетка букв на 400×400 мм.
    static func make() -> ProjectDocument {
        var doc = ProjectDocument()
        doc.ensureDefaultLayers()
        guard let burn = doc.layer(kind: .burn), let cut = doc.layer(kind: .cut) else { return doc }

        let letters = [
            "A", "M", "K", "R", "D",
            "V", "Y", "S", "Q", "L",
            "V", "R", "E", "N", "R",
            "B", "B", "E", "S", "T",
            "N", "P", "G", "T", "H"
        ]
        let columns = 5
        let rows = 5
        let cell: Double = 48
        let gap: Double = 10
        let total = TileGridMath.totalSize(
            columns: columns,
            rows: rows,
            itemWidth: cell,
            itemHeight: cell,
            gapMM: gap
        )
        let originX = (doc.bedWidthMM - total.width) / 2 + cell / 2
        let originY = (doc.bedHeightMM - total.height) / 2 + cell / 2

        for (index, letter) in letters.enumerated() {
            let col = index % columns
            let row = index / columns
            let cx = originX + Double(col) * (cell + gap)
            let cy = originY + Double(row) * (cell + gap)
            let burnItem = DesignItem(
                layerID: burn.id,
                name: letter,
                transform: ItemTransform(centerX: cx, centerY: cy, width: 28, height: 28),
                content: .text(TextPayload(text: letter, fontName: "Times New Roman", fontSizePT: 64)),
                threshold: 0.6
            )
            let cutItem = DesignItem(
                layerID: cut.id,
                name: "Контур \(letter)",
                transform: ItemTransform(centerX: cx, centerY: cy, width: cell, height: cell),
                content: .shape(ShapePayload(kind: .rectangle, cornerRadiusMM: 5, hangHole: false))
            )
            doc.upsert(burnItem)
            doc.upsert(cutItem)
        }
        return doc
    }
}
