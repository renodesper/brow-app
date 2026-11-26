import SwiftUI

/// The Settings window's look from the design canvas: a light page, a pill sidebar, Manrope headings, bordered
/// selects and number fields, pill choices and tinted tiles. Sizes are the canvas's pixels divided by 1.25.
enum SettingsStyle {
    static let ink = Color(rgb: 0x191C21)
    static let muted = Color(rgb: 0x424752)
    static let hint = Color(rgb: 0x727783)
    /// The sidebar, tiles and unselected pills.
    static let surface = Color(rgb: 0xF2F3FB)
    static let outline = Color(rgb: 0xE1E2EA)
    static let dashed = Color(rgb: 0xC2C6D4)
    static let dangerFill = Color(rgb: 0xFFDAD6)
    static let dangerText = Color(rgb: 0x93000A)
    static let goodFill = Color(rgb: 0xD1FAE5)
    static let goodText = Color(rgb: 0x065F46)

    static let body = Typeface.text(12)
    static let label = Typeface.text(11, weight: .semibold)
    static let caption = Typeface.text(10.5)
    static let controlHeight: CGFloat = 34
    static let tileRadius: CGFloat = 13
}

extension Color {
    init(rgb: UInt32) {
        self.init(red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255,
                  blue: Double(rgb & 0xFF) / 255)
    }
}

// MARK: - Page structure

/// One pane: a title, an optional line under it, and its sections.
struct SettingsPage<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(Typeface.number(20))
                        .accessibilityAddTraits(.isHeader)
                    if let subtitle {
                        Text(subtitle).font(SettingsStyle.body).foregroundStyle(SettingsStyle.muted)
                    }
                }
                content
            }
            .foregroundStyle(SettingsStyle.ink)
            .padding(.horizontal, 32)
            .padding(.vertical, 26)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A heading with its controls, optionally with a line of explanation or a note on the right.
struct SettingsSection<Content: View>: View {
    let title: String
    var detail: String?
    var trailing: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(Typeface.number(16, weight: .bold)).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 12)
                if let trailing {
                    Text(trailing).font(SettingsStyle.label).foregroundStyle(Palette.navy)
                }
            }
            if let detail {
                Text(detail).font(SettingsStyle.caption).foregroundStyle(SettingsStyle.hint)
            }
            content
        }
    }
}

struct SettingsDivider: View {
    var body: some View {
        Rectangle().fill(SettingsStyle.surface).frame(height: 1)
    }
}

extension View {
    /// A rounded tinted block, like the calendar access row or an AI usage source.
    func settingsTile(vertical: CGFloat = 11, horizontal: CGFloat = 13) -> some View {
        padding(.vertical, vertical)
            .padding(.horizontal, horizontal)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SettingsStyle.surface, in: RoundedRectangle(cornerRadius: SettingsStyle.tileRadius, style: .continuous))
    }
}

// MARK: - Sidebar

struct SettingsSidebar: View {
    @Binding var selection: SettingsPane

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(SettingsPane.allCases) { pane in
                let isSelected = pane == selection
                Button { selection = pane } label: {
                    HStack(spacing: 8) {
                        Image(systemName: pane.symbol).frame(width: 16)
                        Text(pane.title)
                        Spacer(minLength: 0)
                    }
                    .font(Typeface.text(11.5, weight: isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? Palette.navy : SettingsStyle.muted)
                    .padding(.horizontal, 11)
                    .frame(height: 32)
                    .background {
                        if isSelected {
                            Capsule().fill(.white).shadow(color: .black.opacity(0.05), radius: 1, y: 1)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        // Room for the window's traffic lights, which sit on top of the sidebar.
        .padding(EdgeInsets(top: 38, leading: 10, bottom: 12, trailing: 10))
        .frame(width: 180)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(SettingsStyle.surface.ignoresSafeArea())
    }
}

// MARK: - Controls

/// A checkbox: navy when on, a thin grey outline when off.
struct CheckboxStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(alignment: .top, spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(configuration.isOn ? Palette.navy : .white)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(configuration.isOn ? Palette.navy : SettingsStyle.hint, lineWidth: 1.3)
                    if configuration.isOn {
                        Image(systemName: "checkmark").font(.system(size: 8.5, weight: .heavy)).foregroundStyle(.white)
                    }
                }
                .frame(width: 15, height: 15)
                .padding(.top, 0.5)
                configuration.label
            }
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
    }
}

/// A pill switch, for a source that is connected or not.
struct PillSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            Capsule()
                .fill(configuration.isOn ? Palette.navy : SettingsStyle.dashed)
                .frame(width: 42, height: 26)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle().fill(.white).shadow(color: .black.opacity(0.2), radius: 1, y: 1)
                        .frame(width: 21, height: 21)
                        .padding(2.5)
                }
                .animation(.snappy(duration: 0.18), value: configuration.isOn)
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
    }
}

