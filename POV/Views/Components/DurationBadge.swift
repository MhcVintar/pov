import SwiftUI

/// Bottom-left badge shown on video thumbnails, formatted `m:ss`.
struct DurationBadge: View {
    let duration: TimeInterval

    var body: some View {
        Text(duration.formattedDuration)
            .font(.caption.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(Color.overlayContent)
            .padding(.vertical, 5)
            .padding(.horizontal, 9)
            .background(Color.overlay.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
    }
}
