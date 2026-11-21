import Foundation

/// Een Telenet TV-box gekoppeld aan het huishouden.
struct SetTopBox: Identifiable, Hashable {
    let id: String            // deviceId, bv. "3C36E4-EOSSTB-00xxxxxxxxxx"
    let name: String
    let platform: String?

    var modelDescription: String {
        switch platform {
        case "EOS", "HORIZON": return "Arris DCX960"
        case "EOS2": return "Humax 2008C"
        case "APOLLO": return "Arris VIP5002W"
        default: return platform ?? "TV-box"
        }
    }
}

enum BoxPowerState: String {
    case running = "ONLINE_RUNNING"
    case standby = "ONLINE_STANDBY"
    case offline = "OFFLINE_NETWORK_STANDBY"
    case unknown

    var label: String {
        switch self {
        case .running: return "Aan"
        case .standby: return "Stand-by"
        case .offline: return "Offline"
        case .unknown: return "Onbekend"
        }
    }
}

struct Channel: Identifiable, Hashable {
    let id: String
    let number: Int
    let name: String
    let logoURL: URL?
    let isRadio: Bool
}

/// Wat er momenteel op de box speelt (afgeleid uit `CPE.uiStatus`).
struct NowPlaying: Equatable {
    var uiStatus: String?
    var sourceType: String?
    var channelId: String?
    var appName: String?
}

/// Antwoord van `/auth-service/v1/authorization(/refresh)`.
struct AuthResponse: Decodable {
    let householdId: String
    let accessToken: String
    let refreshToken: String
    let refreshTokenExpiry: Int?
    let username: String?
}

struct AuthErrorResponse: Decodable {
    struct Inner: Decodable {
        let statusCode: Int?
        let message: String?
    }
    let error: Inner?
}
