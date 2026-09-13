import Foundation

/// Имитация GRBL 1.1: приветствие, `ok` на каждую строку, пауза и стоп.
/// Достаточно, чтобы прогнать весь UI без железа.
final class MockGRBLTransport: GRBLTransport {
    let kind: TransportKind = .mock
    private(set) var isConnected = false
    var displayName: String = "Mock GRBL 1.1h"

    var secondsPerLine: TimeInterval = 0.003
    var greeting: String = "Grbl 1.1h ['$' for help]"

    private var queue = DispatchQueue(label: "ru.proaibitrix.laserstol.mock-grbl")
    private var job: StreamJob?

    private struct StreamJob {
        var lines: [String]
        var index: Int
        var paused: Bool
        var cancelled: Bool
        var onProgress: (Double, String) -> Void
        var completion: (Result<Void, Error>) -> Void
    }

    func connect(completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.isConnected = true
            DispatchQueue.main.async {
                completion(.success(()))
            }
        }
    }

    func disconnect() {
        queue.async { [weak self] in
            self?.isConnected = false
            self?.job?.cancelled = true
            self?.job = nil
        }
    }

    func send(_ line: String, completion: @escaping (Result<String, Error>) -> Void) {
        queue.async { [weak self] in
            guard let self = self, self.isConnected else {
                DispatchQueue.main.async { completion(.failure(GRBLTransportError.notConnected)) }
                return
            }
            let reply = self.reply(for: line)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                completion(.success(reply))
            }
        }
    }

    func sendRealtime(_ byte: UInt8) {
        queue.async { [weak self] in
            guard let self = self else { return }
            switch byte {
            case 0x21:
                self.job?.paused = true
            case 0x7E:
                self.job?.paused = false
                self.pump()
            case 0x18:
                self.job?.cancelled = true
                if let job = self.job {
                    DispatchQueue.main.async { job.completion(.failure(GRBLTransportError.cancelled)) }
                }
                self.job = nil
            default:
                break
            }
        }
    }

    func startStreaming(
        lines: [String],
        onProgress: @escaping (Double, String) -> Void,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        queue.async { [weak self] in
            guard let self = self, self.isConnected else {
                DispatchQueue.main.async { completion(.failure(GRBLTransportError.notConnected)) }
                return
            }
            self.job = StreamJob(
                lines: lines,
                index: 0,
                paused: false,
                cancelled: false,
                onProgress: onProgress,
                completion: completion
            )
            self.pump()
        }
    }

    func pauseStreaming() { sendRealtimeHold() }
    func resumeStreaming() { sendRealtimeResume() }
    func stopStreaming() { sendRealtimeReset() }

    private func pump() {
        guard var job = job, !job.cancelled else { return }
        if job.paused { return }
        if job.index >= job.lines.count {
            self.job = nil
            DispatchQueue.main.async { job.completion(.success(())) }
            return
        }
        let line = job.lines[job.index]
        job.index += 1
        self.job = job
        let progress = Double(job.index) / Double(max(job.lines.count, 1))
        let caption = Self.caption(for: line)
        DispatchQueue.main.async { job.onProgress(progress, caption) }

        let delay: TimeInterval
        if line.hasPrefix(";") || line.hasPrefix("G90") || line.hasPrefix("G21") || line.hasPrefix("G94") || line == "M5" {
            delay = 0.0003
        } else {
            delay = secondsPerLine
        }
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.pump()
        }
    }

    private func reply(for line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "ok" }
        if trimmed == "$I" { return "[VER:1.1h.20190825:Mock]\nok" }
        if trimmed == "?" { return "<Idle|MPos:0.000,0.000,0.000|FS:0,0>\nok" }
        if trimmed.hasPrefix("$") { return "ok" }
        return "ok"
    }

    static func caption(for line: String) -> String {
        let u = line.uppercased()
        if u.contains("; СЛОЙ РЕЗ") || (u.hasPrefix("G1") && u.contains("F") && (TimeEstimator.parseWord(u, "F") ?? 9999) < 700) {
            return "Вырезаю контур…"
        }
        if u.contains("; СЛОЙ ПРОЖИГ") || u.hasPrefix("M4") {
            return "Выжигаю рисунок…"
        }
        if u.hasPrefix("G0") {
            return "Переезд…"
        }
        if u.contains("FRAME") {
            return "Обводка рамки…"
        }
        return "Идёт работа…"
    }
}
