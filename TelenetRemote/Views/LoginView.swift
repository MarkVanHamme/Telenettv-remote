import SwiftUI

struct LoginView: View {
    @EnvironmentObject var remote: RemoteController
    @State private var showWebLogin = false
    @State private var showManual = false
    @State private var manualToken = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer(minLength: 40)

                Image(systemName: "appletvremote.gen4.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(Color.accentColor)

                VStack(spacing: 8) {
                    Text("TV Remote")
                        .font(.largeTitle.bold())
                    Text("Bedien je Telenet TV-box vanaf je iPhone.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if case .error(let message) = remote.phase {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                }

                Button {
                    showWebLogin = true
                } label: {
                    Label("Aanmelden met Telenet", systemImage: "person.crop.circle")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .foregroundStyle(.black)

                DisclosureGroup(isExpanded: $showManual) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("""
                        Lukt aanmelden niet? Open telenet.tv op je computer, meld je aan, \
                        open de ontwikkelaarstools (Netwerk-tab) en zoek het verzoek \
                        "authorization/refresh". Kopieer de waarde van "refreshToken" uit het antwoord.
                        """)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                        TextField("refreshToken", text: $manualToken, axis: .vertical)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(.footnote, design: .monospaced))
                            .lineLimit(3...6)
                            .padding(10)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))

                        Button("Gebruik dit token") {
                            Task { await remote.login(refreshToken: manualToken) }
                        }
                        .buttonStyle(.bordered)
                        .disabled(manualToken.trimmingCharacters(in: .whitespacesAndNewlines).count < 20)
                    }
                    .padding(.top, 8)
                } label: {
                    Text("Token handmatig invoeren")
                        .font(.subheadline)
                }
                .tint(.secondary)

                Text("""
                Werkt met de Telenet TV-box (EOS/Horizon-platform). De app verbindt via \
                de Telenet-cloud, dus je iPhone hoeft niet op hetzelfde wifi-netwerk te zitten. \
                Je wachtwoord wordt nooit door de app bewaard — enkel een sessietoken in de Keychain.
                """)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            }
            .padding(24)
        }
        .sheet(isPresented: $showWebLogin) {
            NavigationStack {
                TelenetLoginWebView { token in
                    showWebLogin = false
                    Task { await remote.login(refreshToken: token) }
                }
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Telenet login")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annuleer") { showWebLogin = false }
                    }
                }
            }
        }
    }
}
