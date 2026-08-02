import SwiftUI

enum Orientation: String, CaseIterable {
    case horizontal = "Horizontal"
    case vertical = "Vertical"

    var displayName: String {
        rawValue
    }

    var description: String {
        switch self {
        case .horizontal:
            "Landscape format"
        case .vertical:
            "Portrait format"
        }
    }

    var icon: String {
        switch self {
        case .horizontal:
            "rectangle"
        case .vertical:
            "rectangle.portrait"
        }
    }

    var color: Color {
        switch self {
        case .horizontal:
            .blue
        case .vertical:
            .purple
        }
    }
}
