import SwiftUI
import WakeUpNeoCore

// MARK: - MenuBarIcon

/// The image shown in the system menu bar for WakeUpNeo.
///
/// - Inactive: `eye.slash` (or monochrome prompt) — subtle, blends into the menu bar.
/// - Active:   `eye.fill` — filled, system accent color. Clearly signals that your Mac is awake.
///
/// A symbol effect fires on each state transition to provide subtle,
/// calm feedback without animation loops.
struct MenuBarIcon: View {

    let isActive: Bool

    var body: some View {
        Image(systemName: isActive ? "eye.fill" : "eye.slash")
            .symbolEffect(.bounce, value: isActive)
            .foregroundStyle(isActive ? Color.accentColor : .primary)
            .accessibilityLabel(isActive ? "WakeUpNeo is active" : "WakeUpNeo is inactive")
    }
}
