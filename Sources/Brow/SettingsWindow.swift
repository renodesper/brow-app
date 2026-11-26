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
            window.titleVisibility = .hidden
            // The design is a light page, so the window stays light whatever the Mac is set to.
            window.appearance = NSAppearance(named: .aqua)
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
    @State private var pane: SettingsPane = .general

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selection: $pane)
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.white.ignoresSafeArea())
        .environment(\.colorScheme, .light)
        .tint(Palette.navy)
        .frame(minWidth: 760, minHeight: 540)
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
        SettingsPage(title: "General") {
            SettingsSection(title: "Startup") {
                CheckRow(title: "Open Brow at login", isOn: Binding(
                    get: { opensAtLogin },
                    set: { setOpensAtLogin($0) }))
                if let loginError {
                    Text(loginError).font(SettingsStyle.caption).foregroundStyle(.red)
                }
            }
            SettingsDivider()
            SettingsSection(title: "Opening the island",
                            detail: shortcut.map {
                                "Right-click the island any time for Keep Awake, Pomodoro and these settings, or press \($0) from any app to open them."
                            } ?? "Right-click the island any time for Keep Awake, Pomodoro and these settings.") {
                CheckRow(title: "Open when the pointer rests on the notch",
                         detail: "While the pointer rests on the notch the island grows a little; once the delay has passed it opens fully. Moving away before then cancels it, and it closes when the pointer leaves. Turn it off to open the island only when you click the notch.",
                         isOn: Binding(
                            get: { preferences.openMode == .hover },
                            set: { preferences.openMode = $0 ? .hover : .click }))
                HoverDelaySlider(delay: $preferences.hoverDelay)
                    .padding(.leading, 23)
                    .disabled(preferences.openMode != .hover)
            }
            SettingsDivider()
            islandSize
            SettingsDivider()
            SettingsSection(title: "Beside the notch") {
                CheckRow(title: "Show live activities beside the notch",
                         detail: "Event countdown, Pomodoro time and Keep Awake while they run. Each can be turned off in its own section.",
                         isOn: $preferences.showsLiveActivities)
            }
        }
    }

    /// The closed island's size: the notch's own, or a custom one that is never smaller.
    private var islandSize: some View {
        let detected = island.detectedNotch
        return SettingsSection(title: "Island size") {
            RadioRow(title: "Match the notch",
                     detail: "Detected on this Mac: \(Int(detected.width)) × \(Int(detected.height)) pt.",
                     value: true, selection: $preferences.matchesNotch)
            HStack(spacing: 8) {
                RadioRow(title: "Custom size", value: false, selection: $preferences.matchesNotch)
                Text("· never smaller than the notch").font(SettingsStyle.caption).foregroundStyle(SettingsStyle.hint)
                Spacer()
                Button("Reset to notch size") {
                    preferences.customWidth = Double(detected.width)
                    preferences.customHeight = Double(detected.height)
                }
                .buttonStyle(GhostButtonStyle())
            }
            HStack(alignment: .top, spacing: 24) {
                sizeSlider("Width", value: $preferences.customWidth, notch: Double(detected.width),
                           extra: NotchSizing.extraWidth)
                sizeSlider("Height", value: $preferences.customHeight, notch: Double(detected.height),
                           extra: NotchSizing.extraHeight)
            }
            .padding(.leading, 23)
            .disabled(preferences.matchesNotch)
            .opacity(preferences.matchesNotch ? 0.45 : 1)
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
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(SettingsStyle.label)
                Spacer()
                Text("\(shown) pt").font(SettingsStyle.label).foregroundStyle(Palette.navy).monospacedDigit()
            }
            Slider(value: value, in: notch...(notch + extra))
                .tint(Palette.navy)
                .accessibilityLabel(title)
                .accessibilityValue("\(shown) points")
        }
        .frame(maxWidth: .infinity)
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

