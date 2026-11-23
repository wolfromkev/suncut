import AppKit
import SwiftUI

struct BrightnessSettingsTab: View {
    @ObservedObject var feature: UmbrellaBrightnessFeature
    var onPresetsChanged: () -> Void

    @State private var expandedPresetID: String?
    /// Preset whose row title is showing the brief "Saved" confirmation.
    @State private var savedFlashPresetID: String?
    /// Bumps on every Save so an older flash cannot clear a newer one.
    @State private var savedFlashToken = 0
    @State private var nameFocusID: String?
    @State private var nameSelectAll = false
    @State private var deletePrompt: PresetDeletePrompt?
    @State private var openControlID: String?
    @State private var controlAnchors: [String: CGRect] = [:]
    @State private var sunriseDraft = ""
    @State private var sunsetDraft = ""
    @FocusState private var focusedTime: ScheduleTimeField?

    var body: some View {
        ZStack(alignment: .topLeading) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    displaySection
                    scheduleSection
                    presetsSection
                    powerSection
                }
                .padding(.top, 22)
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollContentBackground(.hidden)
            .background(BrightnessChrome.window)

            if feature.isAutoMode,
               let openControlID,
               let anchor = controlAnchors[openControlID] {
                controlMenuLayer(id: openControlID, anchor: anchor)
            }

