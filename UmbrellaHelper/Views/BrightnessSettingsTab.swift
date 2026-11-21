import AppKit
import SwiftUI

struct BrightnessSettingsTab: View {
    @ObservedObject var feature: UmbrellaBrightnessFeature
    var onPresetsChanged: () -> Void

    @State private var isAdjustingBrightness = false
    @State private var isAdjustingTemperature = false
    @State private var expandedPresetID: String?
    @State private var nameFocusID: String?
    @State private var nameSelectAll = false
    @State private var deletePrompt: PresetDeletePrompt?

    var body: some View {
        Form {
            displaySection
            scheduleSection
            presetsSection
            powerSection
        }
        .formStyle(.grouped)
        .alert(
            Text(deletePrompt?.title ?? "Delete preset?"),
            isPresented: Binding(
                get: { deletePrompt != nil },
                set: { if !$0 { deletePrompt = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { confirmDelete() }
        } message: {
            Text(deletePrompt?.message ?? "")
        }
    }

    @ViewBuilder
    private var displaySection: some View {
        Section {
            PercentSliderRow(
                title: "Brightness",
                percentText: "\(displayPercent)%",
                value: Binding(
                    get: { Double(feature.brightness) },
                    set: { newValue in
                        guard isAdjustingBrightness else { return }
                        feature.setBrightness(Float(newValue), commit: false)
                    }
                ),
                range: Double(UmbrellaBrightnessFeature.minimumBrightness)...1,
                onEditingChanged: { editing in
                    isAdjustingBrightness = editing
                    if !editing { feature.commitPendingChanges() }
                }
            )

            TemperatureSliderRow(
                title: "Color temperature",
                kelvinText: "\(feature.colorTemp)K",
                value: Binding(
                    get: { Double(feature.colorTemp) },
                    set: { newValue in
                        guard isAdjustingTemperature else { return }
                        feature.setColorTemp(Int(newValue.rounded()), commit: false)
                    }
                ),
                isDisabled: feature.isDarkroom,
                onEditingChanged: { editing in
                    isAdjustingTemperature = editing
                    if !editing { feature.commitPendingChanges() }
                }
            )

            presetChipsRow

            SettingsSwitch(
                title: "Remove blue light",
                caption: nil,
                isOn: Binding(
                    get: { feature.isDarkroom },
                    set: { feature.setDarkroom($0) }
                )
            )

            SettingsSwitch(
                title: "Dim external displays only",
                caption: "The built-in display is left unchanged.",
                isOn: Binding(
                    get: { feature.isFilmModeEnabled },
                    set: { feature.setFilmMode($0) }
                )
            )
        } header: {
            Text("Display")
        } footer: {
            HStack {
                Spacer()
                Button("Restore Display Color") {
                    feature.restoreDisplayColor()
                }
                .help("Reset system display color, then re-apply current Suncut settings.")
            }
        }
    }

    private var presetChipsRow: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Presets")
                Text("The same ones shown in the menu bar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            if feature.menuBarFavoritePresets.isEmpty {
                Text("Turn on “Show in menu bar” for a preset.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            } else {
                HStack(spacing: 6) {
                    ForEach(feature.menuBarFavoritePresets) { preset in
                        presetChip(preset)
                    }
                }
            }
        }
    }

    private func presetChip(_ preset: UmbrellaSunPreset) -> some View {
        let active = presetMatchesDisplay(preset)
        return Button {
            feature.applyPreset(id: preset.id)
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(BrightnessSwatch.swatch(brightness: preset.brightness, kelvin: preset.colorTemp))
                    .frame(width: 12, height: 12)
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 1))
                Text(preset.name)
                    .lineLimit(1)
            }
            .font(.system(size: 12))
            .padding(.leading, 7)
            .padding(.trailing, 10)
            .frame(height: 24)
            .background(
                Capsule()
                    .fill(active ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.08))
            )
            .overlay(
                Capsule()
                    .strokeBorder(active ? Color.accentColor.opacity(0.65) : Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(preset.name)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    @ViewBuilder
    private var scheduleSection: some View {
        Section {
            SettingsSwitch(
                title: "Automatic brightness",
                caption: "Follows the curve below: dim at night, brightest at midday. Adjusting the Display controls turns this off.",
                isOn: Binding(
                    get: { feature.isAutoMode },
                    set: { feature.setAutoMode($0) }
                )
            )

            TimelineView(.periodic(from: .now, by: 60)) { context in
                let now = UmbrellaSolarSchedule.minutesOfDay(from: context.date)
                VStack(alignment: .leading, spacing: 8) {
                    scheduleStatus(at: now)
                    if let dayPreset, let nightPreset {
                        BrightnessScheduleGraph(
                            sunriseMinutes: feature.sunriseMinutes,
                            sunsetMinutes: feature.sunsetMinutes,
                            transitionMinutes: feature.transitionMinutes,
                            nowMinutes: now,
                            dayPreset: dayPreset,
                            nightPreset: nightPreset,
                            presets: feature.presets,
                            dayPresetID: Binding(
                                get: { feature.dayPresetID },
                                set: { newValue in
                                    feature.dayPresetID = newValue
                                    feature.refreshAutoStateIfNeeded()
                                }
                            ),
                            nightPresetID: Binding(
                                get: { feature.nightPresetID },
                                set: { newValue in
                                    feature.nightPresetID = newValue
                                    feature.refreshAutoStateIfNeeded()
                                }
                            ),
                            useLocation: feature.useLocationSchedule,
                            showsNow: feature.isAutoMode,
                            onSunrise: commitSunrise,
                            onSunset: commitSunset
                        )
                    }
                }
            }
            .disabled(!feature.isAutoMode)

            SettingsSwitch(
                title: "Use location for sunrise and sunset",
                caption: locationCaption,
                isOn: Binding(
                    get: { feature.useLocationSchedule },
                    set: { feature.setUseLocationSchedule($0) }
                )
            )
            .disabled(!feature.isAutoMode)

            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sunrise and sunset")
                    Text(feature.useLocationSchedule ? "Set by your location." : "Or drag the handles on the graph.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                DatePicker(
                    "Sunrise",
                    selection: sunriseDate,
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.field)
                .disabled(feature.useLocationSchedule)
                DatePicker(
                    "Sunset",
                    selection: sunsetDate,
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.field)
                .disabled(feature.useLocationSchedule)
            }
            .disabled(!feature.isAutoMode)

            Picker(selection: twilightSelection) {
                ForEach(twilightChoices, id: \.self) { minutes in
                    Text(twilightLabel(minutes)).tag(minutes)
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Twilight")
                    Text("How long brightness ramps before sunrise and after sunset. Shaded on the graph.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .pickerStyle(.menu)
            .disabled(!feature.isAutoMode)
        } header: {
            Text("Schedule")
        }
    }

    private func scheduleStatus(at minutes: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(feature.isAutoMode
                ? UmbrellaSolarSchedule.statusText(
                    at: minutes,
                    sunrise: feature.sunriseMinutes,
                    sunset: feature.sunsetMinutes,
                    transition: feature.transitionMinutes
                )
                : "Off · Brightness stays where you set it"
            )
            Spacer(minLength: 12)
            if feature.isAutoMode, let sample = scheduledSample(at: minutes) {
                Text("Now \(Int((sample.brightness * 100).rounded()))% · \(sample.colorTemp)K")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .font(.system(size: 12))
    }

    @ViewBuilder
    private var presetsSection: some View {
        Section {
            ForEach(feature.presets) { preset in
                PresetLibraryRow(
                    feature: feature,
                    presetID: preset.id,
                    initialName: preset.name,
                    isExpanded: expandedPresetID == preset.id,
                    wantsNameFocus: nameFocusID == preset.id,
                    selectAllName: nameSelectAll && nameFocusID == preset.id,
                    onToggle: { togglePreset(preset.id) },
                    onEdit: { editPreset(preset.id) },
                    onConsumeNameFocus: {
                        nameFocusID = nil
                        nameSelectAll = false
                    },
                    onRequestDelete: { requestDelete(preset) },
                    onPresetsChanged: onPresetsChanged
                )
            }

            Button(action: saveCurrentSettingsAsPreset) {
                Label("Save Current Settings as Preset", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
        } header: {
            Text("Presets")
        }
    }

    private var powerSection: some View {
        Section {
            SettingsSwitch(
                title: "Keep Awake",
                caption: nil,
                isOn: Binding(
                    get: { feature.isKeepAwakeEnabled },
                    set: { feature.setKeepAwake($0) }
                )
            )
        } header: {
            Text("Power")
        }
    }

    private var displayPercent: Int {
        Int((feature.brightness * 100).rounded())
    }

    private var dayPreset: UmbrellaSunPreset? {
        feature.presets.first { $0.id == feature.dayPresetID } ?? feature.presets.first
    }

    private var nightPreset: UmbrellaSunPreset? {
        feature.presets.first { $0.id == feature.nightPresetID } ?? feature.presets.last ?? feature.presets.first
    }

    private var locationCaption: String {
        guard feature.useLocationSchedule else {
            return "Times are set by hand below."
        }
        if let locationName = feature.locationName, !locationName.isEmpty {
            return locationName
        }
        return "Updated daily from your location."
    }

    private var twilightChoices: [Int] {
        var values = [15, 30, 45, 60, 90]
        if !values.contains(feature.transitionMinutes) {
            values.append(feature.transitionMinutes)
        }
        return values.sorted()
    }

    private var twilightSelection: Binding<Int> {
        Binding(
            get: { feature.transitionMinutes },
            set: { minutes in
                feature.updateTransitionMinutes(minutes)
                let maxSunset = UmbrellaSolarSchedule.minutesPerDay - minutes - 5
                if feature.sunsetMinutes > maxSunset {
                    feature.updateSunset(max(0, maxSunset))
                }
            }
        )
    }

    private var sunriseDate: Binding<Date> {
        Binding(
            get: { date(from: feature.sunriseMinutes) },
            set: { newDate in
                let minutes = UmbrellaSolarSchedule.minutesOfDay(from: newDate)
                guard minutes != feature.sunriseMinutes else { return }
                commitSunrise(minutes)
            }
        )
    }

    private var sunsetDate: Binding<Date> {
        Binding(
            get: { date(from: feature.sunsetMinutes) },
            set: { newDate in
                let minutes = UmbrellaSolarSchedule.minutesOfDay(from: newDate)
                guard minutes != feature.sunsetMinutes else { return }
                commitSunset(minutes)
            }
        )
    }

    private func date(from minutes: Int) -> Date {
        let wrapped = UmbrellaSolarSchedule.wrap(minutes)
        return Calendar.current.date(
            bySettingHour: wrapped / 60,
            minute: wrapped % 60,
            second: 0,
            of: Date()
        ) ?? Date()
    }

    private func twilightLabel(_ minutes: Int) -> String {
        switch minutes {
        case 60: return "1 hour"
        case 90: return "1.5 hours"
        case 120: return "2 hours"
        case 180: return "3 hours"
        case 240: return "4 hours"
        default:
            if minutes > 0, minutes % 60 == 0 {
                return "\(minutes / 60) hours"
            }
            return "\(minutes) min"
        }
    }

    private func scheduledSample(at minutes: Int) -> (brightness: Float, colorTemp: Int)? {
        guard let dayPreset, let nightPreset else { return nil }
        let progress = UmbrellaSolarSchedule.daylightProgress(
            at: minutes,
            sunrise: feature.sunriseMinutes,
            sunset: feature.sunsetMinutes,
            transition: feature.transitionMinutes
        )
        let brightness = nightPreset.brightness + (dayPreset.brightness - nightPreset.brightness) * progress
        let colorTemp = nightPreset.colorTemp + Int((Float(dayPreset.colorTemp - nightPreset.colorTemp) * progress).rounded())
        return (brightness, colorTemp)
    }

    private func presetMatchesDisplay(_ preset: UmbrellaSunPreset) -> Bool {
        let brightnessMatches = Int((feature.brightness * 100).rounded()) == Int((preset.brightness * 100).rounded())
        let temperatureMatches = nearestHundred(feature.colorTemp) == nearestHundred(preset.colorTemp)
        return brightnessMatches
            && temperatureMatches
            && feature.isDarkroom == preset.isDarkroom
            && feature.isFilmModeEnabled == preset.isFilmMode
    }

    private func nearestHundred(_ kelvin: Int) -> Int {
        Int((Double(kelvin) / 100).rounded()) * 100
    }

    private func snapFive(_ minutes: Int) -> Int {
        let snapped = Int((Double(minutes) / 5).rounded()) * 5
        return min(1435, max(0, snapped))
    }

    private func commitSunrise(_ minutes: Int) {
        let next = clampedSunrise(snapFive(minutes))
        guard next != feature.sunriseMinutes else { return }
        feature.updateSunrise(next)
    }

    private func commitSunset(_ minutes: Int) {
        let next = clampedSunset(snapFive(minutes))
        guard next != feature.sunsetMinutes else { return }
        feature.updateSunset(next)
    }

    /// Keeps sunrise and sunset at least two hours apart when the day fits on one clock.
    private func clampedSunrise(_ minutes: Int) -> Int {
        let lower = max(120, feature.transitionMinutes)
        let upper = feature.sunsetMinutes - 120
        guard upper >= lower else { return min(1439, max(0, minutes)) }
        return min(upper, max(lower, minutes))
    }

    private func clampedSunset(_ minutes: Int) -> Int {
        let lower = feature.sunriseMinutes + 120
        let upper = UmbrellaSolarSchedule.minutesPerDay - feature.transitionMinutes - 5
        guard upper >= lower else { return min(1439, max(0, minutes)) }
        return min(upper, max(lower, minutes))
    }

    private func togglePreset(_ id: String) {
        expandedPresetID = expandedPresetID == id ? nil : id
    }

    private func editPreset(_ id: String) {
        expandedPresetID = id
        nameSelectAll = false
        nameFocusID = id
    }

    private func saveCurrentSettingsAsPreset() {
        let id = feature.addPreset(name: uniqueNewPresetName())
        expandedPresetID = id
        nameSelectAll = true
        nameFocusID = id
        onPresetsChanged()
    }

    private func uniqueNewPresetName() -> String {
        var name = "New Preset"
        var index = 2
        while feature.presets.contains(where: { $0.name == name }) {
            name = "New Preset \(index)"
            index += 1
        }
        return name
    }

    private func requestDelete(_ preset: UmbrellaSunPreset) {
        guard feature.presets.count > 1 else { return }
        deletePrompt = PresetDeletePrompt(
            id: preset.id,
            title: "Delete “\(preset.name)”?",
            message: deleteMessage(for: preset)
        )
    }

    private func confirmDelete() {
        guard let prompt = deletePrompt else { return }
        deletePrompt = nil
        guard feature.removePreset(prompt.id) else { return }
        if expandedPresetID == prompt.id {
            expandedPresetID = nil
        }
        onPresetsChanged()
    }

    private func deleteMessage(for preset: UmbrellaSunPreset) -> String {
        let others = feature.presets.filter { $0.id != preset.id }
        let isDay = preset.id == feature.dayPresetID
        let isNight = preset.id == feature.nightPresetID
        guard (isDay || isNight), !others.isEmpty else {
            return "This can’t be undone."
        }
        var parts: [String] = []
        if isDay, let brightest = UmbrellaBrightnessFeature.brightestPreset(in: others) {
            parts.append("Day will switch to “\(brightest.name)”")
        }
        if isNight, let dimmest = UmbrellaBrightnessFeature.dimmestPreset(in: others) {
            parts.append("Night will switch to “\(dimmest.name)”")
        }
        guard !parts.isEmpty else { return "This can’t be undone." }
        return "The schedule uses this preset. \(parts.joined(separator: " and "))."
    }
}

private struct PresetDeletePrompt {
    var id: String
    var title: String
    var message: String
}

private struct SettingsSwitch: View {
    var title: String
    var caption: String?
    @Binding var isOn: Bool
    var isDisabled = false

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let caption, !caption.isEmpty {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .toggleStyle(.switch)
        .disabled(isDisabled)
    }
}

private struct PercentSliderRow: View {
    var title: String
    var percentText: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var onEditingChanged: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(percentText)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            HStack(spacing: 10) {
                Image(systemName: "sun.min")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(width: 16)
                    .accessibilityHidden(true)
                Slider(value: $value, in: range, onEditingChanged: onEditingChanged)
                    .accessibilityLabel(title)
                    .accessibilityValue(percentText)
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.tertiary)
                    .frame(width: 16)
                    .accessibilityHidden(true)
            }
        }
    }
}

private struct TemperatureSliderRow: View {
    var title: String
    var kelvinText: String
    @Binding var value: Double
    var isDisabled = false
    var onEditingChanged: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(kelvinText)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            HStack(spacing: 10) {
                Circle()
                    .fill(Color(red: 1, green: 0.478, blue: 0.102))
                    .frame(width: 9, height: 9)
                    .frame(width: 16)
                    .accessibilityHidden(true)
                Slider(
                    value: $value,
                    in: 1200...6500,
                    step: Double(UmbrellaBrightnessFeature.colorTempStep),
                    onEditingChanged: onEditingChanged
                )
                .disabled(isDisabled)
                .accessibilityLabel(title)
                .accessibilityValue(kelvinText)
                Circle()
                    .fill(Color(red: 0.933, green: 0.953, blue: 1))
                    .frame(width: 9, height: 9)
                    .frame(width: 16)
                    .accessibilityHidden(true)
            }
            HStack {
                Text("Warmer")
                Spacer()
                Text("Cooler")
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 26)
            .accessibilityHidden(true)
        }
    }
}

private struct PresetLibraryRow: View {
    @ObservedObject var feature: UmbrellaBrightnessFeature
    var presetID: String
    var isExpanded: Bool
    var wantsNameFocus: Bool
    var selectAllName: Bool
    var onToggle: () -> Void
    var onEdit: () -> Void
    var onConsumeNameFocus: () -> Void
    var onRequestDelete: () -> Void
    var onPresetsChanged: () -> Void

    @State private var nameDraft: String
    @State private var isHovering = false
    @State private var isAdjustingBrightness = false
    @State private var isAdjustingTemperature = false
    @FocusState private var nameFocused: Bool

    init(
        feature: UmbrellaBrightnessFeature,
        presetID: String,
        initialName: String,
        isExpanded: Bool,
        wantsNameFocus: Bool,
        selectAllName: Bool,
        onToggle: @escaping () -> Void,
        onEdit: @escaping () -> Void,
        onConsumeNameFocus: @escaping () -> Void,
        onRequestDelete: @escaping () -> Void,
        onPresetsChanged: @escaping () -> Void
    ) {
        _feature = ObservedObject(wrappedValue: feature)
        self.presetID = presetID
        self.isExpanded = isExpanded
        self.wantsNameFocus = wantsNameFocus
        self.selectAllName = selectAllName
        self.onToggle = onToggle
        self.onEdit = onEdit
        self.onConsumeNameFocus = onConsumeNameFocus
        self.onRequestDelete = onRequestDelete
        self.onPresetsChanged = onPresetsChanged
        _nameDraft = State(initialValue: initialName)
        _isHovering = State(initialValue: false)
        _isAdjustingBrightness = State(initialValue: false)
        _isAdjustingTemperature = State(initialValue: false)
    }

    private var preset: UmbrellaSunPreset? {
        feature.presets.first { $0.id == presetID }
    }

    var body: some View {
        if let preset {
            VStack(alignment: .leading, spacing: 0) {
                row(preset)
                if isExpanded {
                    editor(preset)
                        .padding(.bottom, 8)
                }
            }
        }
    }

    private func row(_ preset: UmbrellaSunPreset) -> some View {
        HStack(spacing: 8) {
            Button(action: onToggle) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(BrightnessSwatch.swatch(brightness: preset.brightness, kelvin: preset.colorTemp))
                        .frame(width: 16, height: 16)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 1))
                    Text(preset.name)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    badges(preset)
                    Spacer(minLength: 4)
                    Text(valueText(preset))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !isExpanded {
                Button("Apply") {
                    feature.applyPreset(id: preset.id)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .opacity(isHovering ? 1 : 0)
                .allowsHitTesting(isHovering)
            }

            presetMenu(preset)

            Button(action: onToggle) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .animation(.easeInOut(duration: 0.15), value: isExpanded)
                    .frame(width: 24, height: 22)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel(isExpanded ? "Close \(preset.name)" : "Edit \(preset.name)")
        }
        .frame(minHeight: 42)
        .onHover { isHovering = $0 }
    }

    private func badges(_ preset: UmbrellaSunPreset) -> some View {
        HStack(spacing: 4) {
            if preset.id == feature.dayPresetID {
                PresetBadge(title: "Day", tint: Color(red: 1, green: 0.84, blue: 0.04))
            }
            if preset.id == feature.nightPresetID {
                PresetBadge(title: "Night", tint: Color(red: 0.70, green: 0.69, blue: 1))
            }
            if feature.isMenuBarFavorite(preset.id) {
                PresetBadge(title: "Menu bar", tint: .secondary)
            }
        }
    }

    private func presetMenu(_ preset: UmbrellaSunPreset) -> some View {
        let menuBarFull = feature.menuBarFavoriteIDs.count >= UmbrellaBrightnessFeature.maxMenuBarFavorites
            && !feature.isMenuBarFavorite(preset.id)
        return Menu {
            Button("Apply") {
                feature.applyPreset(id: preset.id)
            }
            Button("Edit", action: onEdit)
            Button("Duplicate") {
                if feature.duplicatePreset(preset.id) != nil {
                    onPresetsChanged()
                }
            }
            Toggle("Show in Menu Bar", isOn: Binding(
                get: { feature.isMenuBarFavorite(preset.id) },
                set: { newValue in
                    guard newValue != feature.isMenuBarFavorite(preset.id) else { return }
                    _ = feature.toggleMenuBarFavorite(preset.id)
                }
            ))
            .disabled(menuBarFull)
            Divider()
            Button("Delete…", role: .destructive, action: onRequestDelete)
                .disabled(feature.presets.count <= 1)
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: 24, height: 22)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("More actions for \(preset.name)")
    }

    private func editor(_ preset: UmbrellaSunPreset) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if preset.id == feature.dayPresetID || preset.id == feature.nightPresetID {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "sun.max.fill")
                        .foregroundStyle(Color(red: 1, green: 0.84, blue: 0.04))
                    Text("Used as the schedule’s \(scheduleRole(preset)) level. Changes here update the curve.")
                        .font(.caption)
                        .foregroundStyle(Color(red: 1, green: 0.84, blue: 0.04))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 9)
            }

            editorLine {
                HStack {
                    Text("Name")
                    Spacer()
                    TextField("Name", text: $nameDraft)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                    .autocorrectionDisabled()
                    .focused($nameFocused)
                    .onAppear { focusNameIfNeeded() }
                    .onChange(of: wantsNameFocus) { _, _ in focusNameIfNeeded() }
                    .onChange(of: nameDraft) { _, newValue in
                        if newValue.count > 32 {
                            nameDraft = String(newValue.prefix(32))
                            return
                        }
                        commitName(newValue)
                    }
                    .onChange(of: nameFocused) { _, focused in
                        guard !focused else { return }
                        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.isEmpty {
                            nameDraft = "Untitled"
                        } else if trimmed != nameDraft {
                            nameDraft = trimmed
                        }
                    }
                }
            }

            PercentSliderRow(
                title: "Brightness",
                percentText: "\(Int((preset.brightness * 100).rounded()))%",
                value: Binding(
                    get: { Double(preset.brightness) },
                    set: { newValue in
                        guard isAdjustingBrightness else { return }
                        update(preset) { $0.brightness = Float(newValue) }
                    }
                ),
                range: Double(UmbrellaBrightnessFeature.minimumBrightness)...1,
                onEditingChanged: { isAdjustingBrightness = $0 }
            )
            .padding(.vertical, 8)

            TemperatureSliderRow(
                title: "Color temperature",
                kelvinText: "\(preset.colorTemp)K",
                value: Binding(
                    get: { Double(preset.colorTemp) },
                    set: { newValue in
                        guard isAdjustingTemperature else { return }
                        update(preset) { $0.colorTemp = Int(newValue.rounded()) }
                    }
                ),
                isDisabled: preset.isDarkroom,
                onEditingChanged: { isAdjustingTemperature = $0 }
            )
            .padding(.vertical, 4)

            editorLine {
                SettingsSwitch(
                    title: "Remove blue light",
                    caption: nil,
                    isOn: Binding(
                        get: { preset.isDarkroom },
                        set: { enabled in
                            update(preset) { $0.isDarkroom = enabled }
                        }
                    )
                )
            }

            editorLine {
                SettingsSwitch(
                    title: "Dim external displays only",
                    caption: "The built-in display is left unchanged.",
                    isOn: Binding(
                        get: { preset.isFilmMode },
                        set: { enabled in
                            update(preset) { $0.isFilmMode = enabled }
                        }
                    )
                )
            }

            editorLine {
                SettingsSwitch(
                    title: "Show in menu bar",
                    caption: menuBarCaption(for: preset),
                    isOn: Binding(
                        get: { feature.isMenuBarFavorite(preset.id) },
                        set: { newValue in
                            guard newValue != feature.isMenuBarFavorite(preset.id) else { return }
                            _ = feature.toggleMenuBarFavorite(preset.id)
                        }
                    ),
                    isDisabled: menuBarToggleDisabled(for: preset)
                )
            }

            HStack {
                Spacer()
                Button("Use Current Settings") {
                    update(preset) { updated in
                        updated.brightness = feature.brightness
                        updated.colorTemp = feature.colorTemp
                        updated.isDarkroom = feature.isDarkroom
                        updated.isFilmMode = feature.isFilmModeEnabled
                    }
                }
                Button("Apply") {
                    feature.applyPreset(id: preset.id)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 10)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .background(Color.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func editorLine<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            Divider()
            content()
                .padding(.vertical, 8)
        }
    }

    private func valueText(_ preset: UmbrellaSunPreset) -> String {
        "\(Int((preset.brightness * 100).rounded()))% · \(preset.colorTemp)K"
    }

    private func scheduleRole(_ preset: UmbrellaSunPreset) -> String {
        switch (preset.id == feature.dayPresetID, preset.id == feature.nightPresetID) {
        case (true, true): return "Day and Night"
        case (true, false): return "Day"
        case (false, true): return "Night"
        case (false, false): return "schedule"
        }
    }

    private func menuBarCaption(for preset: UmbrellaSunPreset) -> String {
        let count = feature.menuBarFavoriteIDs.count
        let maxCount = UmbrellaBrightnessFeature.maxMenuBarFavorites
        if menuBarToggleDisabled(for: preset) {
            return "Menu bar is full (\(maxCount) of \(maxCount)). Turn one off first."
        }
        return "\(count) of \(maxCount) shown"
    }

    private func menuBarToggleDisabled(for preset: UmbrellaSunPreset) -> Bool {
        feature.menuBarFavoriteIDs.count >= UmbrellaBrightnessFeature.maxMenuBarFavorites
            && !feature.isMenuBarFavorite(preset.id)
    }

    private func focusNameIfNeeded() {
        guard wantsNameFocus else { return }
        DispatchQueue.main.async {
            nameFocused = true
            if selectAllName {
                DispatchQueue.main.async {
                    NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                }
            }
            onConsumeNameFocus()
        }
    }

    private func commitName(_ raw: String) {
        guard var preset else { return }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let stored = trimmed.isEmpty ? "Untitled" : trimmed
        guard stored != preset.name else { return }
        preset.name = stored
        feature.updatePreset(preset)
        onPresetsChanged()
    }

    private func update(_ preset: UmbrellaSunPreset, _ mutate: (inout UmbrellaSunPreset) -> Void) {
        var updated = preset
        mutate(&updated)
        feature.updatePreset(updated)
        if updated.id == feature.dayPresetID || updated.id == feature.nightPresetID {
            feature.refreshAutoStateIfNeeded()
        }
    }
}

