import Foundation

enum TransportKind: String, Codable, CaseIterable, Identifiable {
    case mock
    case serial

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mock: return "Макет (Mock GRBL)"
        case .serial: return "Последовательный порт"
        }
    }
}

struct SerialPortInfo: Identifiable, Equatable {
    var id: String { path }
    var path: String
    var name: String
}

enum GRBLTransportError: Error, LocalizedError {
    case notConnected
    case openFailed(String)
    case timeout
    case cancelled

    var errorDescription: String? {
        switch self {
        case .notConnected: return "Станок не подключён"
        case .openFailed(let reason): return "Не удалось открыть порт: \(reason)"
        case .timeout: return "Нет ответа от GRBL"
        case .cancelled: return "Операция отменена"
        }
    }
}

protocol GRBLTransport: AnyObject {
    var kind: TransportKind { get }
    var isConnected: Bool { get }
    var displayName: String { get }

    func connect(completion: @escaping (Result<Void, Error>) -> Void)
    func disconnect()
    func send(_ line: String, completion: @escaping (Result<String, Error>) -> Void)
    func sendRealtime(_ byte: UInt8)
    func startStreaming(
        lines: [String],
        onProgress: @escaping (Double, String) -> Void,
        completion: @escaping (Result<Void, Error>) -> Void
    )
    func pauseStreaming()
    func resumeStreaming()
    func stopStreaming()
}

extension GRBLTransport {
    func sendRealtimeHold() { sendRealtime(0x21) } // !
    func sendRealtimeResume() { sendRealtime(0x7E) } // ~
    func sendRealtimeReset() { sendRealtime(0x18) } // Ctrl-X
}
