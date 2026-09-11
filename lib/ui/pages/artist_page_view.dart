import 'package:musicality/core/globals.dart';
import 'package:musicality/ui/widgets/marquee_widget.dart';
import 'package:musicality/ui/pages/artist_profile_screen.dart';
import 'package:musicality/ui/widgets/custom_search_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:audio_service/audio_service.dart';

class ArtistPageView extends StatefulWidget {
  final List<Color> dynamicThemeColors;
  final MediaItem? currentItem;

  const ArtistPageView({
    super.key,
    required this.dynamicThemeColors,
    required this.currentItem,
  });

  @override
  State<ArtistPageView> createState() => ArtistPageViewState();
}

class ArtistPageViewState extends State<ArtistPageView> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  final FocusNode _searchFocusNode = FocusNode();
  late ScrollController _scrollController;
  bool _isScrolled = false;

  int _lastPlaylistLength = -1;
  Map<String, MediaItem> _cachedArtistSampleMap = {};
  List<String> _cachedAllArtists = [];

  bool get isSearching =>
      _searchQuery.trim().isNotEmpty || _searchController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(() {
      if (_scrollController.offset > 5 && !_isScrolled) {
        setState(() {
          _isScrolled = true;
        });
      } else if (_scrollController.offset <= 5 && _isScrolled) {
        setState(() {
          _isScrolled = false;
        });
      }
    });
  }

  void _ensureArtistCache() {
    if (_lastPlaylistLength == globalPlaylist.length && _cachedAllArtists.isNotEmpty) {
      return;
    }
    _lastPlaylistLength = globalPlaylist.length;
    _cachedArtistSampleMap = {};
    for (final song in globalPlaylist) {
      final artist = extractPrimaryArtist(song.artist);
      if (artist.isNotEmpty && artist != 'Inconnu') {
        _cachedArtistSampleMap.putIfAbsent(artist.toLowerCase(), () => song);
      }
    }
    _cachedAllArtists = _cachedArtistSampleMap.values
        .map((e) => extractPrimaryArtist(e.artist))
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  void clearSearch() {
    _searchController.clear();
    _searchFocusNode.unfocus();
    setState(() {
      _searchQuery = '';
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _ensureArtistCache();
    final artistSampleMap = _cachedArtistSampleMap;
    final allArtists = _cachedAllArtists;

    List<String> matchingArtists = allArtists;

    if (isSearching) {
      final query = normalizeString(_searchQuery);
      matchingArtists = allArtists
          .where((a) => normalizeString(a).contains(query))
          .toList();
    }

    return Column(
      children: [
        SafeArea(
          bottom: false,
          child: CustomSearchBar(
            controller: _searchController,
            focusNode: _searchFocusNode,
            hintText: "Rechercher un artiste...",
            onChanged: (value) {
              setState(() {
                _searchQuery = value;
              });
            },
            onClear: () {
              clearSearch();
            },
          ),
        ),
        Expanded(
          child: matchingArtists.isEmpty
              ? Container(
                  alignment: Alignment.topCenter,
                  padding: const EdgeInsets.only(top: 100),
                  child: Text(
                    isSearching ? "Aucun artiste trouvé" : "Aucun artiste",
                    style: const TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                )
              : TweenAnimationBuilder<Color?>(
                  duration: const Duration(milliseconds: 250),
                  tween: ColorTween(
                    begin: Colors.white,
                    end: _isScrolled
                        ? Colors.white.withValues(alpha: 0.0)
                        : Colors.white,
                  ),
                  builder: (context, topColor, child) {
                    return RepaintBoundary(
                      child: ShaderMask(
                        shaderCallback: (Rect bounds) {
                          return LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              topColor ?? Colors.black,
                              Colors.black,
                              Colors.black,
                            ],
                            stops: const [0.0, 0.05, 1.0],
                          ).createShader(
                            Rect.fromLTWH(0, 0, bounds.width, bounds.height),
                          );
                        },
                        blendMode: BlendMode.dstIn,
                        child: child,
                      ),
                    );
                  },
                  child: ListView.builder(
                    controller: _scrollController,
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.only(
                      top: 10,
                      bottom: MediaQuery.of(context).viewInsets.bottom + 220.0,
                    ),
                  itemCount: matchingArtists.length,
                  itemBuilder: (context, index) {
                    final artistName = matchingArtists[index];
                    final sampleItem = artistSampleMap[artistName.toLowerCase()] ??
                        (globalPlaylist.isNotEmpty
                            ? globalPlaylist.first
                            : MediaItem(
                                id: 'dummy',
                                title: 'Aucune',
                                artist: '',
                              ));

                    return RepaintBoundary(
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 8,
                        ),
                        leading: ClipOval(
                          child: getLocalOrNetworkImage(
                            sampleItem,
                            width: 55,
                            height: 55,
                          ),
                        ),
                        title: MarqueeWidget(
                          resetKey: artistName,
                          child: Text(
                            artistName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            softWrap: false,
                          ),
                        ),
                        trailing: const Icon(
                          CupertinoIcons.chevron_right,
                          color: Colors.white54,
                          size: 20,
                        ),
                        onTap: () {
                          if (isHapticFeedbackEnabledNotifier.value) {
                            HapticFeedback.lightImpact();
                          }
                          FocusScope.of(context).unfocus();
                          Navigator.of(context).push(
                            PageRouteBuilder(
                              pageBuilder: (context, animation, secondaryAnimation) =>
                                  ArtistProfileScreen(
                                    artistName: artistName,
                                    sampleItem: sampleItem,
                                    themeColors: widget.dynamicThemeColors,
                                    currentItem: widget.currentItem,
                                  ),
                              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                                return FadeTransition(
                                  opacity: animation,
                                  child: child,
                                );
                              },
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
        ),
      ],
    );
  }
}