            if let deletePrompt {
                DeletePresetSheet(
                    title: deletePrompt.title,
                    message: deletePrompt.message,
                    onCancel: { self.deletePrompt = nil },
                    onDelete: confirmDelete
                )
            }
        }
        .coordinateSpace(name: "brightnessTab")
        .environment(\.colorScheme, .dark)
        .tint(BrightnessChrome.accent)
        .onPreferenceChange(BrightnessControlAnchorKey.self) { controlAnchors = $0 }
        .onExitCommand {
            if deletePrompt != nil {
                deletePrompt = nil
            } else if openControlID != nil {
                openControlID = nil
            }
        }
        .task(id: savedFlashToken) {
            let token = savedFlashToken
            guard savedFlashPresetID != nil else { return }
            do {
                try await Task.sleep(nanoseconds: 1_500_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled, savedFlashToken == token else { return }
            savedFlashPresetID = nil
        }
    }

    @ViewBuilder
    private var displaySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            groupedHeader("Display")
            if let pause = feature.schedulePause {
                schedulePauseBanner(pause)
            }
            groupedBox {
                groupRow(stacked: true, divider: false) {
                    PercentSliderRow(
                        title: "Brightness",
                        percentText: "\(displayPercent)%",
                        value: Binding(
                            get: { Double(feature.brightness) },
                            set: { feature.setBrightness(Float($0), commit: false) }
                        ),
                        range: Double(UmbrellaBrightnessFeature.minimumBrightness)...1,
                        onEditingChanged: { editing in
                            if !editing { feature.commitPendingChanges() }
                        }
                    )
                }
                groupRow(stacked: true) {
                    TemperatureSliderRow(
                        title: "Color temperature",
                        kelvinText: "\(feature.colorTemp)K",
                        value: Binding(
                            get: { Double(feature.colorTemp) },
                            set: { feature.setColorTemp(Int($0.rounded()), commit: false) }
                        ),
                        isDisabled: feature.isDarkroom,
                        onEditingChanged: { editing in
                            if !editing { feature.commitPendingChanges() }
                        }
                    )
                }
                groupRow {
                    presetChipsRow
                }
                groupRow {
                    SettingsSwitch(
                        title: "Remove blue light",
                        caption: nil,
                        isOn: Binding(
                            get: { feature.isDarkroom },
                            set: { feature.setDarkroom($0) }
                        )
                    )
                }
            }
            HStack {
                Spacer()
                Button("Restore Display Color") {
                    feature.restoreDisplayColor()
                }
                .buttonStyle(MockChromeButtonStyle())
                .help("Reset system display color, then re-apply current Suncut settings.")
            }
        }
    }

    private var presetChipsRow: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Menu Bar Presets")
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
                    .fill(BrightnessSwatch.swatch(for: preset))
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
        VStack(alignment: .leading, spacing: 8) {
            groupedHeader("Schedule")
            groupedBox {
            groupRow(divider: false) {
            SettingsSwitch(
                title: "Automatic brightness",
                caption: "Follows the curve below: dim at night, brightest at midday. Adjusting the Display controls pauses it until the next sunrise or sunset.",
                isOn: Binding(
                    get: { feature.isAutoMode },
                    set: { feature.setAutoMode($0) }
                )
            )
            }

            groupRow(stacked: true) {
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
                            openControlID: openControlID,
                            onSunrise: commitSunrise,
                            onSunset: commitSunset,
                            onOpenControl: toggleControl
                        )
                    }
                }
            }
            .modifier(ScheduleBodyFade(isAutomatic: feature.isAutoMode))
            }

            groupRow {
            SettingsSwitch(
                title: "Use location for sunrise and sunset",
                caption: locationCaption,
                isOn: Binding(
                    get: { feature.useLocationSchedule },
                    set: { feature.setUseLocationSchedule($0) }
                )
            )
            .modifier(ScheduleBodyFade(isAutomatic: feature.isAutoMode))
            }

            groupRow {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sunrise and sunset")
                    Text(feature.useLocationSchedule ? "Set by your location." : "Or drag the handles on the graph.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                timeField("Sunrise", minutes: feature.sunriseMinutes, field: .sunrise, commit: commitSunrise)
                timeField("Sunset", minutes: feature.sunsetMinutes, field: .sunset, commit: commitSunset)
            }
            .onChange(of: focusedTime) { old, _ in
                if old == .sunrise { commitTimeDraft(.sunrise) }
                if old == .sunset { commitTimeDraft(.sunset) }
            }
            .modifier(ScheduleBodyFade(isAutomatic: feature.isAutoMode))
            }

            groupRow {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Twilight")
                    Text("How long brightness ramps before sunrise and after sunset. Shaded on the graph.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                MockPopupButton(
                    title: twilightLabel(feature.transitionMinutes),
                    isOpen: openControlID == "twilight",
                    action: { toggleControl("twilight") }
                )
                .background(controlAnchor("twilight"))
            }
            .modifier(ScheduleBodyFade(isAutomatic: feature.isAutoMode))
            }
            }
        }
    }

    private func scheduleStatus(at minutes: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(feature.isAutoMode
                ? BrightnessScheduleCopy.phaseText(
                    at: minutes,
                    sunrise: feature.sunriseMinutes,
                    sunset: feature.sunsetMinutes,
                    transition: feature.transitionMinutes
                )
                : "Off · Brightness stays where you set it"
            )
            Spacer(minLength: 12)
            if feature.isAutoMode, let pause = feature.schedulePause {
                Text("Paused until \(pause.resumeDate.formatted(date: .omitted, time: .shortened))")
                    .foregroundStyle(.orange)
                    .monospacedDigit()
            } else if feature.isAutoMode, let sample = scheduledSample(at: minutes) {
                Text("Now \(Int((sample.brightness * 100).rounded()))% · \(sample.colorLabel)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .font(.system(size: 12))
    }

    @ViewBuilder
    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            groupedHeader("Presets")
            groupedBox {
            ForEach(feature.presets) { preset in
                groupRow(
                    top: 0,
                    bottom: 0,
                    minHeight: 0,
                    leading: 0,
                    trailing: 0,
                    divider: preset.id != feature.presets.first?.id
                ) {
                PresetLibraryRow(
                    feature: feature,
                    presetID: preset.id,
                    initialName: preset.name,
                    isExpanded: expandedPresetID == preset.id,
                    showsSavedConfirmation: savedFlashPresetID == preset.id,
                    wantsNameFocus: nameFocusID == preset.id,
                    selectAllName: nameSelectAll && nameFocusID == preset.id,
                    onToggle: { togglePreset(preset.id) },
                    onApply: { feature.applyPreset(id: preset.id) },
                    onDelete: { requestDelete(preset) },
                    onSave: { saveExpandedPreset(preset.id) },
                    onConsumeNameFocus: {
                        nameFocusID = nil
                        nameSelectAll = false
                    },
                    onPresetsChanged: onPresetsChanged
                )
                }
            }

            groupRow(top: 11, bottom: 11, minHeight: 0, divider: !feature.presets.isEmpty) {
            Button(action: saveCurrentSettingsAsPreset) {
                Label("Save Current Settings as Preset", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            }
            }
        }
    }

    private var powerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            groupedHeader("Power")
            groupedBox {
                groupRow(divider: false) {
                    SettingsSwitch(
                        title: "Keep Awake",
                        caption: nil,
                        isOn: Binding(
                            get: { feature.isKeepAwakeEnabled },
                            set: { feature.setKeepAwake($0) }
                        )
                    )
                }
            }
        }
    }

    private func groupedHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(BrightnessChrome.text)
            .padding(.leading, 2)
    }

    private func groupedBox<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(BrightnessChrome.group, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
        )
    }

    private func groupRow<Content: View>(
        stacked: Bool = false,
        top: CGFloat? = nil,
        bottom: CGFloat? = nil,
        minHeight: CGFloat? = nil,
        leading: CGFloat = 14,
        trailing: CGFloat = 14,
        divider: Bool = true,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(.leading, leading)
            .padding(.trailing, trailing)
            .padding(.top, top ?? (stacked ? 11 : 10))
            .padding(.bottom, bottom ?? (stacked ? 12 : 10))
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: minHeight ?? (stacked ? 0 : 42))
            .overlay(alignment: .top) {
                if divider {
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 1)
                        .padding(.horizontal, 14)
                }
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
        feature.useLocationSchedule
            ? "Updated daily from your location."
            : "Times are set by hand below."
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

    private func toggleControl(_ id: String) {
        openControlID = openControlID == id ? nil : id
    }

    private func timeField(
        _ title: String,
        minutes: Int,
        field: ScheduleTimeField,
        commit: @escaping (Int) -> Void
    ) -> some View {
        let editable = !feature.useLocationSchedule
        return HStack(spacing: 7) {
            Text(title)
                .foregroundStyle(BrightnessChrome.secondaryText)
            TextField(title, text: timeDraft(field, minutes: minutes))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .multilineTextAlignment(.center)
                .frame(width: 84, height: 24)
                .padding(.horizontal, 7)
                .foregroundStyle(BrightnessChrome.text)
                .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(
                            focusedTime == field ? BrightnessChrome.accent : Color.white.opacity(0.12),
                            lineWidth: focusedTime == field ? 2 : 1
                        )
                )
                .focused($focusedTime, equals: field)
                .onSubmit { commitTimeDraft(field) }
                .accessibilityLabel(title)
                .accessibilityValue(timeText(minutes))
                .accessibilityAdjustableAction { direction in
                    guard editable else { return }
                    let delta = direction == .increment ? 5 : -5
                    commit(minutes + delta)
                }
        }
        .opacity(editable ? 1 : 0.55)
        .allowsHitTesting(editable)
    }

    private func timeDraft(_ field: ScheduleTimeField, minutes: Int) -> Binding<String> {
        Binding(
            get: {
                if focusedTime == field {
                    return field == .sunrise ? sunriseDraft : sunsetDraft
                }
                return timeText(minutes)
            },
            set: { newValue in
                if field == .sunrise {
                    sunriseDraft = newValue
                } else {
                    sunsetDraft = newValue
                }
            }
        )
    }

    private func commitTimeDraft(_ field: ScheduleTimeField) {
        let text = field == .sunrise ? sunriseDraft : sunsetDraft
        guard let minutes = minutes(fromTime: text) else { return }
        if field == .sunrise {
            commitSunrise(minutes)
            sunriseDraft = timeText(feature.sunriseMinutes)
        } else {
            commitSunset(minutes)
            sunsetDraft = timeText(feature.sunsetMinutes)
        }
    }

    private func minutes(fromTime text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let short = DateFormatter()
        short.locale = .current
        short.timeStyle = .short
        short.dateStyle = .none
        if let date = short.date(from: trimmed) {
            return UmbrellaSolarSchedule.minutesOfDay(from: date)
        }
        let formats = ["h:mm a", "hh:mm a", "H:mm", "HH:mm"]
        for format in formats {
            let parser = DateFormatter()
            parser.locale = .current
            parser.dateFormat = format
            if let date = parser.date(from: trimmed) {
                return UmbrellaSolarSchedule.minutesOfDay(from: date)
            }
        }
        return nil
    }

    private func timeText(_ minutes: Int) -> String {
        date(from: minutes).formatted(date: .omitted, time: .shortened)
    }

    private func controlAnchor(_ id: String) -> some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: BrightnessControlAnchorKey.self,
                value: [id: proxy.frame(in: .named("brightnessTab"))]
            )
        }
    }

    private func controlMenuLayer(id: String, anchor: CGRect) -> some View {
        let choices = controlChoices(id)
        let menuHeight = min(240, CGFloat(max(choices.count, 1)) * 28 + 12)
        return GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { openControlID = nil }
                Button(action: { openControlID = nil }) {
                    EmptyView()
                }
                .keyboardShortcut(.cancelAction)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
                BrightnessChoiceMenu(choices: choices) { choice in
                    applyControlChoice(id, choice: choice)
                }
                .frame(width: 220, height: menuHeight)
                .offset(controlMenuOffset(anchor: anchor, in: geo.size, menuHeight: menuHeight))
            }
        }
    }

    private func controlChoices(_ id: String) -> [BrightnessChoice] {
        switch id {
        case "twilight":
            return twilightChoices.map { minutes in
                BrightnessChoice(
                    id: "\(minutes)",
                    title: twilightLabel(minutes),
                    isSelected: minutes == feature.transitionMinutes
                )
            }
        case "day", "night", "night-leading", "night-trailing":
            let selected = id == "day" ? feature.dayPresetID : feature.nightPresetID
            return feature.presets.map { preset in
                BrightnessChoice(id: preset.id, title: preset.name, isSelected: preset.id == selected)
            }
        default:
            return []
        }
    }

    private func applyControlChoice(_ id: String, choice: BrightnessChoice) {
        switch id {
        case "twilight":
            if let minutes = Int(choice.id) {
                twilightSelection.wrappedValue = minutes
            }
        case "day":
            feature.dayPresetID = choice.id
            feature.refreshAutoStateIfNeeded()
        case "night", "night-leading", "night-trailing":
            feature.nightPresetID = choice.id
            feature.refreshAutoStateIfNeeded()
        default:
            break
        }
        openControlID = nil
    }

    private func controlMenuOffset(anchor: CGRect, in size: CGSize, menuHeight: CGFloat) -> CGSize {
        let menuWidth: CGFloat = 220
        let x = min(max(8, anchor.minX), max(8, size.width - menuWidth - 8))
        var y = anchor.maxY + 4
        if y + menuHeight > size.height - 8 {
            y = max(8, anchor.minY - menuHeight - 4)
        }
        return CGSize(width: x, height: y)
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

    private func scheduledSample(at minutes: Int) -> (brightness: Float, colorLabel: String)? {
        guard let dayPreset, let nightPreset else { return nil }
        let progress = UmbrellaSolarSchedule.daylightProgress(
            at: minutes,
            sunrise: feature.sunriseMinutes,
            sunset: feature.sunsetMinutes,
            transition: feature.transitionMinutes
        )
        let brightness = nightPreset.brightness + (dayPreset.brightness - nightPreset.brightness) * progress
        let colorTemp = nightPreset.colorTemp + Int((Float(dayPreset.colorTemp - nightPreset.colorTemp) * progress).rounded())
        return (brightness, "\(colorTemp)K")
    }

    private func presetMatchesDisplay(_ preset: UmbrellaSunPreset) -> Bool {
        let brightnessMatches = Int((feature.brightness * 100).rounded()) == Int((preset.brightness * 100).rounded())
        guard feature.isDarkroom == preset.isDarkroom else { return false }
        let temperatureMatches = nearestHundred(feature.colorTemp) == nearestHundred(preset.colorTemp)
        return brightnessMatches && temperatureMatches
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

    /// Save still applies the open preset. Gamma uses brightness, color temperature,
    /// and blue light. The dot color stays on the swatch and is not applied to the display.
    /// The editor then closes, and "Saved" shows beside that preset's name for 1.5 seconds.
    private func saveExpandedPreset(_ id: String) {
        feature.applyPreset(id: id)
        if expandedPresetID == id {
            expandedPresetID = nil
        }
        savedFlashPresetID = id
        savedFlashToken += 1
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

    private func schedulePauseBanner(_ pause: UmbrellaSchedulePause) -> some View {
        let time = pause.resumeDate.formatted(date: .omitted, time: .shortened)
        let when = pause.isTomorrow ? "\(pause.eventName) tomorrow" : pause.eventName
        return HStack(spacing: 10) {
            Image(systemName: "pause.circle")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            (Text("Manual adjustment. ").bold() + Text("The schedule resumes at \(when) (\(time))."))
                .font(.system(size: 12))
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Resume Schedule") {
                feature.resumeSchedule()
            }
            .buttonStyle(MockChromeButtonStyle(kind: .small))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.11), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }

    private func requestDelete(_ preset: UmbrellaSunPreset) {
        guard feature.presets.count > 1 else { return }
        openControlID = nil
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
        Button {
            guard !isDisabled else { return }
            isOn.toggle()
        } label: {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(BrightnessChrome.text)
                    if let caption, !caption.isEmpty {
                        Text(caption)
                            .font(.system(size: 11))
                            .foregroundStyle(BrightnessChrome.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 16)
                MockSwitchTrack(isOn: isOn)
                    .opacity(isDisabled ? 0.35 : 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilityLabel: String {
        guard let caption, !caption.isEmpty else { return title }
        return "\(title). \(caption)"
    }
}

private struct MockSwitchTrack: View {
    var isOn: Bool

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(isOn ? BrightnessChrome.accent : Color.white.opacity(0.17))
            Circle()
                .fill(Color.white)
                .frame(width: 16, height: 16)
                .shadow(color: Color.black.opacity(0.45), radius: 1, y: 1)
                .offset(x: isOn ? 15 : 1)
        }
        .frame(width: 32, height: 18)
        .animation(.easeInOut(duration: 0.18), value: isOn)
    }
}

private struct MockChromeButtonStyle: ButtonStyle {
    enum Kind {
        case regular
        case small
        case primary
    }

    var kind: Kind = .regular

    func makeBody(configuration: Configuration) -> some View {
        MockChromeButtonBody(kind: kind, isPressed: configuration.isPressed) {
            configuration.label
        }
    }
}

private struct MockChromeButtonBody<Label: View>: View {
    var kind: MockChromeButtonStyle.Kind
    var isPressed: Bool
    @ViewBuilder var label: () -> Label
    @State private var hovering = false

    var body: some View {
        label()
            .font(.system(size: kind == .small ? 12 : 13))
            .foregroundStyle(kind == .primary ? Color.white : BrightnessChrome.text)
            .padding(.horizontal, kind == .small ? 9 : 11)
            .frame(height: kind == .small ? 22 : 24)
            .background(fill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.45), lineWidth: 0.5)
            )
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
                    .mask(alignment: .top) {
                        Rectangle().frame(height: 1)
                    }
            }
            .shadow(color: Color.black.opacity(0.3), radius: 1.5, y: 1)
            .onHover { hovering = $0 }
    }

    private var fill: Color {
        if kind == .primary {
            return isPressed || hovering
                ? Color(red: 36 / 255, green: 145 / 255, blue: 255 / 255)
                : BrightnessChrome.accent
        }
        if isPressed { return Color.white.opacity(0.22) }
        if hovering { return Color.white.opacity(0.16) }
        return Color.white.opacity(0.11)
    }
}

