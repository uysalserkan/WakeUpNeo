import SwiftUI
import AppKit

// MARK: - Liquid Glass Design System

/// Design tokens and Liquid Glass styling matching macOS modern translucent materials,
/// card surfaces, frosted glass pills, and vibrant accent states.
public enum NativeTheme {
    /// Standard width matching the assets layout (~284 pt).
    public static let popoverWidth: CGFloat = 286

    /// Outer Popover Padding
    public static let outerPadding: CGFloat = 10
    public static let cardSpacing: CGFloat = 8

    /// Card Properties
    public static let cardCornerRadius: CGFloat = 14
    public static let cardPadding: CGFloat = 12

    /// Pill Properties
    public static let pillCornerRadius: CGFloat = 10
    public static let pillHeight: CGFloat = 28
    public static let rowCornerRadius: CGFloat = 8
    public static let rowIconWidth: CGFloat = 20
    public static let rowSpacing: CGFloat = 6
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

// MARK: - Liquid Glass Card Modifier

public struct LiquidGlassCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    public func body(content: Content) -> some View {
        content
            .padding(NativeTheme.cardPadding)
            .background {
                RoundedRectangle(cornerRadius: NativeTheme.cardCornerRadius, style: .continuous)
                    .fill(
                        colorScheme == .dark
                            ? Color(nsColor: .windowBackgroundColor).opacity(0.65)
                            : Color(nsColor: .controlBackgroundColor).opacity(0.85)
                    )
                    .background(
                        RoundedRectangle(cornerRadius: NativeTheme.cardCornerRadius, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: NativeTheme.cardCornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.14 : 0.40),
                                Color.white.opacity(colorScheme == .dark ? 0.04 : 0.10)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.75
                    )
            }
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.25 : 0.06),
                radius: 6,
                x: 0,
                y: 2
            )
    }
}

// MARK: - Liquid Glass Pill Modifier

public struct LiquidGlassPillModifier: ViewModifier {
    var isSelected: Bool = false
    var activeColor: Color = .accentColor
    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    public func body(content: Content) -> some View {
        content
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: NativeTheme.pillCornerRadius, style: .continuous)
                        .fill(activeColor)
                        .shadow(color: activeColor.opacity(0.35), radius: 4, x: 0, y: 1)
                } else {
                    RoundedRectangle(cornerRadius: NativeTheme.pillCornerRadius, style: .continuous)
                        .fill(
                            colorScheme == .dark
                                ? Color.white.opacity(isHovered ? 0.14 : 0.08)
                                : Color.black.opacity(isHovered ? 0.09 : 0.05)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: NativeTheme.pillCornerRadius, style: .continuous)
                                .strokeBorder(
                                    Color.white.opacity(colorScheme == .dark ? 0.08 : 0.20),
                                    lineWidth: 0.5
                                )
                        }
                }
            }
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.12)) {
                    isHovered = hovering
                }
            }
    }
}

// MARK: - Standard Row Icon

public struct MenuRowIcon: View {
    let systemName: String
    var foregroundColor: Color = .secondary
    var size: CGFloat = 15

    public init(_ systemName: String, color: Color = .secondary, size: CGFloat = 15) {
        self.systemName = systemName
        self.foregroundColor = color
        self.size = size
    }

    public var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size))
            .foregroundStyle(foregroundColor)
            .frame(width: NativeTheme.rowIconWidth, alignment: .center)
            .accessibilityHidden(true)
    }
}

// MARK: - View Extensions

public extension View {
    /// Wraps content in a frosted Liquid Glass card container.
    func liquidGlassCard() -> some View {
        self.modifier(LiquidGlassCardModifier())
    }

    /// Styles an interactive button as a frosted Liquid Glass pill.
    func liquidGlassPill(isSelected: Bool = false, activeColor: Color = .accentColor) -> some View {
        self.modifier(LiquidGlassPillModifier(isSelected: isSelected, activeColor: activeColor))
    }

    /// Applies subtle standard macOS hover highlight to list rows.
    func nativeMenuRowHover(cornerRadius: CGFloat = NativeTheme.rowCornerRadius) -> some View {
        self.modifier(NativeMenuRowHoverModifier(cornerRadius: cornerRadius))
    }
}


