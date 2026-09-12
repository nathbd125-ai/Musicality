import 'package:musicality/ui/widgets/song_tile.dart';
import 'package:musicality/core/my_audio_handler.dart';
import 'package:musicality/core/globals.dart';
import 'package:musicality/ui/widgets/custom_search_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:audio_service/audio_service.dart';
import 'package:musicality/ui/sheets/explorer_sheet.dart';


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
    final cleanQuery = _searchQuery.trim();
    if (cleanQuery.isEmpty) {
      _filteredPlaylist = [];
    } else {
      final query = normalizeString(cleanQuery);
      _filteredPlaylist = globalPlaylist.where((item) {
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
                    ExplorerSectionCard(
                      title: "Vos favoris",
                      subtitle: "Les artistes que vous écoutez le plus souvent",
                      icon: CupertinoIcons.star_fill,
                      dynamicGradientColors: widget.dynamicGradientColors,
                      onExplore: () => _showExplorerSheet(
                        context,
                        "Vos favoris",
                        ExplorerFavoritesContent(
                          currentItem: widget.currentItem,
                          dynamicGradientColors: widget.dynamicGradientColors,
                        ),
                      ),
                    ),
                    ExplorerSectionCard(
                      title: "Recommandations",
                      subtitle: "Basé sur l'artiste que vous écoutez actuellement",
                      icon: CupertinoIcons.sparkles,
                      dynamicGradientColors: widget.dynamicGradientColors,
                      onExplore: () {
                        final target = widget.currentItem?.artist ?? "Damso";
                        _showExplorerSheet(
                          context,
                          "Pour vous",
                          ExplorerRecommendationsContent(
                            targetArtist: target,
                            isDiscover: false,
                            currentItem: widget.currentItem,
                            dynamicGradientColors: widget.dynamicGradientColors,
                          ),
                        );
                      },
                    ),
                    ExplorerSectionCard(
                      title: "À découvrir",
                      subtitle: "Tendances et nouveautés selon vos goûts",
                      icon: CupertinoIcons.compass_fill,
                      dynamicGradientColors: widget.dynamicGradientColors,
                      onExplore: () {
                        final target = widget.currentItem?.artist ?? "Damso";
                        _showExplorerSheet(
                          context,
                          "À découvrir",
                          ExplorerRecommendationsContent(
                            targetArtist: target,
                            isDiscover: true,
                            currentItem: widget.currentItem,
                            dynamicGradientColors: widget.dynamicGradientColors,
                          ),
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
                        _searchFocusNode.unfocus(
                          disposition: UnfocusDisposition.previouslyFocusedChild,
                        );
                        FocusManager.instance.primaryFocus?.unfocus();

                        final currentHistory = List<String>.from(
                          searchHistoryNotifier.value,
                        );
                        currentHistory.remove(item.id);
                        currentHistory.insert(0, item.id);
                        if (currentHistory.length > 50) {
                          currentHistory.removeLast();
                        }
                        searchHistoryNotifier.value = currentHistory;

                        final fullList = getSortedGlobalPlaylist();
                        final targetIndex =
                            fullList.indexWhere((m) => m.id == item.id);
                        (globalAudioHandler as MyAudioHandler).playFromList(
                          fullList,
                          targetIndex >= 0 ? targetIndex : 0,
                          contextTag: 'search',
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