private struct PercentSliderRow: View {
    var title: String
    var percentText: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var onEditingChanged: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
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
                AccentRangeSlider(
                    value: $value,
                    range: range,
                    step: 0.01,
                    onEditingChanged: onEditingChanged
                )
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
        VStack(alignment: .leading, spacing: 7) {
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
                KelvinGradientSlider(
                    kelvin: Binding(
                        get: { Int(value.rounded()) },
                        set: { value = Double($0) }
                    ),
                    isEnabled: !isDisabled,
                    onEditingChanged: onEditingChanged
                )
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
    var showsSavedConfirmation: Bool
    var wantsNameFocus: Bool
    var selectAllName: Bool
    var onToggle: () -> Void
    var onApply: () -> Void
    var onDelete: () -> Void
    var onSave: () -> Void
    var onConsumeNameFocus: () -> Void
    var onPresetsChanged: () -> Void

    @State private var nameDraft: String
    @FocusState private var nameFocused: Bool

    init(
        feature: UmbrellaBrightnessFeature,
        presetID: String,
        initialName: String,
        isExpanded: Bool,
        showsSavedConfirmation: Bool,
        wantsNameFocus: Bool,
        selectAllName: Bool,
        onToggle: @escaping () -> Void,
        onApply: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onSave: @escaping () -> Void,
        onConsumeNameFocus: @escaping () -> Void,
        onPresetsChanged: @escaping () -> Void
    ) {
        _feature = ObservedObject(wrappedValue: feature)
        self.presetID = presetID
        self.isExpanded = isExpanded
        self.showsSavedConfirmation = showsSavedConfirmation
        self.wantsNameFocus = wantsNameFocus
        self.selectAllName = selectAllName
        self.onToggle = onToggle
        self.onApply = onApply
        self.onDelete = onDelete
        self.onSave = onSave
        self.onConsumeNameFocus = onConsumeNameFocus
        self.onPresetsChanged = onPresetsChanged
        _nameDraft = State(initialValue: initialName)
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
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                }
            }
        }
    }

    private func row(_ preset: UmbrellaSunPreset) -> some View {
        HStack(spacing: 0) {
            Button(action: { handleHeaderTap() }) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(BrightnessSwatch.swatch(for: preset))
                        .frame(width: 16, height: 16)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 1))
                    Text(preset.name)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if showsSavedConfirmation {
                        Text("Saved")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(BrightnessChrome.secondaryText)
                            .fixedSize(horizontal: true, vertical: false)
                            .layoutPriority(1)
                            .accessibilityHidden(true)
                    }
                    badges(preset)
                    Spacer(minLength: 4)
                    Text(valueText(preset))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .padding(.leading, 14)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(headerAccessibilityLabel(preset))
            .accessibilityValue(valueText(preset))
            .accessibilityHint(
                isExpanded
                    ? "Closes preset settings without changing the display"
                    : "Sets display brightness and color to this preset"
            )

            Button(action: onToggle) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .animation(.easeInOut(duration: 0.15), value: isExpanded)
                    .frame(width: 24, height: 22)
                    .padding(.leading, 8)
                    .padding(.trailing, 8)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel(isExpanded ? "Close \(preset.name) settings" : "Open \(preset.name) settings")
        }
        .frame(minHeight: 42)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func handleHeaderTap() {
        if isExpanded {
            onToggle()
        } else {
            onApply()
        }
    }

    private func headerAccessibilityLabel(_ preset: UmbrellaSunPreset) -> String {
        let base = isExpanded ? "Collapse \(preset.name)" : applyAccessibilityLabel(preset)
        guard showsSavedConfirmation else { return base }
        return "\(base), Saved"
    }

    private func applyAccessibilityLabel(_ preset: UmbrellaSunPreset) -> String {
        var parts = [preset.name]
        if preset.id == feature.dayPresetID { parts.append("Day") }
        if preset.id == feature.nightPresetID { parts.append("Night") }
        if feature.isMenuBarFavorite(preset.id) { parts.append("Menu bar") }
        return "Apply \(parts.joined(separator: ", "))"
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
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 7)
                    .frame(width: 220, height: 24)
                    .foregroundStyle(BrightnessChrome.text)
                    .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(
                                nameFocused ? BrightnessChrome.accent : Color.white.opacity(0.12),
                                lineWidth: nameFocused ? 2 : 1
                            )
                    )
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
                        update(preset) { $0.brightness = Float(newValue) }
                    }
                ),
                range: Double(UmbrellaBrightnessFeature.minimumBrightness)...1,
                onEditingChanged: { _ in }
            )
            .padding(.vertical, 8)

            TemperatureSliderRow(
                title: "Color temperature",
                kelvinText: "\(preset.colorTemp)K",
                value: Binding(
                    get: { Double(preset.colorTemp) },
                    set: { newValue in
                        update(preset) { updated in
                            updated.colorTemp = Int(newValue.rounded())
                        }
                    }
                ),
                isDisabled: preset.isDarkroom,
                onEditingChanged: { _ in }
            )
            .padding(.vertical, 4)

            editorLine {
                HStack(alignment: .center, spacing: 12) {
                    Text("Color")
                        .foregroundStyle(BrightnessChrome.text)
                    Spacer(minLength: 12)
                    if preset.customTint != nil {
                        Button("Clear") {
                            updateSwatch(preset) { $0.clearCustomTint() }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(BrightnessChrome.secondaryText)
                        .help("Use the color from the color temperature")
                        .accessibilityLabel("Clear color for \(preset.name)")
                    }
                    ColorPicker("Color", selection: colorBinding(for: preset), supportsOpacity: false)
                        .labelsHidden()
                        .accessibilityLabel("Color for \(preset.name)")
                        .help("Colors the dot next to the preset name. Does not change the screen.")
                }
            }

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

            HStack(spacing: 8) {
                Button(action: onDelete) {
                    Label("Delete Preset", systemImage: "trash")
                        .font(.system(size: 13))
                        .foregroundStyle(Color(red: 1, green: 69 / 255, blue: 58 / 255))
                }
                .buttonStyle(.plain)
                .disabled(feature.presets.count <= 1)
                .opacity(feature.presets.count > 1 ? 1 : 0.35)
                .help(feature.presets.count > 1 ? "Delete this preset" : "At least one preset is required")
                .accessibilityLabel("Delete \(preset.name)")
                Spacer(minLength: 8)
                Button("Save") {
                    commitName(nameDraft)
                    onSave()
                }
                .buttonStyle(MockChromeButtonStyle(kind: .primary))
                .accessibilityLabel("Save \(preset.name)")
                .accessibilityHint("Applies this preset to the display and closes the editor")
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
        "\(Int((preset.brightness * 100).rounded()))% · \(preset.colorSummary)"
    }

    private func colorBinding(for preset: UmbrellaSunPreset) -> Binding<Color> {
        Binding(
            get: { presetWellColor(preset) },
            set: { newValue in
                guard let srgb = NSColor(newValue).usingColorSpace(.sRGB) else { return }
                let red = Float(srgb.redComponent)
                let green = Float(srgb.greenComponent)
                let blue = Float(srgb.blueComponent)
                if let existing = preset.customTint,
                   abs(existing.0 - red) < 0.001,
                   abs(existing.1 - green) < 0.001,
                   abs(existing.2 - blue) < 0.001 {
                    return
                }
                if preset.customTint == nil {
                    let kelvin = BrightnessSwatch.components(kelvin: preset.colorTemp)
                    if abs(kelvin.0 - Double(red)) < 0.02,
                       abs(kelvin.1 - Double(green)) < 0.02,
                       abs(kelvin.2 - Double(blue)) < 0.02 {
                        return
                    }
                }
                updateSwatch(preset) { updated in
                    updated.setCustomTint(red: red, green: green, blue: blue)
                }
            }
        )
    }

    private func presetWellColor(_ preset: UmbrellaSunPreset) -> Color {
        if let tint = preset.customTint {
            return Color(red: Double(tint.0), green: Double(tint.1), blue: Double(tint.2))
        }
        return BrightnessSwatch.kelvinColor(preset.colorTemp)
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

    /// Writes the dot color only. Does not reapply display gamma.
    private func updateSwatch(_ preset: UmbrellaSunPreset, _ mutate: (inout UmbrellaSunPreset) -> Void) {
        var updated = preset
        mutate(&updated)
        feature.updatePreset(updated)
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

private struct ScheduleBodyFade: ViewModifier {
    var isAutomatic: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isAutomatic ? 1 : 0.38)
            .allowsHitTesting(isAutomatic)
            .animation(.easeInOut(duration: 0.2), value: isAutomatic)
    }
}

private struct SchedulePillSizeKey: PreferenceKey {
    static var defaultValue: [String: CGSize] = [:]

    static func reduce(value: inout [String: CGSize], nextValue: () -> [String: CGSize]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private enum BrightnessScheduleCopy {
    /// Phase lines from the settings mock. The curve itself stays `daylightProgress`.
    static func phaseText(at minutes: Int, sunrise: Int, sunset: Int, transition: Int) -> String {
        let dawn = UmbrellaSolarSchedule.wrap(sunrise - max(0, transition))
        let dusk = UmbrellaSolarSchedule.wrap(sunset + max(0, transition))
        let rise = UmbrellaSolarSchedule.wrap(sunrise)
        let set = UmbrellaSolarSchedule.wrap(sunset)
        let midday = UmbrellaSolarSchedule.middayMinutes(sunrise: sunrise, sunset: sunset)
        let span = UmbrellaSolarSchedule.forwardDistance(from: dawn, to: dusk)
        let elapsed = UmbrellaSolarSchedule.forwardDistance(from: dawn, to: UmbrellaSolarSchedule.wrap(minutes))
        if span == 0 || elapsed >= span {
            return "Night · Holding at the Night level"
        }
        func along(_ target: Int) -> Int {
            UmbrellaSolarSchedule.forwardDistance(from: dawn, to: target)
        }
        if elapsed < along(rise) {
            return "Dawn twilight · Starting to brighten"
        }
        if elapsed < along(UmbrellaSolarSchedule.wrap(midday - 45)) {
            return "Morning · Brightening toward midday"
        }
        if elapsed <= along(UmbrellaSolarSchedule.wrap(midday + 45)) {
            return "Midday · At the Day level"
        }
        if elapsed < along(set) {
            return "Afternoon · Easing down from midday"
        }
        return "Evening twilight · Dimming toward night"
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
    var openControlID: String?
    var onSunrise: (Int) -> Void
    var onSunset: (Int) -> Void
    var onOpenControl: (String) -> Void

    @State private var draggedHandle: ScheduleHandle?
    @State private var pillSizes: [String: CGSize] = [:]

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
                    BrightnessScheduleCopy.phaseText(
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

                pill(title: "DAY", accessibility: "Day preset, midday peak", sizeKey: "day", selection: $dayPresetID)
                    .offset(dayPillOffset(width: width))
                    .background(controlAnchor("day", offset: dayPillOffset(width: width)))
                ForEach(nightLabelPlacements(width: width)) { placement in
                    let offset = nightPillOffset(width: width, centerX: placement.centerX, sizeKey: placement.id)
                    pill(
                        title: "NIGHT",
                        accessibility: placement.accessibility,
                        sizeKey: placement.id,
                        selection: $nightPresetID
                    )
                    .offset(offset)
                    .background(controlAnchor(placement.id, offset: offset))
                }
            }
            .onPreferenceChange(SchedulePillSizeKey.self) { pillSizes = $0 }
        }
        .frame(height: canvasHeight)
    }

    private func pill(title: String, accessibility: String, sizeKey: String, selection: Binding<String>) -> some View {
        let selected = presets.first { $0.id == selection.wrappedValue }?.name ?? ""
        return Button {
            onOpenControl(sizeKey)
        } label: {
            HStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 9.5, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(BrightnessChrome.secondaryText)
                Text(selected)
                    .font(.system(size: 12))
                    .foregroundStyle(BrightnessChrome.text)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .padding(.leading, 4)
            }
            .padding(.leading, 9)
            .padding(.trailing, 8)
            .frame(height: 24)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: SchedulePillSizeKey.self,
                    value: [sizeKey: proxy.size]
                )
            }
        }
        .background(Color(red: 30 / 255, green: 30 / 255, blue: 30 / 255).opacity(0.94), in: Capsule())
        .overlay(
            Capsule().strokeBorder(
                openControlID == sizeKey ? BrightnessChrome.accent : Color.white.opacity(0.17),
                lineWidth: 1
            )
        )
        .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
        .accessibilityLabel(accessibility)
        .accessibilityValue(selected)
    }

    private func controlAnchor(_ id: String, offset: CGSize) -> some View {
        GeometryReader { proxy in
            let frame = proxy.frame(in: .named("brightnessTab"))
            let visual = CGRect(
                x: frame.minX + offset.width,
                y: frame.minY + offset.height,
                width: frame.width,
                height: frame.height
            )
            Color.clear.preference(
                key: BrightnessControlAnchorKey.self,
                value: [id: visual]
            )
        }
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
        fillCurve(fill, shading: shading, context: &context, width: width)
        context.stroke(curve, with: shading, style: StrokeStyle(lineWidth: 2, lineJoin: .round))

        if showsNow {
            let nowPoint = CGPoint(
                x: xOf(nowMinutes, width: width),
                y: yOf(brightness: curveBrightness(at: nowMinutes))
            )
            let tint = curveColor(at: nowMinutes)
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

    /// Kelvin fill at 34% opacity, masked so it fades smoothly from 90% at the top of the plot to 12% on the axis.
    private func fillCurve(
        _ fill: Path,
        shading: GraphicsContext.Shading,
        context: inout GraphicsContext,
        width: CGFloat
    ) {
        let fade = GraphicsContext.Shading.linearGradient(
            Gradient(stops: [
                Gradient.Stop(color: Color.white.opacity(0.9), location: 0),
                Gradient.Stop(color: Color.white.opacity(0.12), location: 1)
            ]),
            startPoint: CGPoint(x: 0, y: plotTop),
            endPoint: CGPoint(x: 0, y: axisY)
        )
        context.drawLayer { layer in
            layer.opacity = 0.34
            layer.fill(fill, with: shading)
            layer.opacity = 1
            layer.blendMode = .destinationIn
            layer.fill(
                Path(CGRect(x: 0, y: 0, width: width, height: canvasHeight)),
                with: fade
            )
        }
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
            context.stroke(dot, with: .color(Color.primary.opacity(0.35)), lineWidth: 1)
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
        let label = Text(title)
            .font(.system(size: 11))
            .foregroundColor(Color.primary.opacity(0.32))
            + Text(" \(timeLabel(minutes))")
            .font(.system(size: 11))
            .foregroundColor(Color.primary.opacity(0.55))
        context.draw(label, at: CGPoint(x: x, y: axisY + 16), anchor: .top)
    }

    private func temperatureStops() -> [Gradient.Stop] {
        stride(from: 0, through: UmbrellaSolarSchedule.minutesPerDay, by: 30).map { minute in
            Gradient.Stop(
                color: curveColor(at: minute),
                location: Double(minute) / Double(UmbrellaSolarSchedule.minutesPerDay)
            )
        }
    }

    private func curveColor(at minutes: Int) -> Color {
        BrightnessSwatch.kelvinColor(curveTemperature(at: minutes))
    }

    private func dayPillOffset(width: CGFloat) -> CGSize {
        let midday = UmbrellaSolarSchedule.middayMinutes(sunrise: sunriseMinutes, sunset: sunsetMinutes)
        let widthEstimate = measuredPillWidth("day", named: presets.first { $0.id == dayPresetID }?.name ?? dayPreset.name)
        let x = min(max(0, xOf(midday, width: width) - widthEstimate / 2), max(0, width - widthEstimate))
        let y = max(0, yOf(brightness: CGFloat(dayPreset.brightness)) - 32)
        return CGSize(width: x, height: y)
    }

    /// Night sits on both flats beside the daylight hump. When the day wraps past midnight,
    /// night is one span, so a single label stays on that span.
    private func nightLabelPlacements(width: CGFloat) -> [NightLabelPlacement] {
        let dawn = UmbrellaSolarSchedule.wrap(sunriseMinutes - transitionMinutes)
        let dusk = UmbrellaSolarSchedule.wrap(sunsetMinutes + transitionMinutes)
        if dawn <= dusk {
            let leftEdge = xOf(dawn, width: width)
            let rightEdge = xOf(dusk, width: width)
            return [
                NightLabelPlacement(
                    id: "night-leading",
                    centerX: leftEdge / 2,
                    accessibility: "Night preset before sunrise"
                ),
                NightLabelPlacement(
                    id: "night-trailing",
                    centerX: (rightEdge + width) / 2,
                    accessibility: "Night preset after sunset"
                )
            ]
        }
        return [
            NightLabelPlacement(
                id: "night",
                centerX: (xOf(dusk, width: width) + xOf(dawn, width: width)) / 2,
                accessibility: "Night preset, night floor"
            )
        ]
    }

    private func nightPillOffset(width: CGFloat, centerX: CGFloat, sizeKey: String) -> CGSize {
        let widthEstimate = measuredPillWidth(sizeKey, named: presets.first { $0.id == nightPresetID }?.name ?? nightPreset.name)
        let x = min(max(0, centerX - widthEstimate / 2), max(0, width - widthEstimate))
        let y = max(0, yOf(brightness: CGFloat(nightPreset.brightness)) - 32)
        return CGSize(width: x, height: y)
    }

    private func measuredPillWidth(_ key: String, named name: String) -> CGFloat {
        if let width = pillSizes[key]?.width, width > 1 {
            return width
        }
        return CGFloat(name.count) * 7.2 + 78
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
        let (red, green, blue) = components(kelvin: kelvin)
        return Color(red: red, green: green, blue: blue)
    }

    static func components(kelvin: Int) -> (Double, Double, Double) {
        let (red, green, blue) = rgb(kelvin)
        return (red / 255, green / 255, blue / 255)
    }

    static func swatch(brightness: Float, kelvin: Int) -> Color {
        let (red, green, blue) = rgb(kelvin)
        return scaled(red: red / 255, green: green / 255, blue: blue / 255, brightness: brightness)
    }

    static func swatch(for preset: UmbrellaSunPreset) -> Color {
        if let tint = preset.customTint {
            return scaled(
                red: Double(tint.0),
                green: Double(tint.1),
                blue: Double(tint.2),
                brightness: preset.brightness
            )
        }
        return swatch(brightness: preset.brightness, kelvin: preset.colorTemp)
    }

    private static func scaled(red: Double, green: Double, blue: Double, brightness: Float) -> Color {
        let scale = 0.3 + 0.7 * Double(min(max(brightness, 0), 1))
        return Color(red: red * scale, green: green * scale, blue: blue * scale)
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

private struct NightLabelPlacement: Identifiable {
    var id: String
    var centerX: CGFloat
    var accessibility: String
}

private enum BrightnessChrome {
    static let window = Color(red: 30 / 255, green: 30 / 255, blue: 30 / 255)
    static let group = Color(red: 40 / 255, green: 40 / 255, blue: 40 / 255)
    static let accent = Color(red: 10 / 255, green: 132 / 255, blue: 255 / 255)
    static let text = Color.white.opacity(0.88)
    static let secondaryText = Color.white.opacity(0.55)
}

private enum ScheduleTimeField: Hashable {
    case sunrise
    case sunset
}

private struct BrightnessChoice: Identifiable {
    var id: String
    var title: String
    var isSelected: Bool
}

private struct BrightnessControlAnchorKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private struct MockPopupButton: View {
    var title: String
    var isOpen: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(BrightnessChrome.text)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.75))
            }
            .padding(.leading, 10)
            .padding(.trailing, 8)
            .frame(height: 24)
            .background(Color.white.opacity(0.11), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(isOpen ? BrightnessChrome.accent : Color.black.opacity(0.45), lineWidth: isOpen ? 1 : 0.5)
            )
        }
        .buttonStyle(.plain)
        .fixedSize()
    }
}