/// How long the pointer rests on the notch before the island opens, from 0.2 s to 2 s.
private struct HoverDelaySlider: View {
    @Binding var delay: Double
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 11) {
            Text("Hover delay").font(SettingsStyle.label)
            Text("0.2 s").font(SettingsStyle.caption).foregroundStyle(SettingsStyle.hint)
            Slider(value: $delay, in: IslandPreferences.hoverDelayRange, step: 0.1)
                .tint(Palette.navy)
                .accessibilityLabel("Hover delay")
                .accessibilityValue(Self.text(delay))
            Text("2 s").font(SettingsStyle.caption).foregroundStyle(SettingsStyle.hint)
            Text(Self.text(delay))
                .font(Typeface.text(11, weight: .bold))
                .foregroundStyle(Palette.navy)
                .monospacedDigit()
                .frame(minWidth: 38, alignment: .trailing)
        }
        .frame(maxWidth: 460)
        .opacity(isEnabled ? 1 : 0.45)
    }

    private static func text(_ seconds: Double) -> String {
        seconds.formatted(.number.precision(.fractionLength(1))) + " s"
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
        SettingsPage(title: "Screens",
                     subtitle: "The open island shows one screen at a time. Swipe left or right with two fingers on the island to move between them.") {
            VStack(alignment: .leading, spacing: 10) {
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
                Text("Drag to change the order. Up to \(IslandScreens.maxCount) screens.")
                    .font(SettingsStyle.caption).foregroundStyle(SettingsStyle.hint)
            }
            SettingsDivider()
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Screen \(current + 1)").font(Typeface.number(16, weight: .bold))
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button("Delete screen") {
                        preferences.screens.remove(at: current)
                        selected = max(current - 1, 0)
                    }
                    .buttonStyle(DangerButtonStyle())
                    .disabled(screens.count <= 1)
                }
                layoutChoices(current: current)
                widgetSelects(current: current, layout: screens[current].layout)
            }
            SettingsDivider()
            SettingsSection(title: "When the island opens") {
                RadioRow(title: "Show the first screen", value: false, selection: $preferences.opensOnLastScreen)
                RadioRow(title: "Show the screen I used last", value: true, selection: $preferences.opensOnLastScreen)
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
                Image(systemName: "plus").font(.system(size: 14, weight: .bold))
                Text("Add screen").font(Typeface.text(11, weight: .semibold))
            }
            .foregroundStyle(Palette.navy)
            .frame(width: 128, height: 77)
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(SettingsStyle.dashed, style: StrokeStyle(lineWidth: 1.6, dash: [5, 4])))
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func layoutChoices(current: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Layout").font(SettingsStyle.label)
            HStack(spacing: 10) {
                ForEach(ScreenLayout.allCases, id: \.self) { layout in
                    let isSelected = preferences.screens[current].layout == layout
                    Button { preferences.screens[current].setLayout(layout) } label: {
                        HStack(spacing: 11) {
                            LayoutDiagram(layout: layout, color: isSelected ? Palette.navy : SettingsStyle.dashed)
                                .frame(width: 38, height: 24)
                            Text(layout.title)
                                .font(Typeface.text(11.5, weight: isSelected ? .bold : .semibold))
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(isSelected ? Palette.navy : SettingsStyle.muted)
                        .padding(.horizontal, 13)
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                        .background(isSelected ? Palette.paleBlue : SettingsStyle.surface,
                                    in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .overlay {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(Palette.navy, lineWidth: 1.6)
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
    }

    private func widgetSelects(current: Int, layout: ScreenLayout) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 13), GridItem(.flexible())], alignment: .leading, spacing: 12) {
            ForEach(0..<preferences.screens[current].widgets.count, id: \.self) { slot in
                VStack(alignment: .leading, spacing: 6) {
                    Text(slotName(slot, of: layout)).font(SettingsStyle.label)
                    Select(label: slotName(slot, of: layout),
                           selection: Binding(
                            get: { preferences.screens[current].widgets[slot] },
                            set: { preferences.screens[current].setWidget($0, at: slot) }),
                           options: BrowCore.Widget.allCases.map { (value: $0, title: $0.title) },
                           minWidth: 200)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
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

/// A layout in miniature, one block per card.
private struct LayoutDiagram: View {
    let layout: ScreenLayout
    let color: Color

    var body: some View {
        switch layout {
        case .one:
            block
        case .two:
            HStack(spacing: 3) { block; block }
        case .four:
            VStack(spacing: 3) {
                HStack(spacing: 3) { block; block }
                HStack(spacing: 3) { block; block }
            }
        }
    }

    private var block: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous).fill(color)
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
                    .fill(isSelected ? Palette.paleBlue : SettingsStyle.surface)
                blocks
                    .padding(EdgeInsets(top: 11, leading: 6, bottom: 6, trailing: 6))
                    .frame(width: 106, height: 61)
                    .background(Color.black, in: UnevenRoundedRectangle(bottomLeadingRadius: 11, bottomTrailingRadius: 11))
            }
            .frame(width: 128, height: 77)
            .overlay {
                if isSelected || isDropTarget {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(Palette.navy, style: StrokeStyle(lineWidth: 1.6, dash: isDropTarget ? [4, 3] : []))
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(opensFirst ? "Screen \(index + 1) · opens first" : "Screen \(index + 1)")
                    .font(Typeface.text(10.5, weight: isSelected ? .bold : .semibold))
                    .foregroundStyle(isSelected ? Palette.navy : SettingsStyle.ink)
                Text(screen.title).font(Typeface.text(10)).foregroundStyle(SettingsStyle.hint)
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
        let shown = calendar.calendars.filter { !calendar.excludedCalendarIDs.contains($0.id) }.count
        SettingsPage(title: "Calendar") {
            HStack(spacing: 10) {
                Text("Calendar access").font(Typeface.text(12, weight: .semibold))
                StatusBadge(text: accessText, isGood: calendar.access == .granted)
                Spacer()
                if calendar.access == .notAsked {
                    Button("Allow Access…") { Task { await calendar.requestAccess() } }
                        .buttonStyle(GhostButtonStyle())
                } else {
                    Button("Open Privacy Settings") { openPrivacySettings() }
                        .buttonStyle(GhostButtonStyle())
                }
            }
            .settingsTile()

            SettingsSection(title: "Beside the notch") {
                CheckRow(title: "Show upcoming events beside the notch",
                         detail: "A countdown, then “Now”. It leaves 5 minutes after the start.",
                         isOn: $calendar.announcesEvents)
                HStack(spacing: 10) {
                    Text("Start showing").font(SettingsStyle.body)
                    Select(label: "Start showing",
                           selection: $calendar.leadMinutes,
                           options: Agenda.leadChoices.map { Int($0 / 60) }.map { (value: $0, title: "\($0) minutes before") },
                           minWidth: 160)
                        .disabled(!calendar.announcesEvents)
                }
                .padding(.leading, 23)
                CheckRow(title: "Open the island for a moment when an event starts", isOn: $calendar.peeksOnStart)
                    .padding(.leading, 23)
            }
            SettingsDivider()
            SettingsSection(title: "Calendars",
                            detail: "Pick the calendars the island uses. Events from unchecked ones don’t appear in the island or beside the notch.",
                            trailing: calendar.calendars.isEmpty ? nil : summary(shown: shown)) {
                if calendar.calendars.isEmpty {
                    Text(calendar.access == .granted ? "No calendars on this Mac." : "Allow access to choose calendars.")
                        .font(SettingsStyle.body)
                        .foregroundStyle(SettingsStyle.hint)
                } else {
                    ForEach(calendar.accounts) { account in
                        AccountTile(account: account, calendar: calendar)
                    }
                }
                CheckRow(title: "Include all-day events", isOn: $calendar.includesAllDay)
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

/// How many calendars are shown, and from how many accounts.
private extension CalendarPane {
    func summary(shown: Int) -> String {
        let accounts = calendar.accounts.count
        return "\(shown) of \(calendar.calendars.count) calendars shown, from \(accounts) account\(accounts == 1 ? "" : "s")"
    }
}

/// One account and its calendars to tick, which can be folded away. Subscribed and birthday calendars start folded.
private struct AccountTile: View {
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 11) {
                Image(systemName: account.kind.symbol)
                    .font(.system(size: 14))
                    .foregroundStyle(SettingsStyle.muted)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(account.title).font(Typeface.text(12, weight: .semibold))
                    // An account named after its kind, like iCloud, would just say it twice.
                    if account.title != account.kind.label {
                        Text(account.kind.label).font(SettingsStyle.caption).foregroundStyle(SettingsStyle.hint)
                    }
                }
                Spacer()
                Text(shown == 0 ? "None of \(account.calendars.count) shown" : "\(shown) of \(account.calendars.count) shown")
                    .font(Typeface.text(10.5, weight: shown == 0 ? .regular : .semibold))
                    .foregroundStyle(shown == 0 ? SettingsStyle.hint : Palette.navy)
                Button { isExpanded.toggle() } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(SettingsStyle.muted)
                        .frame(width: 26, height: 26)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "Fold \(account.title)" : "Unfold \(account.title)")
                .accessibilityAddTraits(.isButton)
            }
            if isExpanded {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 20), GridItem(.flexible())], alignment: .leading, spacing: 9) {
                    ForEach(account.calendars) { info in
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
                                Circle().fill(info.color).frame(width: 8, height: 8)
                                Text(info.title).font(SettingsStyle.body)
                            }
                        }
                        .toggleStyle(CheckboxStyle())
                    }
                }
                .padding(.leading, 29)
                .padding(.bottom, 4)
            }
        }
        .settingsTile(vertical: 8, horizontal: 14)
    }
}

