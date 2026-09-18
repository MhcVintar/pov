import SwiftUI

struct CompletionView: View {
    var body: some View {
        InfoComponent(
            icon: "checkmark.arrow.trianglehead.clockwise",
            iconColor: .green,
            title: "Video Processed",
            caption: "Your processed video has been saved to Photos."
        )
    }
}

#Preview {
    CompletionView()
}