private struct BrightnessChoiceMenu: View {
    var choices: [BrightnessChoice]
    var onSelect: (BrightnessChoice) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(choices) { choice in
                    Button {
                        onSelect(choice)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .semibold))
                                .frame(width: 14)
                                .opacity(choice.isSelected ? 1 : 0)
                            Text(choice.title)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .font(.system(size: 13))
                        .foregroundStyle(BrightnessChrome.text)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 44 / 255, green: 44 / 255, blue: 44 / 255), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.55), radius: 16, y: 8)
    }
}

private struct AccentRangeSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double
    var isEnabled = true
    var onEditingChanged: (Bool) -> Void

    private let thumbSize: CGFloat = 20

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, thumbSize)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.16))
                    .frame(height: 4)
                Capsule()
                    .fill(BrightnessChrome.accent)
                    .frame(width: max(4, thumbCenter(in: width)), height: 4)
                Circle()
                    .fill(Color(red: 0.949, green: 0.949, blue: 0.949))
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.45), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.5), radius: 1.5, y: 1)
                    .frame(width: thumbSize, height: thumbSize)
                    .offset(x: thumbOrigin(in: width))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(drag(in: width))
        }
        .frame(height: thumbSize)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityElement()
        .accessibilityAdjustableAction { direction in
            guard isEnabled else { return }
            let delta = direction == .increment ? step : -step
            onEditingChanged(true)
            value = snapped(value + delta)
            onEditingChanged(false)
        }
    }

    private func drag(in width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard isEnabled else { return }
                onEditingChanged(true)
                self.value = amount(at: value.location.x, width: width)
            }
            .onEnded { _ in
                guard isEnabled else { return }
                onEditingChanged(false)
            }
    }

    private func fraction(for amount: Double) -> CGFloat {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return CGFloat(min(max(0, (amount - range.lowerBound) / span), 1))
    }

    private func thumbOrigin(in width: CGFloat) -> CGFloat {
        fraction(for: value) * max(width - thumbSize, 1)
    }

    private func thumbCenter(in width: CGFloat) -> CGFloat {
        thumbOrigin(in: width) + thumbSize / 2
    }

    private func amount(at x: CGFloat, width: CGFloat) -> Double {
        let span = max(width - thumbSize, 1)
        let fraction = min(max(0, (x - thumbSize / 2) / span), 1)
        let raw = range.lowerBound + Double(fraction) * (range.upperBound - range.lowerBound)
        return snapped(raw)
    }

    private func snapped(_ raw: Double) -> Double {
        guard step > 0 else { return min(range.upperBound, max(range.lowerBound, raw)) }
        let steps = ((raw - range.lowerBound) / step).rounded()
        let value = range.lowerBound + steps * step
        return min(range.upperBound, max(range.lowerBound, value))
    }
}

