enum Orientation: String, CaseIterable {
    case horizontal = "Horizontal"
    case vertical = "Vertical"

    var displayName: String {
        switch self {
        case .horizontal:
            "Landscape"
        case .vertical:
            "Portrait"
        }
    }
}
