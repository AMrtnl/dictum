import Observation
import SwiftUI

/// Pages of the main window, in sidebar order.
enum MainPage: String, Hashable, CaseIterable, Identifiable {
    case home, modes, vocabulary, configuration, sound, models, history, about

    var id: Self { self }

    var title: String {
        switch self {
        case .home: "Home"
        case .modes: "Modes"
        case .vocabulary: "Vocabulary"
        case .configuration: "Configuration"
        case .sound: "Sound"
        case .models: "Models library"
        case .history: "History"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .modes: "sparkle"
        case .vocabulary: "book.closed.fill"
        case .configuration: "gearshape.fill"
        case .sound: "speaker.wave.2.fill"
        case .models: "books.vertical.fill"
        case .history: "clock.arrow.circlepath"
        case .about: "info.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .home: .orange
        case .modes, .vocabulary: .blue
        case .history: .purple
        default: Color(white: 0.5)
        }
    }

    /// Sidebar groups, separated by space like superwhisper's.
    static let groups: [[MainPage]] = [[.home], [.modes, .vocabulary], [.configuration, .sound, .models], [.history]]
}

/// Which page the main window shows; set before opening it to deep-link.
@Observable
final class MainNavigation {
    static let shared = MainNavigation()
    var page: MainPage = .home
    private init() {}
}

struct MainWindowView: View {
    @Bindable private var navigation = MainNavigation.shared

    var body: some View {
        NavigationSplitView {
            Sidebar(selection: $navigation.page)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            detail
                .navigationTitle(navigation.page.title)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) { MicrophoneMenu() }
                }
        }
        .frame(minWidth: 780, minHeight: 540)
    }

    @ViewBuilder
    private var detail: some View {
        switch navigation.page {
        case .home: HomeView()
        case .modes: ModesPage()
        case .vocabulary: VocabularyView()
        case .configuration: ConfigurationPage()
        case .sound: SoundPage()
        case .models: ModelSettings()
        case .history: HistoryPage()
        case .about: AboutSettings()
        }
    }
}

private struct Sidebar: View {
    @Binding var selection: MainPage

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(Array(MainPage.groups.enumerated()), id: \.offset) { _, group in
                    Section {
                        ForEach(group) { page in
                            Label {
                                Text(page.title)
                            } icon: {
                                SidebarIcon(symbol: page.symbol, tint: page.tint)
                            }
                            .tag(page)
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            AppBadge { selection = .about }
                .padding(12)
        }
    }
}

/// White symbol on a coloured rounded square, like System Settings' sidebar.
struct SidebarIcon: View {
    let symbol: String
    let tint: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(tint.gradient)
            .frame(width: 22, height: 22)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
            }
    }
}

/// "Dictum 1.1" at the bottom of the sidebar; opens About.
private struct AppBadge: View {
    let action: () -> Void
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                AppGlyph(size: 22)
                Text("Dictum").font(.system(size: 14, weight: .semibold))
                Spacer(minLength: 4)
                Text(version)
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.18)))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.1)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.secondary.opacity(0.18)))
        }
        .buttonStyle(.plain)
        .help("About Dictum")
    }
}

/// Current input device in the toolbar, like superwhisper's; pick another from the menu.
private struct MicrophoneMenu: View {
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        let devices = AudioDevices.inputs()
        Menu {
            Picker("Microphone", selection: $settings.microphoneUID) {
                Text("System Default").tag(String?.none)
                ForEach(devices) { Text($0.name).tag(Optional($0.uid)) }
            }
            .pickerStyle(.inline)
        } label: {
            Label(title(devices), systemImage: symbol(devices))
                .labelStyle(.titleAndIcon)
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Microphone")
    }

    private func title(_ devices: [AudioDevices.Device]) -> String {
        if let uid = settings.microphoneUID, let device = devices.first(where: { $0.uid == uid }) {
            return device.name
        }
        return "\(AudioDevices.defaultInputName() ?? "Microphone") (Default)"
    }

    private func symbol(_ devices: [AudioDevices.Device]) -> String {
        title(devices).localizedCaseInsensitiveContains("airpods") ? "airpodspro" : "mic.fill"
    }
}
