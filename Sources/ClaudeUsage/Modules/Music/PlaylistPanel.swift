import SwiftUI

/// The songs of the playlist being played. The playing one is highlighted and scrolled to the middle;
/// clicking a song plays it. Rows are built lazily, so long playlists stay light.
struct PlaylistPanel: View {
    @ObservedObject var bridge: MusicBridge

    var body: some View {
        Group {
            if let list = bridge.playlist {
                if list.isEmpty {
                    Text("Song list isn't available for this source.")
                        .font(.app(11))
                        .foregroundStyle(Palette.text3)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                } else {
                    rows(list)
                }
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: 60)
            }
        }
    }

    private func rows(_ list: [PlaylistTrack]) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(list) { item in
                        PlaylistRow(item: item, current: bridge.currentIndex == item.index - 1) { bridge.play(item) }
                            .id(item.index)
                    }
                }
            }
            .frame(height: 196)
            .onAppear { center(proxy) }
            .onChange(of: bridge.currentIndex) { _, _ in withAnimation(Motion.smooth) { center(proxy) } }
        }
    }

    private func center(_ proxy: ScrollViewProxy) {
        guard let index = bridge.currentIndex else { return }
        proxy.scrollTo(index + 1, anchor: .center)
    }
}

private struct PlaylistRow: View {
    let item: PlaylistTrack
    let current: Bool
    let play: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if current {
                    MusicVisualizer(playing: true, color: Palette.amber)
                        .scaleEffect(0.75)
                } else {
                    Text("\(item.index)")
                        .font(.app(9.5))
                        .foregroundStyle(Palette.text3)
                        .monospacedDigit()
                }
            }
            .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.app(11.5, current ? .semibold : .regular))
                    .foregroundStyle(current ? Palette.text : Palette.text2)
                    .lineLimit(1)
                Text(item.artist)
                    .font(.app(10))
                    .foregroundStyle(Palette.text3)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(current ? Palette.hover : hovering ? Palette.glass : .clear))
        .contentShape(Rectangle())
        .onTapGesture(perform: play)
        .onHover { h in withAnimation(Motion.quick) { hovering = h } }
    }
}
