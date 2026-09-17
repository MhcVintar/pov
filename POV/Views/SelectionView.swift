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

            SelectionButton(appState.asset == nil ? "Open Library" : "Change Video") {
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
                        OrientationCard(
                            orientation: orientation,
                            isSelected: self.orientation == orientation,
                            action: { self.orientation = orientation }
                        )
                    }
                }
            }
            .padding(.horizontal, 8)

            SelectionButton("Process") {
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

private struct SelectionButton: View {
    let label: String
    let action: () -> Void

    init(_ label: String, action: @escaping () -> Void) {
        self.label = label
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(label)
                .foregroundStyle(.white)
                .font(.headline)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        }
        .background(.blue)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 8)
    }
}

private struct OrientationCard: View {
    let orientation: Orientation
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? orientation.color.opacity(0.15) : .clear)
                    .strokeBorder(isSelected ? orientation.color : .secondary.opacity(0.5), lineWidth: 2)
                    .frame(width: 60, height: 40)
                    .overlay {
                        Image(systemName: orientation.icon)
                            .foregroundStyle(isSelected ? orientation.color : .secondary)
                            .font(.title2)
                    }

                VStack(spacing: 2) {
                    Text(orientation.displayName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(isSelected ? orientation.color : .primary)

                    Text(orientation.description)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.secondary)
                }
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? orientation.color.opacity(0.1) : Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                isSelected ? orientation.color.opacity(0.5) : .secondary.opacity(0.5),
                                lineWidth: isSelected ? 2 : 1,
                            ),
                    ),
            )
        }
    }
}
