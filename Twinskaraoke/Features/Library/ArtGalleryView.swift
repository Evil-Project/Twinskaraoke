import Combine
import SwiftUI

struct GalleryArtist: Codable, Identifiable, Equatable {
  let id: String
  let name: String
  let socialLink: String?
  let userId: String?
  let arts: [GalleryArt]?
}

struct GalleryArt: Codable, Identifiable, Equatable {
  let id: String
  let fileName: String?
  let description: String?
  let credit: String?
  let cloudflareId: String?
  let absolutePath: String?
  let upvotes: Int?
  var imageURL: URL? {
    if let identifier = cloudflareId {
      return URL(string: "https://images.neurokaraoke.com/\(identifier)/public")
    }
    guard let path = absolutePath else { return nil }
    return URL(string: "https://images.neurokaraoke.com" + path + "/quality=95")
  }
  var blurPreviewURL: URL? {
    guard let path = absolutePath else { return nil }
    return URL(string: "https://images.neurokaraoke.com" + path + "/width=20,quality=30,blur=30")
  }
}

class ArtGalleryViewModel: ObservableObject {
  @Published var artists: [GalleryArtist] = []
  @Published var isLoading = false
  func fetch() {
    guard artists.isEmpty else { return }
    guard let url = URL(string: "https://api.neurokaraoke.com/api/media/artists?loadArts=true")
    else { return }
    isLoading = true
    var request = URLRequest(url: url)
    request.setValue(GuestIdentity.current, forHTTPHeaderField: "x-guest-id")
    URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
      guard let self = self else { return }
      if let data, let decoded = try? JSONDecoder().decode([GalleryArtist].self, from: data) {
        let filtered = decoded.filter { ($0.arts?.count ?? 0) > 0 }
          .sorted { ($0.arts?.count ?? 0) > ($1.arts?.count ?? 0) }
        DispatchQueue.main.async {
          self.artists = filtered
          self.isLoading = false
        }
      } else {
        DispatchQueue.main.async { self.isLoading = false }
      }
    }.resume()
  }
}

struct ArtGalleryView: View {
  @StateObject private var viewModel = ArtGalleryViewModel()
  var body: some View {
    ScrollView {
      if viewModel.isLoading && viewModel.artists.isEmpty {
        LoadingIndicator(size: 64)
          .frame(maxWidth: .infinity)
          .padding(.top, 120)
      } else if viewModel.artists.isEmpty {
        VStack(spacing: 16) {
          Image(systemName: "paintpalette")
            .font(.system(size: 48))
            .foregroundColor(.secondary)
          Text("No artwork yet")
            .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 120)
      } else {
        VStack(alignment: .leading, spacing: 28) {
          if let featured = featuredArt {
            NavigationLink {
              ArtDetailView(art: featured.art, artist: featured.artist)
            } label: {
              FeaturedArtCard(art: featured.art, artist: featured.artist)
            }
            .buttonStyle(PressableButtonStyle())
            .padding(.horizontal, 16)
          }
          if !topArtists.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
              SectionHeader(title: "Featured Artists")
              ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                  ForEach(topArtists) { artist in
                    NavigationLink {
                      ArtistArtsView(artist: artist)
                    } label: {
                      ArtistCircleCard(artist: artist)
                    }
                    .buttonStyle(PressableButtonStyle())
                  }
                }
                .padding(.horizontal, 16)
              }
            }
          }
          VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "All Artists")
            LazyVStack(spacing: 0) {
              ForEach(Array(viewModel.artists.enumerated()), id: \.element.id) { idx, artist in
                NavigationLink {
                  ArtistArtsView(artist: artist)
                } label: {
                  ArtistListRow(artist: artist)
                }
                .buttonStyle(.plain)
                if idx < viewModel.artists.count - 1 {
                  Divider().padding(.leading, 78)
                }
              }
            }
            .padding(.horizontal, 16)
          }
        }
        .padding(.vertical, 16)
      }
    }
    .navigationTitle("Art Gallery")
    .navigationBarTitleDisplayMode(.large)
    .onAppear { viewModel.fetch() }
  }
  private var featuredArt: (art: GalleryArt, artist: GalleryArtist)? {
    for artist in viewModel.artists {
      if let art = artist.arts?.max(by: { ($0.upvotes ?? 0) < ($1.upvotes ?? 0) }) {
        return (art, artist)
      }
    }
    return nil
  }
  private var topArtists: [GalleryArtist] {
    Array(viewModel.artists.prefix(12))
  }
}

