import Carbon.HIToolbox
import Foundation

/// A key combination that works whichever app is in front, registered with `RegisterEventHotKey`.
///
/// That call is public, needs no permission (a global event monitor would need Accessibility), and costs nothing
/// while idle: macOS tells the app when the keys are pressed. Registering can fail, for instance when another
/// app already holds the combination; then `init` returns nil and the app simply has no shortcut.
@MainActor
final class GlobalShortcut {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    /// The four-character code that marks this app's hot keys.
    private static let signature: OSType = 0x42524F57 // "BROW"

    /// - Parameters:
    ///   - keyCode: A virtual key code, like `kVK_ANSI_Comma`.
    ///   - modifiers: Carbon modifier flags, like `cmdKey | optionKey`.
    init?(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let shortcut = Unmanaged<GlobalShortcut>.fromOpaque(userData).takeUnretainedValue()
            Task { @MainActor in shortcut.action() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard installed == noErr else { return nil }
        let registered = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers),
                                             EventHotKeyID(signature: Self.signature, id: 1),
                                             GetApplicationEventTarget(), 0, &hotKey)
        guard registered == noErr else {
            if let handler { RemoveEventHandler(handler) }
            return nil
        }
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
