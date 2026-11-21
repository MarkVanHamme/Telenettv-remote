import Foundation

/// Minimale MQTT 3.1.1-client over WebSockets, zonder externe afhankelijkheden.
/// Ondersteunt wat een afstandsbediening nodig heeft: CONNECT, SUBSCRIBE,
/// PUBLISH (QoS 0 uitgaand, QoS 0/1/2 inkomend) en keep-alive pings.
final class MQTTClient: NSObject, URLSessionWebSocketDelegate {
    enum State: Equatable {
        case disconnected
        case connecting
        case connected
        case failed(String)
    }

    /// Callbacks worden altijd op de main thread aangeroepen.
    var onStateChange: (@MainActor (State) -> Void)?
    var onMessage: (@MainActor (_ topic: String, _ payload: Data) -> Void)?

    let clientId: String
    private let url: URL
    private let username: String
    private let password: String
    private let keepAlive: UInt16 = 30

    private let queue = DispatchQueue(label: "be.telenetremote.mqtt")
    private var session: URLSession!
    private var task: URLSessionWebSocketTask?
    private var buffer = Data()
    private var pingTimer: DispatchSourceTimer?
    private var nextPacketId: UInt16 = 1
    private var pendingSubscriptions: [String] = []
    private(set) var state: State = .disconnected {
        didSet {
            let s = state
            DispatchQueue.main.async { MainActor.assumeIsolated { self.onStateChange?(s) } }
        }
    }

    init(url: URL, clientId: String, username: String, password: String) {
        self.url = url
        self.clientId = clientId
        self.username = username
        self.password = password
        super.init()
        let delegateQueue = OperationQueue()
        delegateQueue.underlyingQueue = queue
        delegateQueue.maxConcurrentOperationCount = 1
        session = URLSession(configuration: .default, delegate: self, delegateQueue: delegateQueue)
    }

    static func randomClientId(length: Int = 10) -> String {
        let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
        return String((0..<length).map { _ in letters.randomElement()! })
    }

    // MARK: - Publieke API

    func connect() {
        queue.async { [self] in
            guard state != .connecting, state != .connected else { return }
            state = .connecting
            buffer.removeAll()
            let task = session.webSocketTask(with: url, protocols: ["mqtt"])
            task.maximumMessageSize = 4 * 1024 * 1024
            self.task = task
            task.resume()
            receive(on: task)
        }
    }

    func disconnect() {
        queue.async { [self] in
            if state == .connected { send(Data([0xE0, 0x00])) } // DISCONNECT
            teardown(.disconnected)
            session.finishTasksAndInvalidate() // geeft de delegate (self) vrij
        }
    }

    func subscribe(_ topics: [String]) {
        queue.async { [self] in
            guard state == .connected else {
                pendingSubscriptions.append(contentsOf: topics)
                return
            }
            var body = Data()
            body.append(uint16: packetId())
            for t in topics {
                body.append(mqttString: t)
                body.append(0x00) // QoS 0
            }
            send(packet(type: 0x82, body: body))
        }
    }