private struct SectionHeader: View {
  let title: String
  var body: some View {
    Text(title)
      .font(.system(size: 22, weight: .bold))
      .padding(.horizontal, 16)
  }
}

private struct FeaturedArtCard: View {
  let art: GalleryArt
  let artist: GalleryArtist
  var body: some View {
    ZStack(alignment: .bottomLeading) {
      Group {
        if let url = art.imageURL {
          LoadingImage(
            url: url, cornerRadius: 16, showsLoading: false, lowResURL: art.blurPreviewURL, transparentBackground: true)
        } else {
          RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color(.tertiarySystemFill))
        }
      }
      .aspectRatio(4 / 5, contentMode: .fill)
      .frame(maxWidth: .infinity)
      .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
      .shadow(color: .black.opacity(0.2), radius: 14, y: 6)
      LinearGradient(
        colors: [.clear, .black.opacity(0.7)],
        startPoint: .center, endPoint: .bottom
      )
      .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
      .allowsHitTesting(false)
      VStack(alignment: .leading, spacing: 4) {
        Text("FEATURED ART")
          .font(.system(size: 11, weight: .bold))
          .foregroundColor(.white.opacity(0.85))
          .tracking(0.6)
        Text(artist.name)
          .font(.system(size: 22, weight: .bold))
          .foregroundColor(.white)
          .lineLimit(1)
        if let upvotes = art.upvotes, upvotes > 0 {
          Label("\(upvotes)", systemImage: "heart.fill")
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.white.opacity(0.9))
            .padding(.top, 2)
        }
      }
      .padding(20)
    }
  }
}

