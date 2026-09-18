import SwiftUI

struct InfoComponent: View {
    let icon: String
    let iconColor: Color
    let title: String
    let caption: String

    @State private var isIconEffectActive = true

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 60))
                .foregroundStyle(iconColor)
                .symbolEffect(.drawOn.individually, options: .nonRepeating, isActive: isIconEffectActive)

            Text(title)
                .font(.title)
                .fontWeight(.bold)

            Text(caption)
                .font(.callout)
                .multilineTextAlignment(.center)
        }
        .onAppear {
            isIconEffectActive = false
        }
        .onDisappear {
            // Reset so a re-appearance (e.g. the same view identity reused) has a
            // true -> false transition to animate again, instead of a no-op.
            isIconEffectActive = true
        }
    }
}

#Preview {
    InfoComponent(
        icon: "checkmark.arrow.trianglehead.clockwise",
        iconColor: .green,
        title: "Processing completed!",
        caption: "The processed video has been saved to Phots."
    )
}
