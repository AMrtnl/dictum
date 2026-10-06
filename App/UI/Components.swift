import SwiftUI

/// A numbered checklist row: title, one-line purpose, and a status or action on the right.
struct ChecklistRow<Trailing: View>: View {
    let number: Int
    let title: String
    let detail: String
    let done: Bool
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle().fill(done ? Color.green.opacity(0.18) : Color.secondary.opacity(0.12))
                if done {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.green)
                } else {
                    Text("\(number)").font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
    }
}

struct GrantedLabel: View {
    var text = "Granted"

    var body: some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .labelStyle(.titleAndIcon)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.green)
    }
}

/// Key caps for a shortcut, e.g. ⌥ Space.
struct KeycapsView: View {
    let keys: [String]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                Text(key)
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 6)
                    .frame(minWidth: 20, minHeight: 20)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(0.15)))
            }
        }
    }
}

/// Thumbnail cards for choosing the recording window style, like superwhisper's.
struct RecordingStylePicker: View {
    @Binding var selection: RecordingWindowStyle

    var body: some View {
        HStack(spacing: 12) {
            ForEach(RecordingWindowStyle.allCases) { style in
                StyleCard(style: style, selected: selection == style) { selection = style }
            }
        }
    }
}

private struct StyleCard: View {
    let style: RecordingWindowStyle
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                thumbnail
                    .frame(width: 132, height: 64)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
                    .overlay(border)
                Text(style.title)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: 10)
            .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: selected ? 2.5 : 1)
    }

    @ViewBuilder
    private var thumbnail: some View {
        switch style {
        case .classic:
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.black)
                .frame(width: 104, height: 44)
                .overlay(alignment: .top) { MiniBars(count: 22, height: 10).padding(.top, 9) }
                .overlay(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.12)).frame(height: 10).padding(5)
                }
        case .mini:
            Capsule().fill(Color.black).frame(width: 64, height: 22)
                .overlay { MiniBars(count: 7, height: 10) }
        case .none:
            Image(systemName: "eye.slash").font(.system(size: 18)).foregroundStyle(.secondary)
        }
    }
}

/// Static, centre-weighted bars for the style thumbnails.
private struct MiniBars: View {
    let count: Int
    let height: CGFloat

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<count, id: \.self) { index in
                Capsule().fill(Color.white.opacity(0.9)).frame(width: 1.6, height: barHeight(index))
            }
        }
    }

    private func barHeight(_ index: Int) -> CGFloat {
        let half = Double(count - 1) / 2
        let distance = abs(Double(index) - half) / (half + 1)
        let wobble = 0.55 + 0.45 * abs(sin(Double(index) * 1.7))
        return max(2, height * CGFloat((1 - distance * distance) * wobble))
    }
}

/// A settings card with a title row and free-form content.
struct Card<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                if let subtitle {
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.07)))
    }
}