private struct ArtistCircleCard: View {
  let artist: GalleryArtist
  var body: some View {
    VStack(spacing: 8) {
      ZStack {
        if let art = artist.arts?.first, let url = art.imageURL {
          LoadingImage(
            url: url, cornerRadius: 100, showsLoading: false, lowResURL: art.blurPreviewURL, transparentBackground: true)
        } else {
          Circle()
            .fill(LinearGradient(
              colors: [Color.appAccent.opacity(0.85), Color.purple.opacity(0.85)],
              startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(
              Text(initials(artist.name))
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.white)
            )
        }
      }
      .frame(width: 96, height: 96)
      .clipShape(Circle())
      .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
      Text(artist.name)
        .font(.system(size: 13, weight: .medium))
        .foregroundColor(.primary)
        .lineLimit(2)
        .multilineTextAlignment(.center)
        .frame(width: 100)
    }
  }
  private func initials(_ name: String) -> String {
    let trimmed = name.trimmingCharacters(in: .whitespaces)
    guard let first = trimmed.first else { return "?" }
    return String(first).uppercased()
  }
}

private struct ArtistListRow: View {
  let artist: GalleryArtist
  var body: some View {
    HStack(spacing: 14) {
      Group {
        if let art = artist.arts?.first, let url = art.imageURL {
          LoadingImage(
            url: url, cornerRadius: 100, showsLoading: false, lowResURL: art.blurPreviewURL, transparentBackground: true)
        } else {
          Circle()
            .fill(LinearGradient(
              colors: [Color.appAccent.opacity(0.85), Color.purple.opacity(0.85)],
              startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(
              Text(String(artist.name.first ?? "?").uppercased())
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
            )
        }
      }
      .frame(width: 50, height: 50)
      .clipShape(Circle())
      VStack(alignment: .leading, spacing: 2) {
        Text(artist.name)
          .font(.system(size: 16, weight: .medium))
          .foregroundColor(.primary)
          .lineLimit(1)
        Text("\(artist.arts?.count ?? 0) artworks")
          .font(.system(size: 13))
          .foregroundColor(.secondary)
      }
      Spacer()
      Image(systemName: "chevron.right")
        .font(.system(size: 13, weight: .semibold))
        .foregroundColor(.secondary.opacity(0.6))
    }
    .padding(.vertical, 10)
    .contentShape(Rectangle())
  }
}

struct ArtistArtsView: View {
  let artist: GalleryArtist
  private let cols = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
  var body: some View {
    let arts = artist.arts ?? []
    ScrollView {
      VStack(spacing: 18) {
        if let hero = arts.first, let heroURL = hero.imageURL {
          LoadingImage(
            url: heroURL, cornerRadius: 14, showsLoading: false, lowResURL: hero.blurPreviewURL,
            transparentBackground: true
          )
          .aspectRatio(1, contentMode: .fit)
          .frame(width: 240, height: 240)
          .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
          .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
        }
        VStack(spacing: 4) {
          Text(artist.name)
            .font(.title2.bold())
            .multilineTextAlignment(.center)
          if let social = artist.socialLink, !social.isEmpty {
            Text(social)
              .font(.subheadline)
              .foregroundColor(.secondary)
          }
          Text("\(arts.count) artworks")
            .font(.subheadline)
            .foregroundColor(.secondary)
        }
        .padding(.horizontal)
        if !arts.isEmpty {
          LazyVGrid(columns: cols, spacing: 8) {
            ForEach(arts) { art in
              NavigationLink {
                ArtDetailView(art: art, artist: artist)
              } label: {
                ArtThumbnail(art: art)
              }
              .buttonStyle(PressableButtonStyle())
            }
          }
          .padding(.horizontal, 8)
        } else {
          VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle")
              .font(.system(size: 40))
              .foregroundColor(.secondary)
            Text("No artwork yet")
              .foregroundColor(.secondary)
          }
          .frame(maxWidth: .infinity)
          .padding(.top, 40)
        }
      }
      .padding(.top, 12)
      .padding(.bottom, 16)
    }
    .navigationTitle(artist.name)
    .navigationBarTitleDisplayMode(.inline)
  }
}

private struct ArtThumbnail: View {
  let art: GalleryArt
  var body: some View {
    Group {
      if let url = art.imageURL {
        LoadingImage(
          url: url, cornerRadius: 8, showsLoading: false, lowResURL: art.blurPreviewURL, transparentBackground: true)
      } else {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(Color(.tertiarySystemFill))
      }
    }
    .aspectRatio(1, contentMode: .fill)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

struct ArtDetailView: View {
  let art: GalleryArt
  let artist: GalleryArtist

  @State private var showFullScreen = false
  @State private var saveStatus: SaveStatus = .idle
  enum SaveStatus { case idle, saving, success, failed(String) }
  private var fullResURL: URL? {
    guard let path = art.absolutePath else { return art.imageURL }
    return URL(string: "https://images.neurokaraoke.com" + path + "/quality=95")
  }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        if let url = fullResURL {
          Button {
            showFullScreen = true
          } label: {
            LoadingImage(
              url: url, cornerRadius: 12, contentMode: .fit, showsLoading: false,
              lowResURL: art.blurPreviewURL, transparentBackground: true
            )
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: .infinity)
          }
          .buttonStyle(PressableButtonStyle())
        }
        VStack(alignment: .leading, spacing: 8) {
          Text(artist.name)
            .font(.title3.bold())
          if let social = artist.socialLink, !social.isEmpty {
            Text(social)
              .font(.system(size: 13))
              .foregroundColor(.secondary)
          }
          if let upvotes = art.upvotes, upvotes > 0 {
            Label("\(upvotes)", systemImage: "heart.fill")
              .font(.system(size: 13))
              .foregroundColor(.secondary)
              .padding(.top, 2)
          }
          if let desc = art.description, !desc.isEmpty {
            Text(desc)
              .font(.system(size: 14))
              .foregroundColor(.primary.opacity(0.85))
              .padding(.top, 4)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
      }
      .padding(.vertical)
    }
    .navigationTitle(artist.name)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          saveImage()
        } label: {
          switch saveStatus {
          case .saving:
            ProgressView()
          case .success:
            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
          case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
          case .idle:
            Image(systemName: "square.and.arrow.down")
          }
        }
        .disabled({ if case .saving = saveStatus { return true } else { return false } }())
      }
    }
    .fullScreenCover(isPresented: $showFullScreen) {
      ZoomableImageViewer(url: fullResURL, lowResURL: art.blurPreviewURL, onSave: saveImage)
    }
  }
  private func saveImage() {
    guard let url = fullResURL else { return }
    saveStatus = .saving
    URLSession.shared.dataTask(with: url) { data, _, error in
      DispatchQueue.main.async {
        #if canImport(UIKit)
          if let data, let image = UIImage(data: data) {
            ImageSaver.shared.save(image: image) { result in
              DispatchQueue.main.async {
                switch result {
                case .success:
                  saveStatus = .success
                case .failure(let err):
                  saveStatus = .failed(err.localizedDescription)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                  saveStatus = .idle
                }
              }
            }
            return
          }
        #endif
        saveStatus = .failed(error?.localizedDescription ?? "Couldn't save")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saveStatus = .idle }
      }
    }.resume()
  }
}
#if canImport(UIKit)
  import UIKit

  final class ImageSaver: NSObject {
    static let shared = ImageSaver()
    private var completion: ((Result<Void, Error>) -> Void)?
    func save(image: UIImage, completion: @escaping (Result<Void, Error>) -> Void) {
      self.completion = completion
      UIImageWriteToSavedPhotosAlbum(
        image, self, #selector(didFinishSaving(_:didFinishSavingWithError:contextInfo:)), nil)
    }
    @objc private func didFinishSaving(
      _ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer
    ) {
      if let error = error {
        completion?(.failure(error))
      } else {
        completion?(.success(()))
      }
      completion = nil
    }
  }
#endif

struct ZoomableImageViewer: View {
  let url: URL?
  let lowResURL: URL?
  let onSave: () -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var scale: CGFloat = 1
  @State private var lastScale: CGFloat = 1
  @State private var offset: CGSize = .zero
  @State private var lastOffset: CGSize = .zero
  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()
      if let url {
        LoadingImage(
          url: url, cornerRadius: 0, contentMode: .fit, showsLoading: false,
          lowResURL: lowResURL, transparentBackground: true
        )
        .scaleEffect(scale)
        .offset(offset)
        .gesture(
          MagnificationGesture()
            .onChanged { value in
              scale = max(1, min(5, lastScale * value))
            }
            .onEnded { _ in
              lastScale = scale
              if scale <= 1 {
                withAnimation(.spring()) {
                  offset = .zero
                  lastOffset = .zero
                }
              }
            }
        )
        .simultaneousGesture(
          DragGesture()
            .onChanged { value in
              guard scale > 1 else { return }
              offset = CGSize(
                width: lastOffset.width + value.translation.width,
                height: lastOffset.height + value.translation.height)
            }
            .onEnded { _ in lastOffset = offset }
        )
        .onTapGesture(count: 2) {
          withAnimation(.spring()) {
            if scale > 1 {
              scale = 1
              lastScale = 1
              offset = .zero
              lastOffset = .zero
            } else {
              scale = 2
              lastScale = 2
            }
          }
        }
      }
      VStack {
        HStack {
          Button { dismiss() } label: {
            Image(systemName: "xmark")
              .font(.system(size: 16, weight: .semibold))
              .foregroundColor(.white)
              .frame(width: 36, height: 36)
              .background(Color.black.opacity(0.4))
              .clipShape(Circle())
          }
          Spacer()
          Button { onSave() } label: {
            Image(systemName: "square.and.arrow.down")
              .font(.system(size: 16, weight: .semibold))
              .foregroundColor(.white)
              .frame(width: 36, height: 36)
              .background(Color.black.opacity(0.4))
              .clipShape(Circle())
          }
        }
        .padding()
        Spacer()
      }
    }
    .statusBarHidden(true)
  }
}
