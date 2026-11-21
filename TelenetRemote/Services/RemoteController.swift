import Foundation
import SwiftUI
import UIKit

/// Centrale app-state: aanmelden, MQTT-verbinding, boxen en het versturen van toetsen.
@MainActor
final class RemoteController: ObservableObject {
    enum Phase: Equatable {
        case loggedOut
        case connecting(String)
        case ready
        case error(String)
    }

    @Published var phase: Phase = .loggedOut
    @Published var boxes: [SetTopBox] = []
    @Published var selectedBoxId: String? {
        didSet {
            UserDefaults.standard.set(selectedBoxId, forKey: "selectedBoxId")
            if let id = selectedBoxId { requestUiStatus(id) }
        }
    }
    @Published var powerStates: [String: BoxPowerState] = [:]
    @Published var nowPlaying: [String: NowPlaying] = [:]
    @Published var channels: [Channel] = []
    @Published var mqttConnected = false

    @AppStorage("hapticsEnabled") var hapticsEnabled = true

    private let api = HorizonAPI()
    private var mqtt: MQTTClient?
    private var householdId = ""
    private var reconnectAttempts = 0
    private var reconnectTask: Task<Void, Never>?

    var selectedBox: SetTopBox? { boxes.first { $0.id == selectedBoxId } }
    var selectedPowerState: BoxPowerState { selectedBoxId.flatMap { powerStates[$0] } ?? .unknown }

    var currentChannel: Channel? {
        guard let id = selectedBoxId, let channelId = nowPlaying[id]?.channelId else { return nil }
        return channels.first { $0.id == channelId }
    }

    init() {
        if HorizonAPI.storedRefreshToken != nil {
            Task { await start() }
        }
    }

    // MARK: - Aanmelden

    func login(refreshToken: String) async {
        HorizonAPI.storedRefreshToken = refreshToken.trimmingCharacters(in: .whitespacesAndNewlines)
        await start()
    }

    func logout() {
        reconnectTask?.cancel()
        mqtt?.disconnect()
        mqtt = nil
        Task { await api.logout() }
        boxes = []
        channels = []
        powerStates = [:]
        nowPlaying = [:]
        mqttConnected = false
        phase = .loggedOut
    }

