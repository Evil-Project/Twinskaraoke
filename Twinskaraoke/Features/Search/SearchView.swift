import SwiftUI

struct SearchView: View {
  @StateObject var viewModel = SearchViewModel()
  @EnvironmentObject var audioManager: AudioPlayerManager
  var body: some View {
    NavigationStack {
      Group {
        if viewModel.isSearching {
          LoadingIndicator(size: 64)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, 80)
            .transition(.opacity)
        } else if viewModel.results.isEmpty && !viewModel.searchText.isEmpty {
          VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
              .font(.system(size: 42))
              .foregroundColor(.secondary)
            Text("No results for \"\(viewModel.searchText)\"")
              .foregroundColor(.secondary)
              .multilineTextAlignment(.center)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .transition(.opacity)
        } else if viewModel.results.isEmpty {
          BrowseCategoriesView()
            .transition(.opacity)
        } else {
          List(viewModel.results) { song in
            Button {
              audioManager.play(song: song, context: viewModel.results)
            } label: {
              SearchResultRow(song: song)
            }
            .buttonStyle(PressableButtonStyle())
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
          }
          .listStyle(.plain)
          .transition(.opacity)
        }
      }
      .animation(
        .easeInOut(duration: 0.3),
        value: "\(viewModel.isSearching)-\(viewModel.results.count)-\(viewModel.searchText.isEmpty)"
      )
      .navigationTitle("Search")
      .searchable(
        text: $viewModel.searchText,
        placement: .navigationBarDrawer(displayMode: .always),
        prompt: "Songs, Artists, Lyrics, and More"
      )
    }
  }
}

