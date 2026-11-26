import AppKit
import EventKit
import BrowCore
import ServiceManagement
import SwiftUI

/// The Settings window, made the first time it is asked for and kept for the rest of the run.
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
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.setContentSize(NSSize(width: 800, height: 600))
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
}

struct SettingsView: View {
    let model: AppModel
    @State private var pane: SettingsPane? = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $pane) { pane in
                Label(pane.title, systemImage: pane.symbol)
            }
            .navigationSplitViewColumnWidth(190)
        } detail: {
            Group {
                switch pane ?? .general {
                case .general: GeneralPane(preferences: model.preferences)
                case .screens: ScreensPane(preferences: model.preferences)
                case .calendar: CalendarPane(calendar: model.calendar)
                case .pomodoro: PomodoroPane(pomodoro: model.pomodoro)
                case .keepAwake: KeepAwakePane(keepAwake: model.keepAwake)
                case .usage: UsagePane(usage: model.usage)
                }
            }
            .formStyle(.grouped)
            .navigationTitle((pane ?? .general).title)
        }
        .tint(Palette.navy)
        .frame(minWidth: 760, minHeight: 540)
    }
}

/// A setting's label with a line of explanation under it.
private struct Explained: View {
    let title: String
    let detail: String

    init(_ title: String, _ detail: String) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(detail).font(.callout).foregroundStyle(.secondary)
        }
    }
}

// MARK: - General

private struct GeneralPane: View {
    @Bindable var preferences: IslandPreferences
    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Open Brow at login", isOn: Binding(
                    get: { opensAtLogin },
                    set: { setOpensAtLogin($0) }))
                if let loginError {
                    Text(loginError).font(.callout).foregroundStyle(.red)
                }
            }
            Section("Opening the island") {
                Picker("Open the island", selection: $preferences.openMode) {
                    Explained("When the pointer rests on the notch",
                              "Opens after a short pause and closes when the pointer leaves.")
                        .tag(IslandPreferences.OpenMode.hover)
                    Text("Only when I click the notch").tag(IslandPreferences.OpenMode.click)
                }
                .pickerStyle(.radioGroup)
                Text("Right-click the island any time for Keep Awake, Pomodoro and these settings.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("Beside the notch") {
                Toggle(isOn: $preferences.showsLiveActivities) {
                    Explained("Show live activities beside the notch",
                              "Event countdown, Pomodoro time and Keep Awake while they run. Each can be turned off in its own section.")
                }
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

    var body: some View {
        let screens = preferences.screens
        let current = min(selected, screens.count - 1)
        Form {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(Array(screens.enumerated()), id: \.element.id) { index, screen in
                            Button { selected = index } label: {
                                ScreenThumbnail(screen: screen, index: index, isSelected: index == current,
                                                opensFirst: index == 0 && !preferences.opensOnLastScreen)
                            }
                            .buttonStyle(.plain)
                        }
                        if screens.count < IslandScreens.maxCount {
                            Button {
                                preferences.screens.append(IslandScreens.newScreen(after: screens))
                                selected = preferences.screens.count - 1
                            } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: "plus").font(.system(size: 16, weight: .semibold))
                                    Text("Add screen").font(.callout.weight(.semibold))
                                }
                                .foregroundStyle(Palette.navy)
                                .frame(width: 140, height: 84)
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                                    .foregroundStyle(.secondary))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                HStack {
                    Button("Move Left") { move(current, by: -1) }
                        .disabled(current == 0)
                    Button("Move Right") { move(current, by: 1) }
                        .disabled(current >= screens.count - 1)
                    Spacer()
                    Button("Delete Screen", role: .destructive) {
                        preferences.screens.remove(at: current)
                        selected = max(current - 1, 0)
                    }
                    .disabled(screens.count <= 1)
                }
            } header: {
                Text("Screens")
            } footer: {
                Text("The open island shows one screen at a time. Swipe left or right with two fingers on the island to move between them. Up to \(IslandScreens.maxCount) screens.")
            }

            Section("Screen \(current + 1)") {
                Picker("Layout", selection: Binding(
                    get: { preferences.screens[current].layout },
                    set: { preferences.screens[current].setLayout($0) })) {
                    Text("One widget").tag(ScreenLayout.one)
                    Text("Two side by side").tag(ScreenLayout.two)
                    Text("Four in a grid").tag(ScreenLayout.four)
                }
                .pickerStyle(.segmented)
                ForEach(0..<screens[current].widgets.count, id: \.self) { slot in
                    Picker(slotName(slot, of: screens[current].layout), selection: Binding(
                        get: { preferences.screens[current].widgets[slot] },
                        set: { preferences.screens[current].setWidget($0, at: slot) })) {
                        ForEach(BrowCore.Widget.allCases, id: \.self) { widget in
                            Text(widget.title).tag(widget)
                        }
                    }
                }
            }

            Section("When the island opens") {
                Picker("Show", selection: $preferences.opensOnLastScreen) {
                    Text("The first screen").tag(false)
                    Text("The screen I used last").tag(true)
                }
                .pickerStyle(.radioGroup)
            }
        }
    }

    private func move(_ index: Int, by offset: Int) {
        let target = index + offset
        guard preferences.screens.indices.contains(index), preferences.screens.indices.contains(target) else { return }
        preferences.screens.swapAt(index, target)
        selected = target
    }

    private func slotName(_ slot: Int, of layout: ScreenLayout) -> String {
        switch layout {
        case .one: "Widget"
        case .two: ["Left", "Right"][slot]
        case .four: ["Top left", "Top right", "Bottom left", "Bottom right"][slot]
        }
    }
}

