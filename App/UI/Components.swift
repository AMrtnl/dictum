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

/// Cards for choosing the recording window style, each with a picture of the real window.
struct RecordingStylePicker: View {
    @Binding var selection: RecordingWindowStyle
    var waveform: WaveformStyle = .conveyor

    var body: some View {
        HStack(spacing: 12) {
            ForEach(RecordingWindowStyle.allCases) { style in
                StyleCard(style: style, waveform: waveform, selected: selection == style) { selection = style }
            }
        }
    }
}

private struct StyleCard: View {
    let style: RecordingWindowStyle
    let waveform: WaveformStyle
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                thumbnail
                    .frame(width: 176, height: 84)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.12)))
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
        if let image = RecordingWindowThumbnails.image(for: style, waveform: waveform) {
            // Classic is scaled to fit; Mini stays near its real size, so it reads as the small one.
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: style == .classic ? 160 : 112)
        } else {
            Image(systemName: "eye.slash").font(.system(size: 20)).foregroundStyle(.secondary)
        }
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