private struct KelvinGradientSlider: View {
    @Binding var kelvin: Int
    var isEnabled = true
    var onEditingChanged: (Bool) -> Void

    private let minimum = 1200
    private let maximum = 6500
    private let thumbSize: CGFloat = 20

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, thumbSize)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(trackGradient)
                    .frame(height: 6)
                Circle()
                    .fill(Color(white: 0.95))
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.45), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.35), radius: 1, y: 1)
                    .frame(width: thumbSize, height: thumbSize)
                    .offset(x: thumbOrigin(in: width))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(drag(in: width))
        }
        .frame(height: thumbSize)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityElement()
        .accessibilityLabel("Color temperature")
        .accessibilityValue("\(kelvin)K")
        .accessibilityAdjustableAction { direction in
            guard isEnabled else { return }
            let delta = direction == .increment ? UmbrellaBrightnessFeature.colorTempStep : -UmbrellaBrightnessFeature.colorTempStep
            onEditingChanged(true)
            kelvin = snapped(kelvin + delta)
            onEditingChanged(false)
        }
    }

    private var trackGradient: LinearGradient {
        var stops = Array(stride(from: minimum, to: maximum, by: 500))
        stops.append(maximum)
        let colors = stops.map { BrightnessSwatch.kelvinColor($0) }
        return LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
    }

    private func drag(in width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard isEnabled else { return }
                onEditingChanged(true)
                kelvin = kelvin(at: value.location.x, width: width)
            }
            .onEnded { _ in
                guard isEnabled else { return }
                onEditingChanged(false)
            }
    }

    private func thumbOrigin(in width: CGFloat) -> CGFloat {
        let span = max(width - thumbSize, 1)
        let fraction = CGFloat(kelvin - minimum) / CGFloat(maximum - minimum)
        return min(max(0, fraction), 1) * span
    }

    private func kelvin(at x: CGFloat, width: CGFloat) -> Int {
        let span = max(width - thumbSize, 1)
        let fraction = min(max(0, (x - thumbSize / 2) / span), 1)
        let raw = Double(minimum) + Double(fraction) * Double(maximum - minimum)
        return snapped(Int(raw.rounded()))
    }

    private func snapped(_ value: Int) -> Int {
        let step = UmbrellaBrightnessFeature.colorTempStep
        let rounded = Int((Double(value) / Double(step)).rounded()) * step
        return min(maximum, max(minimum, rounded))
    }
}

