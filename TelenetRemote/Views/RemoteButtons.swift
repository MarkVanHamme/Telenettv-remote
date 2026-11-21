import SwiftUI

/// Ronde knop met SF Symbol of tekst.
struct RemoteButton: View {
    @EnvironmentObject var remote: RemoteController
    let key: RemoteKey
    var symbol: String? = nil
    var title: String? = nil
    var size: CGFloat = 60
    var tint: Color = Color(.secondarySystemBackground)
    var foreground: Color = .primary

    var body: some View {
        Button { remote.send(key) } label: {
            Group {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: size * 0.36, weight: .semibold))
                } else {
                    Text(title ?? key.rawValue).font(.system(size: size * 0.3, weight: .semibold))
                }
            }
            .frame(width: size, height: size)
            .foregroundStyle(foreground)
            .background(tint, in: Circle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(title ?? key.rawValue)
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .brightness(configuration.isPressed ? 0.15 : 0)
            .animation(.spring(duration: 0.15), value: configuration.isPressed)
    }
}

/// Klassieke ronde navigatieknop met pijlen en OK in het midden.
struct DPadView: View {
    @EnvironmentObject var remote: RemoteController
    var diameter: CGFloat = 250

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(.secondarySystemBackground))
            arrow(.up, "chevron.up").offset(y: -diameter * 0.34)
            arrow(.down, "chevron.down").offset(y: diameter * 0.34)
            arrow(.left, "chevron.left").offset(x: -diameter * 0.34)
            arrow(.right, "chevron.right").offset(x: diameter * 0.34)

            Button { remote.send(.ok) } label: {
                Text("OK")
                    .font(.title2.bold())
                    .frame(width: diameter * 0.4, height: diameter * 0.4)
                    .foregroundStyle(.black)
                    .background(Color.accentColor, in: Circle())
            }
            .buttonStyle(PressableStyle())
        }
        .frame(width: diameter, height: diameter)
    }

    private func arrow(_ key: RemoteKey, _ symbol: String) -> some View {
        Button { remote.send(key) } label: {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .bold))
                .frame(width: diameter * 0.28, height: diameter * 0.28)
                .contentShape(Rectangle())
                .foregroundStyle(.primary)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(key.rawValue)
    }
}

/// Touchpad: veeg om te navigeren, tik voor OK.
struct TouchpadView: View {
    @EnvironmentObject var remote: RemoteController
    @State private var lastDirection: RemoteKey?

    var body: some View {
        RoundedRectangle(cornerRadius: 28)
            .fill(Color(.secondarySystemBackground))
            .overlay {
                VStack(spacing: 6) {
                    Image(systemName: "hand.draw")
                        .font(.largeTitle)
                    Text("Veeg om te navigeren · tik voor OK")
                        .font(.caption)
                }
                .foregroundStyle(.tertiary)
            }
            .overlay(alignment: .center) {
                if let lastDirection {
                    Image(systemName: icon(for: lastDirection))
                        .font(.system(size: 60, weight: .bold))
                        .foregroundStyle(Color.accentColor.opacity(0.6))
                        .transition(.opacity)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 25)
                    .onEnded { value in
                        let dx = value.translation.width, dy = value.translation.height
                        let key: RemoteKey = abs(dx) > abs(dy) ? (dx > 0 ? .right : .left) : (dy > 0 ? .down : .up)
                        remote.send(key)
                        flash(key)
                    }
            )
            .simultaneousGesture(TapGesture().onEnded { remote.send(.ok); flash(.ok) })
            .frame(height: 260)
    }

    private func flash(_ key: RemoteKey) {
        withAnimation { lastDirection = key }
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation { lastDirection = nil }
        }
    }

    private func icon(for key: RemoteKey) -> String {
        switch key {
        case .up: return "chevron.up"
        case .down: return "chevron.down"
        case .left: return "chevron.left"
        case .right: return "chevron.right"
        default: return "circle.fill"
        }
    }
}

/// Verticale wip voor kanaal +/-.
struct RockerView: View {
    @EnvironmentObject var remote: RemoteController
    let label: String
    let upKey: RemoteKey
    let downKey: RemoteKey

    var body: some View {
        VStack(spacing: 0) {
            Button { remote.send(upKey) } label: {
                Image(systemName: "plus").font(.title2.bold()).frame(width: 64, height: 64)
            }
            Text(label).font(.caption2.bold()).foregroundStyle(.secondary)
            Button { remote.send(downKey) } label: {
                Image(systemName: "minus").font(.title2.bold()).frame(width: 64, height: 64)
            }
        }
        .foregroundStyle(.primary)
        .buttonStyle(PressableStyle())
        .background(Color(.secondarySystemBackground), in: Capsule())
    }
}

struct ColorKeysView: View {
    @EnvironmentObject var remote: RemoteController

    var body: some View {
        HStack(spacing: 14) {
            key(.red, .red)
            key(.green, .green)
            key(.yellow, .yellow)
            key(.blue, .blue)
        }
    }

    private func key(_ key: RemoteKey, _ color: Color) -> some View {
        Button { remote.send(key) } label: {
            Capsule().fill(color).frame(height: 20)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(key.rawValue)
    }
}
