import PounceKit
import SwiftUI

/// Asks the server whether it would take a typed name, as the name is saved, so a refused one
/// gets a worded reason on the spot. The server checks every name again whatever this says, so
/// a slow or failed check lets the name through.
enum NameGate {
    static let patience: Duration = .seconds(3)

    static func verdict(_ api: any SafetyService, _ name: String, kind: NameKind) async -> NameVerdict {
        await withTaskGroup(of: NameVerdict.self) { group in
            group.addTask { (try? await api.checkName(name, kind: kind)) ?? .ok }
            group.addTask {
                try? await Task.sleep(for: patience)
                return .ok
            }
            let first = await group.next() ?? .ok
            group.cancelAll()
            return first
        }
    }

    /// The short reason shown under the field; nil when the name is fine.
    static func words(_ verdict: NameVerdict) -> String? {
        switch verdict {
        case .ok: nil
        case .badName: String(localized: "Name not allowed. Try another.", comment: "Under a name field: the server's name filter refused it")
        case .notAllowed: String(localized: "Ask a grown-up to change this.", comment: "Under a name field: a kitten can't type names")
        }
    }
}

/// The reason under a name field, in the editors that type names.
struct NameRefusal: View {
    let text: String
    var size: CGFloat = 16

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(Palette.refuse).overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 3)))
            .fixedSize(horizontal: false, vertical: true)
            .transition(.scale(scale: 0.8).combined(with: .opacity))
            .accessibilityIdentifier("name.refused")
    }
}

/// Report and Block on a player's card (App Store guideline 1.2), for a person on another phone.
/// Report asks why (three worded reasons, nothing typed) and tells the server, which records who
/// was reported, at which table and under what name. Block stops that player's pounces and
/// nudges reaching you and keeps them out of tables you start; the same button undoes it.
struct SafetyActions: View {
    let api: any SafetyService
    /// The table, and the person on the card.
    let code: String
    let person: Person
    /// The local person the block belongs to.
    let me: String?
    var scale: CGFloat = 1

    private enum Note: Equatable {
        case reported, blocked, unblocked, failed, tooMany

        var text: String {
            switch self {
            case .reported: String(localized: "Report sent.", comment: "Player card: after a report was sent")
            case .blocked: String(localized: "Blocked.", comment: "Player card: after blocking")
            case .unblocked: String(localized: "Unblocked.", comment: "Player card: after unblocking")
            case .failed: String(localized: "Didn't go through. Try again.", comment: "Player card: a report or block failed")
            case .tooMany: String(localized: "Too many. Try again later.", comment: "Player card: too many reports or blocks")
            }
        }
    }

    @State private var asking = false
    @State private var confirmingBlock = false
    @State private var busy = false
    @State private var reported = false
    /// The server's handle for this player once they're blocked (nil: not blocked).
    @State private var blockedID: String?
    @State private var note: Note?

    var body: some View {
        VStack(spacing: 10 * scale) {
            HStack(spacing: 12 * scale) {
                chip(
                    reported
                        ? String(localized: "Reported", comment: "Player card: this player was reported")
                        : String(localized: "Report", comment: "Player card: report this player"),
                    color: Palette.orange, dim: reported
                ) {
                    asking = true
                }
                .disabled(reported || busy)
                .accessibilityIdentifier("player.report")
                chip(
                    blockedID == nil
                        ? String(localized: "Block", comment: "Player card: block this player")
                        : String(localized: "Unblock", comment: "Player card: undo a block"),
                    color: blockedID == nil ? Palette.refuse : Palette.sky, dim: false
                ) {
                    if blockedID == nil { confirmingBlock = true } else { unblock() }
                }
                .disabled(busy)
                .accessibilityIdentifier("player.block")
            }
            if let note {
                Text(note.text)
                    .font(.system(size: 15 * scale, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
                    .accessibilityIdentifier("player.safetyNote")
            }
        }
        .padding(.top, 6 * scale)
        .animation(.easeOut(duration: 0.2).paced, value: note)
        .task { await load() }
        .confirmationDialog(
            String(localized: "Report \(person.name)?", comment: "Report picker title: whom"),
            isPresented: $asking, titleVisibility: .visible
        ) {
            Button(String(localized: "Rude name", comment: "Report reason")) { report(.name) }
                .accessibilityIdentifier("report.name")
            Button(String(localized: "Bothering me", comment: "Report reason: too many nudges or pounces")) { report(.bothering) }
                .accessibilityIdentifier("report.bothering")
            Button(String(localized: "Something else", comment: "Report reason")) { report(.other) }
                .accessibilityIdentifier("report.other")
            Button(String(localized: "Cancel", comment: "Report picker: never mind"), role: .cancel) {}
        } message: {
            Text("Tell us why.", comment: "Report picker: under the title")
        }
        .alert(
            String(localized: "Block \(person.name)?", comment: "Block confirmation title: whom"),
            isPresented: $confirmingBlock
        ) {
            Button(String(localized: "Block", comment: "Block confirmation: the destructive button"), role: .destructive) { block() }
                .accessibilityIdentifier("block.confirm")
            Button(String(localized: "Cancel", comment: "Block confirmation: never mind"), role: .cancel) {}
        } message: {
            Text(
                "They can't join your tables or send you nudges and pounces.",
                comment: "Block confirmation: what blocking does")
        }
    }

    private func chip(_ title: String, color: Color, dim: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.shared.tick()
            Sound.shared.play(ArtName.Sound.sfxTick)
            action()
        } label: {
            OutlinedText(title, size: 18 * scale, fill: .white, width: 3)
                .padding(.horizontal, 18 * scale)
                .frame(minWidth: 116 * scale, minHeight: 46 * scale)
                .background(Capsule().fill(color).overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 4)))
                .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 4)
                .saturation(dim ? 0.3 : 1)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: "\(title), \(person.name)"))
    }

    private func load() async {
        guard let list = try? await api.blocks(me: me) else { return }
        blockedID = list.first { $0.person.lowercased() == person.id.lowercased() }?.id
    }

    private func run(_ done: Note, _ work: @escaping () async throws -> Void) {
        guard !busy else { return }
        busy = true
        Task {
            do {
                try await work()
                note = done
                Haptics.shared.success()
                UIAccessibility.post(notification: .announcement, argument: done.text)
            } catch APIError.rateLimited {
                note = .tooMany
            } catch {
                note = .failed
            }
            busy = false
        }
    }

    private func report(_ reason: ReportReason) {
        run(.reported) {
            try await api.report(code: code, person: person.id, reason: reason)
            reported = true
        }
    }

    private func block() {
        run(.blocked) { blockedID = try await api.block(code: code, person: person.id, me: me) }
    }

    private func unblock() {
        guard let id = blockedID else { return }
        run(.unblocked) {
            try await api.unblock(id: id, me: me)
            blockedID = nil
        }
    }
}
