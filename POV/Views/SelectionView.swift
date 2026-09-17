import SwiftUI
import PhotosUI

struct SelectionView: View {
    @EnvironmentObject var appState: AppState

    @Binding var orientation: Orientation

    @State private var showPicker = false
    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            InfoComponent(
                icon: "video.badge.plus",
                iconColor: .blue,
                title: "Select a Video",
                caption: "Select a video from your Photos library."
            )

            ButtonComponent(appState.asset == nil ? "Open Library" : "Change Video") {
                showPicker = true
            }

            Spacer()

            VStack(spacing: 14) {
                Text("Orientation")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 14)

                HStack(spacing: 8) {
                    ForEach(Orientation.allCases, id: \.self) { orientation in
                        ClickableCardComponent(data: ClickableCardData(
                            color: orientation.color,
                            icon: orientation.icon,
                            isSelected: self.orientation == orientation,
                            label: orientation.displayName,
                            caption: orientation.description,
                            action: { self.orientation = orientation }
                        ))
                    }
                }
            }
            .padding(.horizontal, 8)

            ButtonComponent("Process") {
                appState.navigationPath.append(NavigationDestination.processingView)
            }
            .disabled(appState.asset == nil)
            .opacity(appState.asset == nil ? 0.5 : 1)
        }
        .photosPicker(
            isPresented: $showPicker,
            selection: $photoItem,
            matching: .videos,
            photoLibrary: .shared())
        .onChange(of: photoItem) { _, newItem in
            guard let item = newItem else { return }

            Task {
                let asset = try await getAVAsset(from: item)

                // TODO: make sure the asset is a 4:3

                await MainActor.run {
                    self.photoItem = nil
                    self.appState.asset = asset
                }
            }
        }
    }

    private func getAVAsset(from item: PhotosPickerItem) async throws -> AVAsset {
        guard let assetIdentifier = item.itemIdentifier else {
            throw AppError.recoverableError("Failed to get asset identifier.")
        }

        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)
        guard let phAsset = fetchResult.firstObject else {
            throw AppError.recoverableError("Failed to load PHAsset.")
        }

        return try await withCheckedThrowingContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.version = .original
            options.deliveryMode = .highQualityFormat

            PHImageManager.default().requestAVAsset(forVideo: phAsset, options: options) { avAsset, _, info in
                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let avAsset else {
                    continuation.resume(throwing: AppError.recoverableError("Failed to load AVAsset."))
                    return
                }

                continuation.resume(returning: avAsset)
            }
        }
    }
}

#Preview {
    SelectionView(orientation: .constant(.horizontal))
}
