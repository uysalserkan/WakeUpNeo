import SwiftUI
import AppKit

// MARK: - MenuBarFooterView

/// Footer actions: "Settings…" (⌘,) and "Quit WakeUpNeo" (⌘Q).
/// Uses clean standard list row styling with aligned keyboard shortcuts and native hover states.
struct MenuBarFooterView: View {

    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(spacing: NativeTheme.rowSpacing) {
            // Settings Row
            Button {
                onOpenSettings()
            } label: {
                HStack(spacing: 8) {
                    MenuRowIcon("gearshape", color: .secondary)

                    Text("Settings…")
                        .font(.body)
                        .foregroundStyle(.primary)

                    Spacer(minLength: 8)

                    Text("⌘,")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, NativeTheme.rowHorizontalPadding)
                .padding(.vertical, NativeTheme.rowVerticalPadding)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .nativeMenuRowHover()
            .keyboardShortcut(",", modifiers: .command)
            .accessibilityLabel("Open Settings")

            // Quit Row
            Button {
                onQuit()
            } label: {
                HStack(spacing: 8) {
                    MenuRowIcon("power", color: .secondary)

                    Text("Quit WakeUpNeo")
                        .font(.body)
                        .foregroundStyle(.primary)

                    Spacer(minLength: 8)

                    Text("⌘Q")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, NativeTheme.rowHorizontalPadding)
                .padding(.vertical, NativeTheme.rowVerticalPadding)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .nativeMenuRowHover()
            .keyboardShortcut("q", modifiers: .command)
            .accessibilityLabel("Quit WakeUpNeo")
        }
    }
}
