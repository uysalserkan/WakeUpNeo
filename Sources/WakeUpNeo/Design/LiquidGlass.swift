import SwiftUI
import AppKit

// MARK: - Native macOS Design System

/// Design tokens and layout constants matching Apple's native macOS MenuBarExtra & Control Center conventions.
/// Emphasizes system typography, subtle materials, native control interaction, and clean vertical rhythm.
public enum NativeTheme {
    /// Standard width for macOS menu bar utility popovers (Control Center / Wi-Fi / Battery style).
    public static let popoverWidth: CGFloat = 320

    /// Layout Spacing Scale (4, 8, 12, 16, 20, 24)
    public static let horizontalPadding: CGFloat = 16
    public static let headerTopPadding: CGFloat = 14
    public static let headerBottomPadding: CGFloat = 12
    public static let sectionSpacing: CGFloat = 12
    public static let rowSpacing: CGFloat = 2
    public static let dividerVerticalPadding: CGFloat = 10
    public static let footerBottomPadding: CGFloat = 12

    /// Row & Component Sizing
    public static let rowIconWidth: CGFloat = 20
    public static let rowIconSize: CGFloat = 15
    public static let rowVerticalPadding: CGFloat = 5
    public static let rowHorizontalPadding: CGFloat = 6
    public static let rowCornerRadius: CGFloat = 6

    /// Segmented Control Sizing
    public static let segmentedHeight: CGFloat = 26
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

// MARK: - Standard Row Icon Container

public struct MenuRowIcon: View {
    let systemName: String
    var foregroundColor: Color = .secondary
    var size: CGFloat = NativeTheme.rowIconSize

    public init(_ systemName: String, color: Color = .secondary, size: CGFloat = NativeTheme.rowIconSize) {
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

