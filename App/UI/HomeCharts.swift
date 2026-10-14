import SwiftUI

// Home's charts, drawn by hand so they look like Dictum rather than a generic dashboard.
// One accent hue for "in the selected period", gray for context, hover for the details.

/// The last 30 days as a waveform: each day a bar mirrored around a centre line, like the
/// recording window's; a quiet day is a dot. Days in the selected period are in the accent
/// colour, the rest gray. Hover a day for its numbers.
struct RhythmChart: View {
    let days: [UsageStats.Day]
    let period: UsageStats.Period
    @State private var hovered: Int?

    static let plotHeight: CGFloat = 104
    private static let axisHeight: CGFloat = 18

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let slot = width / CGFloat(max(days.count, 1))
            let barWidth = min(9, max(3, slot * 0.46))
            let peak = CGFloat(max(days.map(\.words).max() ?? 0, 1))

            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    let mid = Self.plotHeight / 2
                    for (index, day) in days.enumerated() {
                        let x = slot * (CGFloat(index) + 0.5)
                        let color = colour(for: day, hovered: hovered == index)
                        if day.words == 0 {
                            let radius: CGFloat = hovered == index ? 2.5 : 1.5
                            context.fill(Path(ellipseIn: CGRect(x: x - radius, y: mid - radius,
                                                                width: radius * 2, height: radius * 2)),
                                         with: .color(color))
                        } else {
                            let height = max(barWidth, CGFloat(day.words) / peak * (Self.plotHeight - 6))
                            let bar = CGRect(x: x - barWidth / 2, y: mid - height / 2, width: barWidth, height: height)
                            context.fill(Path(roundedRect: bar, cornerRadius: barWidth / 2), with: .color(color))
                        }
                    }
                }
                .frame(height: Self.plotHeight)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point): hovered = min(days.count - 1, max(0, Int(point.x / slot)))
                    case .ended: hovered = nil
                    }
                }

                axis(slot: slot)
                    .offset(y: Self.plotHeight + 4)

                if let hovered, days.indices.contains(hovered) {
                    tooltip(for: days[hovered])
                        .fixedSize()
                        .alignmentGuide(.leading) { size in
                            let centre = slot * (CGFloat(hovered) + 0.5)
                            return -min(max(centre - size.width / 2, 0), width - size.width)
                        }
                        .offset(y: -38)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
        }
        .frame(height: Self.plotHeight + Self.axisHeight)
        .animation(.easeOut(duration: 0.12), value: hovered)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Words per day, last \(days.count) days")
        .accessibilityValue(accessibilitySummary)
    }

    private func inPeriod(_ day: UsageStats.Day) -> Bool {
        guard let start = period.start else { return true }
        return day.date.addingTimeInterval(86_400) > start
    }

    private func colour(for day: UsageStats.Day, hovered: Bool) -> Color {
        if day.words == 0 { return Color.secondary.opacity(hovered ? 0.7 : 0.35) }
        if inPeriod(day) { return Color.accentColor.opacity(hovered ? 0.72 : 1) }
        return Color.secondary.opacity(hovered ? 0.6 : 0.3)
    }

    /// First day, a week marker in the middle, and today.
    private func axis(slot: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            if let first = days.first {
                Text(first.date.formatted(.dateTime.day().month(.abbreviated)))
            }
            if days.count > 14 {
                let middle = days.count / 2
                Text(days[middle].date.formatted(.dateTime.day().month(.abbreviated)))
                    .alignmentGuide(.leading) { size in -(slot * (CGFloat(middle) + 0.5) - size.width / 2) }
            }
            Text("Today")
                .frame(width: slot * CGFloat(days.count), alignment: .trailing)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }

    private func tooltip(for day: UsageStats.Day) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(day.words == 0 ? "No dictation" : "\(day.words.formatted()) words")
                .font(.system(size: 12, weight: .semibold))
            Text(detail(for: day))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color(nsColor: .windowBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.primary.opacity(0.1)))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
    }

    private func detail(for day: UsageStats.Day) -> String {
        let date = Calendar.current.isDateInToday(day.date)
            ? "Today" : day.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        guard day.dictations > 0 else { return date }
        let minutes = Int((day.seconds / 60).rounded())
        let talk = minutes >= 1 ? " · \(minutes) min" : ""
        return "\(date) · \(day.dictations) dictation\(day.dictations == 1 ? "" : "s")\(talk)"
    }

    private var accessibilitySummary: String {
        let total = days.reduce(0) { $0 + $1.words }
        guard let busiest = days.max(by: { $0.words < $1.words }), busiest.words > 0 else { return "No dictation" }
        return "\(total) words in total. Busiest day \(busiest.date.formatted(date: .complete, time: .omitted)), \(busiest.words) words."
    }
}

