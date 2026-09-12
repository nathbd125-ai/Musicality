import 'package:musicality/ui/widgets/song_tile.dart';
import 'package:musicality/core/my_audio_handler.dart';
import 'package:musicality/core/globals.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:audio_service/audio_service.dart';

class ArtistProfileScreen extends StatefulWidget {
  final String artistName;
  final MediaItem sampleItem;
  final List<Color> themeColors;
  final MediaItem? currentItem;

  const ArtistProfileScreen({
    super.key,
    required this.artistName,
    required this.sampleItem,
    required this.themeColors,
    required this.currentItem,
  });

  @override
  State<ArtistProfileScreen> createState() => _ArtistProfileScreenState();
}

class _ArtistProfileScreenState extends State<ArtistProfileScreen> {
  late ScrollController _scrollController;
  double _overlayOpacity = 0.0;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!mounted) return;

    final topPadding = MediaQuery.of(context).padding.top;
    final baseCollapseOffset = 320.0 - (topPadding + kToolbarHeight);
    final safeTriggerOffset = baseCollapseOffset + 30.0;

    final offset = _scrollController.hasClients
        ? _scrollController.offset
        : 0.0;

    double newOpacity = ((offset - safeTriggerOffset) / 20.0).clamp(0.0, 1.0);

    if ((newOpacity - _overlayOpacity).abs() > 0.01) {
      setState(() {
        _overlayOpacity = newOpacity;
      });
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final artistSongs = globalPlaylist
        .where((e) => extractPrimaryArtist(e.artist).toLowerCase() == widget.artistName.toLowerCase())
        .toList();

    final Map<String, List<MediaItem>> albums = {};
    for (var song in artistSongs) {
      final albumName = song.album ?? 'Singles';
      albums.putIfAbsent(albumName, () => []).add(song);
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          CustomScrollView(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverAppBar(
                expandedHeight: 320,
                pinned: true,
                stretch: true,
                backgroundColor: Colors.black,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                scrolledUnderElevation: 0,
                leading: IconButton(
                  icon: const Icon(CupertinoIcons.back, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                flexibleSpace: FlexibleSpaceBar(
                  stretchModes: const [StretchMode.zoomBackground],
                  titlePadding: const EdgeInsets.only(left: 56, bottom: 12),
                  title: Text(
                    widget.artistName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 24,
                    ),
                  ),
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      Positioned.fill(
                        child: getLocalOrNetworkImage(widget.sampleItem),
                      ),
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.6),
                                Colors.black,
                              ],
                              stops: const [0.0, 0.5, 1.0],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.only(bottom: 150),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final albumName = albums.keys.elementAt(index);
                    final songsInAlbum = albums[albumName]!;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(
                            left: 20,
                            top: 24,
                            bottom: 8,
                          ),
                          child: ShaderMask(
                            blendMode: BlendMode.srcIn,
                            shaderCallback: (bounds) =>
                                LinearGradient(
                                  colors: widget.themeColors,
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                ).createShader(
                                  Rect.fromLTWH(
                                    0,
                                    0,
                                    bounds.width,
                                    bounds.height,
                                  ),
                                ),
                            child: Text(
                              albumName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        ...songsInAlbum.asMap().entries.map((entry) {
                          int idx = entry.key;
                          MediaItem song = entry.value;
                          return SongTile(
                            item: song,
                            isSelected: widget.currentItem?.id == song.id,
                            activeThemeColors: widget.themeColors,
                            heroTag: 'artist_${widget.artistName}_${song.id}',
                            onTap: () {
                              (globalAudioHandler as MyAudioHandler).playFromList(
                                songsInAlbum,
                                idx,
                                contextTag: 'artist:${widget.artistName}',
                              );
                            },
                          );
                        }),
                      ],
                    );
                  }, childCount: albums.keys.length),
                ),
              ),
            ],
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + kToolbarHeight - 1,
            left: 0,
            right: 0,
            height: 40,
            child: IgnorePointer(
              child: Opacity(
                opacity: _overlayOpacity,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black,
                        Colors.black.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
