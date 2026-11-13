import PounceKit
import SwiftUI

/// Move my seat (spec §5.11), the sending phone: pick which seat if this phone holds several,
/// ask the server for a move code, then show its six tiles, a QR of the move link and a share
/// pill. When the other phone claims it the seat leaves this phone's snapshot and the sheet
/// closes (or goes home, if that was this phone's last seat).
struct MoveSeatSheet: View {
    @Environment(AppModel.self) private var model
    let session: RoomSession
    let onBack: () -> Void
    let onMovedAll: () -> Void
    let onClose: () -> Void

    @State private var seat: Seat?
    @State private var sharing = false
    @State private var nope = 0

    /// A code lives 10 minutes on the server; a fresh one is asked for just before.
    private static let codeLife: Duration = .seconds(9 * 60 + 50)

    private var store: RoomStore { session.store }
    private var mySeats: [Seat] { session.model?.mySeats ?? [] }

    private var mine: [(seat: Seat, person: Person)] {
        guard let room = store.room else { return [] }
        return mySeats.compactMap { seat in room.seats[safe: seat]?.person.map { (seat, $0) } }
    }

    /// The code for the chosen seat, once the server sent it.
    private var code: MoveCode? {
        guard let seat, let code = store.moveCode, code.seat == seat else { return nil }
        return code
    }