private struct PresetBadge: View {
    var title: String
    var tint: Color

    var body: some View {
        Text(title)
            .font(.system(size: 10.5))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .foregroundStyle(tint)
            .background(tint.opacity(0.18), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

private struct BrightnessScheduleGraph: View {
    var sunriseMinutes: Int
    var sunsetMinutes: Int
    var transitionMinutes: Int
    var nowMinutes: Int
    var dayPreset: UmbrellaSunPreset
    var nightPreset: UmbrellaSunPreset
    var presets: [UmbrellaSunPreset]
    @Binding var dayPresetID: String
    @Binding var nightPresetID: String
    var useLocation: Bool
    var showsNow: Bool
    var onSunrise: (Int) -> Void
    var onSunset: (Int) -> Void

    @State private var draggedHandle: ScheduleHandle?

    private let canvasHeight: CGFloat = 178
    private let plotTop: CGFloat = 34
    private let plotHeight: CGFloat = 104
    private let axisY: CGFloat = 138

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    drawSchedule(context: &context, size: size)
                }
                .frame(width: width, height: canvasHeight)
                .accessibilityLabel("Brightness schedule over 24 hours")
                .accessibilityValue(
                    UmbrellaSolarSchedule.statusText(
                        at: nowMinutes,
                        sunrise: sunriseMinutes,
                        sunset: sunsetMinutes,
                        transition: transitionMinutes
                    )
                )

                Color.clear
                    .frame(width: width, height: canvasHeight)
                    .contentShape(Rectangle())
                    .gesture(dragGesture(width: width))
                    .accessibilityHidden(true)

                pill(title: "DAY", accessibility: "Day preset, midday peak", selection: $dayPresetID)
                    .offset(dayPillOffset(width: width))
                pill(title: "NIGHT", accessibility: "Night preset, night floor", selection: $nightPresetID)
                    .offset(nightPillOffset(width: width))
            }
        }
        .frame(height: canvasHeight)
    }

    private func pill(title: String, accessibility: String, selection: Binding<String>) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            Picker(accessibility, selection: selection) {
                ForEach(presets) { preset in
                    Text(preset.name).tag(preset.id)
                }
            }
            .labelsHidden()
            .fixedSize()
            .controlSize(.small)
            .accessibilityLabel(accessibility)
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .frame(height: 24)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.17), lineWidth: 1))
        .fixedSize()
    }

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard !useLocation else { return }
                if draggedHandle == nil {
                    let sunriseDistance = abs(value.startLocation.x - xOf(sunriseMinutes, width: width))
                    let sunsetDistance = abs(value.startLocation.x - xOf(sunsetMinutes, width: width))
                    guard min(sunriseDistance, sunsetDistance) <= 22 else { return }
                    draggedHandle = sunriseDistance <= sunsetDistance ? .sunrise : .sunset
                }
                let minutes = minutesAt(x: value.location.x, width: width)
                switch draggedHandle {
                case .sunrise:
                    onSunrise(minutes)
                case .sunset:
                    onSunset(minutes)
                case nil:
                    break
                }
            }
            .onEnded { _ in
                draggedHandle = nil
            }
    }

    private func drawSchedule(context: inout GraphicsContext, size: CGSize) {
        let width = size.width
        guard width > 1 else { return }

        fillTwilight(context: &context, width: width, start: sunriseMinutes - transitionMinutes, end: sunriseMinutes)
        fillTwilight(context: &context, width: width, start: sunsetMinutes, end: sunsetMinutes + transitionMinutes)

        var axis = Path()
        axis.move(to: CGPoint(x: 0, y: axisY))
        axis.addLine(to: CGPoint(x: width, y: axisY))
        context.stroke(axis, with: .color(Color.primary.opacity(0.16)), lineWidth: 1)

        strokeMarker(context: &context, minutes: sunriseMinutes, width: width)
        strokeMarker(context: &context, minutes: sunsetMinutes, width: width)

        var curve = Path()
        let stops = stride(from: 0, through: UmbrellaSolarSchedule.minutesPerDay, by: 5)
        for (index, minute) in stops.enumerated() {
            let point = CGPoint(
                x: xOf(minute, width: width),
                y: yOf(brightness: curveBrightness(at: minute))
            )
            if index == 0 {
                curve.move(to: point)
            } else {
                curve.addLine(to: point)
            }
        }

        var fill = curve
        fill.addLine(to: CGPoint(x: width, y: axisY))
        fill.addLine(to: CGPoint(x: 0, y: axisY))
        fill.closeSubpath()

        let gradient = Gradient(stops: temperatureStops())
        let shading = GraphicsContext.Shading.linearGradient(
            gradient,
            startPoint: CGPoint(x: 0, y: 0),
            endPoint: CGPoint(x: width, y: 0)
        )
        var faded = context
        faded.opacity = 0.34
        faded.fill(fill, with: shading)
        context.stroke(curve, with: shading, style: StrokeStyle(lineWidth: 2, lineJoin: .round))

        if showsNow {
            let nowPoint = CGPoint(
                x: xOf(nowMinutes, width: width),
                y: yOf(brightness: curveBrightness(at: nowMinutes))
            )
            let tint = BrightnessSwatch.kelvinColor(curveTemperature(at: nowMinutes))
            let halo = Path(ellipseIn: CGRect(x: nowPoint.x - 8, y: nowPoint.y - 8, width: 16, height: 16))
            context.fill(halo, with: .color(tint.opacity(0.22)))
            let dot = Path(ellipseIn: CGRect(x: nowPoint.x - 4.5, y: nowPoint.y - 4.5, width: 9, height: 9))
            context.fill(dot, with: .color(tint))
            context.stroke(dot, with: .color(Color(white: 0.12)), lineWidth: 1.5)
        }

        drawHandle(context: &context, minutes: sunriseMinutes, handle: .sunrise, width: width)
        drawHandle(context: &context, minutes: sunsetMinutes, handle: .sunset, width: width)

        drawLabel(context: &context, title: "Sunrise", minutes: sunriseMinutes, width: width)
        let midday = UmbrellaSolarSchedule.middayMinutes(sunrise: sunriseMinutes, sunset: sunsetMinutes)
        if abs(xOf(midday, width: width) - xOf(sunriseMinutes, width: width)) > 108 {
            drawLabel(context: &context, title: "Midday", minutes: midday, width: width)
        }
        drawLabel(context: &context, title: "Sunset", minutes: sunsetMinutes, width: width)
    }

    private func fillTwilight(context: inout GraphicsContext, width: CGFloat, start: Int, end: Int) {
        let startWrapped = UmbrellaSolarSchedule.wrap(start)
        let endWrapped = UmbrellaSolarSchedule.wrap(end)
        let y = plotTop - 8
        let height = axisY - y
        func fill(from startMinute: Int, to endMinute: Int) {
            let x0 = xOf(startMinute, width: width)
            let x1 = endMinute >= UmbrellaSolarSchedule.minutesPerDay
                ? width
                : xOf(endMinute, width: width)
            guard x1 > x0 else { return }
            let rect = Path(CGRect(x: x0, y: y, width: x1 - x0, height: height))
            context.fill(rect, with: .color(Color.primary.opacity(0.04)))
        }
        if startWrapped <= endWrapped {
            fill(from: startWrapped, to: endWrapped)
        } else {
            fill(from: startWrapped, to: UmbrellaSolarSchedule.minutesPerDay)
            fill(from: 0, to: endWrapped)
        }
    }

    private func strokeMarker(context: inout GraphicsContext, minutes: Int, width: CGFloat) {
        var line = Path()
        let x = xOf(minutes, width: width)
        line.move(to: CGPoint(x: x, y: plotTop - 8))
        line.addLine(to: CGPoint(x: x, y: axisY))
        context.stroke(
            line,
            with: .color(Color.primary.opacity(0.22)),
            style: StrokeStyle(lineWidth: 1, dash: [2, 3])
        )
    }

    private func drawHandle(context: inout GraphicsContext, minutes: Int, handle: ScheduleHandle, width: CGFloat) {
        let x = xOf(minutes, width: width)
        if useLocation {
            let dot = Path(ellipseIn: CGRect(x: x - 3, y: axisY - 3, width: 6, height: 6))
            context.fill(dot, with: .color(Color.white.opacity(0.45)))
            return
        }
        let grip = Path(
            roundedRect: CGRect(x: x - 4, y: axisY - 7, width: 8, height: 14),
            cornerRadius: 3
        )
        let active = draggedHandle == handle
        context.fill(grip, with: .color(active ? Color.white : Color(white: 0.9)))
        context.stroke(grip, with: .color(Color.black.opacity(0.5)), lineWidth: 0.5)
    }

    private func drawLabel(context: inout GraphicsContext, title: String, minutes: Int, width: CGFloat) {
        let inset = min(52, width * 0.18)
        let x = min(max(xOf(minutes, width: width), inset), max(inset, width - inset))
        context.draw(
            Text("\(title) \(timeLabel(minutes))")
                .font(.caption2)
                .foregroundColor(.secondary),
            at: CGPoint(x: x, y: axisY + 6),
            anchor: .top
        )
    }

    private func temperatureStops() -> [Gradient.Stop] {
        stride(from: 0, through: UmbrellaSolarSchedule.minutesPerDay, by: 30).map { minute in
            Gradient.Stop(
                color: BrightnessSwatch.kelvinColor(curveTemperature(at: minute)),
                location: Double(minute) / Double(UmbrellaSolarSchedule.minutesPerDay)
            )
        }
    }

    private func dayPillOffset(width: CGFloat) -> CGSize {
        let midday = UmbrellaSolarSchedule.middayMinutes(sunrise: sunriseMinutes, sunset: sunsetMinutes)
        let widthEstimate = pillWidth(named: presets.first { $0.id == dayPresetID }?.name ?? dayPreset.name)
        let x = min(max(0, xOf(midday, width: width) - widthEstimate / 2), max(0, width - widthEstimate))
        let y = max(0, yOf(brightness: CGFloat(dayPreset.brightness)) - 32)
        return CGSize(width: x, height: y)
    }

    private func nightPillOffset(width: CGFloat) -> CGSize {
        let dawn = UmbrellaSolarSchedule.wrap(sunriseMinutes - transitionMinutes)
        let dusk = UmbrellaSolarSchedule.wrap(sunsetMinutes + transitionMinutes)
        let centerX: CGFloat
        if dawn <= dusk {
            let leftSpan = xOf(dawn, width: width)
            let rightSpan = width - xOf(dusk, width: width)
            centerX = leftSpan >= rightSpan ? leftSpan / 2 : (xOf(dusk, width: width) + width) / 2
        } else {
            centerX = (xOf(dusk, width: width) + xOf(dawn, width: width)) / 2
        }
        let widthEstimate = pillWidth(named: presets.first { $0.id == nightPresetID }?.name ?? nightPreset.name)
        let x = min(max(0, centerX - widthEstimate / 2), max(0, width - widthEstimate))
        let y = max(0, yOf(brightness: CGFloat(nightPreset.brightness)) - 32)
        return CGSize(width: x, height: y)
    }

    private func pillWidth(named name: String) -> CGFloat {
        CGFloat(name.count) * 7.2 + 70
    }

    private func curveBrightness(at minutes: Int) -> CGFloat {
        let progress = CGFloat(
            UmbrellaSolarSchedule.daylightProgress(
                at: minutes,
                sunrise: sunriseMinutes,
                sunset: sunsetMinutes,
                transition: transitionMinutes
            )
        )
        let night = CGFloat(nightPreset.brightness)
        let day = CGFloat(dayPreset.brightness)
        return night + (day - night) * progress
    }

    private func curveTemperature(at minutes: Int) -> Int {
        let progress = UmbrellaSolarSchedule.daylightProgress(
            at: minutes,
            sunrise: sunriseMinutes,
            sunset: sunsetMinutes,
            transition: transitionMinutes
        )
        return nightPreset.colorTemp + Int((Float(dayPreset.colorTemp - nightPreset.colorTemp) * progress).rounded())
    }

    private func yOf(brightness: CGFloat) -> CGFloat {
        plotTop + (1 - min(max(brightness, 0), 1)) * plotHeight
    }

    private func xOf(_ minutes: Int, width: CGFloat) -> CGFloat {
        if minutes >= UmbrellaSolarSchedule.minutesPerDay {
            return width
        }
        let wrapped = UmbrellaSolarSchedule.wrap(minutes)
        return CGFloat(wrapped) / CGFloat(UmbrellaSolarSchedule.minutesPerDay) * width
    }

    private func minutesAt(x: CGFloat, width: CGFloat) -> Int {
        let ratio = min(1, max(0, x / max(width, 1)))
        return Int((ratio * Double(UmbrellaSolarSchedule.minutesPerDay) / 5).rounded()) * 5
    }

    private func timeLabel(_ minutes: Int) -> String {
        let wrapped = UmbrellaSolarSchedule.wrap(minutes)
        let date = Calendar.current.date(
            bySettingHour: wrapped / 60,
            minute: wrapped % 60,
            second: 0,
            of: Date()
        ) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    private enum ScheduleHandle {
        case sunrise
        case sunset
    }
}

