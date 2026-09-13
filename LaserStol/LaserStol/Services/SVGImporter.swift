import Foundation

/// Упрощённый импорт SVG: path / rect / circle / ellipse / polyline / polygon.
/// Достаточно для контуров и пиктограмм; фильтры и группы игнорируются.
enum SVGImporter {
    struct ImportedPath: Equatable {
        var points: [MMPoint]
        var closed: Bool
    }

    static func importPaths(data: Data) -> [ImportedPath] {
        let parser = Parser()
        let xml = XMLParser(data: data)
        xml.delegate = parser
        xml.parse()
        return parser.paths
    }

    static func importPaths(url: URL) -> [ImportedPath] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return importPaths(data: data)
    }

    private final class Parser: NSObject, XMLParserDelegate {
        var paths: [ImportedPath] = []

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes: [String: String] = [:]
        ) {
            let name = elementName.lowercased()
            switch name {
            case "rect":
                if let x = Double(attributes["x"] ?? "0"),
                   let y = Double(attributes["y"] ?? "0"),
                   let w = Double(attributes["width"] ?? ""),
                   let h = Double(attributes["height"] ?? "") {
                    let rect = MMRect(origin: MMPoint(x: x, y: y), size: MMSize(width: w, height: h))
                    paths.append(ImportedPath(points: GCodeGenerator.roundedRectPoints(rect, radius: 0), closed: true))
                }
            case "circle":
                if let cx = Double(attributes["cx"] ?? "0"),
                   let cy = Double(attributes["cy"] ?? "0"),
                   let r = Double(attributes["r"] ?? "") {
                    let rect = MMRect(
                        origin: MMPoint(x: cx - r, y: cy - r),
                        size: MMSize(width: r * 2, height: r * 2)
                    )
                    paths.append(ImportedPath(points: GCodeGenerator.ovalPoints(rect, segments: 48), closed: true))
                }
            case "ellipse":
                if let cx = Double(attributes["cx"] ?? "0"),
                   let cy = Double(attributes["cy"] ?? "0"),
                   let rx = Double(attributes["rx"] ?? ""),
                   let ry = Double(attributes["ry"] ?? "") {
                    let rect = MMRect(
                        origin: MMPoint(x: cx - rx, y: cy - ry),
                        size: MMSize(width: rx * 2, height: ry * 2)
                    )
                    paths.append(ImportedPath(points: GCodeGenerator.ovalPoints(rect, segments: 48), closed: true))
                }
            case "polyline":
                let pts = parsePoints(attributes["points"] ?? "")
                if pts.count >= 2 {
                    paths.append(ImportedPath(points: pts, closed: false))
                }
            case "polygon":
                let pts = parsePoints(attributes["points"] ?? "")
                if pts.count >= 2 {
                    paths.append(ImportedPath(points: pts, closed: true))
                }
            case "path":
                if let d = attributes["d"] {
                    paths.append(contentsOf: parsePath(d))
                }
            default:
                break
            }
        }
    }

    static func parsePoints(_ raw: String) -> [MMPoint] {
        let tokens = raw.replacingOccurrences(of: ",", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .compactMap { Double($0) }
        var pts: [MMPoint] = []
        var i = 0
        while i + 1 < tokens.count {
            pts.append(MMPoint(x: tokens[i], y: tokens[i + 1]))
            i += 2
        }
        return pts
    }

    /// Подмножество path: M/L/H/V/Z и кубические C как ломаная по конечной точке + 2 промежуточные.
    static func parsePath(_ d: String) -> [ImportedPath] {
        let commands = tokenizePath(d)
        var result: [ImportedPath] = []
        var current = MMPoint.zero
        var start = MMPoint.zero
        var pts: [MMPoint] = []

        func flush(closed: Bool) {
            if pts.count >= 2 {
                result.append(ImportedPath(points: pts, closed: closed))
            }
            pts = []
        }

        for cmd in commands {
            switch cmd.letter {
            case "M", "m":
                flush(closed: false)
                let abs = cmd.letter == "M"
                var i = 0
                while i + 1 < cmd.nums.count {
                    let p = point(cmd.nums[i], cmd.nums[i + 1], current, abs)
                    if i == 0 {
                        start = p
                        pts = [p]
                    } else {
                        pts.append(p)
                    }
                    current = p
                    i += 2
                }
            case "L", "l":
                let abs = cmd.letter == "L"
                var i = 0
                while i + 1 < cmd.nums.count {
                    let p = point(cmd.nums[i], cmd.nums[i + 1], current, abs)
                    pts.append(p)
                    current = p
                    i += 2
                }
            case "H", "h":
                let abs = cmd.letter == "H"
                for n in cmd.nums {
                    current = MMPoint(x: abs ? n : current.x + n, y: current.y)
                    pts.append(current)
                }
            case "V", "v":
                let abs = cmd.letter == "V"
                for n in cmd.nums {
                    current = MMPoint(x: current.x, y: abs ? n : current.y + n)
                    pts.append(current)
                }
            case "C", "c":
                let abs = cmd.letter == "C"
                var i = 0
                while i + 5 < cmd.nums.count {
                    let c1 = point(cmd.nums[i], cmd.nums[i + 1], current, abs)
                    let c2 = point(cmd.nums[i + 2], cmd.nums[i + 3], current, abs)
                    let p = point(cmd.nums[i + 4], cmd.nums[i + 5], current, abs)
                    pts.append(contentsOf: cubic(from: current, c1: c1, c2: c2, to: p, steps: 8))
                    current = p
                    i += 6
                }
            case "Z", "z":
                pts.append(start)
                current = start
                flush(closed: true)
            default:
                break
            }
        }
        flush(closed: false)
        return result
    }

    private static func point(_ x: Double, _ y: Double, _ current: MMPoint, _ abs: Bool) -> MMPoint {
        if abs { return MMPoint(x: x, y: y) }
        return MMPoint(x: current.x + x, y: current.y + y)
    }

    private static func cubic(from: MMPoint, c1: MMPoint, c2: MMPoint, to: MMPoint, steps: Int) -> [MMPoint] {
        (1...steps).map { i in
            let t = Double(i) / Double(steps)
            let u = 1 - t
            let x = u * u * u * from.x + 3 * u * u * t * c1.x + 3 * u * t * t * c2.x + t * t * t * to.x
            let y = u * u * u * from.y + 3 * u * u * t * c1.y + 3 * u * t * t * c2.y + t * t * t * to.y
            return MMPoint(x: x, y: y)
        }
    }

    private struct PathCommand {
        var letter: Character
        var nums: [Double]
    }

    private static func tokenizePath(_ d: String) -> [PathCommand] {
        var result: [PathCommand] = []
        var currentLetter: Character?
        var currentNums: [Double] = []
        var number = ""

        func flushNumber() {
            if !number.isEmpty, let v = Double(number) {
                currentNums.append(v)
            }
            number = ""
        }

        func flushCommand() {
            flushNumber()
            if let letter = currentLetter {
                result.append(PathCommand(letter: letter, nums: currentNums))
            }
            currentNums = []
        }

        for ch in d {
            if ch.isLetter {
                flushCommand()
                currentLetter = ch
            } else if ch == "-" && (number.isEmpty || number.last == "e" || number.last == "E") {
                number.append(ch)
            } else if ch == "-" || ch == "," || ch.isWhitespace {
                flushNumber()
                if ch == "-" { number = "-" }
            } else {
                number.append(ch)
            }
        }
        flushCommand()
        return result
    }
}
