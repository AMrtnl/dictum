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
            .background(RoundedRectangle(cornerRadius: 12).fill(selected ? Color.accentColor.opacity(0.06) : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.22), lineWidth: selected ? 2 : 1))
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
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.07)))
    }
}
