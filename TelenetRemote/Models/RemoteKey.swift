import Foundation

/// W3C-toetsnamen die de Horizon/EOS set-top box via `CPE.KeyEvent` begrijpt.
enum RemoteKey: String, CaseIterable {
    // Aan/uit
    case power = "Power"
    case standby = "Standby"
    case wakeUp = "WakeUp"

    // Afspelen
    case play = "MediaPlay"
    case pause = "MediaPause"
    case playPause = "MediaPlayPause"
    case stop = "MediaStop"
    case record = "MediaRecord"
    case fastForward = "MediaFastForward"
    case rewind = "MediaRewind"
    case next = "MediaTrackNext"
    case previous = "MediaTrackPrevious"

    // Kanalen / menu's
    case channelUp = "ChannelUp"
    case channelDown = "ChannelDown"
    case menu = "MediaTopMenu"
    case guide = "Guide"
    case help = "Help"
    case info = "Info"
    case contextMenu = "ContextMenu"
    case profile = "NextUserProfile"
    case tv = "TV"
    case teletext = "Teletext"
    case subtitle = "Subtitle"
    case audioTrack = "AudioTrack"

    // D-pad
    case up = "ArrowUp"
    case down = "ArrowDown"
    case left = "ArrowLeft"
    case right = "ArrowRight"
    case ok = "Enter"
    case back = "Escape"
    case backspace = "Backspace"

    // Kleurtoetsen
    case red = "Red"
    case green = "Green"
    case yellow = "Yellow"
    case blue = "Blue"

    // Cijfers
    case d0 = "0", d1 = "1", d2 = "2", d3 = "3", d4 = "4"
    case d5 = "5", d6 = "6", d7 = "7", d8 = "8", d9 = "9"

    static func digit(_ n: Int) -> RemoteKey {
        RemoteKey(rawValue: String(n)) ?? .d0
    }
}
