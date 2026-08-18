import SwiftUI
import AppKit

// MARK: - Native macOS Liquid Theme Design System

/// Design tokens and modifiers matching Apple's native macOS Control Center & MenuBarExtra design language.
/// Provides authentic macOS translucency, continuous rounded corners, and native interaction states.

public enum NativeLiquidTheme {
    public static let cardCornerRadius: CGFloat = 10
    public static let smallCornerRadius: CGFloat = 6
    public static let buttonCornerRadius: CGFloat = 6
}

// MARK: - Native macOS Card ViewModifier

public struct NativeMacOSCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var cornerRadius: CGFloat = NativeLiquidTheme.cardCornerRadius
    var isHighlighted: Bool = false

    public func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        isHighlighted
                            ? Color.accentColor.opacity(colorScheme == .dark ? 0.14 : 0.08)
                            : Color(nsColor: .controlBackgroundColor).opacity(colorScheme == .dark ? 0.45 : 0.65)
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        isHighlighted
                            ? Color.accentColor.opacity(0.25)
                            : Color(nsColor: .separatorColor).opacity(colorScheme == .dark ? 0.20 : 0.12),
                        lineWidth: 0.5
                    )
            }
    }
}

// MARK: - Native Menu Row Hover

public struct NativeMenuRowHoverModifier: ViewModifier {
    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    public func body(content: Content) -> some View {
        content
            .background {
                if isHovered {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(nsColor: .selectedContentBackgroundColor).opacity(colorScheme == .dark ? 0.25 : 0.15))
                }
            }
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.12)) {
                    isHovered = hovering
                }
            }
    }
}

// MARK: - View Extensions

public extension View {
    /// Applies native macOS Control Center-style material card background and border.
    func nativeMacOSCard(cornerRadius: CGFloat = NativeLiquidTheme.cardCornerRadius, isHighlighted: Bool = false) -> some View {
        self.modifier(NativeMacOSCardModifier(cornerRadius: cornerRadius, isHighlighted: isHighlighted))
    }

    /// Applies standard macOS menu hover highlight.
    func nativeMenuRowHover() -> some View {
        self.modifier(NativeMenuRowHoverModifier())
    }
}
