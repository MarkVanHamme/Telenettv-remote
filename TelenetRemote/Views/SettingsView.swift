import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var remote: RemoteController
    @Environment(\.dismiss) private var dismiss
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @State private var confirmLogout = false

    var body: some View {
        NavigationStack {
            Form {
                Section("TV-boxen") {
                    ForEach(remote.boxes) { box in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(box.name)
                                Text(box.modelDescription).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text((remote.powerStates[box.id] ?? .unknown).label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if box.id == remote.selectedBoxId {
                                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { remote.selectedBoxId = box.id }
                    }
                }

                Section("Bediening") {
                    Toggle("Trillen bij toetsdruk", isOn: $hapticsEnabled)
                    LabeledContent("Verbinding", value: remote.mqttConnected ? "Verbonden" : "Niet verbonden")
                    Button("Opnieuw verbinden") {
                        Task { await remote.start() }
                    }
                }

                Section {
                    Button("Afmelden", role: .destructive) { confirmLogout = true }
                } footer: {
                    Text("Deze app is niet officieel en niet verbonden aan Telenet. Ze gebruikt hetzelfde cloudplatform als de Telenet TV-app.")
                }
            }
            .navigationTitle("Instellingen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Klaar") { dismiss() } }
            }
            .confirmationDialog("Afmelden?", isPresented: $confirmLogout) {
                Button("Afmelden", role: .destructive) {
                    dismiss()
                    remote.logout()
                }
            }
        }
    }
}
