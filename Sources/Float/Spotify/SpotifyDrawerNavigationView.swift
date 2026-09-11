import SwiftUI

private enum DrawerTab: String, CaseIterable, Identifiable {
    case now = "Playing"
    case search = "Search"
    case library = "Library"
    var id: String { rawValue }
}

private enum LibraryFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case mine = "Mine"
    case followed = "Followed"
    var id: String { rawValue }
}

struct SpotifyDrawerNavigationView: View {
    @EnvironmentObject private var spotify: SpotifyModel

    @State private var tab: DrawerTab = .now
    @State private var libraryFilter: LibraryFilter = .all
    @State private var searchText = ""
    @State private var listSearch = ""
    @State private var newPlaylistName = ""
    @State private var showNewPlaylist = false

    @State private var seedTrack: SpotifyTrack?

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            body(for: tab)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onChange(of: spotify.openedList) { _, _ in listSearch = "" }
            if let notice = spotify.notice {
                noticeBar(notice, color: Color.accentColor)
            } else if let err = spotify.lastError {
                noticeBar(err, color: .red)
                    .onTapGesture { spotify.lastError = nil }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.14))
        .onAppear { spotify.drawerDidOpen() }
        .onDisappear { spotify.drawerDidClose() }
        .alert("New playlist", isPresented: $showNewPlaylist) {
            TextField("Name", text: $newPlaylistName)
            Button("Create") {
                spotify.createPlaylist(named: newPlaylistName, addingTrack: seedTrack)
                newPlaylistName = ""; seedTrack = nil
            }
            Button("Cancel", role: .cancel) { newPlaylistName = ""; seedTrack = nil }
        } message: {
            Text(seedTrack.map { "Starts with “\($0.name)”." } ?? "Create an empty playlist.")
        }
    }

    @ViewBuilder
    private var topBar: some View {
        if let list = spotify.openedList {
            HStack(spacing: 8) {
                Button { spotify.closeList() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 1) {
                    Text(list.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Text(countLabel(loaded: spotify.openedListTracks.count,
                                    total: spotify.openedListTotal,
                                    complete: spotify.openedListComplete))
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if list.kind == .playlist {
                    Button { spotify.refreshOpenedList() } label: {
                        Image(systemName: "arrow.clockwise").font(.system(size: 10))
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                }
                Button { spotify.playList(uri: list.uri) } label: {
                    Image(systemName: "play.fill").font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
        } else {
            HStack(spacing: 6) {
                Picker("", selection: $tab) {
                    ForEach(DrawerTab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Button {
                    seedTrack = nil; showNewPlaylist = true
                } label: {
                    Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("New playlist")
            }
            .padding(.horizontal, 8).padding(.vertical, 7)
        }
    }

    @ViewBuilder
    private func body(for tab: DrawerTab) -> some View {
        if spotify.openedList != nil {
            listDetail
        } else {
            switch tab {
            case .now: nowPlayingList
            case .search: searchView
            case .library: libraryView
            }
        }
    }

    @ViewBuilder
    private var nowPlayingList: some View {
        if spotify.isLoadingContext && spotify.contextTracks.isEmpty {
            loading
        } else if spotify.contextTracks.isEmpty {
            empty("music.note.list", spotify.isAuthorized ? "Nothing playing" : "Connect Spotify in Settings")
        } else {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    List {
                        Section {
                            ForEach(spotify.contextTracks) { track in
                                TrackRow(track: track,
                                         isCurrent: track.uri == spotify.currentTrackURI,
                                         onPlay: { spotify.playDrawerTrack(track) },
                                         menu: { trackMenu(track) })
                                    .id(track.id)
                            }
                        } header: {
                            Text(spotify.contextName).font(.system(size: 10)).textCase(nil)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .onChange(of: spotify.currentTrackURI) { _, _ in scrollToCurrent(proxy) }
                    .onAppear { scrollToCurrent(proxy) }
                }
                syncFooter(loaded: spotify.contextTracks.count,
                           total: spotify.contextTotal,
                           complete: spotify.contextComplete)
            }
        }
    }

    private func filterTracks(_ tracks: [SpotifyTrack], query: String) -> [SpotifyTrack] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return tracks }
        return tracks.filter {
            $0.name.lowercased().contains(q) || $0.artist.lowercased().contains(q)
        }
    }

    private func inlineSearchField(text: Binding<String>, placeholder: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 10)).foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
            if !text.wrappedValue.isEmpty {
                Button { text.wrappedValue = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 10))
                }
                .buttonStyle(.plain).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
    }

    private func cacheAge(_ date: Date?) -> String {
        guard let date else { return "offline · cached" }
        let s = Int(Date().timeIntervalSince(date))
        if s < 90 { return "offline · just synced" }
        if s < 3600 { return "offline · \(s / 60)m ago" }
        if s < 86400 { return "offline · \(s / 3600)h ago" }
        return "offline · \(s / 86400)d ago"
    }

    private func countLabel(loaded: Int, total: Int, complete: Bool) -> String {
        if complete { return "\(loaded) tracks" }
        return total > 0 ? "\(loaded) / \(total) tracks" : "\(loaded) tracks • syncing"
    }

    @ViewBuilder
    private func syncFooter(loaded: Int, total: Int, complete: Bool) -> some View {
        if !complete {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text(total > 0
                     ? "Syncing playlist… \(loaded) of \(total)"
                     : "Syncing playlist… \(loaded)")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(.white.opacity(0.04))
        }
    }

    @ViewBuilder
    private var searchView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 10)).foregroundStyle(.secondary)
                TextField("Songs, playlists, albums", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .onSubmit { spotify.search(searchText) }
                if !searchText.isEmpty {
                    Button { searchText = ""; spotify.clearSearch() } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 11))
                    }
                    .buttonStyle(.plain).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 7)
            Divider()

            if spotify.searchIsOffline && !spotify.searchResults.isEmpty {
                Label("From your library — Spotify search is offline", systemImage: "wifi.slash")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(.white.opacity(0.04))
            }

            if spotify.isSearching {
                loading
            } else if spotify.searchResults.isEmpty {
                empty("magnifyingglass",
                      searchText.isEmpty ? "Search Spotify"
                        : (spotify.isRateLimited ? "Nothing in your library matches" : "No results"))
            } else {
                List {
                    if !spotify.searchResults.tracks.isEmpty {
                        Section("Songs") {
                            ForEach(spotify.searchResults.tracks) { track in
                                TrackRow(track: track, isCurrent: track.uri == spotify.currentTrackURI,
                                         onPlay: { spotify.playTrack(track, inContext: nil) },
                                         menu: { trackMenu(track) })
                            }
                        }
                    }
                    if !spotify.searchResults.playlists.isEmpty {
                        Section("Playlists") {
                            ForEach(spotify.searchResults.playlists) { browseRow($0) }
                        }
                    }
                    if !spotify.searchResults.albums.isEmpty {
                        Section("Albums") {
                            ForEach(spotify.searchResults.albums) { browseRow($0) }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    @ViewBuilder
    private var libraryView: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()
            libraryList
            HStack(spacing: 5) {
                if spotify.sync.runningFullSync || !spotify.sync.syncing.isEmpty {
                    ProgressView().controlSize(.mini)
                }
                if spotify.playlistsFromCache {
                    Label(cacheAge(spotify.playlistsUpdatedAt), systemImage: "wifi.slash")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                } else {
                    Text(spotify.sync.status)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer()
                Button { Task { await spotify.sync.runFullSync() } } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 8))
                }
                .buttonStyle(.plain).foregroundStyle(.tertiary)
                .help("Sync playlists now")
                .disabled(spotify.sync.runningFullSync)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(.white.opacity(0.03))
        }
    }

    private var filterBar: some View {
        HStack(spacing: 5) {
            ForEach(LibraryFilter.allCases) { f in
                let count = playlists(for: f).count
                Button {
                    libraryFilter = f
                } label: {
                    Text(f == .all ? "All \(count)" : "\(f.rawValue) \(count)")
                        .font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(
                            Capsule().fill(libraryFilter == f
                                           ? Color.accentColor.opacity(0.25)
                                           : Color.white.opacity(0.06))
                        )
                        .overlay(
                            Capsule().strokeBorder(libraryFilter == f
                                                   ? Color.accentColor.opacity(0.6)
                                                   : .clear)
                        )
                        .foregroundStyle(libraryFilter == f ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
    }

    private func playlists(for filter: LibraryFilter) -> [SpotifyPlaylist] {
        switch filter {
        case .all:      return spotify.playlists
        case .mine:     return spotify.playlists.filter { spotify.isOwned($0) }
        case .followed: return spotify.playlists.filter { !spotify.isOwned($0) }
        }
    }

    @ViewBuilder
    private var libraryList: some View {
        let items = playlists(for: libraryFilter)
        if spotify.playlists.isEmpty {
            empty("music.note.list", spotify.isAuthorized ? "No playlists" : "Connect Spotify in Settings")
        } else if items.isEmpty {
            empty("line.3.horizontal.decrease.circle", "No \(libraryFilter.rawValue.lowercased()) playlists")
        } else {
            List {
                ForEach(items) { pl in
                    browseRow(SpotifyBrowseItem(id: pl.id, name: pl.name,
                                                subtitle: pl.collaborative ? "Collaborative"
                                                    : (spotify.isOwned(pl) ? "Playlist" : "Followed"),
                                                uri: pl.uri, kind: .playlist,
                                                ownerID: pl.ownerID, collaborative: pl.collaborative,
                                                imageURL: pl.imageURL))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .refreshable { await spotify.loadPlaylists(force: true) }
        }
    }

    @ViewBuilder
    private var listDetail: some View {
        if spotify.isLoadingList && spotify.openedListTracks.isEmpty {
            loading
        } else if spotify.openedListTracks.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "lock").font(.title3)
                Text(spotify.openListError ?? "Empty")
                    .font(.system(size: 9))
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                if let list = spotify.openedList {
                    Button {
                        spotify.playList(uri: list.uri)
                    } label: {
                        Label("Play", systemImage: "play.fill").font(.system(size: 11))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(14)
        } else {
            let ctx = spotify.openedList?.uri
            let shown = filterTracks(spotify.openedListTracks, query: listSearch)
            VStack(spacing: 0) {
                inlineSearchField(text: $listSearch, placeholder: "Filter this playlist")
                Divider()
                if shown.isEmpty {
                    empty("magnifyingglass", "No tracks match “\(listSearch)”")
                } else {
                    List {
                        ForEach(shown) { track in
                            TrackRow(track: track, isCurrent: track.uri == spotify.currentTrackURI,
                                     onPlay: { spotify.playTrack(track, inContext: ctx) },
                                     menu: { trackMenu(track) })
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
                syncFooter(loaded: spotify.openedListTracks.count,
                           total: spotify.openedListTotal,
                           complete: spotify.openedListComplete)
            }
        }
    }

    private func browseRow(_ item: SpotifyBrowseItem) -> some View {
        let browsable = spotify.canBrowse(item)
        return HStack(spacing: 8) {
            Button {
                if browsable { spotify.openList(item) } else { spotify.playList(uri: item.uri) }
            } label: {
                HStack(spacing: 8) {
                    ArtworkThumbnail(url: item.imageURL, size: 30, cornerRadius: 5,
                                     fallback: item.kind == .album ? "square.stack" : "music.note.list")
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.name).font(.system(size: 11, weight: .medium)).lineLimit(1)
                        Text(item.subtitle).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button { spotify.playList(uri: item.uri) } label: {
                Image(systemName: "play.fill").font(.system(size: 9))
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            if browsable {
                Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
        .listRowInsets(EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8))
        .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private func trackMenu(_ track: SpotifyTrack) -> some View {
        Button { spotify.playTrack(track, inContext: spotify.openedList?.uri) } label: {
            Label("Play", systemImage: "play.fill")
        }
        Button { spotify.queue(track) } label: {
            Label("Add to Queue", systemImage: "text.append")
        }
        if !spotify.playlists.isEmpty {
            Menu {
                ForEach(spotify.playlists) { pl in
                    Button(pl.name) { spotify.addTrack(track, to: pl) }
                }
                Divider()
                Button("New Playlist…") { seedTrack = track; showNewPlaylist = true }
            } label: {
                Label("Add to Playlist", systemImage: "text.badge.plus")
            }
        } else {
            Button { seedTrack = track; showNewPlaylist = true } label: {
                Label("New Playlist…", systemImage: "text.badge.plus")
            }
        }
    }

    private func scrollToCurrent(_ proxy: ScrollViewProxy) {
        guard let id = spotify.contextTracks.first(where: { $0.uri == spotify.currentTrackURI })?.id
        else { return }
        withAnimation { proxy.scrollTo(id, anchor: .center) }
    }

    private var loading: some View {
        ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func empty(_ icon: String, _ text: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.title3)
            Text(text).font(.system(size: 10)).multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(12)
    }

    private func noticeBar(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.white)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(color.opacity(0.85))
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

private struct TrackRow<Menu: View>: View {
    let track: SpotifyTrack
    let isCurrent: Bool
    let onPlay: () -> Void
    @ViewBuilder let menu: () -> Menu

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onPlay) {
                HStack(spacing: 8) {
                    ZStack(alignment: .bottomTrailing) {
                        ArtworkThumbnail(url: track.artworkURL, size: 28, cornerRadius: 4)
                        if isCurrent {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.system(size: 6, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(2.5)
                                .background(Circle().fill(Color.accentColor))
                                .offset(x: 3, y: 3)
                        }
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(track.name)
                            .font(.system(size: 11, weight: isCurrent ? .semibold : .regular))
                            .lineLimit(1)
                        Text(track.artist)
                            .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            SwiftUI.Menu {
                menu()
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 10))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .foregroundStyle(.secondary)
            .frame(width: 18)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: 5)
            .fill(isCurrent ? Color.accentColor.opacity(0.14) : .clear))
        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 6))
        .listRowSeparator(.hidden)
    }
}

/// Cover art thumbnail with a placeholder for tracks/playlists/albums that
/// have none loaded (yet).
private struct ArtworkThumbnail: View {
    let url: URL?
    var size: CGFloat = 28
    var cornerRadius: CGFloat = 4
    var fallback: String = "music.note"

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    private var placeholder: some View {
        Image(systemName: fallback)
            .font(.system(size: size * 0.4))
            .foregroundStyle(.secondary)
    }
}
