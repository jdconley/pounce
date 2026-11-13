import SwiftUI

// Every sheet's corners: the X that closes it sits top trailing, and a page inside a sheet has a
// back arrow top leading. Same pill, same size, same color on every sheet.

/// Closes the sheet (or card) it sits on: a sky pill with the chunky X, top trailing.
struct SheetCloseButton: View {
    var label: LocalizedStringKey = "Close"
    let action: () -> Void

    var body: some View {
        PillButton(icon: ArtName.iconClose, color: Palette.sky, size: .small, width: SheetBar.side,
                   accessibilityLabel: label, action: action)
    }
}

/// Goes back one page inside a sheet: the same pill with the back arrow, top leading.
struct SheetBackButton: View {
    var label: LocalizedStringKey = "Back"
    let action: () -> Void

    var body: some View {
        PillButton(icon: ArtName.iconBack, color: Palette.sky, size: .small, width: SheetBar.side,
                   accessibilityLabel: label, action: action)
    }
}

/// A sheet's top bar: back on a page inside the sheet (leading), a title, close (trailing). Either
/// button can be left out; its corner stays empty so the title stays centered.
struct SheetBar: View {
    static let side: CGFloat = 52

    var title: String?
    var onBack: (() -> Void)?
    var backID = "sheet.back"
    var onClose: (() -> Void)?
    var closeID = "sheet.close"

    var body: some View {
        HStack(spacing: 12) {
            corner {
                if let onBack {
                    SheetBackButton(action: onBack).accessibilityIdentifier(backID)
                }
            }
            Spacer(minLength: 0)
            if let title {
                OutlinedText(title, size: 26, fill: .white, width: 3)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("sheet.title")
            }
            Spacer(minLength: 0)
            corner {
                if let onClose {
                    SheetCloseButton(action: onClose).accessibilityIdentifier(closeID)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    private func corner(@ViewBuilder _ content: () -> some View) -> some View {
        content().frame(width: Self.side, height: PillSize.small.height + 6)
    }
}