/// A screen in miniature: a black island holding one tinted block per card.
private struct ScreenThumbnail: View {
    let screen: IslandScreen
    let index: Int
    let isSelected: Bool
    let opensFirst: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? Color(red: 0xD6 / 255, green: 0xE3 / 255, blue: 1) : Color.secondary.opacity(0.12))
                blocks
                    .padding(EdgeInsets(top: 12, leading: 7, bottom: 7, trailing: 7))
                    .frame(width: 118, height: 66)
                    .background(Color.black, in: UnevenRoundedRectangle(bottomLeadingRadius: 12, bottomTrailingRadius: 12))
            }
            .frame(width: 140, height: 84)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.navy, lineWidth: 2)
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(opensFirst ? "Screen \(index + 1) · opens first" : "Screen \(index + 1)")
                    .font(.callout.weight(isSelected ? .bold : .semibold))
                    .foregroundStyle(isSelected ? Palette.navy : .primary)
                Text(screen.title).font(.caption).foregroundStyle(.secondary)
            }
            .frame(width: 140, alignment: .leading)
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
            VStack(spacing: 4) {
                HStack(spacing: 4) { block(widgets[0]); block(widgets[1]) }
                HStack(spacing: 4) { block(widgets[2]); block(widgets[3]) }
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
        case .calendar: Palette.teal
        case .pomodoro: Palette.amber
        case .keepAwake: Palette.paleBlue
        case .usage: .white
        }
    }
}

// MARK: - Calendar

private struct CalendarPane: View {
    @Bindable var calendar: CalendarModel

    var body: some View {
        Form {
            Section {
                LabeledContent("Calendar access") {
                    HStack(spacing: 10) {
                        Text(accessText).foregroundStyle(calendar.access == .granted ? Color.green : .secondary)
                        if calendar.access == .notAsked {
                            Button("Allow Access…") { Task { await calendar.requestAccess() } }
                        } else {
                            Button("Open Privacy Settings") { openPrivacySettings() }
                        }
                    }
                }
            }
            Section("Beside the notch") {
                Toggle(isOn: $calendar.announcesEvents) {
                    Explained("Show upcoming events beside the notch",
                              "A countdown, then “Now”. It leaves 5 minutes after the start.")
                }
                Picker("Start showing", selection: $calendar.leadMinutes) {
                    ForEach(Agenda.leadChoices.map { Int($0 / 60) }, id: \.self) { minutes in
                        Text("\(minutes) minutes before").tag(minutes)
                    }
                }
                .disabled(!calendar.announcesEvents)
                Toggle("Open the island for a moment when an event starts", isOn: $calendar.peeksOnStart)
            }
            Section {
                if calendar.calendars.isEmpty {
                    Text(calendar.access == .granted ? "No calendars on this Mac." : "Allow access to choose calendars.")
                        .foregroundStyle(.secondary)
                }
                ForEach(calendar.calendars) { info in
                    Toggle(isOn: Binding(
                        get: { !calendar.excludedCalendarIDs.contains(info.id) },
                        set: { include in
                            if include {
                                calendar.excludedCalendarIDs.remove(info.id)
                            } else {
                                calendar.excludedCalendarIDs.insert(info.id)
                            }
                        })) {
                        HStack(spacing: 8) {
                            Circle().fill(info.color).frame(width: 9, height: 9)
                            Text(info.title)
                        }
                    }
                }
                Toggle("Include all-day events", isOn: $calendar.includesAllDay)
            } header: {
                Text("Calendars")
            } footer: {
                Text("Events from unchecked calendars don’t appear in the island or beside the notch.")
            }
        }
        .onAppear { calendar.loadCalendars() }
    }

