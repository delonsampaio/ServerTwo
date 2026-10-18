import SwiftUI

/// Posts text to VoiceOver as an accessibility announcement.
enum VoiceOverAnnouncement {
    @MainActor
    static func post(_ text: String) {
        var message = AttributedString(text)
        // High priority interrupts other speech and cannot itself be
        // interrupted: the latest announcement wins for rapid taps, and a
        // following focus change does not cut it off. This is the one place to
        // change if on-device checks show it overlapping VoiceOver's own label
        // reading (`.low` queues behind it, `.default` is interruptible).
        message.accessibilitySpeechAnnouncementPriority = .high
        AccessibilityNotification.Announcement(message).post()
    }
}