/// A checkbox row with its label and an optional line of explanation.
struct CheckRow: View {
    let title: String
    var detail: String?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(SettingsStyle.body)
                if let detail {
                    Text(detail).font(SettingsStyle.caption).foregroundStyle(SettingsStyle.hint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .toggleStyle(CheckboxStyle())
    }
}

/// One choice of a group, with a round marker.
struct RadioRow<Value: Hashable>: View {
    let title: String
    var detail: String?
    let value: Value
    @Binding var selection: Value

    var body: some View {
        let isSelected = selection == value
        Button { selection = value } label: {
            HStack(alignment: .top, spacing: 8) {
                ZStack {
                    Circle().fill(.white)
                    Circle().strokeBorder(isSelected ? Palette.navy : SettingsStyle.hint, lineWidth: 1.3)
                    if isSelected { Circle().fill(Palette.navy).frame(width: 7.5, height: 7.5) }
                }
                .frame(width: 15, height: 15)
                .padding(.top, 0.5)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(SettingsStyle.body)
                    if let detail {
                        Text(detail).font(SettingsStyle.caption).foregroundStyle(SettingsStyle.hint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A bordered pop-up for choosing one value.
struct Select<Value: Hashable>: View {
    let label: String
    @Binding var selection: Value
    let options: [(value: Value, title: String)]
    var minWidth: CGFloat = 150

    var body: some View {
        let current = options.first { $0.value == selection }?.title ?? ""
        Menu {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                Button { selection = option.value } label: {
                    if option.value == selection {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(current).font(SettingsStyle.body).foregroundStyle(SettingsStyle.ink)
                Spacer(minLength: 6)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(SettingsStyle.hint)
            }
            .padding(.horizontal, 10)
            .frame(minWidth: minWidth, minHeight: SettingsStyle.controlHeight)
            .background(.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(SettingsStyle.outline, lineWidth: 1.6))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(label)
    }
}

/// A bordered whole-number field with a unit after it. Out-of-range input is brought back into range.
struct NumberField: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let unit: String

    var body: some View {
        let clamped = Binding(get: { value }, set: { value = min(max($0, range.lowerBound), range.upperBound) })
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(SettingsStyle.label)
            HStack(spacing: 6) {
                TextField(label, value: clamped, format: .number)
                    .textFieldStyle(.plain)
                    .font(SettingsStyle.body)
                    .padding(.horizontal, 10)
                    .frame(height: SettingsStyle.controlHeight)
                    .background(.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(SettingsStyle.outline, lineWidth: 1.6))
                    .accessibilityLabel(label)
                    .accessibilityValue("\(value) \(unit)")
                    .accessibilityAdjustableAction { direction in
                        clamped.wrappedValue = value + (direction == .increment ? 1 : -1)
                    }
                Text(unit).font(SettingsStyle.caption).foregroundStyle(SettingsStyle.hint)
            }
        }
    }
}

/// A rounded choice among a few, like a Keep Awake length: pale blue with a navy outline when picked.
struct PillChoice: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Typeface.text(11.5, weight: isSelected ? .bold : .semibold))
                .foregroundStyle(isSelected ? Palette.navy : SettingsStyle.muted)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: SettingsStyle.controlHeight)
                .background(isSelected ? Palette.paleBlue : SettingsStyle.surface, in: Capsule())
                .overlay { if isSelected { Capsule().strokeBorder(Palette.navy, lineWidth: 1.6) } }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A text-only button in the accent colour.
struct GhostButtonStyle: ButtonStyle {
    var tint: Color = Palette.navy

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typeface.text(11, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(tint.opacity(configuration.isPressed ? 0.12 : 0), in: Capsule())
            .contentShape(Capsule())
    }
}

/// A button that removes something: pale red with dark red text.
struct DangerButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typeface.text(11.5, weight: .semibold))
            .foregroundStyle(SettingsStyle.dangerText)
            .padding(.horizontal, 13)
            .frame(height: 32)
            .background(SettingsStyle.dangerFill.opacity(configuration.isPressed ? 0.7 : 1), in: Capsule())
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Capsule())
    }
}

/// A small status pill, like "Allowed" or "Connected".
struct StatusBadge: View {
    let text: String
    var isGood = true

    var body: some View {
        Text(text)
            .font(Typeface.text(10, weight: .semibold))
            .foregroundStyle(isGood ? SettingsStyle.goodText : SettingsStyle.muted)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(isGood ? SettingsStyle.goodFill : SettingsStyle.outline, in: Capsule())
    }
}
