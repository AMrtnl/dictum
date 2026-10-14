import SwiftUI

// The pieces every main-window page shares with Home, so the app reads as one thing:
// one scrolling column with the same margins, a sentence that says what the page is for,
// small semibold section titles, and quiet chips.

/// One scrolling column with Home's margins.
struct PageScroll<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) { content }
                .padding(.horizontal, 34)
                .padding(.top, 26)
                .padding(.bottom, 30)
                .frame(maxWidth: 800, alignment: .leading)
        }
    }
}

/// A page's opening sentence, with an optional control on the right.
struct PageLead<Trailing: View>: View {
    let text: Text
    @ViewBuilder var trailing: Trailing

    init(_ text: Text, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.text = text
        self.trailing = trailing()
    }

    init(_ string: String, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.init(Text(string), trailing: trailing)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            text
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 560, alignment: .leading)
            Spacer(minLength: 0)
            trailing
        }
    }
}

/// A small section heading.
struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.system(size: 13, weight: .semibold))
    }
}

/// A short label in a tinted capsule: "Default", "In use", "Most accurate".
struct Chip: View {
    let text: String
    var tint: Color = .accentColor

    init(_ text: String, tint: Color = .accentColor) {
        self.text = text
        self.tint = tint
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.14)))
            .foregroundStyle(tint)
    }
}

/// A selectable panel: an accent border when chosen, a hairline otherwise.
struct Panel<Content: View>: View {
    var selected = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(cornerRadius: 16, tint: selected ? Color.accentColor.opacity(0.22) : nil)
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.accentColor, lineWidth: 2)
                }
            }
    }
}

/// A figure with its label underneath, for model specs and dataset totals.
struct Figure: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.system(size: 13, weight: .semibold))
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
}

/// A one-line note with an icon and an optional action, for things a page needs first.
struct InlineNote<Action: View>: View {
    let symbol: String
    let text: String
    @ViewBuilder var action: Action

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(.secondary)
            Text(text).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            action
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .glassSurface(cornerRadius: 14)
    }
}

// MARK: - DataFast-style lists

/// The fill for a card that sits on the window background, in light and dark.
extension Color {
    static let cardFill = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 1, alpha: 0.05) : NSColor(white: 1, alpha: 0.75)
    })
    static let cardBorder = Color.primary.opacity(0.08)
}

/// A rounded card: the container for lists and charts.
struct DashCard<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(cornerRadius: 16)
    }
}

/// A card's title, set where TabStrip's tabs would sit.
struct CardTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.system(size: 12, weight: .semibold)).padding(.horizontal, 9).padding(.vertical, 4)
    }
}

/// Text tabs at the top of a card: the chosen one sits in a soft pill.
struct TabStrip: View {
    let tabs: [String]
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs.indices, id: \.self) { index in
                Button { selection = index } label: {
                    Text(tabs[index])
                        .font(.system(size: 12, weight: selection == index ? .semibold : .regular))
                        .foregroundStyle(selection == index ? .primary : .secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 7)
                            .fill(selection == index ? Color.primary.opacity(0.08) : .clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// A list row with a bar behind it showing its share; the value sits on the right.
struct BarRow<Icon: View>: View {
    let label: String
    let value: String
    let fraction: Double
    @ViewBuilder var icon: Icon
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            icon.frame(width: 18, height: 18)
            Text(label).font(.system(size: 13)).lineLimit(1)
            Spacer(minLength: 8)
            Text(value).font(.system(size: 12.5, weight: .medium)).monospacedDigit()
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background(alignment: .leading) {
            GeometryReader { proxy in
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(hovering ? 0.28 : 0.17))
                    .frame(width: max(6, proxy.size.width * min(max(fraction, 0), 1)))
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(value)")
    }
}

/// A flag drawn as an icon: the emoji, sized to sit in a list row.
struct FlagIcon: View {
    let code: String

    var body: some View {
        Text(SpeechLanguage.flag(for: code)).font(.system(size: 14))
    }
}

// MARK: - Liquid Glass

extension View {
    /// Liquid Glass (macOS 26 and later) in a rounded shape; a quiet card fill before that.
    @ViewBuilder
    func glassSurface(cornerRadius: CGFloat, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(macOS 26, *) {
            glassEffect(Glass.regular.tint(tint).interactive(interactive),
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            background(RoundedRectangle(cornerRadius: cornerRadius).fill(tint?.opacity(0.12) ?? Color.cardFill))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(Color.cardBorder))
        }
    }

    /// Glass buttons on macOS 26 and later (prominent for the main action); bordered before.
    @ViewBuilder
    func glassButton(prominent: Bool = false) -> some View {
        if #available(macOS 26, *) {
            if prominent { buttonStyle(.glassProminent) } else { buttonStyle(.glass) }
        } else {
            if prominent { buttonStyle(.borderedProminent) } else { buttonStyle(.bordered) }
        }
    }
}
