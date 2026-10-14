import Observation
import SwiftUI

/// Pages of the main window, in sidebar order.
enum MainPage: String, Hashable, CaseIterable, Identifiable {
    case home, modes, vocabulary, configuration, sound, models, history, training, about

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
        case .training: "Training data"
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
        case .training: "waveform.badge.plus"
        case .about: "info.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .home: .orange
        case .modes, .vocabulary: .blue
        case .history: .purple
        case .training: .green
        default: Color(white: 0.5)
        }
    }

    /// Sidebar groups, separated by space like superwhisper's.
    static let groups: [[MainPage]] = [[.home], [.modes, .vocabulary], [.configuration, .sound, .models], [.history, .training]]
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
        case .training: TrainingDataView()
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

            EngineStatus(models: { selection = .models }, about: { selection = .about })
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
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

/// Bottom of the sidebar: whether the speech engine is ready, and with which model.
/// Clicking it opens the Models library; the version opens About.
private struct EngineStatus: View {
    let models: () -> Void
    let about: () -> Void
    private let engine = SpeechEngine.shared
    private let settings = AppSettings.shared

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: models) {
                HStack(spacing: 8) {
                    indicator
                    VStack(alignment: .leading, spacing: 0) {
                        Text(settings.speechModel.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        Text(state).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Speech model — open the Models library")
            Spacer(minLength: 4)
            Button(version, action: about)
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .help("About Dictum")
        }
    }

    @ViewBuilder
    private var indicator: some View {
        switch engine.phase {
        case .ready:
            Circle().fill(Color.green).frame(width: 7, height: 7)
        case .failed, .needsSetup:
            Circle().fill(Color.orange).frame(width: 7, height: 7)
        default:
            ProgressView().controlSize(.mini).frame(width: 7, height: 7)
        }
    }

    private var state: String {
        switch engine.phase {
        case .ready: "Ready, on this Mac"
        case .checking, .starting: "Starting…"
        case .installingRuntime: "Setting up…"
        case .installingModel(let fraction, let converting):
            converting ? "Preparing…" : "Downloading \(Int(fraction * 100)) %"
        case .needsSetup: "Not installed"
        case .failed: "Stopped — open Models"
        }
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
