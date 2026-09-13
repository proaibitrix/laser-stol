import Foundation
import Darwin

#if canImport(IOKit)
import IOKit
import IOKit.serial
#endif

/// Перечисление CU-портов через IOKit (без ORSSerialPort — меньше зависимости, Xcode 14.2).
enum SerialPortEnumerator {
    static func availablePorts() -> [SerialPortInfo] {
        var ports: [SerialPortInfo] = []
        #if canImport(IOKit)
        let matching = IOServiceMatching(kIOSerialBSDServiceValue) as NSMutableDictionary
        matching[kIOSerialBSDTypeKey] = kIOSerialBSDAllTypes

        var iterator: io_iterator_t = 0
        let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard kr == KERN_SUCCESS else { return fallbackPorts() }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            if let path = stringProperty(kIOCalloutDeviceKey, service: service)
                ?? stringProperty(kIODialinDeviceKey, service: service) {
                let name = stringProperty("USB Product Name", service: service)
                    ?? (path as NSString).lastPathComponent
                ports.append(SerialPortInfo(path: path, name: name))
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        #endif
        if ports.isEmpty {
            ports = fallbackPorts()
        }
        return ports.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    #if canImport(IOKit)
    private static func stringProperty(_ key: String, service: io_object_t) -> String? {
        let unmanaged = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)
        guard let value = unmanaged?.takeRetainedValue() as? String else { return nil }
        return value
    }
    #endif

    private static func fallbackPorts() -> [SerialPortInfo] {
        let fm = FileManager.default
        let dir = "/dev"
        guard let items = try? fm.contentsOfDirectory(atPath: dir) else { return [] }
        return items.compactMap { name in
            if name.hasPrefix("cu.") {
                return SerialPortInfo(path: "\(dir)/\(name)", name: name)
            }
            return nil
        }
    }
}

/// Простой POSIX-транспорт 115200 8N1, построчный GRBL.
final class SerialPortTransport: GRBLTransport {
    let kind: TransportKind = .serial
    private(set) var isConnected = false
    var displayName: String { port.path }

    var port: SerialPortInfo
    var baud: speed_t = speed_t(B115200)

    private var fd: Int32 = -1
    private let queue = DispatchQueue(label: "ru.proaibitrix.laserstol.serial")
    private var reader: DispatchSourceRead?
    private var lineBuffer = Data()
    private var pending: [(String, (Result<String, Error>) -> Void)] = []
    private var stream: StreamState?

    private struct StreamState {
        var lines: [String]
        var index: Int
        var paused: Bool
        var cancelled: Bool
        var waitingOK: Bool
        var onProgress: (Double, String) -> Void
        var completion: (Result<Void, Error>) -> Void
    }

    init(port: SerialPortInfo) {
        self.port = port
    }

