import AppKit
import EventKit
import BrowCore
import ServiceManagement
import SwiftUI

/// The Settings window, made the first time it is asked for and kept for the rest of the run.
/// It sets no appearance of its own, so it follows System Settings → Appearance.
@MainActor
final class SettingsWindowController {
    private let model: AppModel
    private var window: NSWindow?

    init(model: AppModel) {
        self.model = model
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
            window.title = "Brow Settings"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 760, height: 580))
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        // The app has no Dock icon, so it is brought forward by hand.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, screens, calendar, pomodoro, keepAwake, usage

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .screens: "Screens"
        case .calendar: "Calendar"
        case .pomodoro: "Pomodoro"
        case .keepAwake: "Keep Awake"
        case .usage: "AI Usage"
        }
    }

    var symbol: String {
        switch self {
        case .general: "slider.horizontal.3"
        case .screens: "rectangle.on.rectangle"
        case .calendar: "calendar"
        case .pomodoro: "timer"
        case .keepAwake: "cup.and.saucer"
        case .usage: "gauge.with.dots.needle.33percent"
        }
    }

    /// The colour of the sidebar icon's tile, from the v2 design.
    var tile: Color {
        switch self {
        case .general: .gray
        case .screens: .indigo
        case .calendar: .red
        case .pomodoro: .orange
        case .keepAwake: .cyan
        case .usage: .purple
        }
    }
}

struct SettingsView: View {
    let model: AppModel
    @State private var pane: SettingsPane = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: Binding<SettingsPane?>(
                get: { pane },
                set: { newPane in if let newPane { pane = newPane } })) { pane in
                Label {
                    Text(pane.title)
                } icon: {
                    Image(systemName: pane.symbol)
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(pane.tile, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                .tag(pane)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 230)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            Group {
                switch pane {
                case .general: GeneralPane(preferences: model.preferences, island: model.island, shortcut: model.settingsShortcut)
                case .screens: ScreensPane(preferences: model.preferences)
                case .calendar: CalendarPane(calendar: model.calendar)
                case .pomodoro: PomodoroPane(pomodoro: model.pomodoro)
                case .keepAwake: KeepAwakePane(keepAwake: model.keepAwake)
                case .usage: UsagePane(usage: model.usage)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(pane.title)
        }
        .frame(minWidth: 700, minHeight: 480)
    }
}

/// A switch with its label and an optional line of explanation under it.
private struct ToggleRow: View {
    let title: String
    var detail: String?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title)
            if let detail {
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// The note under a section, left-aligned with the rows above it.
private struct FooterText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A whole number with a unit after it and a stepper beside it.
private struct StepperRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let unit: String

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Text("\(value) \(unit)").monospacedDigit()
                Stepper(title, value: $value, in: range).labelsHidden()
            }
        }
    }
}

// MARK: - General

