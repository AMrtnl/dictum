import Charts
import SwiftUI

/// Dashboard: usage stats, a get-started checklist and what's new.
struct HomeView: View {
    private let history = HistoryStore.shared
    private let permissions = Permissions.shared
    @State private var period = UsageStats.Period.allTime

    private static let changes: [(date: String, title: String, detail: String)] = [
        ("Oct 7", "Hands-free, auto language, more models",
         "Tap the shortcut to dictate hands-free, automatic English/French detection, training data, seven waveform styles and a new icon."),
        ("Oct 7", "Home window and Vocabulary",
         "A dashboard with your dictation stats, and custom vocabulary to fix how names and terms are written."),
        ("Oct 6", "Sleeping pill",
         "The small window rests as a thin pill, opens a toolbar on hover, and snaps to screen edges and corners."),
        ("Oct 6", "Dictum 1.0",
         "On-device dictation with Cohere Transcribe, and Rewrite mode with Tiny Aya."),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                if permissions.accessibility != .granted { pasteBanner }
                stats
                activity
                getStarted
                whatsNew
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .frame(maxWidth: 820, alignment: .leading)
        }
    }

    // MARK: Paste permission

    private var pasteBanner: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 18))
                .foregroundStyle(.orange)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 6) {
                Text("Auto-paste is off").font(.system(size: 14, weight: .semibold))
                Text("macOS hasn't given Dictum Accessibility access, so transcripts are copied instead of pasted. Turn Dictum on in Privacy & Security → Accessibility.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Already on but still not pasting? macOS is holding an outdated entry: reset it, then switch Dictum on again.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button("Grant Access") { permissions.requestAccessibility() }
                        .buttonStyle(.borderedProminent)
                    Button("Reset Permission") { permissions.resetAccessibility() }
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.orange.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.orange.opacity(0.35)))
    }

    // MARK: Stats

    private var stats: some View {
        let stats = UsageStats(history.entries, period: period)
        return VStack(alignment: .leading, spacing: 12) {
            Picker("Period", selection: $period) {
                ForEach(UsageStats.Period.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            .buttonStyle(.borderless)
            .font(.system(size: 15, weight: .semibold))

            HStack(spacing: 0) {
                stat(stats.wordsPerMinute > 0 ? "\(stats.wordsPerMinute) WPM" : "–", "Average speed")
                stat(stats.words.formatted(), "Words")
                stat("\(stats.appsUsed)", "Apps used")
                stat(stats.savedDescription, "Saved \(period == .allTime ? "all time" : period.title.lowercased())",
                     help: "Compared with typing at \(Int(UsageStats.typingWPM)) words per minute.")
            }
            .padding(.vertical, 18)
            .padding(.horizontal, 20)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.secondary.opacity(0.08)))
        }
    }

    private func stat(_ value: String, _ label: String, help: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.system(size: 20, weight: .semibold)).monospacedDigit()
            HStack(spacing: 4) {
                Text(label)
                if help != nil { Image(systemName: "info.circle").imageScale(.small) }
            }
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(help ?? "")
    }

    // MARK: Activity

    private var activity: some View {
        let daily = UsageStats.daily(history.entries)
        let languages = UsageStats.languages(history.entries)
        let apps = UsageStats.topApps(history.entries)
        return HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Words per day").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                Chart(daily, id: \.day) { item in
                    BarMark(x: .value("Day", item.day, unit: .day), y: .value("Words", item.words))
                        .foregroundStyle(Color.accentColor.gradient)
                        .cornerRadius(3)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                        AxisValueLabel(format: .dateTime.weekday(.narrow))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine().foregroundStyle(Color.secondary.opacity(0.15))
                        AxisValueLabel()
                    }
                }
                .frame(height: 120)
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 14) {
                if !languages.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Languages").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                        ForEach(languages.prefix(3), id: \.code) { language in
                            HStack(spacing: 8) {
                                Text(SpeechLanguage(rawValue: language.code)?.title ?? language.code.uppercased())
                                    .font(.system(size: 12))
                                    .frame(width: 64, alignment: .leading)
                                GeometryReader { proxy in
                                    Capsule().fill(Color.secondary.opacity(0.15))
                                        .overlay(alignment: .leading) {
                                            Capsule().fill(Color.accentColor).frame(width: proxy.size.width * language.share)
                                        }
                                }
                                .frame(height: 6)
                                Text("\(Int((language.share * 100).rounded())) %")
                                    .font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
                                    .frame(width: 36, alignment: .trailing)
                            }
                        }
                    }
                }
                if !apps.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Top apps").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                        ForEach(apps, id: \.name) { app in
                            HStack(spacing: 8) {
                                if let icon = AppIcons.icon(for: app.bundleID) {
                                    Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                                } else {
                                    Image(systemName: "app.dashed").frame(width: 18, height: 18).foregroundStyle(.secondary)
                                }
                                Text(app.name).font(.system(size: 12)).lineLimit(1)
                                Spacer()
                                Text("\(app.count)").font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if languages.isEmpty && apps.isEmpty {
                    Text("Your languages and favourite apps show up here after a few dictations.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 240, alignment: .leading)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.secondary.opacity(0.08)))
    }

    // MARK: Get started

    private var getStarted: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Get started").font(.system(size: 15, weight: .semibold)).foregroundStyle(.secondary)
                .padding(.bottom, 6)
            if !permissions.allGranted {
                row("exclamationmark.triangle", "Finish setting up",
                    "Dictum needs Microphone and Accessibility access to hear you and paste.") {
                    WindowManager.shared.show(.onboarding)
                }
            }
            row("record.circle", "Start recording", "Tap the shortcut, speak as long as you like, tap again to paste. Or hold it while you talk.",
                keys: DictationController.keys(for: .pushToTalk)) { }
            row("hand.point.up.left", "Customize your shortcuts", "Change the keyboard shortcuts for Dictum.") {
                MainNavigation.shared.page = .configuration
            }
            row("sparkle", "Try Rewrite", "Clean up fillers and false starts with Tiny Aya.",
                keys: DictationController.keys(for: .pushToTalkRewrite)) {
                MainNavigation.shared.page = .modes
            }
            row("book.closed", "Add vocabulary", "Teach Dictum how to write names and terms.") {
                MainNavigation.shared.page = .vocabulary
            }
        }
    }

    private func row(_ symbol: String, _ title: String, _ detail: String, keys: [String] = [],
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: symbol)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 14, weight: .semibold))
                    Text(detail).font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer()
                if !keys.isEmpty { KeycapsView(keys: keys) }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(HoverRowStyle())
    }

    // MARK: What's new

    private var whatsNew: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("What's new").font(.system(size: 15, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Link("View all changes", destination: URL(string: "https://github.com/AMrtnl/dictum/releases")!)
                    .font(.system(size: 13))
            }
            VStack(spacing: 0) {
                ForEach(Array(Self.changes.enumerated()), id: \.offset) { index, change in
                    HStack(alignment: .firstTextBaseline, spacing: 18) {
                        Text(change.date).font(.system(size: 13)).foregroundStyle(.secondary)
                            .frame(width: 48, alignment: .leading)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(change.title).font(.system(size: 14, weight: .semibold))
                            Text(change.detail).font(.system(size: 13)).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    if index < Self.changes.count - 1 { Divider().padding(.leading, 84) }
                }
            }
            .background(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.secondary.opacity(0.2)))
        }
    }
}

/// A row that highlights under the pointer.
struct HoverRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverRow(configuration: configuration)
    }

    private struct HoverRow: View {
        let configuration: ButtonStyle.Configuration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .background(RoundedRectangle(cornerRadius: 10)
                    .fill(Color.secondary.opacity(configuration.isPressed ? 0.16 : hovering ? 0.08 : 0)))
                .onHover { hovering = $0 }
        }
    }
}
