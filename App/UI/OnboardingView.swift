import SwiftUI

/// First-run checklist: microphone, Accessibility, speech engine, then a place to try it.
struct OnboardingView: View {
    private let permissions = Permissions.shared
    private let engine = SpeechEngine.shared
    @State private var practice = ""
    @FocusState private var practiceFocused: Bool

    private var keys: [String] { DictationController.keys(for: .pushToTalk) }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 34)
                .padding(.bottom, 22)

            VStack(spacing: 0) {
                ChecklistRow(number: 1, title: "Microphone",
                             detail: "So Dictum can hear you while you hold the shortcut.",
                             done: permissions.microphone == .granted) {
                    if permissions.microphone == .granted {
                        GrantedLabel()
                    } else {
                        Button(permissions.microphone == .denied ? "Open Settings" : "Allow") {
                            Task { await permissions.requestMicrophone() }
                        }
                    }
                }
                Divider().padding(.leading, 56)
                ChecklistRow(number: 2, title: "Accessibility",
                             detail: "So Dictum can paste the text into the app you are using.",
                             done: permissions.accessibility == .granted) {
                    if permissions.accessibility == .granted {
                        GrantedLabel()
                    } else {
                        Button("Allow") { permissions.requestAccessibility() }
                    }
                }
                Divider().padding(.leading, 56)
                ChecklistRow(number: 3, title: "Speech engine", detail: engineDetail, done: engine.isReady) {
                    engineAction
                }
                if case .installingModel(let fraction, let converting) = engine.phase {
                    ProgressView(value: converting ? nil : fraction)
                        .padding(.horizontal, 56)
                        .padding(.bottom, 12)
                }
            }
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.07)))
            .padding(.horizontal, 28)

            tryIt
                .padding(.horizontal, 28)
                .padding(.top, 18)

            Spacer(minLength: 18)

            HStack {
                Text("Everything runs on this Mac. Nothing you say leaves it.")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button(isComplete ? "Done" : "Finish Later") { WindowManager.shared.close(.onboarding) }
                    .keyboardShortcut(isComplete ? .defaultAction : .cancelAction)
                    .controlSize(.large)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 22)
        }
        .frame(width: 580, height: 580)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { permissions.refresh() }
    }

    private var isComplete: Bool { permissions.allGranted && engine.isReady }

    private var header: some View {
        VStack(spacing: 10) {
            AppGlyph(size: 68)
            Text("Welcome to Dictum").font(.system(size: 24, weight: .semibold))
            HStack(spacing: 5) {
                Text("Hold")
                KeycapsView(keys: keys)
                Text("anywhere, speak, and let go. Your words are typed for you.")
            }
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
        }
    }

    private var engineDetail: String {
        switch engine.phase {
        case .installingRuntime: "Setting up a private Python runtime with MLX…"
        case .installingModel(let fraction, let converting):
            converting ? "Converting Cohere Transcribe to 4-bit…" : "Downloading Cohere Transcribe… \(Int(fraction * 100)) %"
        case .starting, .checking: "Starting…"
        case .ready: "Cohere Transcribe is ready, 4-bit, on this Mac."
        case .failed(let message): message
        case .needsSetup: "Downloads Cohere Transcribe (2.4 GB) and installs it for this Mac. Takes a few minutes."
        }
    }

    @ViewBuilder
    private var engineAction: some View {
        switch engine.phase {
        case .ready: GrantedLabel(text: "Ready")
        case .needsSetup: Button("Install") { Task { await engine.setUp() } }.buttonStyle(.borderedProminent)
        case .failed: Button("Try Again") { Task { await engine.setUp() } }
        default: ProgressView().controlSize(.small)
        }
    }

    private var tryIt: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Text("Try it:").fontWeight(.semibold)
                Text("click below, hold")
                KeycapsView(keys: keys)
                Text("and say something.")
            }
            .font(.system(size: 13))
            .foregroundStyle(isComplete ? .primary : .secondary)

            TextEditor(text: $practice)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(height: 84)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.25)))
                .focused($practiceFocused)
                .disabled(!isComplete)
        }
    }
}