private struct GeneralPane: View {
    @Bindable var preferences: IslandPreferences
    let island: IslandState
    let shortcut: String?
    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Startup") {
                ToggleRow(title: "Open Brow at login", isOn: Binding(
                    get: { opensAtLogin },
                    set: { setOpensAtLogin($0) }))
                ToggleRow(title: "Say hello when Brow starts",
                          detail: "The island opens for a moment, since Brow has no Dock or menu bar icon to show that it started.",
                          isOn: $preferences.showsLaunchHello)
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }
            Section {
                ToggleRow(title: "Open when the pointer rests on the notch",
                          detail: "While the pointer rests on the notch the island grows a little; once the delay has passed it opens fully. Moving away before then cancels it, and it closes when the pointer leaves. Turn it off to open the island only when you click the notch.",
                          isOn: Binding(
                            get: { preferences.openMode == .hover },
                            set: { preferences.openMode = $0 ? .hover : .click }))
                hoverDelay
            } header: {
                Text("Opening the island")
            } footer: {
                FooterText(shortcut.map {
                    "Right-click the island any time for Keep Awake, Pomodoro and these settings, or press \($0) from any app to open them."
                } ?? "Right-click the island any time for Keep Awake, Pomodoro and these settings.")
            }
            islandSize
            Section("Beside the notch") {
                ToggleRow(title: "Show live activities beside the notch",
                          detail: "Event countdown, Pomodoro time and Keep Awake while they run. Each can be turned off in its own section.",
                          isOn: $preferences.showsLiveActivities)
            }
        }
    }

    /// How long the pointer rests on the notch before the island opens, from 0.2 s to 2 s.
    private var hoverDelay: some View {
        LabeledContent("Hover delay") {
            HStack(spacing: 8) {
                Text("0.2 s").font(.caption).foregroundStyle(.secondary)
                Slider(value: $preferences.hoverDelay, in: IslandPreferences.hoverDelayRange, step: 0.1)
                    .labelsHidden()
                    .frame(width: 160)
                    .accessibilityLabel("Hover delay")
                    .accessibilityValue(Self.text(preferences.hoverDelay))
                Text("2 s").font(.caption).foregroundStyle(.secondary)
                Text(Self.text(preferences.hoverDelay))
                    .monospacedDigit()
                    .frame(minWidth: 40, alignment: .trailing)
            }
        }
        .disabled(preferences.openMode != .hover)
    }

    private static func text(_ seconds: Double) -> String {
        seconds.formatted(.number.precision(.fractionLength(1))) + " s"
    }

    /// The closed island's size: the notch's own, or a custom one that is never smaller.
    private var islandSize: some View {
        let detected = island.detectedNotch
        return Section {
            Picker("Size", selection: $preferences.matchesNotch) {
                Text("Match Notch").tag(true)
                Text("Custom").tag(false)
            }
            .pickerStyle(.segmented)
            sizeSlider("Width", value: $preferences.customWidth, notch: Double(detected.width),
                       extra: NotchSizing.extraWidth)
                .disabled(preferences.matchesNotch)
            sizeSlider("Height", value: $preferences.customHeight, notch: Double(detected.height),
                       extra: NotchSizing.extraHeight)
                .disabled(preferences.matchesNotch)
            Button("Reset to notch size") {
                preferences.customWidth = Double(detected.width)
                preferences.customHeight = Double(detected.height)
            }
        } header: {
            Text("Island size")
        } footer: {
            FooterText("Detected on this Mac: \(Int(detected.width)) × \(Int(detected.height)) pt. A custom size is never smaller than the notch.")
        }
        .onChange(of: preferences.matchesNotch) { _, matches in
            // The first time a custom size is asked for, it starts a little larger than the notch.
            guard !matches, preferences.customWidth == 0 || preferences.customHeight == 0 else { return }
            let start = NotchSizing.starting(detectedWidth: Double(detected.width), detectedHeight: Double(detected.height))
            preferences.customWidth = start.width
            preferences.customHeight = start.height
        }
    }

    private func sizeSlider(_ title: String, value: Binding<Double>, notch: Double, extra: Double) -> some View {
        let shown = Int(max(value.wrappedValue, notch))
        return LabeledContent(title) {
            HStack(spacing: 8) {
                Slider(value: value, in: notch...(notch + extra))
                    .labelsHidden()
                    .frame(width: 200)
                    .accessibilityLabel(title)
                    .accessibilityValue("\(shown) points")
                Text("\(shown) pt").monospacedDigit().frame(minWidth: 48, alignment: .trailing)
            }
        }
    }

    private func setOpensAtLogin(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            loginError = "Couldn’t change this: \(error.localizedDescription)"
        }
        opensAtLogin = SMAppService.mainApp.status == .enabled
    }
}

// MARK: - Screens

private struct ScreensPane: View {
    @Bindable var preferences: IslandPreferences
    @State private var selected = 0
    /// The thumbnail a dragged screen is hovering over.
    @State private var dropTarget: Int?

