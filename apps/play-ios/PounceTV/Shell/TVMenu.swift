import PounceKit
import SwiftUI

/// The TV's menu at a table, made for the remote: three big buttons, and Menu to go back. "Link
/// another table" shows this TV's link while the table stays on: a phone that scans it moves the
/// TV to its own table. The web TV's `TvMenu`.
struct TVMenu: View {
    let model: TVModel
    @FocusState private var focus: Item?

    enum Item: Hashable {
        case link, sound, leave, back, playAGame, unlink
    }

    var body: some View {
        ZStack {
            Palette.ink.opacity(0.74)
                .ignoresSafeArea()
                .accessibilityHidden(true)
            switch model.menu {
            case .items where model.phase == .board: boardItems.transition(.scale(scale: 0.92).combined(with: .opacity))
            case .items: items.transition(.scale(scale: 0.92).combined(with: .opacity))
            case .link: link.transition(.scale(scale: 0.92).combined(with: .opacity))
            case .closed: EmptyView()
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: model.menu)
        // The paw that had the focus is gone under the menu: the remote starts on its first choice.
        .task(id: model.menu) {
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled else { return }
            focus = model.menu == .link ? .back : model.phase == .board ? .playAGame : .link
        }
    }

    /// The board's menu: Play a game (home, the board kept), sound, Unlink.
    private var boardItems: some View {
        VStack(spacing: 40) {
            Button {
                pop()
                model.playAGame()
            } label: {
                TVButtonLabel(icon: ArtName.iconDice, words: String(localized: "Play a game", comment: "TV menu on the board: go home to the games, keeping the board"))
            }
            .buttonStyle(TVButtonStyle(tint: Palette.violet))
            .accessibilityIdentifier("tv.menu.playAGame")
            .focused($focus, equals: .playAGame)

            soundButton

            Button {
                pop()
                model.unlink()
            } label: {
                TVButtonLabel(icon: ArtName.iconLeave, words: String(localized: "Unlink", comment: "TV menu on the board: stop showing this board and forget it"))
            }
            .buttonStyle(TVButtonStyle(tint: Palette.magenta))
            .accessibilityIdentifier("tv.menu.unlink")
            .focused($focus, equals: .unlink)
        }
        .frame(width: 780)
        .padding(56)
        .background(RoundedRectangle(cornerRadius: 56, style: .continuous).fill(Palette.night))
        .overlay(RoundedRectangle(cornerRadius: 56, style: .continuous).strokeBorder(Palette.ink, lineWidth: 8))
        .compositingGroup()
        .focusSection()
        .defaultFocus($focus, .playAGame)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Menu", comment: "TV: VoiceOver, the menu over a table"))
    }

    private var soundButton: some View {
        Button {
            model.toggleSound()
            // The press is heard only when turning sound on.
            pop()
        } label: {
            TVButtonLabel(
                icon: model.soundOn ? ArtName.iconSoundOn : ArtName.iconSoundOff,
                words: model.soundOn
                    ? String(localized: "Sound on", comment: "TV menu: the sound setting, now on")
                    : String(localized: "Sound off", comment: "TV menu: the sound setting, now off"))
        }
        .buttonStyle(TVButtonStyle(tint: Palette.teal))
        .accessibilityIdentifier("tv.menu.sound")
        .focused($focus, equals: .sound)
    }

    private var items: some View {
        VStack(spacing: 40) {
            Button {
                pop()
                model.showLink()
            } label: {
                TVButtonLabel(icon: ArtName.iconQr, words: String(localized: "Link another table", comment: "TV menu: show this TV's link so a phone can move it to its table"))
            }
            .buttonStyle(TVButtonStyle(tint: Palette.violet))
            .accessibilityIdentifier("tv.menu.link")
            .focused($focus, equals: .link)

            Button {
                model.toggleSound()
                // The press is heard only when turning sound on.
                pop()
            } label: {
                TVButtonLabel(
                    icon: model.soundOn ? ArtName.iconSoundOn : ArtName.iconSoundOff,
                    words: model.soundOn
                        ? String(localized: "Sound on", comment: "TV menu: the sound setting, now on")
                        : String(localized: "Sound off", comment: "TV menu: the sound setting, now off"))
            }
            .buttonStyle(TVButtonStyle(tint: Palette.teal))
            .accessibilityIdentifier("tv.menu.sound")
            .focused($focus, equals: .sound)

            Button {
                pop()
                model.leave()
            } label: {
                TVButtonLabel(icon: ArtName.iconLeave, words: String(localized: "Leave table", comment: "TV menu: stop showing this table and go home"))
            }
            .buttonStyle(TVButtonStyle(tint: Palette.magenta))
            .accessibilityIdentifier("tv.menu.leave")
            .focused($focus, equals: .leave)
        }
        .frame(width: 780)
        .padding(56)
        .background(RoundedRectangle(cornerRadius: 56, style: .continuous).fill(Palette.night))
        .overlay(RoundedRectangle(cornerRadius: 56, style: .continuous).strokeBorder(Palette.ink, lineWidth: 8))
        .compositingGroup()
        .focusSection()
        .defaultFocus($focus, .link)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Menu", comment: "TV: VoiceOver, the menu over a table"))
    }

    private var link: some View {
        HStack(spacing: 64) {
            TVQRCode(text: model.menuLink?.url.absoluteString, side: 380)
                .accessibilityLabel(Text("QR code to put a table on this TV", comment: "TV home: the link's QR, for VoiceOver"))
            VStack(spacing: 34) {
                OutlinedText(
                    String(localized: "Scan with your phone to put your table here", comment: "TV home: over the QR a phone scans to link its table"),
                    size: 50, width: 4, lines: 2)
                    .fixedSize(horizontal: false, vertical: true)
                TVCode(code: model.menuLink?.code, size: 84, label: String(localized: "Code", comment: "TV: VoiceOver, before a link's backup code is spelled out"))
                    .accessibilityIdentifier("tv.menu.code")
                if model.menuOffline { TVReconnecting() }
                Button {
                    pop()
                    model.back()
                } label: {
                    TVButtonLabel(icon: ArtName.iconBack, words: String(localized: "Back", comment: "TV menu: from the link back to the menu's choices"), size: 42)
                        .frame(width: 360)
                }
                .buttonStyle(TVButtonStyle(tint: Palette.violet))
                .accessibilityIdentifier("tv.menu.back")
                .focused($focus, equals: .back)
            }
            .frame(width: 640)
        }
        .padding(64)
        .background(RoundedRectangle(cornerRadius: 56, style: .continuous).fill(Palette.night))
        .overlay(RoundedRectangle(cornerRadius: 56, style: .continuous).strokeBorder(Palette.ink, lineWidth: 8))
        .compositingGroup()
        .focusSection()
        .defaultFocus($focus, .back)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Link another table", comment: "TV menu: show this TV's link so a phone can move it to its table"))
    }

    private func pop() {
        Sound.shared.play(ArtName.Sound.sfxPop, volume: 0.5)
    }
}