private enum BrightnessSwatch {
    static func kelvinColor(_ kelvin: Int) -> Color {
        let (red, green, blue) = rgb(kelvin)
        return Color(red: red / 255, green: green / 255, blue: blue / 255)
    }

    static func swatch(brightness: Float, kelvin: Int) -> Color {
        let (red, green, blue) = rgb(kelvin)
        let scale = 0.3 + 0.7 * Double(min(max(brightness, 0), 1))
        return Color(
            red: red / 255 * scale,
            green: green / 255 * scale,
            blue: blue / 255 * scale
        )
    }

    private static func rgb(_ kelvin: Int) -> (Double, Double, Double) {
        let t = Double(max(1200, min(6500, kelvin))) / 100
        let red: Double
        let green: Double
        if t <= 66 {
            red = 255
            green = 99.4708025861 * log(t) - 161.1195681661
        } else {
            red = 329.698727446 * pow(t - 60, -0.1332047592)
            green = 288.1221695283 * pow(t - 60, -0.0755148492)
        }
        let blue: Double
        if t >= 66 {
            blue = 255
        } else if t <= 19 {
            blue = 0
        } else {
            blue = 138.5177312231 * log(t - 10) - 305.0447927307
        }
        func clamp(_ value: Double) -> Double { min(255, max(0, value)) }
        return (clamp(red), clamp(green), clamp(blue))
    }
}
