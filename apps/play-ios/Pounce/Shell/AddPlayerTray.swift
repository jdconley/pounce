import PounceKit
import SwiftUI

/// The lobby's ways to fill the next free seat, right under the rug (first-run funnel, part 1):
/// the ways families play together. People in the same room on their own phones (the QR code),
/// family far away (the share sheet), someone sharing this phone (pass and play) and a House Cat.
/// Four round toy buttons on a tray, each with a word or two under it.
struct AddPlayerTray: View {
    enum Way: String, CaseIterable, Identifiable {
        case room, away, here, bot
        var id: String { rawValue }
    }

    /// Off on a kitten's device (spec §14.1): no links out, so no "Far away".
    let sharesLinks: Bool
    /// The QR code is up: "Same room" shows pressed.
    let scanning: Bool
    let wiggles: (LobbyWiggle) -> Int
    let onPick: (Way) -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var typeSize

    private var ways: [Way] { Way.allCases.filter { sharesLinks || $0 != .away } }

    var body: some View {
        let roomy = sizeClass == .regular
        let face: CGFloat = roomy ? 76 : 54
        VStack(spacing: 8) {
            Text("Add a player", comment: "Lobby: the heading over the ways to fill the next seat")
                .font(.system(roomy ? .callout : .footnote, design: .rounded, weight: .black))
                .foregroundStyle(.white.opacity(0.85))
                .textCase(.uppercase)
                .kerning(0.6)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .accessibilityAddTraits(.isHeader)
            HStack(alignment: .top, spacing: 4) {
                ForEach(ways) { way in
                    button(way, face: face)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Palette.ink.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(.white.opacity(0.18), lineWidth: 2)))
        .frame(maxWidth: roomy ? 520 : 380)
        .padding(.horizontal, 12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("lobby.add")
    }

    private func button(_ way: Way, face: CGFloat) -> some View {
        let on = way == .room && scanning
        return Button {
            onPick(way)
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(Self.color(way).mix(with: Palette.ink, by: 0.5))
                        .offset(y: 4)
                    Circle()
                        .fill(LinearGradient(
                            colors: [Self.color(way).mix(with: .white, by: 0.35), Self.color(way)],
                            startPoint: .top, endPoint: .bottom))
                        .overlay(Circle().strokeBorder(on ? .white : Palette.ink, lineWidth: 4))
                        .overlay {
                            Image(Self.icon(way))
                                .resizable()
                                .scaledToFit()
                                .padding(face * 0.2)
                                .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 2)
                        }
                        .offset(y: on ? 3 : 0)
                }
                .frame(width: face, height: face)
                .compositingGroup()
                .shadow(color: on ? Self.color(way).opacity(0.9) : .clear, radius: 10)
                Text(Self.label(way))
                    .font(.system(sizeClass == .regular ? .body : .caption, design: .rounded, weight: .black))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .fixedSize(horizontal: false, vertical: true)
                    .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            }
            .padding(.top, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .wiggle(trigger: wiggles(Self.wiggle(way)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(Self.label(way)))
        .accessibilityHint(Text(Self.hint(way)))
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier(Self.identifier(way))
        .tipTarget(way == .away ? "lobby.share" : nil)
    }

    static func color(_ way: Way) -> Color {
        switch way {
        case .room: Palette.teal
        case .away: Palette.magenta
        case .here: Palette.sky
        case .bot: Palette.orange
        }
    }

    static func icon(_ way: Way) -> String {
        switch way {
        case .room: ArtName.iconQr
        case .away: ArtName.iconShare
        case .here: ArtName.badgePhone
        case .bot: ArtName.badgeBot
        }
    }

    static func label(_ way: Way) -> String {
        switch way {
        case .room: String(localized: "Same room", comment: "Lobby tray: people here, each on their own phone (shows the QR code)")
        case .away: String(localized: "Far away", comment: "Lobby tray: send the table's link to family far away")
        case .here: String(localized: "This phone", comment: "Lobby tray: someone else plays on this phone (pass and play)")
        case .bot: String(localized: "House Cat", comment: "Lobby tray: the computer player takes the seat")
        }
    }

    static func hint(_ way: Way) -> String {
        switch way {
        case .room: String(localized: "Shows the QR code", comment: "VoiceOver hint: the lobby tray's Same room button")
        case .away: String(localized: "Sends the table's link", comment: "VoiceOver hint: the lobby tray's Far away button")
        case .here: String(localized: "Seats someone on this phone", comment: "VoiceOver hint: the lobby tray's This phone button")
        case .bot: String(localized: "Seats a House Cat", comment: "VoiceOver hint: the lobby tray's House Cat button")
        }
    }

    /// The old controls' identifiers live on: `lobby.qr` shows the QR code, `lobby.share` the
    /// share sheet.
    static func identifier(_ way: Way) -> String {
        switch way {
        case .room: "lobby.qr"
        case .away: "lobby.share"
        case .here: "lobby.here"
        case .bot: "lobby.bot"
        }
    }

    static func wiggle(_ way: Way) -> LobbyWiggle {
        switch way {
        case .room: .scan
        case .away: .share
        case .here: .here
        case .bot: .bot
        }
    }
}

/// The lobby controls that wiggle when the server refuses what they asked.
enum LobbyWiggle: Hashable {
    case seat(Int), start, share, add, scan, here, bot
}
