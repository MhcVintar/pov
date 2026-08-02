import SwiftUI

struct CompletionView: View {
    var body: some View {
        InfoComponent(
            icon: "checkmark.circle",
            iconColor: .green,
            title: "Video Processed",
            caption: "Your processed video has been saved to Photos."
        )
    }
}

#Preview {
    CompletionView()
}
