import AppKit
import SwiftUI

private enum UmbrellaSettingsTab: Hashable {
    case keybindings
    case brightness
    case simpleSnip
}

private enum KeybindingTarget: Hashable {
    case snipArea
    case snipWindow
    case snipFullScreen
    case snipRecord
    case snipText
    case brightnessDown
    case brightnessUp
    case warmthUp
    case warmthDown
    case sunPreset(String)
}

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var selectedTab: UmbrellaSettingsTab = .keybindings
    @State private var launchAtLogin = AppSettings.shared.launchAtLogin
    @State private var soundEffectsEnabled = AppSettings.shared.soundEffectsEnabled

    @State private var snipAreaHotKey = AppSettings.shared.snipAreaHotKey
    @State private var snipWindowHotKey = AppSettings.shared.snipWindowHotKey
    @State private var snipFullScreenHotKey = AppSettings.shared.snipFullScreenHotKey
    @State private var snipRecordHotKey = AppSettings.shared.snipRecordHotKey
    @State private var snipTextHotKey = AppSettings.shared.snipTextHotKey
    @State private var brightnessDownHotKey = AppSettings.shared.brightnessDownHotKey
    @State private var brightnessUpHotKey = AppSettings.shared.brightnessUpHotKey
    @State private var warmthUpHotKey = AppSettings.shared.warmthUpHotKey
    @State private var warmthDownHotKey = AppSettings.shared.warmthDownHotKey
    @State private var sunPresetHotKeys = AppSettings.shared.sunScreenPresetHotKeys
    @State private var recordingTarget: KeybindingTarget?
    @State private var shortcutConflict: String?

    var body: some View {
        VStack(spacing: 0) {
            settingsTabBar
            ZStack {
                switch selectedTab {
                case .keybindings:
                    keybindingsTab
                        .padding(16)
                case .brightness:
                    BrightnessSettingsTab(
                        feature: appModel.brightnessFeature,
                        onPresetsChanged: {
                            refreshPresetBindings()
                            appModel.reloadSunPresetHotKeys()
                        }
                    )
                case .simpleSnip:
                    SimpleSnipTabView(feature: appModel.simpleSnipFeature)
                        .padding(16)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(selectedTab == .brightness ? settingsWindowDark : Color(nsColor: .windowBackgroundColor))
        .ignoresSafeArea(edges: .top)
        .onAppear {
            launchAtLogin = LaunchAtLoginManager.isEnabled
            refreshPresetBindings()
            detectShortcutConflict()
        }
    }

    private var settingsWindowDark: Color {
        Color(red: 30 / 255, green: 30 / 255, blue: 30 / 255)
    }

    private var settingsTabBar: some View {
        HStack {
            Spacer(minLength: 88)
            HStack(spacing: 0) {
                settingsTabButton("Keybindings", tab: .keybindings)
                settingsTabButton("Brightness", tab: .brightness)
                settingsTabButton("SimpleSnip", tab: .simpleSnip)
            }
            .padding(2)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
            )
            Spacer(minLength: 88)
        }
        .frame(height: 52)
        .background(Color(red: 38 / 255, green: 38 / 255, blue: 38 / 255))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.black.opacity(0.55))
                .frame(height: 1)
        }
    }

    private func settingsTabButton(_ title: String, tab: UmbrellaSettingsTab) -> some View {
        let selected = selectedTab == tab
        return Button {
            selectedTab = tab
        } label: {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(selected ? Color.white.opacity(0.88) : Color.white.opacity(0.55))
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(selected ? Color.white.opacity(0.13) : Color.clear)
                        .shadow(color: selected ? Color.black.opacity(0.45) : .clear, radius: 0, y: 0)
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var keybindingsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sectionCard("General") {
                    Toggle("Launch at login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, enabled in
                            AppSettings.shared.launchAtLogin = enabled
                            LaunchAtLoginManager.setEnabled(enabled)
                        }

                    Toggle("Sound effects", isOn: $soundEffectsEnabled)
                        .onChange(of: soundEffectsEnabled) { _, enabled in
                            AppSettings.shared.soundEffectsEnabled = enabled
                        }

                    HStack {
                        Text("Version \(AppUpdateChecker.currentVersion)")
                            .foregroundStyle(.secondary)
                        #if !APP_STORE
                        Spacer()
                        Button("Check for Updates…") {
                            AppUpdateChecker.prompt()
                        }
                        #endif
                    }
                }

                sectionCard("SimpleSnip") {
                    editableBindingRow("Snip area", target: .snipArea)
                    editableBindingRow("Snip window", target: .snipWindow)
                    editableBindingRow("Snip full screen", target: .snipFullScreen)
                    editableBindingRow("Record area / Stop recording", target: .snipRecord)
                    editableBindingRow("Copy text from area", target: .snipText)
                }

                sectionCard("SunScreen") {
                    editableBindingRow("Brightness down", target: .brightnessDown)
                    editableBindingRow("Brightness up", target: .brightnessUp)
                    editableBindingRow("Warmer", target: .warmthUp)
                    editableBindingRow("Cooler", target: .warmthDown)

                    Divider()

                    ForEach(appModel.brightnessFeature.presets) { preset in
                        editableBindingRow("Preset: \(preset.name)", target: .sunPreset(preset.id))
                    }
                }

                if let shortcutConflict {
                    Text(shortcutConflict)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func editableBindingRow(_ title: String, target: KeybindingTarget) -> some View {
        HStack {
            Text(title)
            Spacer()
            HotKeyRecorderView(
                binding: binding(for: target),
                isRecording: recordingTarget == target,
                onBegin: { recordingTarget = target },
                onCommit: { commitHotKey($0, for: target) },
                onCancel: { recordingTarget = nil }
            )

            Button("Clear") {
                clearHotKey(for: target)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(!canClear(target))
        }
    }

    private func binding(for target: KeybindingTarget) -> Binding<HotKeyBinding?> {
        Binding<HotKeyBinding?>(
            get: {
                switch target {
                case .snipArea: return snipAreaHotKey
                case .snipWindow: return snipWindowHotKey
                case .snipFullScreen: return snipFullScreenHotKey
                case .snipRecord: return snipRecordHotKey
                case .snipText: return snipTextHotKey
                case .brightnessDown: return brightnessDownHotKey
                case .brightnessUp: return brightnessUpHotKey
                case .warmthUp: return warmthUpHotKey
                case .warmthDown: return warmthDownHotKey
                case .sunPreset(let id): return sunPresetHotKeys[id]
                }
            },
            set: { newValue in
                guard let newValue else { return }
                commitHotKey(newValue, for: target)
            }
        )
    }

    private func commitHotKey(_ binding: HotKeyBinding, for target: KeybindingTarget) {
        switch target {
        case .snipArea:
            snipAreaHotKey = binding
            AppSettings.shared.snipAreaHotKey = binding
        case .snipWindow:
            snipWindowHotKey = binding
            AppSettings.shared.snipWindowHotKey = binding
        case .snipFullScreen:
            snipFullScreenHotKey = binding
            AppSettings.shared.snipFullScreenHotKey = binding
        case .snipRecord:
            snipRecordHotKey = binding
            AppSettings.shared.snipRecordHotKey = binding
        case .snipText:
            snipTextHotKey = binding
            AppSettings.shared.snipTextHotKey = binding
        case .brightnessDown:
            brightnessDownHotKey = binding
            AppSettings.shared.brightnessDownHotKey = binding
        case .brightnessUp:
            brightnessUpHotKey = binding
            AppSettings.shared.brightnessUpHotKey = binding
        case .warmthUp:
            warmthUpHotKey = binding
            AppSettings.shared.warmthUpHotKey = binding
        case .warmthDown:
            warmthDownHotKey = binding
            AppSettings.shared.warmthDownHotKey = binding
        case .sunPreset(let id):
            sunPresetHotKeys[id] = binding
            AppSettings.shared.sunScreenPresetHotKeys = sunPresetHotKeys
        }
        recordingTarget = nil
        appModel.reloadHotKeys()
        detectShortcutConflict()
    }

    private func clearHotKey(for target: KeybindingTarget) {
        switch target {
        case .snipArea:
            snipAreaHotKey = .snipAreaDefault
            AppSettings.shared.snipAreaHotKey = .snipAreaDefault
        case .snipWindow:
            snipWindowHotKey = .snipWindowDefault
            AppSettings.shared.snipWindowHotKey = .snipWindowDefault
        case .snipFullScreen:
            snipFullScreenHotKey = .snipFullScreenDefault
            AppSettings.shared.snipFullScreenHotKey = .snipFullScreenDefault
        case .snipRecord:
            snipRecordHotKey = .recordAreaDefault
            AppSettings.shared.snipRecordHotKey = .recordAreaDefault
        case .snipText:
            snipTextHotKey = .snipTextDefault
            AppSettings.shared.snipTextHotKey = .snipTextDefault
        case .brightnessDown:
            brightnessDownHotKey = .brightnessDownDefault
            AppSettings.shared.brightnessDownHotKey = .brightnessDownDefault
        case .brightnessUp:
            brightnessUpHotKey = .brightnessUpDefault
            AppSettings.shared.brightnessUpHotKey = .brightnessUpDefault
        case .warmthUp:
            warmthUpHotKey = .warmthUpDefault
            AppSettings.shared.warmthUpHotKey = .warmthUpDefault
        case .warmthDown:
            warmthDownHotKey = .warmthDownDefault
            AppSettings.shared.warmthDownHotKey = .warmthDownDefault
        case .sunPreset(let id):
            sunPresetHotKeys.removeValue(forKey: id)
            AppSettings.shared.sunScreenPresetHotKeys = sunPresetHotKeys
        }
        appModel.reloadHotKeys()
        detectShortcutConflict()
    }

    private func canClear(_ target: KeybindingTarget) -> Bool {
        switch target {
        case .sunPreset(let id):
            return sunPresetHotKeys[id] != nil
        default:
            return true
        }
    }

    private func detectShortcutConflict() {
        var all: [(String, HotKeyBinding)] = [
            ("Snip area", snipAreaHotKey),
            ("Snip window", snipWindowHotKey),
            ("Snip full screen", snipFullScreenHotKey),
            ("Record area", snipRecordHotKey),
            ("Copy text", snipTextHotKey),
            ("Brightness down", brightnessDownHotKey),
            ("Brightness up", brightnessUpHotKey),
            ("Warmer", warmthUpHotKey),
            ("Cooler", warmthDownHotKey),
        ]
        all += appModel.brightnessFeature.presets.compactMap { preset in
            guard let binding = sunPresetHotKeys[preset.id] else { return nil }
            return ("SunScreen: \(preset.name)", binding)
        }

        var map: [String: [String]] = [:]
        for (label, binding) in all {
            map[binding.displayName, default: []].append(label)
        }
        if let conflict = map.first(where: { $0.value.count > 1 }) {
            shortcutConflict = "Conflict: \(conflict.value.joined(separator: ", ")) all use \(conflict.key)."
        } else {
            shortcutConflict = nil
        }
    }

    private func refreshPresetBindings() {
        var sunCurrent = AppSettings.shared.sunScreenPresetHotKeys
        let sunValidIDs = Set(appModel.brightnessFeature.presets.map(\.id))
        sunCurrent = sunCurrent.filter { sunValidIDs.contains($0.key) }
        AppSettings.shared.sunScreenPresetHotKeys = sunCurrent
        sunPresetHotKeys = sunCurrent

        detectShortcutConflict()
    }

    @ViewBuilder
    private func sectionCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: NSColor.controlBackgroundColor))
        )
    }
}

