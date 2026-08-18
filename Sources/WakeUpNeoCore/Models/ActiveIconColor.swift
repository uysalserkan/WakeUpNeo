import Foundation
import SwiftUI

// MARK: - ActiveIconColor

/// User-selectable active icon and accent color for WakeUpNeo.
public enum ActiveIconColor: String, CaseIterable, Identifiable, Sendable, Codable {
    case red
    case green
    case blue
    case orange
    case purple
    case pink
    case cyan
    case yellow

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .red:    return "Red"
        case .green:  return "Green"
        case .blue:   return "Blue"
        case .orange: return "Orange"
        case .purple: return "Purple"
        case .pink:   return "Pink"
        case .cyan:   return "Cyan"
        case .yellow: return "Yellow"
        }
    }

    public var color: Color {
        switch self {
        case .red:    return .red
        case .green:  return .green
        case .blue:   return .blue
        case .orange: return .orange
        case .purple: return .purple
        case .pink:   return .pink
        case .cyan:   return .cyan
        case .yellow: return .yellow
        }
    }
}