    var body: some View {
        let screens = preferences.screens
        let current = min(selected, screens.count - 1)
        Form {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 13) {
                        ForEach(Array(screens.enumerated()), id: \.element.id) { index, screen in
                            thumbnail(screen, at: index, isSelected: index == current, count: screens.count)
                        }
                        if screens.count < IslandScreens.maxCount {
                            addButton(after: screens)
                        }
                    }
                    .padding(2)
                }
            } footer: {
                FooterText("The open island shows one screen at a time. Swipe left or right with two fingers on the island to move between them. Drag to change the order. Up to \(IslandScreens.maxCount) screens.")
            }
            Section("Screen \(current + 1)") {
                Picker("Layout", selection: Binding(
                    get: { preferences.screens[current].layout },
                    set: { preferences.screens[current].setLayout($0) })) {
                    ForEach(ScreenLayout.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                widgetPickers(current: current, layout: screens[current].layout)
                Button("Delete Screen", role: .destructive) {
                    preferences.screens.remove(at: current)
                    selected = max(current - 1, 0)
                }
                .disabled(screens.count <= 1)
            }
            Section("When the island opens") {
                Picker("When the island opens", selection: $preferences.opensOnLastScreen) {
                    Text("Show the first screen").tag(false)
                    Text("Show the screen I used last").tag(true)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }
        }
    }

    private func thumbnail(_ screen: IslandScreen, at index: Int, isSelected: Bool, count: Int) -> some View {
        Button { selected = index } label: {
            ScreenThumbnail(screen: screen, index: index, isSelected: isSelected,
                            opensFirst: index == 0 && !preferences.opensOnLastScreen,
                            isDropTarget: dropTarget == index)
        }
        .buttonStyle(.plain)
        .draggable(String(index))
        .dropDestination(for: String.self) { items, _ in
            guard let raw = items.first, let from = Int(raw) else { return false }
            moveScreen(from: from, to: index)
            return true
        } isTargeted: { isTargeted in
            if isTargeted {
                dropTarget = index
            } else if dropTarget == index {
                dropTarget = nil
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: "Move left") { moveScreen(from: index, to: index - 1) }
        .accessibilityAction(named: "Move right") { moveScreen(from: index, to: index + 1) }
        .contextMenu {
            Button("Move Left") { moveScreen(from: index, to: index - 1) }.disabled(index == 0)
            Button("Move Right") { moveScreen(from: index, to: index + 1) }.disabled(index >= count - 1)
        }
    }

    private func addButton(after screens: [IslandScreen]) -> some View {
        Button {
            preferences.screens.append(IslandScreens.newScreen(after: screens))
            selected = preferences.screens.count - 1
        } label: {
            VStack(spacing: 5) {
                Image(systemName: "plus").font(.system(size: 14, weight: .semibold))
                Text("Add screen").font(.caption)
            }
            .foregroundStyle(Color.accentColor)
            .frame(width: 128, height: 77)
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(.tertiary, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func widgetPickers(current: Int, layout: ScreenLayout) -> some View {
        ForEach(0..<preferences.screens[current].widgets.count, id: \.self) { slot in
            Picker(slotName(slot, of: layout), selection: Binding(
                get: { preferences.screens[current].widgets[slot] },
                set: { preferences.screens[current].setWidget($0, at: slot) })) {
                ForEach(BrowCore.Widget.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
        }
    }

    /// Takes the screen at `from` and puts it where `to` is, then keeps it selected.
    private func moveScreen(from: Int, to: Int) {
        guard from != to, preferences.screens.indices.contains(from), preferences.screens.indices.contains(to) else { return }
        let screen = preferences.screens.remove(at: from)
        preferences.screens.insert(screen, at: to)
        selected = to
    }

    private func slotName(_ slot: Int, of layout: ScreenLayout) -> String {
        switch layout {
        case .one: "Widget"
        case .two: ["Left widget", "Right widget"][slot]
        case .four: ["Top left", "Top right", "Bottom left", "Bottom right"][slot]
        }
    }
}

extension ScreenLayout {
    var title: String {
        switch self {
        case .one: "One widget"
        case .two: "Two side by side"
        case .four: "Four in a grid"
        }
    }
}

/// A screen in miniature: a black island holding one tinted block per card.
private struct ScreenThumbnail: View {
    let screen: IslandScreen
    let index: Int
    let isSelected: Bool
    let opensFirst: Bool
    let isDropTarget: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.06))
                blocks
                    .padding(EdgeInsets(top: 11, leading: 6, bottom: 6, trailing: 6))
                    .frame(width: 106, height: 61)
                    .background(Color.black, in: UnevenRoundedRectangle(bottomLeadingRadius: 11, bottomTrailingRadius: 11))
            }
            .frame(width: 128, height: 77)
            .overlay {
                if isSelected || isDropTarget {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.6, dash: isDropTarget ? [4, 3] : []))
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(opensFirst ? "Screen \(index + 1) · opens first" : "Screen \(index + 1)")
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                Text(screen.title).font(.caption2).foregroundStyle(.secondary)
            }
            .frame(width: 128, alignment: .leading)
            .lineLimit(1)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var blocks: some View {
        let widgets = screen.widgets
        switch screen.layout {
        case .one:
            block(widgets[0])
        case .two:
            HStack(spacing: 4) { block(widgets[0]); block(widgets[1]) }
        case .four:
            VStack(spacing: 3) {
                HStack(spacing: 3) { block(widgets[0]); block(widgets[1]) }
                HStack(spacing: 3) { block(widgets[2]); block(widgets[3]) }
            }
        }
    }

    private func block(_ widget: BrowCore.Widget) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous).fill(widget.tint.opacity(0.45))
    }
}