/// When in the day you dictate: 24 cells, darker for busier hours.
struct HourStrip: View {
    let counts: [Int]
    @State private var hovered: Int?

    var body: some View {
        let busiest = Double(max(counts.max() ?? 0, 1))
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 2) {
                ForEach(0..<24, id: \.self) { hour in
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(counts[hour] == 0
                              ? Color.secondary.opacity(0.13)
                              : Color.accentColor.opacity(0.28 + 0.72 * Double(counts[hour]) / busiest))
                        .overlay {
                            if hovered == hour {
                                RoundedRectangle(cornerRadius: 2.5).strokeBorder(Color.primary.opacity(0.55), lineWidth: 1)
                            }
                        }
                        .frame(height: 24)
                        .contentShape(Rectangle())
                        .onHover { inside in
                            if inside { hovered = hour } else if hovered == hour { hovered = nil }
                        }
                }
            }
            HStack(spacing: 0) {
                ForEach([0, 6, 12, 18], id: \.self) { hour in
                    Text(String(format: "%02d:00", hour)).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
            Text(caption)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Dictations by hour of the day")
        .accessibilityValue(caption)
    }

    private var caption: String {
        if let hovered {
            let count = counts[hovered]
            return String(format: "%02d:00–%02d:00 · ", hovered, (hovered + 1) % 24)
                + (count == 0 ? "none" : "\(count) dictation\(count == 1 ? "" : "s")")
        }
        guard let peak = counts.indices.max(by: { counts[$0] < counts[$1] }), counts[peak] > 0 else {
            return "No dictations in this period"
        }
        return String(format: "Mostly around %02d:00", peak)
    }
}

/// Languages as one bar split by share, with each language's flag and percentage
/// underneath. The main language takes the accent colour, the second gray, the rest lighter.
struct LanguageSplit: View {
    let languages: [(code: String, share: Double)]

    private var segments: [(code: String, name: String, share: Double, colour: Color)] {
        let palette = [Color.accentColor, Color.primary.opacity(0.42), Color.secondary.opacity(0.28)]
        var parts = languages.prefix(2).enumerated().map { index, language in
            (code: language.code, name: SpeechLanguage.name(for: language.code), share: language.share, colour: palette[index])
        }
        let rest = languages.dropFirst(2).reduce(0) { $0 + $1.share }
        if rest > 0.005 { parts.append((code: "", name: "Other", share: rest, colour: palette[2])) }
        return parts
    }

    var body: some View {
        let parts = segments
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { proxy in
                let gaps = CGFloat(max(parts.count - 1, 0)) * 2
                HStack(spacing: 2) {
                    ForEach(parts.indices, id: \.self) { index in
                        UnevenRoundedRectangle(
                            topLeadingRadius: index == 0 ? 4 : 1, bottomLeadingRadius: index == 0 ? 4 : 1,
                            bottomTrailingRadius: index == parts.count - 1 ? 4 : 1,
                            topTrailingRadius: index == parts.count - 1 ? 4 : 1
                        )
                        .fill(parts[index].colour)
                        .frame(width: max(2, (proxy.size.width - gaps) * parts[index].share))
                    }
                }
            }
            .frame(height: 10)
            VStack(alignment: .leading, spacing: 7) {
                ForEach(parts.indices, id: \.self) { index in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 2).fill(parts[index].colour).frame(width: 8, height: 8)
                        Text(parts[index].code.isEmpty ? "🌐" : SpeechLanguage.flag(for: parts[index].code))
                            .font(.system(size: 13))
                        Text(parts[index].name).font(.system(size: 13))
                        Spacer()
                        Text("\(Int((parts[index].share * 100).rounded())) %")
                            .font(.system(size: 13, weight: .semibold)).monospacedDigit()
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Languages")
        .accessibilityValue(parts.map { "\($0.name) \(Int(($0.share * 100).rounded())) percent" }.joined(separator: ", "))
    }
}
