import AVKit
import PhotosUI
import SwiftUI

struct SelectionView: View {
    @Environment(AppState.self) private var appState

    @State private var showPicker = false
    @State private var photoItem: PhotosPickerItem?
    @State private var isLoading = false
    @State private var showWrongFileFormat = false

    var body: some View {
        @Bindable var appState = appState

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
                    EmptyVideoBox(isError: showWrongFileFormat) {
                        showPicker = true
                    }
                }
            }

            if showWrongFileFormat {
                Text("This doesn't look like a valid 4:3 video. Please choose a different one.")
                    .font(.subheadline)
                    .foregroundStyle(Color.red)
            }
        }
    }

    private func selectVideo(from item: PhotosPickerItem) {
        isLoading = true
        showWrongFileFormat = false

        Task {
            do {
                let loaded = try await LibraryManager.loadAsset(from: item)

                async let thumbnailTask = LibraryManager.thumbnail(for: loaded.asset)
                let duration = try await loaded.asset.load(.duration)
                let thumbnail = await thumbnailTask

                photoItem = nil
                isLoading = false
                appState.selectedVideo = SelectedVideo(
                    asset: loaded.asset,
                    fileName: loaded.fileName,
                    thumbnail: thumbnail,
                    duration: duration.seconds
                )
            } catch {
                photoItem = nil
                isLoading = false
                appState.selectedVideo = nil
                showWrongFileFormat = true
            }
        }
    }
}

#Preview {
    SelectionView()
        .environment(AppState())
}
