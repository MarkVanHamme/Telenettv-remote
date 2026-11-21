import SwiftUI

struct RemoteView: View {
    @EnvironmentObject var remote: RemoteController
    @AppStorage("useTouchpad") private var useTouchpad = false
    @State private var showNumbers = false
    @State private var showChannels = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    statusCard

                    // Bovenste rij: aan/uit, terug, menu
                    HStack {
                        RemoteButton(key: .power, symbol: "power", tint: .red.opacity(0.85), foreground: .white)
                        Spacer()
                        RemoteButton(key: .back, symbol: "arrow.uturn.backward", title: "Terug")
                        Spacer()
                        RemoteButton(key: .menu, symbol: "house.fill", title: "Menu")
                        Spacer()
                        RemoteButton(key: .guide, symbol: "list.bullet.rectangle", title: "Gids")
                    }

                    Picker("Navigatie", selection: $useTouchpad) {
                        Text("Knoppen").tag(false)
                        Text("Touchpad").tag(true)
                    }
                    .pickerStyle(.segmented)

                    if useTouchpad {
                        TouchpadView()
                    } else {
                        DPadView()
                    }

                    // Info / context / tv
                    HStack {
                        RemoteButton(key: .info, symbol: "info", title: "Info", size: 52)
                        Spacer()
                        RemoteButton(key: .contextMenu, symbol: "ellipsis", title: "Opties", size: 52)
                        Spacer()
                        RemoteButton(key: .tv, symbol: "tv", title: "TV", size: 52)
                        Spacer()
                        RemoteButton(key: .subtitle, symbol: "captions.bubble", title: "Ondertitels", size: 52)
                    }

                    // Kanaal-wip + snelkoppelingen
                    HStack(alignment: .center) {
                        RockerView(label: "CH", upKey: .channelUp, downKey: .channelDown)
                        Spacer()
                        VStack(spacing: 14) {
                            bigAction("Cijfers", "circle.grid.3x3.fill") { showNumbers = true }
                            bigAction("Zenders", "list.number") { showChannels = true }
                        }
                    }

                    // Afspeelbediening
                    VStack(spacing: 14) {
                        HStack {
                            RemoteButton(key: .rewind, symbol: "backward.fill", size: 54)
                            Spacer()
                            RemoteButton(key: .playPause, symbol: "playpause.fill", size: 64,
                                         tint: .accentColor, foreground: .black)
                            Spacer()
                            RemoteButton(key: .fastForward, symbol: "forward.fill", size: 54)
                        }
                        HStack {
                            RemoteButton(key: .stop, symbol: "stop.fill", size: 46)
                            Spacer()
                            RemoteButton(key: .record, symbol: "record.circle", size: 46, foreground: .red)
                            Spacer()
                            RemoteButton(key: .previous, symbol: "backward.end.fill", size: 46)
                            Spacer()
                            RemoteButton(key: .next, symbol: "forward.end.fill", size: 46)
                        }
                    }

                    ColorKeysView()
                        .padding(.bottom, 12)
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { boxPicker }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
            }
            .sheet(isPresented: $showNumbers) {
                NumberPadView().presentationDetents([.medium])
            }
            .sheet(isPresented: $showChannels) {
                ChannelListView()
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
    }

    private var boxPicker: some View {
        Menu {
            ForEach(remote.boxes) { box in
                Button {
                    remote.selectedBoxId = box.id
                } label: {
                    if box.id == remote.selectedBoxId {
                        Label(box.name, systemImage: "checkmark")
                    } else {
                        Text(box.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(remote.selectedBox?.name ?? "Geen TV-box")
                    .font(.headline)
                    .foregroundStyle(.primary)
                if remote.boxes.count > 1 {
                    Image(systemName: "chevron.down").font(.caption.bold())
                }
            }
        }
    }

    private var statusColor: Color {
        guard remote.mqttConnected else { return .gray }
        switch remote.selectedPowerState {
        case .running: return .green
        case .standby: return .orange
        case .offline: return .red
        case .unknown: return .yellow
        }
    }

    @ViewBuilder
    private var statusCard: some View {
        HStack(spacing: 14) {
            if let channel = remote.currentChannel, let logo = channel.logoURL {
                AsyncImage(url: logo) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Color.clear
                }
                .frame(width: 56, height: 36)
            } else {
                Image(systemName: "tv")
                    .font(.title2)
                    .frame(width: 56, height: 36)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(nowPlayingTitle).font(.subheadline.bold()).lineLimit(1)
                Text(nowPlayingSubtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
        }
        .padding(12)
        .background(Color(.secondarySystemBackground).opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
    }

    private var nowPlayingTitle: String {
        if !remote.mqttConnected { return "Verbinden…" }
        if remote.selectedPowerState == .standby { return "TV-box staat in stand-by" }
        if remote.selectedPowerState == .offline { return "TV-box is offline" }
        if let channel = remote.currentChannel { return "\(channel.number). \(channel.name)" }
        if let id = remote.selectedBoxId, let app = remote.nowPlaying[id]?.appName { return app }
        return remote.selectedBox?.name ?? "Telenet TV-box"
    }

    private var nowPlayingSubtitle: String {
        guard let box = remote.selectedBox else { return "" }
        return "\(box.modelDescription) · \(remote.selectedPowerState.label)"
    }

    private func bigAction(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .frame(width: 170, height: 54)
                .foregroundStyle(.primary)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(PressableStyle())
    }
}
