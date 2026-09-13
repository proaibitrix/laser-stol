import Foundation
import Combine

enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case failed(String)

    var isReady: Bool {
        if case .connected = self { return true }
        return false
    }

    var title: String {
        switch self {
        case .disconnected: return "Не подключено"
        case .connecting: return "Подключение…"
        case .connected: return "Подключено"
        case .failed: return "Ошибка связи"
        }
    }
}

enum JobPhase: Equatable {
    case idle
    case preparing
    case running
    case paused
    case finished
    case demoFinished
    case failed(String)
    case cancelled
}

final class GRBLController: ObservableObject {
    @Published var connection: ConnectionState = .disconnected
    @Published var transportKind: TransportKind = .mock
    @Published var selectedPortPath: String = ""
    @Published var availablePorts: [SerialPortInfo] = []
    @Published var phase: JobPhase = .idle
    @Published var progress: Double = 0
    @Published var statusCaption: String = ""
    @Published var lastError: String?

    private var transport: GRBLTransport
    private let mock = MockGRBLTransport()
    private var pendingJob: GeneratedJob?

    init() {
        transport = mock
        refreshPorts()
    }

    var isConnected: Bool { transport.isConnected && connection.isReady }

    var isDemo: Bool { transport.kind == .mock }

    /// Подпись в UI: макет никогда не называется просто «Подключено».
    var connectionLabel: String {
        switch connection {
        case .connected:
            if transport.kind == .mock {
                return "Демо (Mock)"
            }
            let name = availablePorts.first(where: { $0.path == selectedPortPath })?.name
            if let name = name, !name.isEmpty {
                return "Станок · \(name)"
            }
            if !selectedPortPath.isEmpty {
                return "Станок · \((selectedPortPath as NSString).lastPathComponent)"
            }
            return "Станок подключён"
        default:
            return connection.title
        }
    }

    func refreshPorts() {
        availablePorts = SerialPortEnumerator.availablePorts()
        if selectedPortPath.isEmpty {
            selectedPortPath = availablePorts.first?.path ?? ""
        }
    }

    func connect(kind: TransportKind) {
        disconnect()
        transportKind = kind
        switch kind {
        case .mock:
            transport = mock
        case .serial:
            let info = availablePorts.first(where: { $0.path == selectedPortPath })
                ?? SerialPortInfo(path: selectedPortPath, name: selectedPortPath)
            transport = SerialPortTransport(port: info)
        }
        connection = .connecting
        transport.connect { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success:
                self.connection = .connected
                self.lastError = nil
                if let job = self.pendingJob {
                    self.pendingJob = nil
                    self.run(job: job)
                }
            case .failure(let error):
                self.connection = .failed(error.localizedDescription)
                self.lastError = error.localizedDescription
                self.pendingJob = nil
                self.phase = .failed(error.localizedDescription)
            }
        }
    }

    func disconnect() {
        transport.stopStreaming()
        transport.disconnect()
        connection = .disconnected
        phase = .idle
        progress = 0
    }

    func run(job: GeneratedJob) {
        guard connection.isReady else {
            pendingJob = job
            if case .connecting = connection { return }
            connect(kind: transportKind)
            return
        }
        let lines = job.gcode.components(separatedBy: CharacterSet.newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let motionCount = lines.filter { line in
            let u = line.uppercased()
            return u.hasPrefix("G0") || u.hasPrefix("G1") || u.hasPrefix("G00") || u.hasPrefix("G01")
        }.count
        guard motionCount > 0 else {
            lastError = GRBLTransportError.emptyStream.localizedDescription
            phase = .failed(lastError ?? "")
            statusCaption = lastError ?? ""
            return
        }
        let demo = transport.kind == .mock
        phase = .running
        progress = 0
        statusCaption = demo ? "Демо без станка: прогон G-code…" : "Запускаю задание…"
        transport.startStreaming(lines: lines, onProgress: { [weak self] value, caption in
            self?.progress = value
            if demo {
                self?.statusCaption = "Демо: \(caption)"
            } else {
                self?.statusCaption = caption
            }
            self?.phase = .running
        }, completion: { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success:
                self.progress = 1
                if demo {
                    self.phase = .demoFinished
                    self.statusCaption = "Демо без станка — лазер не двигался"
                } else {
                    self.phase = .finished
                    self.statusCaption = "Готово"
                }
            case .failure(let error):
                if case GRBLTransportError.cancelled = error {
                    self.phase = .cancelled
                    self.statusCaption = "Остановлено"
                } else {
                    self.phase = .failed(error.localizedDescription)
                    self.statusCaption = error.localizedDescription
                    self.lastError = error.localizedDescription
                }
            }
        })
    }

    func pause() {
        transport.pauseStreaming()
        phase = .paused
        statusCaption = "Пауза"
    }

    func resume() {
        transport.resumeStreaming()
        phase = .running
    }

    func stop() {
        transport.stopStreaming()
        phase = .cancelled
        statusCaption = "Остановлено"
    }
}
