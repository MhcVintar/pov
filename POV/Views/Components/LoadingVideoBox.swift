import SwiftUI

struct LoadingVideoBox: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(Color.surface)
            .aspectRatio(4 / 3, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay {
                ProgressView()
                    .tint(Color.accent)
            }
    }
}

#Preview {
    LoadingVideoBox()
        .padding()
}