// MARK: - Pomodoro

private struct PomodoroPane: View {
    @Bindable var pomodoro: PomodoroModel

    var body: some View {
        SettingsPage(title: "Pomodoro") {
            SettingsSection(title: "Lengths") {
                HStack(alignment: .top, spacing: 13) {
                    NumberField(label: "Focus", value: $pomodoro.focusMinutes, range: 1...120, unit: "min")
                    NumberField(label: "Short break", value: $pomodoro.shortBreakMinutes, range: 1...60, unit: "min")
                    NumberField(label: "Long break", value: $pomodoro.longBreakMinutes, range: 1...60, unit: "min")
                    NumberField(label: "Long break after", value: $pomodoro.roundsUntilLongBreak, range: 2...8, unit: "focus")
                }
            }
            SettingsDivider()
            SettingsSection(title: "Between sessions") {
                CheckRow(title: "Start breaks automatically", isOn: $pomodoro.startsBreaksAutomatically)
                CheckRow(title: "Start the next focus session automatically", isOn: $pomodoro.startsFocusAutomatically)
                CheckRow(title: "Open the island when a session ends",
                         detail: "Shows “Focus done” with Start break and Skip break.",
                         isOn: $pomodoro.peeksOnPhaseEnd)
                HStack(spacing: 10) {
                    Text("Sound when a session ends").font(SettingsStyle.body)
                    Select(label: "Sound when a session ends",
                           selection: $pomodoro.soundName,
                           options: PomodoroModel.sounds.map { (value: $0, title: $0) },
                           minWidth: 120)
                }
                .onChange(of: pomodoro.soundName) { _, name in
                    NSSound(named: name)?.play()
                }
            }
            SettingsDivider()
            SettingsSection(title: "Beside the notch") {
                CheckRow(title: "Show the ring and time left while a session runs", isOn: $pomodoro.showsBesideNotch)
            }
        }
    }
}