    func publish(_ topic: String, json: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: json) else { return }
        publish(topic, payload: data)
    }

    func publish(_ topic: String, payload: Data) {
        queue.async { [self] in
            guard state == .connected else { return }
            var body = Data()
            body.append(mqttString: topic)
            body.append(payload)
            send(packet(type: 0x30, body: body))
        }
    }

    // MARK: - WebSocket delegate

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        guard webSocketTask === task else { return }
        sendConnect()
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        guard webSocketTask === task else { return }
        teardown(.failed("Verbinding gesloten (\(closeCode.rawValue))"))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard task === self.task, let error else { return }
        teardown(.failed(error.localizedDescription))
    }

    // MARK: - Intern

    private func teardown(_ newState: State) {
        pingTimer?.cancel()
        pingTimer = nil
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        buffer.removeAll()
        if state != newState { state = newState }
    }

    private func receive(on task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self, task === self.task else { return }
            switch result {
            case .success(.data(let data)):
                self.buffer.append(data)
                self.processBuffer()
                self.receive(on: task)
            case .success(.string(let text)):
                self.buffer.append(Data(text.utf8))
                self.processBuffer()
                self.receive(on: task)
            case .success:
                self.receive(on: task)
            case .failure(let error):
                self.teardown(.failed(error.localizedDescription))
            }
        }
    }

    private func sendConnect() {
        var body = Data()
        body.append(mqttString: "MQTT")
        body.append(0x04)                 // protocol level 3.1.1
        body.append(0xC2)                 // username + password + clean session
        body.append(uint16: keepAlive)
        body.append(mqttString: clientId)
        body.append(mqttString: username)
        body.append(mqttString: password)
        send(packet(type: 0x10, body: body))
    }

    private func startPing() {
        pingTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        let interval = DispatchTimeInterval.seconds(Int(keepAlive) - 5)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in self?.send(Data([0xC0, 0x00])) }
        timer.resume()
        pingTimer = timer
    }

    private func packetId() -> UInt16 {
        defer { nextPacketId = nextPacketId == .max ? 1 : nextPacketId + 1 }
        return nextPacketId
    }

    private func packet(type: UInt8, body: Data) -> Data {
        var out = Data([type])
        var length = body.count
        repeat {
            var byte = UInt8(length % 128)
            length /= 128
            if length > 0 { byte |= 0x80 }
            out.append(byte)
        } while length > 0
        out.append(body)
        return out
    }

    private func send(_ data: Data) {
        task?.send(.data(data)) { [weak self] error in
            if let error { self?.queue.async { self?.teardown(.failed(error.localizedDescription)) } }
        }
    }

    /// Haalt volledige MQTT-pakketten uit de buffer (een WS-frame kan er meerdere of een deel bevatten).
    private func processBuffer() {
        while true {
            let bytes = [UInt8](buffer)
            guard bytes.count >= 2 else { return }
            var multiplier = 1, length = 0, index = 1
            var complete = false
            while index < bytes.count && index <= 4 {
                let b = Int(bytes[index])
                length += (b & 0x7F) * multiplier
                multiplier *= 128
                index += 1
                if b & 0x80 == 0 { complete = true; break }
            }
            guard complete, bytes.count >= index + length else { return }
            let header = bytes[0]
            let body = Array(bytes[index..<(index + length)])
            buffer.removeFirst(index + length)
            handle(header: header, body: body)
        }
    }

    private func handle(header: UInt8, body: [UInt8]) {
        switch header >> 4 {
        case 2: // CONNACK
            let code = body.count >= 2 ? body[1] : 0xFF
            if code == 0 {
                state = .connected
                startPing()
                if !pendingSubscriptions.isEmpty {
                    let topics = pendingSubscriptions
                    pendingSubscriptions.removeAll()
                    subscribe(topics)
                }
            } else {
                let reason = code == 4 || code == 5 ? "MQTT-token geweigerd" : "MQTT-fout \(code)"
                teardown(.failed(reason))
            }
        case 3: // PUBLISH
            let qos = (header >> 1) & 0x03
            guard body.count >= 2 else { return }
            let topicLen = Int(body[0]) << 8 | Int(body[1])
            var offset = 2 + topicLen
            guard body.count >= offset else { return }
            let topic = String(decoding: body[2..<offset], as: UTF8.self)
            if qos > 0 {
                guard body.count >= offset + 2 else { return }
                let pid = [body[offset], body[offset + 1]]
                offset += 2
                // QoS1 -> PUBACK, QoS2 -> PUBREC
                let ackType: UInt8 = qos == 1 ? 0x40 : 0x50
                send(Data([ackType, 0x02] + pid))
            }
            let payload = Data(body[offset...])
            DispatchQueue.main.async { MainActor.assumeIsolated { self.onMessage?(topic, payload) } }
        case 6: // PUBREL -> PUBCOMP
            if body.count >= 2 { send(Data([0x70, 0x02, body[0], body[1]])) }
        default:
            break // SUBACK, PINGRESP, ...
        }
    }
}

private extension Data {
    mutating func append(uint16 value: UInt16) {
        append(UInt8(value >> 8))
        append(UInt8(value & 0xFF))
    }

    mutating func append(mqttString string: String) {
        let utf8 = Data(string.utf8)
        append(uint16: UInt16(utf8.count))
        append(utf8)
    }
}
