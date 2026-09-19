import PhotosUI
import SwiftUI

struct SelectionView: View {
    @EnvironmentObject var appState: AppState

    @Binding var orientation: Orientation

    @State private var showPicker = false
    @State private var photoItem: PhotosPickerItem?
    @State private var thumbnail: UIImage?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VideoPickerCard(thumbnail: thumbnail) {
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
                        let isSelected = self.orientation == orientation

                        Button {
                            self.orientation = orientation
                        } label: {
                            Text(orientation.displayName)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(isSelected ? Color.blue : .primary)
                                .frame(maxWidth: .infinity)
                                .frame(height: SelectionButton.height * 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(isSelected ? Color.blue.opacity(0.1) : Color(.systemBackground))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(
                                                    isSelected ? Color.blue.opacity(0.5) : .secondary.opacity(0.5),
                                                    lineWidth: isSelected ? 2 : 1
                                                )
                                        )
                                )
                        }
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
            photoLibrary: .shared()
        )
        .onChange(of: photoItem) { _, newItem in
            guard let item = newItem else { return }

            Task {
                do {
                    let asset = try await LibraryManager.loadAsset(from: item)

                    let thumbnail = await LibraryManager.thumbnail(for: asset)

                    await MainActor.run {
                        self.photoItem = nil
                        self.appState.asset = asset
                        self.thumbnail = thumbnail
                    }
                } catch {
                    await MainActor.run {
                        self.photoItem = nil
                        self.appState.asset = nil
                        self.thumbnail = nil
                        appState.present(error)
                    }
                }
            }
        }
    }
}

#Preview {
    SelectionView(orientation: .constant(.horizontal))
}

private struct VideoPickerCard: View {
    let thumbnail: UIImage?
    let action: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Button(action: action) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemBackground))
                    .frame(maxWidth: .infinity)
                    .aspectRatio(4 / 3, contentMode: .fit)
                    .overlay {
                        if let thumbnail {
                            Image(uiImage: thumbnail)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        } else {
                            VStack(spacing: 12) {
                                Image(systemName: "video.badge.plus")
                                    .font(.system(size: 40))
                                    .foregroundStyle(.blue)

                                Text("Tap to select a video")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(
                                thumbnail == nil ? Color.secondary.opacity(0.4) : Color.clear,
                                style: StrokeStyle(lineWidth: 2, dash: thumbnail == nil ? [8] : [])
                            )
                    )
            }
            .buttonStyle(.plain)

            if thumbnail != nil {
                Button("Change Video", action: action)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
        }
        .padding(.horizontal, 8)
    }
}

private struct SelectionButton: View {
    static let height: CGFloat = 52

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
                .frame(height: Self.height)
        }
        .background(.blue)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 8)
    }
}