    private var accessText: String {
        switch calendar.access {
        case .granted: "Allowed"
        case .denied: "Not allowed"
        case .notAsked: "Not asked yet"
        }
    }

    private func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Pomodoro

private struct PomodoroPane: View {
    @Bindable var pomodoro: PomodoroModel

    var body: some View {
        Form {
            Section("Lengths") {
                Stepper("Focus: \(pomodoro.focusMinutes) min", value: $pomodoro.focusMinutes, in: 1...120)
                Stepper("Short break: \(pomodoro.shortBreakMinutes) min", value: $pomodoro.shortBreakMinutes, in: 1...60)
                Stepper("Long break: \(pomodoro.longBreakMinutes) min", value: $pomodoro.longBreakMinutes, in: 1...60)
                Stepper("Long break after \(pomodoro.roundsUntilLongBreak) focus sessions",
                        value: $pomodoro.roundsUntilLongBreak, in: 2...8)
            }
            Section("Between sessions") {
                Toggle("Start breaks automatically", isOn: $pomodoro.startsBreaksAutomatically)
                Toggle("Start the next focus session automatically", isOn: $pomodoro.startsFocusAutomatically)
                Toggle(isOn: $pomodoro.peeksOnPhaseEnd) {
                    Explained("Open the island when a session ends", "Shows “Focus done” with Start break and Skip break.")
                }
                Picker("Sound when a session ends", selection: $pomodoro.soundName) {
                    ForEach(PomodoroModel.sounds, id: \.self) { Text($0).tag($0) }
                }
                .onChange(of: pomodoro.soundName) { _, name in
                    NSSound(named: name)?.play()
                }
            }
            Section("Beside the notch") {
                Toggle("Show the ring and time left while a session runs", isOn: $pomodoro.showsBesideNotch)
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
                    ForEach(KeepAwake.presets) { preset in
                        Text(preset.label == "No end" ? "Until turned off" : preset.label).tag(preset.id)
                    }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("Outlined on the island’s Keep Awake card as the one to pick without thinking.")
            }
            Section("What stays awake") {
                Picker("What stays awake", selection: $keepAwake.keepsDisplayOn) {
                    Text("The Mac and the display").tag(true)
                    Explained("The Mac only", "The display may sleep; downloads and builds keep running.").tag(false)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }
            Section {
                Toggle("Turn off when the battery drops below", isOn: $keepAwake.batteryCutoffEnabled)
                Picker("Battery level", selection: $keepAwake.batteryCutoffLevel) {
                    ForEach(KeepAwake.batteryLevels, id: \.self) { Text("\($0)%").tag($0) }
                }
                .disabled(!keepAwake.batteryCutoffEnabled)
            } header: {
                Text("Battery")
            } footer: {
                Text("Only while running on battery.")
            }
            Section("Beside the notch") {
                Toggle("Show the cup and time left while Keep Awake is on", isOn: $keepAwake.showsBesideNotch)
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
                Text("Limits are read from files on this Mac when the island opens. Nothing is sent over the network.")
                    .foregroundStyle(.secondary)
            }
            Section {
                LabeledContent {
                    Button(claudeConnected ? "Remove Hook" : "Connect") { toggleClaude() }
                } label: {
                    Explained(claudeConnected ? "Claude Code · connected" : "Claude Code · not connected",
                              "Keeps a copy of what Claude Code sends to its status line: the 5-hour and 7-day limits. Your own status line still runs.")
                }
                if let claudeError {
                    Text(claudeError).font(.callout).foregroundStyle(.red)
                }
                Toggle(isOn: $usage.readsCodex) {
                    Explained("Codex", "Reads the newest local session log: the 5-hour and weekly limits.")
                }
            } header: {
                Text("Sources")
            } footer: {
                if let lastRead = usage.lastRead {
                    Text("Last read at \(lastRead.formatted(date: .omitted, time: .shortened)).")
                }
            }
            Section("Display") {
                Toggle("Colour a limit amber from 80%", isOn: $usage.highlightsHighUse)
                Toggle("Show when each limit resets", isOn: $usage.showsResetTimes)
            }
        }
        .onAppear { claudeConnected = usage.isClaudeConnected }
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
