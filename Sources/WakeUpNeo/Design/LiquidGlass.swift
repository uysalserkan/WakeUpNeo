import SwiftUI
import AppKit

// MARK: - macOS Liquid Glass Theme Design System

/// Design tokens and modifiers embodying Apple's next-generation macOS Liquid Glass design language.
/// Provides authentic macOS translucency, specular lighting rims, continuous rounded corners,
/// fluid hover states, and dynamic luminous glow accents.
public enum NativeLiquidTheme {
    public static let cardCornerRadius: CGFloat = 12
    public static let smallCornerRadius: CGFloat = 8
    public static let buttonCornerRadius: CGFloat = 7
    public static let pillCornerRadius: CGFloat = 20
}

// MARK: - 1. Liquid Glass Card Modifier

public struct LiquidGlassCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var cornerRadius: CGFloat = NativeLiquidTheme.cardCornerRadius
    var isHighlighted: Bool = false
    var glowColor: Color = .accentColor

    public func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    // Base translucent glass material
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            colorScheme == .dark
                                ? Color(nsColor: .controlBackgroundColor).opacity(isHighlighted ? 0.50 : 0.38)
                                : Color(nsColor: .controlBackgroundColor).opacity(isHighlighted ? 0.75 : 0.55)
                        )

                    // Subtle top specular inner highlight gradient (Liquid Glass sheen)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.25), location: 0.0),
                                    .init(color: Color.clear, location: 0.35)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    // Optional subtle active glow
                    if isHighlighted {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(glowColor.opacity(colorScheme == .dark ? 0.12 : 0.06))
                    }
                }
            }
            .overlay {
                // Precision Specular Rim (Apple Liquid Glass border)
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(
                                    color: isHighlighted
                                        ? glowColor.opacity(0.60)
                                        : (colorScheme == .dark ? Color.white.opacity(0.22) : Color.white.opacity(0.70)),
                                    location: 0.0
                                ),
                                .init(
                                    color: isHighlighted
                                        ? glowColor.opacity(0.25)
                                        : (colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.06)),
                                    location: 0.5
                                ),
                                .init(
                                    color: isHighlighted
                                        ? glowColor.opacity(0.15)
                                        : (colorScheme == .dark ? Color.white.opacity(0.02) : Color.black.opacity(0.02)),
                                    location: 1.0
                                )
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.75
                    )
            }
            .shadow(
                color: isHighlighted
                    ? glowColor.opacity(colorScheme == .dark ? 0.20 : 0.12)
                    : Color.black.opacity(colorScheme == .dark ? 0.18 : 0.06),
                radius: isHighlighted ? 10 : 6,
                x: 0,
                y: isHighlighted ? 3 : 2
            )
    }
}

// MARK: - 2. Liquid Glass Pill Preset Button Style

public struct LiquidGlassPillButtonStyle: ButtonStyle {
    var isSelected: Bool
    var tintColor: Color
    @Environment(\.colorScheme) private var colorScheme

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
            .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.90))
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background {
                ZStack {
                    if isSelected {
                        // Vibrant glowing gradient for active state
                        RoundedRectangle(cornerRadius: NativeLiquidTheme.pillCornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        tintColor.opacity(0.95),
                                        tintColor.opacity(0.75)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )

                        // Top inner specular sheen
                        RoundedRectangle(cornerRadius: NativeLiquidTheme.pillCornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    stops: [
                                        .init(color: Color.white.opacity(0.35), location: 0),
                                        .init(color: Color.clear, location: 0.5)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    } else {
                        // Translucent liquid glass pill
                        RoundedRectangle(cornerRadius: NativeLiquidTheme.pillCornerRadius, style: .continuous)
                            .fill(
                                colorScheme == .dark
                                    ? Color.white.opacity(configuration.isPressed ? 0.12 : 0.06)
                                    : Color.black.opacity(configuration.isPressed ? 0.08 : 0.04)
                            )
                    }
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: NativeLiquidTheme.pillCornerRadius, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? LinearGradient(
                                colors: [Color.white.opacity(0.50), Color.white.opacity(0.15)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            : LinearGradient(
                                colors: [
                                    colorScheme == .dark ? Color.white.opacity(0.16) : Color.white.opacity(0.50),
                                    colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.04)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                        lineWidth: 0.65
                    )
            }
            .shadow(
                color: isSelected ? tintColor.opacity(colorScheme == .dark ? 0.35 : 0.20) : Color.clear,
                radius: 6,
                x: 0,
                y: 2
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.75), value: configuration.isPressed)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isSelected)
    }
}

// MARK: - 3. Liquid Glass Row Hover Modifier

public struct LiquidGlassRowHoverModifier: ViewModifier {
    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme
    var cornerRadius: CGFloat = NativeLiquidTheme.smallCornerRadius

    public func body(content: Content) -> some View {
        content
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background {
                if isHovered {
                    ZStack {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                colorScheme == .dark
                                    ? Color.white.opacity(0.08)
                                    : Color.black.opacity(0.05)
                            )

                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(
                                colorScheme == .dark
                                    ? Color.white.opacity(0.14)
                                    : Color.black.opacity(0.08),
                                lineWidth: 0.5
                            )
                    }
                    .transition(.opacity)
                }
            }
            .contentShape(Rectangle())
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.12)) {
                    isHovered = hovering
                }
            }
    }
}

// MARK: - 4. Liquid Glow Modifier

public struct LiquidGlowModifier: ViewModifier {
    var color: Color
    var radius: CGFloat = 8
    var isActive: Bool = true

    public func body(content: Content) -> some View {
        content
            .shadow(
                color: isActive ? color.opacity(0.40) : Color.clear,
                radius: radius,
                x: 0,
                y: 0
            )
    }
}

// MARK: - View Extensions

public extension View {
    /// Applies the refined macOS Liquid Glass card background with specular rim and ambient depth.
    func liquidGlassCard(
        cornerRadius: CGFloat = NativeLiquidTheme.cardCornerRadius,
        isHighlighted: Bool = false,
        glowColor: Color = .accentColor
    ) -> some View {
        self.modifier(
            LiquidGlassCardModifier(
                cornerRadius: cornerRadius,
                isHighlighted: isHighlighted,
                glowColor: glowColor
            )
        )
    }

    /// Alias for backwards compatibility, using the liquid glass card design.
    func nativeMacOSCard(
        cornerRadius: CGFloat = NativeLiquidTheme.cardCornerRadius,
        isHighlighted: Bool = false
    ) -> some View {
        self.liquidGlassCard(cornerRadius: cornerRadius, isHighlighted: isHighlighted)
    }

    /// Applies interactive liquid glass hover highlight to menu rows and list items.
    func liquidMenuRowHover(cornerRadius: CGFloat = NativeLiquidTheme.smallCornerRadius) -> some View {
        self.modifier(LiquidGlassRowHoverModifier(cornerRadius: cornerRadius))
    }

    /// Alias for backwards compatibility.
    func nativeMenuRowHover() -> some View {
        self.liquidMenuRowHover()
    }

    /// Applies a luminous liquid glow effect around icons and badges.
    func liquidGlow(color: Color, radius: CGFloat = 8, isActive: Bool = true) -> some View {
        self.modifier(LiquidGlowModifier(color: color, radius: radius, isActive: isActive))
    }
}
