#if canImport(SwiftUI)
import SwiftUI
import FieldSession

// The external trigger: a Bluetooth key that takes a measurement without the screen
// being touched, or looked at.
//
// ## Two kinds of remote, and why the order matters
//
// Most cheap "Bluetooth shutter" remotes present themselves as a **HID keyboard** and
// send a volume-up, Enter or Space key press. Those are handled by `onKeyPress`, which
// is supported API and needs no tricks — so it is the primary path here.
//
// Some remotes instead drive the audio route's volume, with no key event at all. The
// usual way to catch that is to observe `AVAudioSession.outputVolume` and treat a change
// as a press. It works, but it has to hold an audio session, it fights the real volume
// control, and it stops reporting once the volume is already at either end of its range,
// so it has to keep nudging the level back to the middle. It is a fallback, labelled as
// one, and it lives in its own file so nothing else depends on it.
//
// **None of this file has been run.** The decisions a trigger could get wrong — what a
// press means in each state, how a key repeat is told from a deliberate second press,
// what may be accepted without looking — are all in `FieldSession`, where they are
// tested. What is left here is plumbing.

/// Key presses that count as the external trigger.
///
/// Deliberately a named set rather than "any key": a remote that sends something else
/// should be discovered on the device and added here, not caught by a rule broad enough
/// to fire on a stray keyboard.
///
/// What is **not** in this list is the volume keys. A HID remote that sends volume
/// up/down does reach `onKeyPress`, but the key equivalent it arrives as is not
/// something to guess at — a wrong constant here would simply never match, and the
/// failure would look like a flat battery. Plug the remote in, log
/// `press.key.character.unicodeScalars`, and add what it actually sends. Until then,
/// a volume-only remote needs the audio-session fallback described at the top of this
/// file.
public enum ExternalTriggerKey: Sendable {

    public static let keys: Set<KeyEquivalent> = [
        .return,
        .space,
        .upArrow,
        .downArrow
    ]
}

public extension View {

    /// Routes external key presses to one action.
    ///
    /// The action is called once per key-down. Debouncing is **not** done here: the
    /// recorder debounces with the press timestamp, so that a repeat is judged by the
    /// same rule whether it came from a key, the screen, or a test.
    func onExternalTrigger(perform action: @escaping () -> Void) -> some View {
        #if os(iOS) || os(macOS) || os(visionOS)
        return self.onKeyPress(phases: .down) { press in
            guard ExternalTriggerKey.keys.contains(press.key) else { return .ignored }
            action()
            return .handled
        }
        #else
        return self
        #endif
    }
}
#endif