extension BrowCore.Widget {
    var tint: Color {
        switch self {
        case .calendar: Palette.red
        case .pomodoro: Palette.orange
        case .keepAwake: Palette.cyan
        case .usage: Palette.purple
        }
    }
}

// MARK: - Calendar

private struct CalendarPane: View {
    @Bindable var calendar: CalendarModel

    var body: some View {
        let shown = calendar.calendars.filter { !calendar.excludedCalendarIDs.contains($0.id) }.count
        Form {
            Section {
                Toggle("Calendar access", isOn: Binding(
                    get: { calendar.access == .granted },
                    set: { _ in changeAccess() }))
            } footer: {
                FooterText("Change it in System Settings › Privacy & Security › Calendars.")
            }
            Section("Beside the notch") {
                ToggleRow(title: "Show upcoming events beside the notch",
                          detail: "A countdown, then “Now”. It leaves 5 minutes after the start.",
                          isOn: $calendar.announcesEvents)
                Picker("Start showing", selection: $calendar.leadMinutes) {
                    ForEach(Agenda.leadChoices.map { Int($0 / 60) }, id: \.self) { Text("\($0) minutes before").tag($0) }
                }
                .pickerStyle(.menu)
                .disabled(!calendar.announcesEvents)
                ToggleRow(title: "Open the island for a moment when an event starts", isOn: $calendar.peeksOnStart)
            }
            Section {
                if calendar.calendars.isEmpty {
                    Text(calendar.access == .granted ? "No calendars on this Mac." : "Allow access to choose calendars.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(calendar.accounts) { account in
                        AccountGroup(account: account, calendar: calendar)
                    }
                }
                ToggleRow(title: "Include all-day events", isOn: $calendar.includesAllDay)
            } header: {
                HStack {
                    Text("Calendars")
                    Spacer()
                    if !calendar.calendars.isEmpty {
                        Text(summary(shown: shown))
                    }
                }
            } footer: {
                FooterText("Pick the calendars the island uses. Events from unchecked ones don’t appear in the island or beside the notch.")
            }
        }
        .onAppear { calendar.loadCalendars() }
    }

    /// Asks the first time; after that only System Settings can change it, so the switch takes you there.
    private func changeAccess() {
        if calendar.access == .notAsked {
            Task { await calendar.requestAccess() }
        } else {
            openPrivacySettings()
        }
    }

    private func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    /// How many calendars are shown, and from how many accounts.
    private func summary(shown: Int) -> String {
        let accounts = calendar.accounts.count
        return "\(shown) of \(calendar.calendars.count) calendars shown, from \(accounts) account\(accounts == 1 ? "" : "s")"
    }
}

/// One account and its calendars to tick, which can be folded away. Subscribed and birthday calendars start folded.
private struct AccountGroup: View {
    let account: CalendarModel.Account
    @Bindable var calendar: CalendarModel
    @State private var isExpanded: Bool

    init(account: CalendarModel.Account, calendar: CalendarModel) {
        self.account = account
        self.calendar = calendar
        _isExpanded = State(initialValue: !account.kind.startsFolded)
    }

