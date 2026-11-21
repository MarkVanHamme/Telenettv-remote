import SwiftUI

@main
struct TelenetRemoteApp: App {
    @StateObject private var remote = RemoteController()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(remote)
                .preferredColorScheme(.dark)
                .tint(.accentColor)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { remote.appBecameActive() }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var remote: RemoteController

    var body: some View {
        switch remote.phase {
        case .loggedOut, .error:
            LoginView()
        case .connecting(let message):
            VStack(spacing: 16) {
                ProgressView().controlSize(.large)
                Text(message).foregroundStyle(.secondary)
            }
        case .ready:
            if remote.boxes.isEmpty {
                ContentUnavailableView("Geen TV-box gevonden",
                                       systemImage: "tv.slash",
                                       description: Text("Er is geen Telenet TV-box gekoppeld aan dit account."))
            } else {
                RemoteView()
            }
        }
    }
}
