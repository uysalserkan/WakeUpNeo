import SwiftUI
import AppKit

// MARK: - Native macOS Design System

/// Design tokens and modifiers matching Apple's native macOS MenuBarExtra & Control Center conventions.
/// Emphasizes system typography, subtle materials, native control interaction, and clean vertical rhythm.
public enum NativeTheme {
    public static let popoverWidth: CGFloat = 300
    public static let rowCornerRadius: CGFloat = 6
    public static let segmentedCornerRadius: CGFloat = 7
    public static let innerSegmentCornerRadius: CGFloat = 5
}

// MARK: - Native Menu Row Hover Modifier

public struct NativeMenuRowHoverModifier: ViewModifier {
    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme
    var cornerRadius: CGFloat = NativeTheme.rowCornerRadius

    public func body(content: Content) -> some View {
        content
            .background {
                if isHovered {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            Color(nsColor: .selectedContentBackgroundColor)
                                .opacity(colorScheme == .dark ? 0.20 : 0.12)
                        )
                }
            }
            .contentShape(Rectangle())
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.10)) {
                    isHovered = hovering
                }
            }
    }
}

// MARK: - View Extensions

public extension View {
    /// Applies subtle standard macOS hover highlight to list rows and buttons.
    func nativeMenuRowHover(cornerRadius: CGFloat = NativeTheme.rowCornerRadius) -> some View {
        self.modifier(NativeMenuRowHoverModifier(cornerRadius: cornerRadius))
    }

    /// Alias for backwards compatibility.
    func liquidMenuRowHover(cornerRadius: CGFloat = NativeTheme.rowCornerRadius) -> some View {
        self.nativeMenuRowHover(cornerRadius: cornerRadius)
    }

    /// Legacy compatibility helper.
    func nativeMacOSCard(cornerRadius: CGFloat = 10, isHighlighted: Bool = false) -> some View {
        self
    }
}
