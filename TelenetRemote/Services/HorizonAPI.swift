import Foundation

enum HorizonError: LocalizedError {
    case notLoggedIn
    case invalidToken
    case http(Int, String?)
    case missingService(String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .notLoggedIn: return "Je bent niet aangemeld."
        case .invalidToken: return "Je sessie is verlopen. Meld je opnieuw aan."
        case .http(let code, let msg): return "Serverfout \(code)\(msg.map { ": \($0)" } ?? "")"
        case .missingService(let s): return "Dienst '\(s)' niet gevonden in de configuratie."
        case .badResponse: return "Onverwacht antwoord van de server."
        }
    }
}

/// REST-client voor het Liberty Global "Horizon / Spark" platform dat Telenet gebruikt.
///
/// Flow:
/// 1. refresh token  -> access token + householdId (`/auth-service/v1/authorization/refresh`)
/// 2. backoffice.json -> URL's van alle diensten (o.a. mqttBroker)
/// 3. `/v1/mqtt/token` -> wachtwoord voor de MQTT-broker
/// 4. `/v1/customer/{householdId}` -> lijst met gekoppelde TV-boxen
actor HorizonAPI {
    static let baseURL = URL(string: "https://spark-prod-be.gnp.cloud.telenet.tv")!
    private static let refreshKey = "telenet.refreshToken"

    private let session: URLSession
    private let cookies: HTTPCookieStorage
    private var services: [String: String] = [:]

    private(set) var householdId: String?
    private var accessToken: String?
    private var accessTokenFetched: Date?

    init() {
        let config = URLSessionConfiguration.ephemeral
        cookies = config.httpCookieStorage ?? HTTPCookieStorage.shared
        config.httpCookieAcceptPolicy = .always
        config.timeoutIntervalForRequest = 20
        config.httpAdditionalHeaders = ["Accept": "application/json"]
        session = URLSession(configuration: config)
    }

    // MARK: - Refresh token opslag

    static var storedRefreshToken: String? {
        get { Keychain.get(refreshKey) }
        set { Keychain.set(newValue, for: refreshKey) }
    }

    // MARK: - Authenticatie

    @discardableResult
    func authenticate() async throws -> String {
        guard let refresh = Self.storedRefreshToken, !refresh.isEmpty else {
            throw HorizonError.notLoggedIn
        }
        var request = URLRequest(url: Self.baseURL.appending(path: "/auth-service/v1/authorization/refresh"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["refreshToken": refresh])

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let err = try? JSONDecoder().decode(AuthErrorResponse.self, from: data)
            if status == 401 || err?.error?.statusCode == 97401 || err?.error?.statusCode == 97402 {
                throw HorizonError.invalidToken
            }
            throw HorizonError.http(status, err?.error?.message)
        }
        let auth = try JSONDecoder().decode(AuthResponse.self, from: data)
        householdId = auth.householdId
        accessToken = auth.accessToken
        accessTokenFetched = Date()
        // Telenet roteert refresh tokens: altijd het nieuwe bewaren.
        Self.storedRefreshToken = auth.refreshToken
        return auth.householdId
    }

    private func ensureAuthenticated() async throws {
        // Access tokens zijn ±2 uur geldig; we vernieuwen ruim op tijd.
        if accessToken == nil || (accessTokenFetched.map { Date().timeIntervalSince($0) > 3600 } ?? true) {
            try await authenticate()
        }
    }

    // MARK: - Generieke GET

    private func get(_ url: URL, retry: Bool = true) async throws -> Any {
        try await ensureAuthenticated()
        injectAccessCookie(for: url)
        let request = URLRequest(url: url)
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 && retry {
            accessToken = nil
            return try await get(url, retry: false)
        }
        guard (200..<300).contains(status) else { throw HorizonError.http(status, nil) }
        return try JSONSerialization.jsonObject(with: data)
    }

    /// Het platform verwacht het access token als `ACCESSTOKEN` cookie. De auth-service
    /// zet die normaal zelf, maar voor andere hosts voegen we hem voor de zekerheid toe.
    private func injectAccessCookie(for url: URL) {
        guard let token = accessToken, let host = url.host else { return }
        let existing = cookies.cookies(for: url) ?? []
        if existing.contains(where: { $0.name == "ACCESSTOKEN" && $0.value == token }) { return }
        if let cookie = HTTPCookie(properties: [
            .name: "ACCESSTOKEN", .value: token, .domain: host, .path: "/", .secure: "TRUE",
        ]) {
            cookies.setCookie(cookie)
        }
    }

    // MARK: - Configuratie

    func serviceURL(_ name: String) async throws -> String {
        if services.isEmpty {
            let url = Self.baseURL.appending(path: "/be/en/config-service/conf/web/backoffice.json")
            guard let json = try await get(url) as? [String: Any] else { throw HorizonError.badResponse }
            for (key, value) in json {
                if let dict = value as? [String: Any], let u = dict["URL"] as? String {
                    services[key] = u
                }
            }
        }
        guard let url = services[name] else { throw HorizonError.missingService(name) }
        return url
    }

    func mqttBrokerURL() async throws -> URL {
        let raw = try await serviceURL("mqttBroker")
        guard let url = URL(string: raw) else { throw HorizonError.badResponse }
        return url
    }

    func mqttToken() async throws -> String {
        let base = try await serviceURL("authorizationService")
        guard let url = URL(string: base + "/v1/mqtt/token"),
              let json = try await get(url) as? [String: Any],
              let token = json["token"] as? String else { throw HorizonError.badResponse }
        return token
    }

    // MARK: - Klantgegevens

    struct CustomerInfo {
        var boxes: [SetTopBox]
        var cityId: Int?
        var language: String
    }

    func customer() async throws -> CustomerInfo {
        try await ensureAuthenticated()
        guard let hh = householdId else { throw HorizonError.notLoggedIn }
        let base = try await serviceURL("personalizationService")
        guard let url = URL(string: base + "/v1/customer/\(hh)?with=profiles%2Cdevices"),
              let json = try await get(url) as? [String: Any] else { throw HorizonError.badResponse }

        let devices = (json["assignedDevices"] as? [[String: Any]]) ?? []
        let boxes: [SetTopBox] = devices.compactMap { d in
            guard let id = d["deviceId"] as? String else { return nil }
            let settings = d["settings"] as? [String: Any]
            let name = (settings?["deviceFriendlyName"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? id
            return SetTopBox(id: id, name: name, platform: d["platformType"] as? String)
        }
        let profiles = (json["profiles"] as? [[String: Any]]) ?? []
        let lang = (profiles.first?["options"] as? [String: Any])?["lang"] as? String ?? "nl"
        return CustomerInfo(boxes: boxes, cityId: json["cityId"] as? Int, language: lang)
    }

    func channels(cityId: Int, language: String) async throws -> [Channel] {
        let base = try await serviceURL("linearService")
        guard let url = URL(string: base + "/v2/channels?cityId=\(cityId)&language=\(language)&productClass=Orion-DASH"),
              let list = try await get(url) as? [[String: Any]] else { throw HorizonError.badResponse }
        return list.compactMap { c in
            guard let id = c["id"] as? String, let name = c["name"] as? String else { return nil }
            let number = (c["logicalChannelNumber"] as? Int) ?? Int("\(c["logicalChannelNumber"] ?? "")") ?? 0
            let logo = ((c["logo"] as? [String: Any])?["focused"] as? String).flatMap(URL.init(string:))
            return Channel(id: id, number: number, name: name, logoURL: logo, isRadio: (c["isRadio"] as? Bool) ?? false)
        }
        .sorted { $0.number < $1.number }
    }

    func logout() {
        Self.storedRefreshToken = nil
        accessToken = nil
        householdId = nil
        services = [:]
        cookies.cookies?.forEach(cookies.deleteCookie)
    }
}
