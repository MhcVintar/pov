import AVKit
import PhotosUI
import SwiftUI

struct SelectionView: View {
    @EnvironmentObject var appState: AppState

    @State private var showPicker = false
    @State private var photoItem: PhotosPickerItem?
    @State private var isLoading = false
    @State private var showWrongAspectRatio = false

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            videoArea

            VStack(alignment: .leading, spacing: 12) {
                Text("OUTPUT")
                    .font(.footnote.weight(.semibold))
                    .tracking(1.04)
                    .foregroundStyle(Color.textSecondary)

                OrientationControl(orientation: $appState.orientation)
            }

            Spacer(minLength: 0)

            VStack(spacing: 12) {
                if let hint {
                    Text(hint)
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                        .frame(maxWidth: .infinity)
                }

                PrimaryButton(title: "Continue to processing", isEnabled: appState.selectedVideo != nil) {
                    appState.navigationPath.append(NavigationDestination.processingView)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .background(Color.appBackground.ignoresSafeArea())
        .photosPicker(
            isPresented: $showPicker,
            selection: $photoItem,
            matching: .videos,
            photoLibrary: .shared()
        )
        .onChange(of: photoItem) { _, newItem in
            guard let item = newItem else { return }
            selectVideo(from: item)
        }
    }

    private var hint: String? {
        appState.selectedVideo == nil ? "Select a 4:3 video to continue" : nil
    }

    @ViewBuilder
    private var videoArea: some View {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                if isLoading {
                    LoadingVideoBox()
                } else if let video = appState.selectedVideo {
                    SelectedVideoBox(
                        video: video,
                        onReplace: { showPicker = true }
                    )
                } else {
                    EmptyVideoBox(isError: showWrongAspectRatio) {
                        showPicker = true
                    }
                }
            }

            if showWrongAspectRatio {
                Text("The video needs to be 4:3. Please choose a different one.")
                    .font(.subheadline)
                    .foregroundStyle(Color.red)
            }
        }
    }

    private func selectVideo(from item: PhotosPickerItem) {
        isLoading = true
        showWrongAspectRatio = false

        Task {
            do {
                let loaded = try await LibraryManager.loadAsset(from: item)

                async let thumbnailTask = LibraryManager.thumbnail(for: loaded.asset)
                let duration = try await loaded.asset.load(.duration)
                let thumbnail = await thumbnailTask

                await MainActor.run {
                    photoItem = nil
                    isLoading = false
                    appState.selectedVideo = SelectedVideo(
                        asset: loaded.asset,
                        fileName: loaded.fileName,
                        thumbnail: thumbnail,
                        duration: duration.seconds
                    )
                }
            } catch AppError.wrongAspectRatio {
                await MainActor.run {
                    photoItem = nil
                    isLoading = false
                    appState.selectedVideo = nil
                    showWrongAspectRatio = true
                }
            } catch {
                await MainActor.run {
                    photoItem = nil
                    isLoading = false
                    appState.selectedVideo = nil
                    showWrongAspectRatio = false
                    appState.present(error)
                }
            }
        }
    }
}

#Preview {
    SelectionView()
        .environmentObject(AppState())
}

/// The 4:3 box shown before a video is picked, and again (in its error styling)
/// after a wrong-aspect-ratio pick.
private struct EmptyVideoBox: View {
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

private struct LoadingVideoBox: View {
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

private struct SelectedVideoBox: View {
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