private struct DeletePresetSheet: View {
    var title: String
    var message: String
    var onCancel: () -> Void
    var onDelete: () -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture(perform: onCancel)
                card
                    .padding(.top, geo.size.height * 0.18)
            }
        }
        .accessibilityAddTraits(.isModal)
    }

    private var card: some View {
        VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 1, green: 0.70, blue: 0.25), Color(red: 1, green: 0.48, blue: 0.10)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "sun.max.fill")
                            .foregroundStyle(.white)
                    )
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.88))
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)
                Text(message)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .lineSpacing(3)
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
                HStack(spacing: 8) {
                    sheetButton(
                        "Cancel",
                        fill: Color.white.opacity(0.11),
                        foreground: Color.white.opacity(0.88),
                        shortcut: .cancelAction,
                        action: onCancel
                    )
                    sheetButton(
                        "Delete",
                        fill: Color(red: 1, green: 69 / 255, blue: 58 / 255),
                        foreground: .white,
                        shortcut: .defaultAction,
                        action: onDelete
                    )
                }
                .padding(.top, 14)
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 14)
            .frame(width: 264)
            .background(Color(red: 44 / 255, green: 44 / 255, blue: 44 / 255), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.6), radius: 25, y: 10)
    }

    private func sheetButton(
        _ title: String,
        fill: Color,
        foreground: Color,
        shortcut: KeyboardShortcut,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity)
                .frame(height: 24)
                .background(fill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(shortcut)
    }
}
