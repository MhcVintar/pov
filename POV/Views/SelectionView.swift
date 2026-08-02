import SwiftUI
import PhotosUI

struct SelectionView: View {
    @EnvironmentObject var appState: AppState
    
    @State private var showPicker = false
    @State private var photoItem: PhotosPickerItem?
    
    var body: some View {
        VStack {
            Spacer()
            
            InfoComponent(
                icon: "video.badge.plus",
                iconColor: .blue,
                title: "Select a Video",
                caption: "Select a video from your Photos library."
            )
            
            Spacer()
            
            ButtonComponent("Open Library") {
                showPicker = true
            }
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
                    self.appState.navigationPath.append(NavigationDestination.configurationView)
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
    SelectionView()
}
