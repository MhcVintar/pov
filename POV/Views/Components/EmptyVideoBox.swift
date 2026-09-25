import SwiftUI

/// The 4:3 box shown before a video is picked, and again (in its error styling)
/// after a wrong-aspect-ratio pick.
struct EmptyVideoBox: View {
    let isError: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.surface)
                .aspectRatio(4 / 3, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(
                            isError ? Color.red : Color.borderDashed,
                            style: StrokeStyle(lineWidth: 1.5, dash: [6])
                        )
                )
                .overlay {
                    VStack(spacing: 14) {
                        Image(systemName: "video.badge.plus")
                            .font(.system(size: 40))
                            .foregroundStyle(Color.accent)

                        VStack(spacing: 4) {
                            Text("Select a 4:3 video")
                                .font(.body.weight(.medium))
                                .foregroundStyle(Color.textPrimary)

                            Text("From your Photos library")
                                .font(.footnote)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    EmptyVideoBox(isError: false) {}
        .padding()
}
