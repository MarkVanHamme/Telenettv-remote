import SwiftUI

struct ChannelListView: View {
    @EnvironmentObject var remote: RemoteController
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @AppStorage("favoriteChannels") private var favoritesRaw = ""

    private var favorites: Set<String> {
        Set(favoritesRaw.split(separator: ",").map(String.init))
    }

    private var filtered: [Channel] {
        let list = remote.channels.filter { !$0.isRadio }
        guard !search.isEmpty else { return list }
        return list.filter {
            $0.name.localizedCaseInsensitiveContains(search) || "\($0.number)".hasPrefix(search)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                let favs = filtered.filter { favorites.contains($0.id) }
                if !favs.isEmpty && search.isEmpty {
                    Section("Favorieten") {
                        ForEach(favs) { row($0) }
                    }
                }
                Section(search.isEmpty ? "Alle zenders" : "Resultaten") {
                    ForEach(filtered) { row($0) }
                }
            }
            .overlay {
                if remote.channels.isEmpty {
                    ContentUnavailableView("Geen zenders geladen",
                                           systemImage: "tv.slash",
                                           description: Text("Gebruik het cijferklavier om van zender te wisselen."))
                }
            }
            .searchable(text: $search, prompt: "Zoek zender of nummer")
            .navigationTitle("Zenders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Klaar") { dismiss() }
                }
            }
        }
    }

    private func row(_ channel: Channel) -> some View {
        Button {
            remote.tune(to: channel)
            dismiss()
        } label: {
            HStack(spacing: 14) {
                Text("\(channel.number)")
                    .font(.system(.body, design: .monospaced).bold())
                    .frame(width: 40, alignment: .trailing)
                    .foregroundStyle(.secondary)
                AsyncImage(url: channel.logoURL) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Color.clear
                }
                .frame(width: 48, height: 28)
                Text(channel.name).foregroundStyle(.primary)
                Spacer()
                if channel.id == remote.currentChannel?.id {
                    Image(systemName: "play.circle.fill").foregroundStyle(Color.accentColor)
                }
            }
        }
        .swipeActions {
            Button {
                toggleFavorite(channel)
            } label: {
                Label("Favoriet", systemImage: favorites.contains(channel.id) ? "star.slash" : "star")
            }
            .tint(.yellow)
        }
    }

    private func toggleFavorite(_ channel: Channel) {
        var set = favorites
        if set.contains(channel.id) { set.remove(channel.id) } else { set.insert(channel.id) }
        favoritesRaw = set.sorted().joined(separator: ",")
    }
}