private final class SnipColorPanelController: NSObject {
    static let shared = SnipColorPanelController()
    private var onColor: ((NSColor) -> Void)?

    func show(color: NSColor, onChange: @escaping (NSColor) -> Void) {
        onColor = onChange
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.color = color
        panel.isContinuous = true
        panel.setTarget(self)
        panel.setAction(#selector(colorChanged(_:)))
        center(panel)
        panel.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self] in
            self?.center(panel)
        }
    }

    @objc private func colorChanged(_ sender: NSColorPanel) {
        onColor?(sender.color)
    }

    private func center(_ panel: NSWindow) {
        let screen = NSApp.keyWindow?.screen ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        var frame = panel.frame
        frame.origin = NSPoint(
            x: visible.midX - frame.width / 2,
            y: visible.midY - frame.height / 2
        )
        panel.setFrame(frame, display: true)
    }
}

private struct SimpleSnipTabView: View {
    @ObservedObject var feature: UmbrellaSimpleSnipFeature

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                section("Permissions") {
                    HStack {
                        Text("Screen capture")
                            .frame(width: 140, alignment: .leading)
                        Text(feature.screenCaptureState.label)
                            .foregroundStyle(permissionColor(feature.screenCaptureState))
                        Spacer()
                        Button("Open Settings") { feature.openScreenCaptureSettings() }
                    }

                    HStack {
                        Text("Microphone")
                            .frame(width: 140, alignment: .leading)
                        Text(feature.microphoneState.label)
                            .foregroundStyle(permissionColor(feature.microphoneState))
                        Spacer()
                        if feature.microphoneState != .allowed {
                            Button("Request Access") { feature.requestMicrophonePermission() }
                        }
                        Button("Open Settings") { feature.openMicrophoneSettings() }
                    }
                }

