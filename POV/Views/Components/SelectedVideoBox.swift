import AVKit
import SwiftUI

struct SelectedVideoBox: View {
    let video: SelectedVideo
    let onReplace: () -> Void

    @State private var player: AVPlayer?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                if let player {
                    VideoPlayer(player: player)
                } else {
                    Group {
                        if let thumbnail = video.thumbnail {
                            Image(uiImage: thumbnail)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else {
                            Color.surface
                        }
                    }
                    .overlay(alignment: .bottomLeading) {
                        DurationBadge(duration: video.duration)
                            .padding(12)
                    }
                    .overlay {
                        Button {
                            player = AVPlayer(playerItem: AVPlayerItem(asset: video.asset))
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
            .frame(maxWidth: .infinity)
            .aspectRatio(4 / 3, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 20))

            HStack {
                Text(video.fileName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Button("Replace", action: onReplace)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.textPrimary)
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                    .background(Color.chip, in: Capsule())
            }
        }
    }
}
