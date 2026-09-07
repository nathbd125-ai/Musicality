import 'package:musicality/ui/widgets/song_tile.dart';
import 'package:musicality/ui/widgets/marquee_widget.dart';
import 'package:musicality/core/my_audio_handler.dart';
import 'package:musicality/core/globals.dart';
import 'package:musicality/ui/widgets/custom_search_bar.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:audio_service/audio_service.dart';
import 'package:musicality/ui/sheets/explorer_sheet.dart';
import 'package:url_launcher/url_launcher.dart';


class SearchPageView extends StatefulWidget {
  final MediaItem? currentItem;
  final List<Color> dynamicGradientColors;

  const SearchPageView({
    super.key,
    required this.currentItem,
    required this.dynamicGradientColors,
  });

  @override
  State<SearchPageView> createState() => SearchPageViewState();
}

class SearchPageViewState extends State<SearchPageView> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  late ScrollController _scrollController;
  bool _isScrolled = false;
  List<MediaItem> _filteredPlaylist = [];

  bool get isSearching =>
      _searchQuery.trim().isNotEmpty || _searchController.text.trim().isNotEmpty;

  void clearSearch() {
    _searchController.clear();
    _searchFocusNode.unfocus();
    setState(() {
      _searchQuery = '';
      _updateFilter();
    });
  }

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

  void _updateFilter() {
    if (_searchQuery.trim().isEmpty) {
      _filteredPlaylist = [];
    } else {
      _filteredPlaylist = globalPlaylist.where((item) {
        final query = normalizeString(_searchQuery);
        final titleMatch = normalizeString(item.title).contains(query);
        final artistMatch = normalizeString(item.artist ?? '').contains(query);
        return titleMatch || artistMatch;
      }).toList();
      _filteredPlaylist.sort(
        (a, b) => normalizeString(a.title).compareTo(normalizeString(b.title)),
      );
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _launchYouTube(String title, String artist) async {
    final query = Uri.encodeComponent("$title $artist audio");
    final url = Uri.parse(
      'https://www.youtube.com/results?search_query=$query',
    );
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      debugPrint("Impossible d'ouvrir YouTube");
    }
  }

  void _showExplorerSheet(BuildContext context, String title, Widget content) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return ExplorerSheet(
          title: title,
          themeColors: widget.dynamicGradientColors,
          content: content,
        );
      },
    );
  }

  Widget _buildSectionCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onExplore,
  }) {
    return Container(
      height: 140,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onExplore,
            highlightColor: Colors.white.withValues(alpha: 0.05),
            splashColor: Colors.white.withValues(alpha: 0.1),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 20, right: 20, top: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(icon, color: Colors.white70, size: 28),
                          const SizedBox(width: 12),
                          ShaderMask(
                            blendMode: BlendMode.srcIn,
                            shaderCallback: (bounds) =>
                                LinearGradient(
                                  colors: widget.dynamicGradientColors.length >= 2
                                      ? widget.dynamicGradientColors
                                      : (widget.dynamicGradientColors.isNotEmpty
                                            ? [
                                                widget.dynamicGradientColors[0],
                                                widget.dynamicGradientColors[0]
                                                    .withValues(alpha: 0.8),
                                              ]
                                            : [Colors.blue, Colors.purple]),
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
                              title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Padding(
                        padding: const EdgeInsets.only(right: 95.0),
                        child: Text(
                          subtitle,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 13,
                            height: 1.3,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  bottom: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Text(
                      "Explorer",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFavorisContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ValueListenableBuilder<Map<String, int>>(
          valueListenable: artistListeningTimeNotifier,
          builder: (context, times, child) {
            if (times.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  "Aucun temps d'écoute pour le moment. Écoutez vos morceaux !",
                  style: TextStyle(color: Colors.white54),
                ),
              );
            }
            var sortedArtists = times.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value));
            
            // Limiter à un top 25
            sortedArtists = sortedArtists.take(25).toList();

            return SizedBox(
              height: 140,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: sortedArtists.length,
                itemBuilder: (context, index) {
                  final artistName = sortedArtists[index].key;
                  final timeSecs = sortedArtists[index].value;

                  return Container(
                    width: 130,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: index == 0
                                ? const Color(0xFFFFD700).withValues(alpha: 0.2)
                                : Colors.white10,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            "${index + 1}",
                            style: TextStyle(
                              color: index == 0
                                  ? const Color(0xFFFFD700)
                                  : Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4.0),
                          child: MarqueeWidget(
                            resetKey: artistName,
                            alignment: Alignment.center,
                            child: Text(
                              artistName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              softWrap: false,
                            ),
                          ),
                        ),
                        Text(
                          formatArtistTime(timeSecs),
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        ),
        const Padding(
          padding: EdgeInsets.only(left: 20, top: 24, bottom: 8),
          child: Text(
            "Titres les plus appréciés",
            style: TextStyle(
              color: Colors.white70,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        ValueListenableBuilder<Map<String, int>>(
          valueListenable: songPlayCountNotifier,
          builder: (context, playCounts, child) {
            final mostPlayedItems = globalPlaylist.toList()
              ..sort((a, b) {
                final countA = playCounts[a.id] ?? 0;
                final countB = playCounts[b.id] ?? 0;
                // Si les counts sont égaux, trier par titre pour éviter les sauts aléatoires
                if (countA == countB) return a.title.compareTo(b.title);
                return countB.compareTo(countA);
              });

            // On prend les 25 musiques les plus écoutées (ayant au moins 1 écoute)
            final topItems = mostPlayedItems
                .where((i) => (playCounts[i.id] ?? 0) > 0)
                .take(25)
                .toList();

            if (topItems.isEmpty) return const SizedBox();

            return Column(
              children: topItems.asMap().entries.map((entry) {
                int idx = entry.key;
                MediaItem item = entry.value;
                return SongTile(
                  item: item,
                  isSelected: widget.currentItem?.id == item.id,
                  activeThemeColors: widget.dynamicGradientColors,
                  heroTag: 'fav_exp_${item.id}',
                  showPlayCount: true,
                  onTap: () {
                    (globalAudioHandler as MyAudioHandler).playFromList(
                      topItems,
                      idx,
                    );
                  },
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildRecommendationList(String targetArtist, bool isDiscover) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: fetchArtistRecommendations(targetArtist, isDiscover: isDiscover),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: CircularProgressIndicator(color: Colors.white),
            ),
          );
        }
        final recs = snapshot.data ?? [];
        if (recs.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: Text(
                "Aucune recommandation trouvée.",
                style: TextStyle(color: Colors.white54),
              ),
            ),
          );
        }

        return Column(
          children: recs.map((reco) {
            final bool isLocal = reco['isLocal'] as bool;
            final String title = reco['title'] as String;
            final String artist = reco['artist'] as String;
            final String artUri = reco['artUri'] as String;
            final bool isSelected = (isLocal &&
                    widget.currentItem?.id == reco['localId']) ||
                (widget.currentItem?.title.toLowerCase() ==
                        title.toLowerCase() &&
                    widget.currentItem?.artist?.toLowerCase() ==
                        artist.toLowerCase());

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.white.withValues(alpha: 0.15)
                    : Colors.black.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.2)
                      : Colors.white.withValues(alpha: 0.1),
                  width: 1,
                ),
              ),
              child: Material(
                type: MaterialType.transparency,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child:
                        isLocal &&
                            File(
                              '$globalDocumentPath/${getSafeFileName(getBaseId(reco['localId'] as String))}.jpg',
                            ).existsSync()
                        ? Image.file(
                            File(
                              '$globalDocumentPath/${getSafeFileName(getBaseId(reco['localId'] as String))}.jpg',
                            ),
                            width: 55,
                            height: 55,
                            cacheWidth: 165,
                            fit: BoxFit.cover,
                          )
                        : Image.network(
                            artUri,
                            width: 55,
                            height: 55,
                            cacheWidth: 200,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                Container(
                                  color: Colors.grey,
                                  width: 55,
                                  height: 55,
                                ),
                          ),
                  ),
                  title: MarqueeWidget(
                    resetKey:
                        'reco_title_${isSelected ? 'sel' : 'unsel'}_${reco['localId'] ?? title}',
                    child: isSelected
                        ? ShaderMask(
                            blendMode: BlendMode.srcIn,
                            shaderCallback: (bounds) {
                              return LinearGradient(
                                colors: widget.dynamicGradientColors,
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                                stops: getGradientStops(
                                  widget.dynamicGradientColors.length,
                                ),
                              ).createShader(
                                Rect.fromLTWH(
                                  0,
                                  0,
                                  bounds.width,
                                  bounds.height,
                                ),
                              );
                            },
                            child: Text(
                              title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.visible,
                            ),
                          )
                        : Text(
                            title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.visible,
                          ),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 2.0),
                    child: MarqueeWidget(
                      resetKey:
                          'reco_artist_${isSelected ? 'sel' : 'unsel'}_${reco['localId'] ?? artist}',
                      child: isSelected
                          ? ShaderMask(
                              blendMode: BlendMode.srcIn,
                              shaderCallback: (bounds) {
                                return LinearGradient(
                                  colors: widget.dynamicGradientColors,
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                  stops: getGradientStops(
                                    widget.dynamicGradientColors.length,
                                  ),
                                ).createShader(
                                  Rect.fromLTWH(
                                    0,
                                    0,
                                    bounds.width,
                                    bounds.height,
                                  ),
                                );
                              },
                              child: Text(
                                artist,
                                style: TextStyle(
                                  color: Colors.white.withValues(
                                    alpha: 0.85,
                                  ),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.visible,
                              ),
                            )
                          : Text(
                              artist,
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 13,
                              ),
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.visible,
                            ),
                    ),
                  ),

                  trailing: isLocal
                      ? _buildLocalLikeButton(reco['localId'] as String)
                      : _buildYouTubeButton(),

                  onTap: () {
                    if (isLocal) {
                      (globalAudioHandler as MyAudioHandler).playFromList(
                        globalPlaylist,
                        reco['localIndex'] as int,
                      );
                      Navigator.pop(context);
                    } else {
                      _launchYouTube(title, artist);
                    }
                  },
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildYouTubeButton() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFF0000).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFFF0000).withValues(alpha: 0.5),
        ),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            CupertinoIcons.play_arrow_solid,
            color: Color(0xFFFF0000),
            size: 14,
          ),
          SizedBox(width: 4),
          Text(
            "YouTube",
            style: TextStyle(
              color: Color(0xFFFF0000),
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocalLikeButton(String id) {
    return ValueListenableBuilder<Set<String>>(
      valueListenable: likedSongsNotifier,
      builder: (context, likedSongs, child) {
        final idBase = getBaseId(id);
        final isLiked = likedSongs.contains(id) ||
            likedSongs.any((e) => getBaseId(e) == idBase);
        return GestureDetector(
          onTap: () {
            final currentLikes = Set<String>.from(likedSongsNotifier.value);
            final item = globalPlaylist.firstWhere(
              (e) => getBaseId(e.id) == idBase,
              orElse: () => globalPlaylist.firstWhere((e) => e.id == id),
            );
            if (isLiked) {
              currentLikes.removeWhere((e) => getBaseId(e) == idBase);
              updateArtistScore(item.artist ?? '', -10);
            } else {
              currentLikes.add(item.id);
              updateArtistScore(item.artist ?? '', 10);
            }
            likedSongsNotifier.value = currentLikes;
          },
          child: Container(
            color: Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: isLiked
                  ? ShaderMask(
                      key: const ValueKey('liked'),
                      blendMode: BlendMode.srcIn,
                      shaderCallback: (bounds) =>
                          LinearGradient(
                            colors: widget.dynamicGradientColors,
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            stops: getGradientStops(
                              widget.dynamicGradientColors.length,
                            ),
                          ).createShader(
                            Rect.fromLTWH(0, 0, bounds.width, bounds.height),
                          ),
                      child: const Icon(CupertinoIcons.heart_fill, size: 24),
                    )
                  : const Icon(
                      CupertinoIcons.heart,
                      key: ValueKey('unliked'),
                      color: Colors.white54,
                      size: 24,
                    ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSearching = _searchQuery.trim().isNotEmpty;

    return Column(
      children: [
        SafeArea(
          bottom: false,
          child: CustomSearchBar(
            controller: _searchController,
            focusNode: _searchFocusNode,
            hintText: "Rechercher un artiste, un titre...",
            onChanged: (value) {
              setState(() {
                _searchQuery = value;
                _updateFilter();
              });
            },
            onClear: () {
              clearSearch();
            },
          ),
        ),

        Expanded(
          child: ValueListenableBuilder<List<String>>(
            valueListenable: searchHistoryNotifier,
            builder: (context, historyIds, child) {
              List<MediaItem> displayedList = [];

              if (isSearching) {
                displayedList = _filteredPlaylist;
              } else {
                for (String id in historyIds) {
                  try {
                    displayedList.add(
                      globalPlaylist.firstWhere((item) => item.id == id),
                    );
                  } catch (e) {
                    debugPrint("Item non trouvé dans l'historique : $e");
                  }
                }
              }


              if (!isSearching) {
                return ListView(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.only(
                    top: 10,
                    bottom: MediaQuery.of(context).viewInsets.bottom + 220.0,
                  ),
                  children: [
                    _buildSectionCard(
                      context,
                      title: "Vos favoris",
                      subtitle: "Les artistes que vous écoutez le plus souvent",
                      icon: CupertinoIcons.star_fill,
                      onExplore: () => _showExplorerSheet(
                        context,
                        "Vos favoris",
                        _buildFavorisContent(),
                      ),
                    ),
                    _buildSectionCard(
                      context,
                      title: "Recommandations",
                      subtitle: "Basé sur l'artiste que vous écoutez actuellement",
                      icon: CupertinoIcons.sparkles,
                      onExplore: () {
                        final target = widget.currentItem?.artist ?? "Damso";
                        _showExplorerSheet(
                          context,
                          "Pour vous",
                          _buildRecommendationList(target, false),
                        );
                      },
                    ),
                    _buildSectionCard(
                      context,
                      title: "À découvrir",
                      subtitle: "Tendances et nouveautés selon vos goûts",
                      icon: CupertinoIcons.compass_fill,
                      onExplore: () {
                        final target = widget.currentItem?.artist ?? "Damso";
                        _showExplorerSheet(
                          context,
                          "À découvrir",
                          _buildRecommendationList(target, true),
                        );
                      },
                    ),
                  ],
                );
              }

              if (displayedList.isEmpty) {
                return Container(
                  alignment: Alignment.topCenter,
                  padding: const EdgeInsets.only(top: 100),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        CupertinoIcons.search,
                        color: Colors.white.withValues(alpha: 0.2),
                        size: 60,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        "Aucun résultat pour cette recherche",
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                );
              }

              return TweenAnimationBuilder<Color?>(
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
                  itemCount: displayedList.length,
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).viewInsets.bottom + 180.0,
                  ),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  itemBuilder: (context, index) {
                    final item = displayedList[index];
                    final isSelected = widget.currentItem?.id == item.id;

                    return SongTile(
                      item: item,
                      isSelected: isSelected,
                      activeThemeColors: widget.dynamicGradientColors,
                      heroTag: 'search_${index}_${item.id}',
                      onRemoveFromHistory: !isSearching
                          ? () {
                              final currentHistory = List<String>.from(
                                searchHistoryNotifier.value,
                              );
                              currentHistory.remove(item.id);
                              searchHistoryNotifier.value = currentHistory;
                            }
                          : null,
                      onTap: () {
                        FocusScope.of(context).unfocus();

                        final currentHistory = List<String>.from(
                          searchHistoryNotifier.value,
                        );
                        currentHistory.remove(item.id);
                        currentHistory.insert(0, item.id);
                        if (currentHistory.length > 50) {
                          currentHistory.removeLast();
                        }
                        searchHistoryNotifier.value = currentHistory;

                        (globalAudioHandler as MyAudioHandler).playFromList(
                          displayedList,
                          index,
                        );
                      },
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