                section("Folders") {
                    HStack {
                        Text("Screenshots")
                            .frame(width: 110, alignment: .leading)
                        Text(feature.screenshotFolderPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Choose…") { feature.chooseScreenshotFolder() }
                        Button("Open") { feature.openScreenshotFolder() }
                    }

                    HStack {
                        Text("Recordings")
                            .frame(width: 110, alignment: .leading)
                        Text(feature.recordingFolderPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Choose…") { feature.chooseRecordingFolder() }
                        Button("Open") { feature.openRecordingFolder() }
                    }
                }

                section("Options") {
                    Toggle("Reveal screenshot in Finder", isOn: Binding(
                        get: { feature.revealScreenshotInFinder },
                        set: {
                            feature.revealScreenshotInFinder = $0
                            feature.saveSettings()
                        }
                    ))

                    Toggle("Reveal recording in Finder", isOn: Binding(
                        get: { feature.revealRecordingInFinder },
                        set: {
                            feature.revealRecordingInFinder = $0
                            feature.saveSettings()
                        }
                    ))

                    Toggle("Record system audio", isOn: Binding(
                        get: { feature.recordSystemAudio },
                        set: {
                            feature.recordSystemAudio = $0
                            feature.saveSettings()
                        }
                    ))

                    Toggle("Record microphone", isOn: Binding(
                        get: { feature.recordMicrophone },
                        set: {
                            feature.recordMicrophone = $0
                            feature.saveSettings()
                            if $0 { feature.requestMicrophonePermission() }
                        }
                    ))
                }

                section("Colors") {
                    snipColorPicker("Screenshot", color: $feature.screenshotSelectionColor)
                    snipColorPicker("Screen Record", color: $feature.recordingSelectionColor)
                    snipColorPicker("Text copy", color: $feature.textCopySelectionColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
        .onAppear {
            feature.refreshPermissionState()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            feature.refreshPermissionState()
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: NSColor.controlBackgroundColor))
        )
    }

    private func snipColorPicker(_ title: String, color: Binding<NSColor>) -> some View {
        HStack {
            Text(title)
            Spacer()
            Button {
                SnipColorPanelController.shared.show(color: color.wrappedValue) { picked in
                    color.wrappedValue = picked.usingColorSpace(.sRGB) ?? picked
                    feature.saveSettings()
                }
            } label: {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(nsColor: color.wrappedValue))
                    .frame(width: 44, height: 22)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.25), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(title) color")
        }
    }

    private func permissionColor(_ state: UmbrellaPermissionState) -> Color {
        switch state {
        case .allowed:
            return .green
        case .notRequested:
            return .secondary
        case .notAllowed:
            return .orange
        }
    }
}
