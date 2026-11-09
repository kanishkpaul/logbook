import AppKit
import Carbon.HIToolbox
import LogbookUI
import SwiftUI

/// The floating Quick Entry pill, summoned from anywhere with ⌥Space.
final class QuickEntryPanel: NSPanel {
    init(today: TodayModel) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 80),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        backgroundColor = .clear
        let root = QuickEntryField(model: today, onDone: { [weak self] in self?.orderOut(nil) })
            .padding(14)
            .frame(width: 620)
            .glassEffect(.regular, in: .rect(cornerRadius: 18))
        let host = NSHostingView(rootView: root)
        host.sizingOptions = [.preferredContentSize]
        contentView = host
    }

    override var canBecomeKey: Bool { true }

    func toggle() {
        if isVisible {
            orderOut(nil)
            return
        }
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            setFrameTopLeftPoint(NSPoint(x: f.midX - frame.width / 2, y: f.maxY - f.height * 0.22))
        }
        NSApplication.shared.activate()
        makeKeyAndOrderFront(nil)
    }
}

/// A system-wide hotkey via Carbon's `RegisterEventHotKey` (no Accessibility
/// permission needed). Tries each candidate until one isn't taken by another
/// app (⌥Space is also ChatGPT's default). Lives for the app's lifetime.
final class GlobalHotKey {
    struct Combo {
        let keyCode: Int
        let modifiers: Int
        let label: String
    }

    static let candidates = [
        Combo(keyCode: kVK_Space, modifiers: optionKey, label: "⌥ Space"),
        Combo(keyCode: kVK_Space, modifiers: controlKey | optionKey, label: "⌃⌥ Space"),
        Combo(keyCode: kVK_ANSI_L, modifiers: controlKey | optionKey, label: "⌃⌥ L"),
    ]

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void
    /// The shortcut that was registered, if any.
    private(set) var active: Combo?

    init(action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            // Carbon delivers application events on the main thread.
            MainActor.assumeIsolated {
                Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue().action()
            }
            return noErr
        }, 1, &spec, me, &handlerRef)
        let id = EventHotKeyID(signature: OSType(0x4C4F_4742), id: 1) // "LOGB"
        for combo in Self.candidates {
            let status = RegisterEventHotKey(UInt32(combo.keyCode), UInt32(combo.modifiers), id, GetApplicationEventTarget(), 0, &hotKeyRef)
            if status == noErr, hotKeyRef != nil {
                active = combo
                break
            }
        }
    }
}
