import SwiftUI

struct InfoComponent: View {
    let icon: String
    let iconColor: Color
    let title: String
    let caption: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 60))
                .foregroundStyle(iconColor)

            Text(title)
                .font(.title)
                .fontWeight(.bold)

            Text(caption)
                .font(.callout)
                .multilineTextAlignment(.center)
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
