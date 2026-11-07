import PounceKit
import SwiftUI

/// The last tile in Home's row of tables: the owner's cat asleep and how many tables are archived.
struct ArchivedTile: View {
    let count: Int
    let cat: Int
    let action: () -> Void

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 26, style: .continuous) }

    var body: some View {
        Button {
            Haptics.shared.tick()
            Sound.shared.play(ArtName.Sound.sfxPop)
            action()
        } label: {
            ZStack {
                shape.fill(Palette.ink.opacity(0.55))
                shape.strokeBorder(
                    Palette.sky, style: StrokeStyle(lineWidth: 5, lineCap: .round, dash: [2, 11]))
                VStack(spacing: 4) {
                    ZStack(alignment: .topTrailing) {
                        Image(ArtName.cat(cat, .asleep))
                            .resizable().scaledToFit()
                            .frame(width: 70, height: 70)
                            .saturation(0.6)
                        countBadge
                            .offset(x: 10, y: -6)
                    }
                    .frame(height: 78)
                    OutlinedText(
                        String(localized: "Archived", comment: "Home: the tile that opens archived tables"),
                        size: 15, fill: .white, width: 2.5)
                }
                .padding(.vertical, 8)
            }
            .frame(width: TableCard.size.width, height: TableCard.size.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Archived tables, \(count)", comment: "VoiceOver: Home's archived tile"))
        .accessibilityIdentifier("home.archived")
    }

    private var countBadge: some View {
        OutlinedText("\(count)", size: 16, fill: .white, width: 2)
            .frame(minWidth: 30, minHeight: 30)
            .background(Circle().fill(Palette.sky))
            .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 3))
    }
}

/// Tables archived off Home. Tap one to put it back on Home; the sheet closes once none are left.
struct ArchivedSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let items = model.archivedItems
        VStack(spacing: 0) {
            HStack {
                OutlinedText(
                    String(localized: "Archived", comment: "Archived sheet: title"), size: 28, fill: .white)
                Spacer()
                PillButton(icon: ArtName.iconBack, color: Palette.sky, size: .small, accessibilityLabel: "Close") {
                    dismiss()
                }
                .accessibilityIdentifier("archived.close")
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)

            Text("Tap a table to put it back on Home.", comment: "Archived sheet: how to restore a table")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 8)

            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: TableCard.size.width), spacing: 14)], spacing: 18
                ) {
                    ForEach(items) { item in
                        TableCard(item: item, people: model.tablePeople(item), identifier: "archived.table.\(item.id)") {
                            Haptics.shared.success()
                            Sound.shared.play(ArtName.Sound.sfxPop)
                            model.restore(code: item.id)
                        }
                        .accessibilityHint(Text("Puts it back on Home", comment: "VoiceOver: an archived table"))
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
                }
                .animation(.spring(duration: 0.4, bounce: 0.35), value: items.map(\.id))
                .padding(.horizontal, 24)
                .padding(.vertical, 22)
            }
            .scrollClipDisabled()
        }
        .onChange(of: items.isEmpty) { _, empty in
            if empty { dismiss() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sheet-archived")
    }
}
