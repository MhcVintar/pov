import SwiftUI

/// Custom two-option segmented control for choosing landscape vs. portrait output.
/// The native segmented `Picker` is only 32pt tall and can't show an icon and a
/// label together, so this is hand-rolled instead.
struct OrientationControl: View {
    @Binding var orientation: Orientation

    var body: some View {
        HStack(spacing: 4) {
            segment(for: .horizontal, label: "Landscape")
            segment(for: .vertical, label: "Portrait")
        }
        .padding(4)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.segmentBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func segment(for value: Orientation, label: String) -> some View {
        let isSelected = orientation == value

        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                orientation = value
            }
        } label: {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(isSelected ? Color.segmentSelectedText : Color.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.segmentSelectedFill : Color.clear)
            )
            .selectedSegmentShadow(isSelected)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private extension View {
    /// The design only calls for the selected segment's shadow in light mode.
    @ViewBuilder
    func selectedSegmentShadow(_ isSelected: Bool) -> some View {
        modifier(SelectedSegmentShadowModifier(isSelected: isSelected))
    }
}

private struct SelectedSegmentShadowModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let isSelected: Bool

    func body(content: Content) -> some View {
        let showShadow = isSelected && colorScheme == .light
        // `textPrimary` is exactly `#1C1A18` in light mode (the only mode this shadow shows in).
        content.shadow(color: Color.textPrimary.opacity(showShadow ? 0.12 : 0), radius: 3, x: 0, y: 1)
    }
}

#Preview {
    OrientationControl(orientation: .constant(.horizontal))
        .padding()
}
