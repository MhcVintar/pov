import SwiftUI

enum Quality: String, CaseIterable {
    case uhd4k = "4K"
    case k27 = "2.7K"
    case fullhd = "1080p"

    var displayName: String {
        rawValue
    }

    var description: String {
        switch self {
        case .uhd4k:
            "Ultra HD"
        case .k27:
            "High Quality"
        case .fullhd:
            "Standard HD"
        }
    }

    var icon: String {
        switch self {
        case .uhd4k:
            "4k.tv"
        case .k27:
            "tv"
        case .fullhd:
            "tv.fill"
        }
    }

    var color: Color {
        switch self {
        case .uhd4k:
            .red
        case .k27:
            .orange
        case .fullhd:
            .green
        }
    }

    var size4by3: CGSize {
        switch self {
        case .uhd4k:
            CGSize(width: 3840, height: 2880)
        case .k27:
            CGSize(width: 2704, height: 2028)
        case .fullhd:
            CGSize(width: 1920, height: 1440)
        }
    }
    
    var size16by9: CGSize {
        switch self {
        case .uhd4k:
            CGSize(width: 3840, height: 2160)
        case .k27:
            CGSize(width: 2704, height: 1521)
        case .fullhd:
            CGSize(width: 1920, height: 1080)
        }
    }
    
    var size9by16: CGSize {
        switch self {
        case .uhd4k:
            CGSize(width: 2160, height: 3840)
        case .k27:
            CGSize(width: 1521, height: 2704)
        case .fullhd:
            CGSize(width: 1080, height: 1920)
        }
    }
}