    private var person: Person? {
        seat.flatMap { seat in mine.first { $0.seat == seat }?.person }
    }

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                SheetBackButton { onBack() }
                    .accessibilityIdentifier("move.back")
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            Spacer(minLength: 0)
            if seat == nil {
                picker
            } else if let code {
                codeCard(code)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            } else {
                YarnIndicator()
                    .scaleEffect(1.6)
                    .accessibilityIdentifier("move.waiting")
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .shake(trigger: nope)
        .animation(.spring(duration: 0.45, bounce: 0.35).paced, value: code)
        .background(ShareRoom(
            isPresented: $sharing,
            url: code.map { DeepLink.moveURL(code: session.code, moveCode: $0.code) } ?? DeepLink.shareURL(code: session.code),
            tableName: session.store.room?.title ?? TableName.fallback(code: session.code),
            catArt: ArtName.cat(person?.cat ?? 0, .idle)))
        .onAppear {
            if seat == nil, mine.count == 1 { pick(mine[0].seat) }
        }
        .onChange(of: session.lobbyNope) {
            // The server refused (game over, say): shake, and let the person pick again.
            nope += 1
            seat = nil
            Haptics.shared.thump()
            Sound.shared.play(ArtName.Sound.sfxNope)
        }
        .onChange(of: mySeats) { _, seats in
            guard let seat, !seats.contains(seat) else { return }
            moved(remaining: seats)
        }
        .task(id: code?.code) {
            guard let code else { return }
            try? await Task.sleep(for: Self.codeLife)
            if !Task.isCancelled, self.code == code { pick(code.seat) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sheet-move-seat")
    }

    // MARK: pieces

    private var picker: some View {
        HStack(spacing: 18) {
            ForEach(mine, id: \.seat) { entry in
                Button {
                    Haptics.shared.tick()
                    Sound.shared.play(ArtName.Sound.sfxPop)
                    pick(entry.seat)
                } label: {
                    VStack(spacing: 4) {
                        Image(ArtName.cat(entry.person.cat, .idle))
                            .resizable()
                            .scaledToFit()
                            .frame(width: 92, height: 92)
                            .background(
                                Circle()
                                    .fill(Palette.violet)
                                    .overlay(Circle().strokeBorder(SeatInfo.ringColor(entry.seat), lineWidth: 6))
                                    .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 2.5).padding(-1))
                            )
                            .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 5)
                        OutlinedText(entry.person.name, size: 20, width: 2.5)
                            .lineLimit(1)
                    }
                    .frame(width: 110)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(
                    "Move \(entry.person.name)'s seat",
                    comment: "VoiceOver: pick which of this phone's seats moves to another phone"))
                .accessibilityIdentifier("move.seat.\(entry.seat)")
            }
        }
        .padding(.horizontal, 16)
    }

    private func codeCard(_ code: MoveCode) -> some View {
        let url = DeepLink.moveURL(code: session.code, moveCode: code.code)
        return VStack(spacing: 22) {
            if let person {
                HStack(spacing: 8) {
                    Image(ArtName.cat(person.cat, .awake))
                        .resizable().scaledToFit()
                        .frame(width: 56, height: 56)
                    OutlinedText(person.name, size: 26, width: 3)
                        .lineLimit(1)
                }
                .accessibilityHidden(true)
            }
            HStack(spacing: 6) {
                ForEach(Array(code.code.enumerated()), id: \.offset) { _, char in
                    CodeTile(char: char, active: false)
                }
            }
            .frame(maxWidth: 340)
            .accessibilityElement()
            .accessibilityLabel(Text(
                "Move code \(code.code.map(String.init).joined(separator: " "))",
                comment: "VoiceOver: the six-letter code that moves a seat to another phone"))
            .accessibilityIdentifier("move.code")
            QRTile(text: url.absoluteString, side: 190)
                .accessibilityLabel(Text(
                    "QR code to move the seat",
                    comment: "VoiceOver: scan with another phone to move this seat there"))
                .accessibilityAddTraits(.isImage)
                .accessibilityIdentifier("move.qr")
            if model.limits.sharesLinks {
                PillButton(icon: ArtName.iconShare, color: Palette.magenta, size: .medium, width: 160, accessibilityLabel: "Share the move link") {
                    sharing = true
                }
                .accessibilityIdentifier("move.share")
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: actions

    private func pick(_ seat: Seat) {
        self.seat = seat
        session.send(.moveSeat(seat: seat))
    }

    private func moved(remaining: [Seat]) {
        Haptics.shared.success()
        Sound.shared.play(ArtName.Sound.sfxSparkle)
        if remaining.isEmpty { onMovedAll() } else { onClose() }
    }
}

/// Move my seat, the receiving phone: the link's six tiles while `claimMove` is checked. A bad
/// code shakes the tiles and the cat droops; home from there. (Too many tries is a state card.)
struct MoveClaimView: View {
    let moveCode: String
    let refused: Bool
    let onHome: () -> Void

    @State private var shake = 0

    var body: some View {
        ZStack {
            RoomBackground()
            VStack(spacing: 30) {
                Image(ArtName.cat(3, refused ? .terrified : .awake))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 170, height: 170)
                    .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 6)
                    .accessibilityHidden(true)
                HStack(spacing: 6) {
                    ForEach(Array(moveCode.enumerated()), id: \.offset) { _, char in
                        CodeTile(char: char, active: false)
                    }
                }
                .frame(maxWidth: 340)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(LinearGradient(
                            colors: [Palette.violet.mix(with: Palette.ink, by: 0.25), Palette.night],
                            startPoint: .top, endPoint: .bottom))
                        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Palette.ink, lineWidth: 5))
                )
                .shake(trigger: shake)
                .accessibilityElement()
                .accessibilityLabel(refused
                    ? Text("That move code didn't work", comment: "VoiceOver: a move link's code was refused")
                    : Text("Moving a seat to this phone", comment: "VoiceOver: claiming a seat moved from another phone"))
                .accessibilityIdentifier("claim.code")
                if refused {
                    PillButton(icon: ArtName.iconHome, color: Palette.orange, size: .large, accessibilityLabel: "Home") {
                        onHome()
                    }
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityIdentifier("claim.home")
                } else {
                    YarnIndicator()
                }
            }
            .padding(.horizontal, 16)
        }
        .animation(.spring(duration: 0.4, bounce: 0.4).paced, value: refused)
        .overlay(alignment: .topLeading) {
            CornerHomeButton { onHome() }
                .padding(.leading, 16)
                .padding(.top, 4)
        }
        .onChange(of: refused, initial: true) { _, now in
            guard now else { return }
            shake += 1
            Haptics.shared.thump()
            Sound.shared.play(ArtName.Sound.sfxNope)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen-move-claim")
    }
}