    func start() async {
        phase = .connecting("Aanmelden bij Telenet…")
        do {
            householdId = try await api.authenticate()

            phase = .connecting("TV-boxen ophalen…")
            let customer = try await api.customer()
            boxes = customer.boxes
            let saved = UserDefaults.standard.string(forKey: "selectedBoxId")
            selectedBoxId = boxes.first(where: { $0.id == saved })?.id ?? boxes.first?.id

            phase = .connecting("Verbinden met je TV-box…")
            try await connectMQTT()
            phase = .ready

            if let city = customer.cityId {
                channels = (try? await api.channels(cityId: city, language: customer.language)) ?? []
            }
        } catch HorizonError.invalidToken, HorizonError.notLoggedIn {
            HorizonAPI.storedRefreshToken = nil
            phase = .error("Je Telenet-sessie is verlopen of ongeldig. Meld je opnieuw aan.")
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    // MARK: - MQTT

    private func connectMQTT() async throws {
        let url = try await api.mqttBrokerURL()
        let token = try await api.mqttToken()

        mqtt?.disconnect()
        let client = MQTTClient(url: url, clientId: MQTTClient.randomClientId(),
                                username: householdId, password: token)
        client.onStateChange = { [weak self, weak client] state in
            guard let self, let client, client === self.mqtt else { return }
            self.mqttStateChanged(state)
        }
        client.onMessage = { [weak self, weak client] topic, payload in
            guard let self, let client, client === self.mqtt else { return }
            self.handleMessage(topic: topic, payload: payload)
        }
        mqtt = client
        client.connect()
    }

    private func mqttStateChanged(_ state: MQTTClient.State) {
        switch state {
        case .connected:
            mqttConnected = true
            reconnectAttempts = 0
            onMQTTConnected()
        case .failed, .disconnected:
            mqttConnected = false
            if case .failed = state, phase == .ready { scheduleReconnect() }
        case .connecting:
            break
        }
    }

    private func onMQTTConnected() {
        guard let mqtt else { return }
        let hh = householdId
        mqtt.subscribe([
            hh,
            "\(hh)/\(mqtt.clientId)",
            "\(hh)/+/status",
        ])
        // Meld deze app aan als "HGO"-client (zoals de Telenet TV-app dat doet).
        mqtt.publish("\(hh)/\(mqtt.clientId)/status", json: [
            "source": mqtt.clientId,
            "state": BoxPowerState.running.rawValue,
            "deviceType": "HGO",
        ])
        boxes.forEach { requestUiStatus($0.id) }
    }

    private func scheduleReconnect() {
        reconnectTask?.cancel()
        reconnectAttempts += 1
        let delay = min(pow(2.0, Double(reconnectAttempts)), 60)
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled else { return }
            try? await self.connectMQTT() // haalt telkens een vers MQTT-token op
        }
    }

    /// Opnieuw verbinden wanneer de app terug op de voorgrond komt.
    func appBecameActive() {
        guard phase == .ready, !mqttConnected else { return }
        reconnectAttempts = 0
        scheduleReconnect()
    }

    private func handleMessage(topic: String, payload: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else { return }

        if topic.hasSuffix("/status"), let source = json["source"] as? String,
           boxes.contains(where: { $0.id == source }) {
            let state = BoxPowerState(rawValue: (json["state"] as? String ?? "").uppercased()) ?? .unknown
            powerStates[source] = state
            if state == .running { requestUiStatus(source) }
            return
        }

        if json["type"] as? String == "CPE.uiStatus", let source = json["source"] as? String {
            let status = json["status"] as? [String: Any] ?? [:]
            let player = status["playerState"] as? [String: Any]
            let apps = status["appsState"] as? [String: Any]
            nowPlaying[source] = NowPlaying(
                uiStatus: status["uiStatus"] as? String,
                sourceType: player?["sourceType"] as? String,
                channelId: (player?["source"] as? [String: Any])?["channelId"] as? String,
                appName: apps?["appName"] as? String
            )
        }
    }

    private func requestUiStatus(_ boxId: String) {
        guard let mqtt, mqttConnected else { return }
        mqtt.publish("\(householdId)/\(boxId)", json: [
            "id": MQTTClient.randomClientId(length: 8),
            "type": "CPE.getUiStatus",
            "source": mqtt.clientId,
        ])
    }

    // MARK: - Commando's

    func send(_ key: RemoteKey) {
        haptic(key == .power ? .heavy : .light)
        guard let mqtt, let box = selectedBoxId else { return }
        mqtt.publish("\(householdId)/\(box)", json: [
            "type": "CPE.KeyEvent",
            "runtimeType": "key",
            "id": MQTTClient.randomClientId(length: 8),
            "source": box.lowercased(),
            "status": ["w3cKey": key.rawValue, "eventType": "keyDownUp"],
        ])
    }

    /// Tik een kanaalnummer in (bv. "12" -> toetsen 1, 2).
    func sendDigits(_ number: String) {
        Task {
            for ch in number {
                guard let n = ch.wholeNumberValue else { continue }
                send(.digit(n))
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    /// Rechtstreeks naar een kanaal schakelen (zoals "Bekijk op TV" in de Telenet-app).
    func tune(to channel: Channel) {
        haptic(.medium)
        guard let mqtt, let box = selectedBoxId else { return }
        mqtt.publish("\(householdId)/\(box)", json: [
            "id": MQTTClient.randomClientId(length: 8),
            "type": "CPE.pushToTV",
            "source": ["clientId": mqtt.clientId, "friendlyDeviceName": "iPhone"],
            "status": [
                "sourceType": "linear",
                "source": ["channelId": channel.id],
                "relativePosition": 0,
                "speed": 1,
            ],
        ])
    }

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard hapticsEnabled else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}
