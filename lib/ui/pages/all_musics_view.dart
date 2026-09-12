import 'package:musicality/ui/widgets/song_tile.dart';
import 'package:musicality/core/my_audio_handler.dart';
import 'package:musicality/core/globals.dart';
import 'package:musicality/ui/widgets/custom_search_bar.dart';
import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';

class AllMusicsView extends StatefulWidget {
  final MediaItem? currentItem;
  final List<Color> dynamicGradientColors;

  const AllMusicsView({
    super.key,
    required this.currentItem,
    required this.dynamicGradientColors,
  });

  @override
  State<AllMusicsView> createState() => AllMusicsViewState();
}

class AllMusicsViewState extends State<AllMusicsView> {
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
    _updateFilter();
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
      _filteredPlaylist = List<MediaItem>.from(globalPlaylist);
    } else {
      final query = normalizeString(cleanQuery);
      _filteredPlaylist = globalPlaylist.where((item) {
        final titleMatch = normalizeString(item.title).contains(query);
        final artistMatch = normalizeString(item.artist ?? '').contains(query);
        return titleMatch || artistMatch;
      }).toList();
    }
    _filteredPlaylist.sort(
      (a, b) => normalizeString(a.title).compareTo(normalizeString(b.title)),
    );
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
    return Column(
      children: [
        SafeArea(
          bottom: false,
          child: CustomSearchBar(
            controller: _searchController,
            focusNode: _searchFocusNode,
            hintText: "Filtrer vos musiques...",
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
          child: _filteredPlaylist.isEmpty
              ? Container(
                  alignment: Alignment.topCenter,
                  padding: const EdgeInsets.only(top: 100),
                  child: const Text(
                    "Aucun résultat pour cette recherche",
                    style: TextStyle(color: Colors.white70, fontSize: 16),
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
                    itemCount: _filteredPlaylist.length,
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.of(context).viewInsets.bottom + 180.0,
                    ),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    itemBuilder: (context, index) {
                      final item = _filteredPlaylist[index];
                      final isSelected = widget.currentItem?.id == item.id;

                      return SongTile(
                        item: item,
                        isSelected: isSelected,
                        activeThemeColors: widget.dynamicGradientColors,
                        heroTag: 'allmusic_${index}_${item.id}',
                        onTap: () {
                          FocusScope.of(context).unfocus();
                          final fullList = getSortedGlobalPlaylist();
                          final targetIndex =
                              fullList.indexWhere((m) => m.id == item.id);
                          (globalAudioHandler as MyAudioHandler).playFromList(
                            fullList,
                            targetIndex >= 0 ? targetIndex : 0,
                            contextTag: 'all_musics',
                          );
                        },
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}