private struct BrowseCategoriesView: View {
  private let topPicks: [(String, [Color])] = [
    (
      "Twinskaraoke Top 100",
      [Color(red: 0.96, green: 0.30, blue: 0.45), Color(red: 0.55, green: 0.10, blue: 0.30)]
    ),
    (
      "Charts",
      [Color(red: 0.20, green: 0.55, blue: 0.95), Color(red: 0.10, green: 0.20, blue: 0.55)]
    ),
    (
      "Hits",
      [Color(red: 0.95, green: 0.45, blue: 0.10), Color(red: 0.55, green: 0.15, blue: 0.05)]
    ),
    (
      "New Releases",
      [Color(red: 0.10, green: 0.75, blue: 0.85), Color(red: 0.05, green: 0.30, blue: 0.45)]
    ),
  ]
  private let activitiesAndMoods: [(String, [Color])] = [
    (
      "Workout",
      [Color(red: 0.95, green: 0.20, blue: 0.20), Color(red: 0.40, green: 0.05, blue: 0.05)]
    ),
    (
      "Chill",
      [Color(red: 0.20, green: 0.55, blue: 0.65), Color(red: 0.05, green: 0.20, blue: 0.30)]
    ),
    (
      "Focus",
      [Color(red: 0.30, green: 0.30, blue: 0.55), Color(red: 0.05, green: 0.05, blue: 0.20)]
    ),
    (
      "Sleep",
      [Color(red: 0.20, green: 0.20, blue: 0.45), Color(red: 0.05, green: 0.05, blue: 0.20)]
    ),
    (
      "Party",
      [Color(red: 0.90, green: 0.30, blue: 0.75), Color(red: 0.40, green: 0.05, blue: 0.40)]
    ),
    (
      "Romance",
      [Color(red: 0.95, green: 0.40, blue: 0.55), Color(red: 0.45, green: 0.10, blue: 0.20)]
    ),
  ]
  private let decades: [(String, [Color])] = [
    (
      "2020s",
      [Color(red: 0.10, green: 0.55, blue: 0.95), Color(red: 0.05, green: 0.20, blue: 0.55)]
    ),
    (
      "2010s",
      [Color(red: 0.55, green: 0.30, blue: 0.95), Color(red: 0.20, green: 0.05, blue: 0.45)]
    ),
    (
      "2000s",
      [Color(red: 0.95, green: 0.55, blue: 0.20), Color(red: 0.45, green: 0.20, blue: 0.05)]
    ),
    (
      "90s", [Color(red: 0.95, green: 0.30, blue: 0.30), Color(red: 0.45, green: 0.05, blue: 0.05)]
    ),
    (
      "80s", [Color(red: 0.95, green: 0.20, blue: 0.55), Color(red: 0.40, green: 0.05, blue: 0.30)]
    ),
    (
      "70s", [Color(red: 0.85, green: 0.55, blue: 0.10), Color(red: 0.40, green: 0.20, blue: 0.05)]
    ),
    (
      "60s", [Color(red: 0.60, green: 0.45, blue: 0.20), Color(red: 0.25, green: 0.15, blue: 0.05)]
    ),
  ]
  private let genres: [(String, [Color])] = [
    (
      "Pop", [Color(red: 0.90, green: 0.20, blue: 0.55), Color(red: 0.40, green: 0.05, blue: 0.30)]
    ),
    (
      "Hip-Hop",
      [Color(red: 0.60, green: 0.30, blue: 0.95), Color(red: 0.20, green: 0.05, blue: 0.45)]
    ),
    (
      "R&B", [Color(red: 0.95, green: 0.55, blue: 0.20), Color(red: 0.45, green: 0.20, blue: 0.05)]
    ),
    (
      "Rock",
      [Color(red: 0.85, green: 0.20, blue: 0.20), Color(red: 0.30, green: 0.05, blue: 0.05)]
    ),
    (
      "Country",
      [Color(red: 0.85, green: 0.65, blue: 0.30), Color(red: 0.45, green: 0.25, blue: 0.05)]
    ),
    (
      "Electronic",
      [Color(red: 0.10, green: 0.75, blue: 0.85), Color(red: 0.05, green: 0.30, blue: 0.45)]
    ),
    (
      "Latin",
      [Color(red: 0.95, green: 0.35, blue: 0.20), Color(red: 0.45, green: 0.10, blue: 0.05)]
    ),
    (
      "K-Pop",
      [Color(red: 0.95, green: 0.45, blue: 0.75), Color(red: 0.40, green: 0.10, blue: 0.40)]
    ),
    (
      "Jazz",
      [Color(red: 0.60, green: 0.45, blue: 0.20), Color(red: 0.25, green: 0.15, blue: 0.05)]
    ),
    (
      "Classical",
      [Color(red: 0.40, green: 0.55, blue: 0.40), Color(red: 0.10, green: 0.25, blue: 0.15)]
    ),
    (
      "Reggae",
      [Color(red: 0.30, green: 0.65, blue: 0.30), Color(red: 0.10, green: 0.30, blue: 0.10)]
    ),
    (
      "Soundtracks",
      [Color(red: 0.45, green: 0.45, blue: 0.55), Color(red: 0.15, green: 0.15, blue: 0.25)]
    ),
  ]
  let columns = [GridItem(.flexible(), spacing: AM.Spacing.m), GridItem(.flexible(), spacing: AM.Spacing.m)]
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: AM.Spacing.xxl) {
        section(title: "Browse Categories", items: topPicks)
        section(title: "Activities & Moods", items: activitiesAndMoods)
        section(title: "Decades", items: decades)
        section(title: "Genres", items: genres)
      }
      .padding(.top, AM.Spacing.s)
      .padding(.bottom, AM.Spacing.l)
    }
  }
  private func section(title: String, items: [(String, [Color])]) -> some View {
    VStack(alignment: .leading, spacing: AM.Spacing.m) {
      AMSectionHeader(title)
      LazyVGrid(columns: columns, spacing: AM.Spacing.m) {
        ForEach(items, id: \.0) { item in
          CategoryTile(title: item.0, gradient: item.1)
        }
      }
      .padding(.horizontal, AM.Spacing.screenMargin)
    }
  }
}

private struct CategoryTile: View {
  let title: String
  let gradient: [Color]
  var body: some View {
    ZStack(alignment: .topLeading) {
      LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
      LinearGradient(
        colors: [Color.white.opacity(0.18), Color.white.opacity(0.0)],
        startPoint: .topLeading,
        endPoint: .center
      )
      Text(title)
        .font(.system(size: 17, weight: .bold))
        .foregroundColor(.white)
        .padding(AM.Spacing.m)
    }
    .frame(height: 96)
    .clipShape(RoundedRectangle(cornerRadius: AM.Radius.tile, style: .continuous))
  }
}

struct SearchResultRow: View {
  let song: Song
  var body: some View {
    SongRow(song: song, size: .regular)
  }
}

struct SearchRowSkeleton: View {
  var body: some View {
    SongRowSkeleton(size: .regular)
  }
}