// MARK: - Keep Awake

private struct KeepAwakePane: View {
    @Bindable var keepAwake: KeepAwake

    private func defaultChoice(_ preset: KeepAwake.Preset) -> some View {
        PillChoice(title: preset.settingsLabel, isSelected: keepAwake.defaultPresetID == preset.id) {
            keepAwake.defaultPresetID = preset.id
        }
    }

    var body: some View {
        SettingsPage(title: "Keep Awake") {
            SettingsSection(title: "Default length",
                            detail: "Outlined on the island’s Keep Awake card as the one to pick without thinking.") {
                // Five across, then the rest, with the last one ("Indefinitely") twice as wide, as the design draws it.
                let choices = KeepAwake.choices
                Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                    GridRow {
                        ForEach(choices.prefix(5)) { defaultChoice($0) }
                    }
                    GridRow {
                        ForEach(choices.dropFirst(5).dropLast()) { defaultChoice($0) }
                        defaultChoice(choices[choices.count - 1]).gridCellColumns(2)
                    }
                }
            }
            SettingsDivider()
            SettingsSection(title: "What stays awake") {
                RadioRow(title: "The Mac and the display", value: true, selection: $keepAwake.keepsDisplayOn)
                RadioRow(title: "The Mac only", detail: "The display may sleep; downloads and builds keep running.",
                         value: false, selection: $keepAwake.keepsDisplayOn)
            }
            SettingsDivider()
            SettingsSection(title: "Battery", detail: "Only while running on battery.") {
                HStack(spacing: 10) {
                    CheckRow(title: "Turn off when the battery drops below", isOn: $keepAwake.batteryCutoffEnabled)
                    Select(label: "Battery level",
                           selection: $keepAwake.batteryCutoffLevel,
                           options: KeepAwake.batteryLevels.map { (value: $0, title: "\($0)%") },
                           minWidth: 80)
                        .disabled(!keepAwake.batteryCutoffEnabled)
                }
            }
            SettingsDivider()
            SettingsSection(title: "Beside the notch") {
                CheckRow(title: "Show the cup and time left while Keep Awake is on", isOn: $keepAwake.showsBesideNotch)
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
        SettingsPage(title: "AI Usage",
                     subtitle: "Limits are read from files on this Mac when the island opens. Nothing is sent over the network.") {
            SettingsSection(title: "Sources") {
                source(name: "Claude Code",
                       isOn: Binding(get: { claudeConnected }, set: { _ in toggleClaude() }),
                       badge: claudeConnected ? connectedText : "Not connected", badgeIsGood: claudeConnected,
                       detail: "Shows your 5-hour and 7-day limits, read from Claude Code’s status line. Your own status line keeps working.",
                       note: "Turning this off puts your status line back exactly as it was.")
                if let claudeError {
                    Text(claudeError).font(SettingsStyle.caption).foregroundStyle(.red)
                }
                source(name: "Codex",
                       isOn: $usage.readsCodex,
                       badge: usage.readsCodex ? connectedText : "Off", badgeIsGood: usage.readsCodex,
                       detail: "Shows your 5-hour and weekly limits, read from Codex’s newest local session log. Nothing to set up.",
                       note: nil)
            }
            SettingsDivider()
            SettingsSection(title: "Display") {
                CheckRow(title: "Colour a limit amber from 80%", isOn: $usage.highlightsHighUse)
                CheckRow(title: "Show when each limit resets", isOn: $usage.showsResetTimes)
            }
        }
        .onAppear { claudeConnected = usage.isClaudeConnected }
    }

    private var connectedText: String {
        guard let lastRead = usage.lastRead else { return "Connected" }
        return "Connected · read \(lastRead.formatted(date: .omitted, time: .shortened))"
    }

    private func source(name: String, isOn: Binding<Bool>, badge: String, badgeIsGood: Bool, detail: String,
                        note: String?) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 9) {
                    Text(name).font(Typeface.text(12, weight: .semibold))
                    StatusBadge(text: badge, isGood: badgeIsGood)
                }
                Text(detail).font(Typeface.text(11)).foregroundStyle(SettingsStyle.muted)
                if let note {
                    Text(note).font(Typeface.text(10)).foregroundStyle(SettingsStyle.hint)
                }
            }
            Spacer(minLength: 0)
            Toggle(name, isOn: isOn)
                .labelsHidden()
                .toggleStyle(PillSwitchStyle())
        }
        .settingsTile(vertical: 13, horizontal: 14)
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