    var body: some View {
        let shown = account.calendars.filter { !calendar.excludedCalendarIDs.contains($0.id) }.count
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(account.calendars) { info in
                Toggle(info.title, isOn: Binding(
                    get: { !calendar.excludedCalendarIDs.contains(info.id) },
                    set: { include in
                        if include {
                            calendar.excludedCalendarIDs.remove(info.id)
                        } else {
                            calendar.excludedCalendarIDs.insert(info.id)
                        }
                    }))
                .toggleStyle(.checkbox)
                .tint(info.color)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: account.kind.symbol).foregroundStyle(.secondary).frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(account.title)
                    // An account named after its kind, like iCloud, would just say it twice.
                    if account.title != account.kind.label {
                        Text(account.kind.label).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(shown == 0 ? "None of \(account.calendars.count) shown" : "\(shown) of \(account.calendars.count) shown")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Pomodoro

private struct PomodoroPane: View {
    @Bindable var pomodoro: PomodoroModel

    var body: some View {
        Form {
            Section("Lengths") {
                StepperRow(title: "Focus", value: $pomodoro.focusMinutes, range: 1...120, unit: "min")
                StepperRow(title: "Short break", value: $pomodoro.shortBreakMinutes, range: 1...60, unit: "min")
                StepperRow(title: "Long break", value: $pomodoro.longBreakMinutes, range: 1...60, unit: "min")
                StepperRow(title: "Long break after", value: $pomodoro.roundsUntilLongBreak, range: 2...8, unit: "focus sessions")
            }
            Section("Between sessions") {
                ToggleRow(title: "Start breaks automatically", isOn: $pomodoro.startsBreaksAutomatically)
                ToggleRow(title: "Start the next focus session automatically", isOn: $pomodoro.startsFocusAutomatically)
                ToggleRow(title: "Open the island when a session ends",
                          detail: "Shows “Focus done” with Start break and Skip break.",
                          isOn: $pomodoro.peeksOnPhaseEnd)
                Picker("Sound when a session ends", selection: $pomodoro.soundName) {
                    ForEach(PomodoroModel.sounds, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu)
                .onChange(of: pomodoro.soundName) { _, name in
                    NSSound(named: name)?.play()
                }
            }
            Section("Beside the notch") {
                ToggleRow(title: "Show the ring and time left while a session runs", isOn: $pomodoro.showsBesideNotch)
            }
        }
    }
}

// MARK: - Keep Awake

private struct KeepAwakePane: View {
    @Bindable var keepAwake: KeepAwake

    var body: some View {
        Form {
            Section {
                Picker("Default length", selection: $keepAwake.defaultPresetID) {
                    ForEach(KeepAwake.choices) { Text($0.settingsLabel).tag($0.id) }
                }
                .pickerStyle(.menu)
            } footer: {
                FooterText("Added to the island’s Keep Awake buttons when it isn’t one of 30m, 1h, 2h or No end.")
            }
            Section {
                ToggleRow(title: "Keep the display on",
                          detail: "When off, the Mac stays awake but the display may sleep.",
                          isOn: $keepAwake.keepsDisplayOn)
            }
            Section {
                ToggleRow(title: "Turn off on low battery", isOn: $keepAwake.batteryCutoffEnabled)
                Picker("Below", selection: $keepAwake.batteryCutoffLevel) {
                    ForEach(KeepAwake.batteryLevels, id: \.self) { Text("\($0)%").tag($0) }
                }
                .pickerStyle(.menu)
                .disabled(!keepAwake.batteryCutoffEnabled)
            } header: {
                Text("Battery")
            } footer: {
                FooterText("Only while running on battery.")
            }
            Section("Beside the notch") {
                ToggleRow(title: "Show the cup and time left while Keep Awake is on", isOn: $keepAwake.showsBesideNotch)
            }
        }
    }
}

// MARK: - AI Usage

private struct UsagePane: View {
    @Bindable var usage: UsageModel
    @State private var claudeConnected = false
    @State private var claudeError: String?

    var body: some View {
        Form {
            Section {
                source(name: "Claude Code",
                       isOn: Binding(get: { claudeConnected }, set: { _ in toggleClaude() }),
                       detail: "Shows your 5-hour and 7-day limits, read from Claude Code’s status line. Your own status line keeps working.",
                       note: "Turning this off puts your status line back exactly as it was.")
                if let claudeError {
                    Text(claudeError).font(.caption).foregroundStyle(.red)
                }
                source(name: "Codex",
                       isOn: $usage.readsCodex,
                       detail: "Shows your 5-hour and weekly limits, read from Codex’s newest local session log. Nothing to set up.",
                       note: nil)
            } header: {
                Text("Sources")
            } footer: {
                FooterText("Limits are read from files on this Mac when the island opens. Nothing is sent over the network.")
            }
            Section("Display") {
                ToggleRow(title: "Colour a limit amber from 80%", isOn: $usage.highlightsHighUse)
                ToggleRow(title: "Show when each limit resets", isOn: $usage.showsResetTimes)
            }
        }
        .onAppear { claudeConnected = usage.isClaudeConnected }
    }

    private func source(name: String, isOn: Binding<Bool>, detail: String, note: String?) -> some View {
        Toggle(isOn: isOn) {
            Text(name)
            Text(detail).font(.caption).foregroundStyle(.secondary)
            if let note {
                Text(note).font(.caption).foregroundStyle(.tertiary)
            }
        }
    }

    private func toggleClaude() {
        do {
            try usage.setClaudeConnected(!claudeConnected)
            claudeError = nil
        } catch StatusLineHook.Failure.claudeCodeNotFound {
            claudeError = "Claude Code wasn’t found: there is no ~/.claude folder on this Mac."
        } catch {
            claudeError = "~/.claude/settings.json couldn’t be read as JSON, so it was left alone."
        }
        claudeConnected = usage.isClaudeConnected
    }
}