    func connect(completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { [weak self] in
            guard let self = self else { return }
            do {
                try self.openPort()
                self.isConnected = true
                DispatchQueue.main.async { completion(.success(())) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    func disconnect() {
        queue.async { [weak self] in
            self?.closePort()
        }
    }

    func send(_ line: String, completion: @escaping (Result<String, Error>) -> Void) {
        queue.async { [weak self] in
            guard let self = self, self.isConnected else {
                DispatchQueue.main.async { completion(.failure(GRBLTransportError.notConnected)) }
                return
            }
            self.pending.append((line, completion))
            if self.pending.count == 1 {
                self.writeLine(line)
            }
        }
    }

    func sendRealtime(_ byte: UInt8) {
        queue.async { [weak self] in
            guard let self = self, self.fd >= 0 else { return }
            var b = byte
            _ = withUnsafePointer(to: &b) { ptr in
                Darwin.write(self.fd, ptr, 1)
            }
            if byte == 0x21 { self.stream?.paused = true }
            if byte == 0x7E {
                self.stream?.paused = false
                self.pumpStream()
            }
            if byte == 0x18 {
                self.stream?.cancelled = true
                if let stream = self.stream {
                    DispatchQueue.main.async { stream.completion(.failure(GRBLTransportError.cancelled)) }
                }
                self.stream = nil
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
            self.stream = StreamState(
                lines: lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty },
                index: 0,
                paused: false,
                cancelled: false,
                waitingOK: false,
                onProgress: onProgress,
                completion: completion
            )
            self.pumpStream()
        }
    }

    func pauseStreaming() { sendRealtimeHold() }
    func resumeStreaming() { sendRealtimeResume() }
    func stopStreaming() { sendRealtimeReset() }

    private func openPort() throws {
        closePort()
        let path = port.path
        let opened = path.withCString { Darwin.open($0, O_RDWR | O_NOCTTY | O_NONBLOCK) }
        guard opened >= 0 else {
            throw GRBLTransportError.openFailed(String(cString: strerror(errno)))
        }
        fd = opened

        var settings = termios()
        if tcgetattr(fd, &settings) != 0 {
            closePort()
            throw GRBLTransportError.openFailed("tcgetattr")
        }
        cfmakeraw(&settings)
        cfsetspeed(&settings, baud)
        settings.c_cflag |= tcflag_t(CLOCAL | CREAD | CS8)
        settings.c_cflag &= ~tcflag_t(PARENB | CSTOPB | CRTSCTS)
        settings.c_iflag &= ~tcflag_t(IXON | IXOFF | IXANY)
        withUnsafeMutableBytes(of: &settings.c_cc) { raw in
            let cc = raw.bindMemory(to: cc_t.self)
            if Int(VMIN) < cc.count { cc[Int(VMIN)] = 0 }
            if Int(VTIME) < cc.count { cc[Int(VTIME)] = 1 }
        }
        guard tcsetattr(fd, TCSANOW, &settings) == 0 else {
            closePort()
            throw GRBLTransportError.openFailed("tcsetattr")
        }
        _ = fcntl(fd, F_SETFL, 0)

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            self?.readAvailable()
        }
        source.resume()
        reader = source
    }

    private func closePort() {
        reader?.cancel()
        reader = nil
        if fd >= 0 {
            Darwin.close(fd)
            fd = -1
        }
        isConnected = false
        lineBuffer.removeAll()
        pending.removeAll()
        stream = nil
    }

    private func writeLine(_ line: String) {
        var payload = line
        if !payload.hasSuffix("\n") { payload.append("\n") }
        guard let data = payload.data(using: .utf8) else { return }
        data.withUnsafeBytes { raw in
            guard let ptr = raw.baseAddress else { return }
            _ = Darwin.write(self.fd, ptr, raw.count)
        }
    }

    private func readAvailable() {
        var chunk = [UInt8](repeating: 0, count: 1024)
        let n = Darwin.read(fd, &chunk, chunk.count)
        guard n > 0 else { return }
        lineBuffer.append(contentsOf: chunk.prefix(n))
        while let range = lineBuffer.range(of: Data([0x0A])) {
            let row = lineBuffer.subdata(in: lineBuffer.startIndex..<range.lowerBound)
            lineBuffer.removeSubrange(lineBuffer.startIndex..<range.upperBound)
            if let text = String(data: row, encoding: .utf8)
                ?? String(data: row, encoding: .ascii) {
                handleIncoming(text.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
    }

    private func handleIncoming(_ line: String) {
        if line.isEmpty { return }
        if line == "ok" || line.hasPrefix("error") {
            if !pending.isEmpty {
                let item = pending.removeFirst()
                DispatchQueue.main.async { item.1(.success(line)) }
                if let next = pending.first {
                    writeLine(next.0)
                }
            }
            if stream != nil {
                stream?.waitingOK = false
                pumpStream()
            }
        }
    }

    private func pumpStream() {
        guard var state = stream else { return }
        if state.cancelled { return }
        if state.paused || state.waitingOK { return }
        if state.index >= state.lines.count {
            stream = nil
            DispatchQueue.main.async { state.completion(.success(())) }
            return
        }
        let line = state.lines[state.index]
        state.index += 1
        state.waitingOK = true
        stream = state
        let progress = Double(state.index) / Double(max(state.lines.count, 1))
        let caption = MockGRBLTransport.caption(for: line)
        DispatchQueue.main.async { state.onProgress(progress, caption) }
        if line.hasPrefix(";") {
            state.waitingOK = false
            stream = state
            pumpStream()
            return
        }
        writeLine(line)
    }
}
