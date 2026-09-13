import Foundation

enum TimeEstimator {
    struct Distances: Equatable {
        var burnMM: Double
        var cutMM: Double
        var travelMM: Double
        var dwellSeconds: Double
    }

    static func distances(in gcode: String) -> Distances {
        var x = 0.0
        var y = 0.0
        var laserOn = false
        var feed = 1000.0
        var burn = 0.0
        var cut = 0.0
        var travel = 0.0
        var dwell = 0.0
        var lastPower = 0.0

        for raw in gcode.split(whereSeparator: { $0.isNewline }) {
            let line = stripComment(String(raw)).trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            let upper = line.uppercased()

            if upper.hasPrefix("M5") {
                laserOn = false
                continue
            }
            if upper.hasPrefix("M3") || upper.hasPrefix("M4") {
                lastPower = parseWord(upper, "S") ?? lastPower
                laserOn = lastPower > 0
                continue
            }
            if let s = parseWord(upper, "S"), upper.contains("S") && !upper.hasPrefix("G") {
                lastPower = s
                laserOn = lastPower > 0
            }
            if let f = parseWord(upper, "F") {
                feed = f
            }
            if upper.hasPrefix("G4") {
                if let p = parseWord(upper, "P") {
                    dwell += p > 10 ? p / 1000 : p
                }
                continue
            }

            let isRapid = upper.hasPrefix("G0") || upper.hasPrefix("G00")
            let isLinear = upper.hasPrefix("G1") || upper.hasPrefix("G01")
            guard isRapid || isLinear else { continue }

            let nx = parseWord(upper, "X") ?? x
            let ny = parseWord(upper, "Y") ?? y
            let dist = hypot(nx - x, ny - y)
            x = nx
            y = ny

            if isRapid || !laserOn {
                travel += dist
            } else if feed < 700 {
                cut += dist
            } else {
                burn += dist
            }
        }

        return Distances(burnMM: burn, cutMM: cut, travelMM: travel, dwellSeconds: dwell)
    }

    static func estimateSeconds(
        distances: Distances,
        burnFeed: Double,
        cutFeed: Double,
        travelFeed: Double = 3000,
        overheadFactor: Double = 1.18
    ) -> Double {
        let burnT = distances.burnMM / max(60.0, burnFeed) * 60.0
        let cutT = distances.cutMM / max(60.0, cutFeed) * 60.0
        let travelT = distances.travelMM / max(120.0, travelFeed) * 60.0
        return (burnT + cutT + travelT + distances.dwellSeconds) * overheadFactor
    }

    static func estimateSeconds(gcode: String, burnFeed: Double, cutFeed: Double) -> Double {
        estimateSeconds(distances: distances(in: gcode), burnFeed: burnFeed, cutFeed: cutFeed)
    }

    static func formatDuration(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded()))
        let m = s / 60
        let r = s % 60
        if m >= 60 {
            let h = m / 60
            let mm = m % 60
            return String(format: "%d ч %02d мин", h, mm)
        }
        if m == 0 {
            return String(format: "%d с", r)
        }
        return String(format: "%d мин %02d с", m, r)
    }

    private static func stripComment(_ line: String) -> String {
        if let idx = line.firstIndex(of: ";") {
            return String(line[..<idx])
        }
        if let start = line.firstIndex(of: "("), let end = line.firstIndex(of: ")") {
            return String(line[..<start]) + String(line[line.index(after: end)...])
        }
        return line
    }

    /// Читает первое слово вроде X12.3 из строки.
    static func parseWord(_ line: String, _ letter: Character) -> Double? {
        let chars = Array(line.uppercased())
        let target = Character(letter.uppercased().first ?? letter)
        var i = 0
        while i < chars.count {
            if chars[i] == target {
                var j = i + 1
                if j < chars.count && (chars[j] == "+" || chars[j] == "-") { j += 1 }
                let start = j
                while j < chars.count && (chars[j].isNumber || chars[j] == ".") { j += 1 }
                if j > start {
                    return Double(String(chars[start..<j]))
                }
            }
            i += 1
        }
        return nil
    }
}
