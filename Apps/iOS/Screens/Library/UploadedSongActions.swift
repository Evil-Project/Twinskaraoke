import SwiftUI

/// Edit and Delete for a row of the Uploaded list: trailing swipe actions
/// and the same two as accessibility actions. The row's menus get them
/// through `\.uploadedSongMenuActions`.
struct UploadedSongRowActions: ViewModifier {
    let song: Song
    let edit: (Song) -> Void
    let delete: (Song) -> Void

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                // Not `.destructive`: that role removes the row before the
                // confirmation has been answered.
                Button {
                    delete(song)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .tint(Color.appDestructive)

                Button {
                    edit(song)
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
            }
            .accessibilityAction(named: Text("Edit")) { edit(song) }
            .accessibilityAction(named: Text("Delete")) { delete(song) }
    }
}

/// The edit sheet, the delete confirmation and the failure alert for the
/// Uploaded list.
struct UploadedSongManagement: ViewModifier {
    let viewModel: UploadedSongsViewModel
    @Binding var editing: Song?
    @Binding var deleting: Song?
    @State private var deleteFailure: SongUploadFailure?

    func body(content: Content) -> some View {
        content
            .sheet(item: $editing) { song in
                EditUploadedSongSheet(song: song) { edit in
                    await viewModel.update(song, edit: edit)
                }
            }
            // An alert, not a confirmation dialog: on iPhone the dialog shows
            // as a popover by the row, without a Cancel button.
            .alert(
                Text("Delete “\(deleting?.title ?? "")”?"),
                isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                presenting: deleting
            ) { song in
                Button("Delete Song", role: .destructive) {
                    Task { await delete(song) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("The song is deleted permanently and removed from all your playlists.")
            }
            .alert(
                "Couldn't Delete Song",
                isPresented: Binding(get: { deleteFailure != nil }, set: { if !$0 { deleteFailure = nil } }),
                presenting: deleteFailure
            ) { _ in
                Button("OK") {}
            } message: { failure in
                Text(failure.userMessage)
            }
    }

    private func delete(_ song: Song) async {
        AppHaptic.dismiss.play()
        if let failure = await viewModel.delete(song) {
            AppHaptic.error.play()
            deleteFailure = failure
        }
    }
}
