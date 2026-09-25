import AVKit
import SwiftUI

struct CompletionView: View {
    @Environment(AppState.self) private var appState

    @State private var player: AVPlayer?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()

                if let outputVideo = appState.outputVideo {
                    ShareLink(item: outputVideo.url) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 22))
                            .foregroundStyle(Color.accent)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Share video")
                }
            }

            Spacer()

            VStack(spacing: 24) {
                resultPreview

                VStack(spacing: 6) {
                    Text("Your video is ready")
                        .font(.body.weight(.medium))
                        .foregroundStyle(Color.textPrimary)

                    Text("Reframed to \(appState.orientation.displayName.lowercased()) and saved to Photos")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                }
            }

            Spacer()

            PrimaryButton(title: "Reframe another video", isEnabled: true) {
                appState.reset()
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .background(Color.appBackground.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }

    @ViewBuilder
    private var resultPreview: some View {
        if let outputVideo = appState.outputVideo {
            Group {
                if let player {
                    VideoPlayer(player: player)
                } else {
                    Group {
                        if let thumbnail = outputVideo.thumbnail {
                            Image(uiImage: thumbnail)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else {
                            Color.surface
                        }
                    }
                    .overlay(alignment: .bottomLeading) {
                        DurationBadge(duration: outputVideo.duration)
                            .padding(12)
                    }
                    .overlay {
                        Button {
                            player = AVPlayer(url: outputVideo.url)
                            player?.play()
                        } label: {
                            Circle()
                                .fill(Color.overlay.opacity(0.6))
                                .frame(width: 64, height: 64)
                                .overlay {
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 24))
                                        .foregroundStyle(Color.overlayContent)
                                }
                        }
                        .accessibilityLabel("Play video")
                    }
                }
            }
            .aspectRatio(outputVideo.orientation == .vertical ? 9.0 / 16.0 : 16.0 / 9.0, contentMode: .fit)
            .frame(maxWidth: outputVideo.orientation == .vertical ? 300 : .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
    }
}

#Preview {
    CompletionView()
        .environment(AppState())
}
