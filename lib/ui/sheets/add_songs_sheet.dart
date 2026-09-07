import 'package:musicality/core/globals.dart';
import 'package:musicality/ui/widgets/custom_search_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:audio_service/audio_service.dart';
import 'dart:ui';

class AddSongsSheet extends StatefulWidget {
  final String playlistName;
  final List<Color> activeThemeColors;

  const AddSongsSheet({
    super.key,
    required this.playlistName,
    required this.activeThemeColors,
  });

  @override
  State<AddSongsSheet> createState() => _AddSongsSheetState();
}

class _AddSongsSheetState extends State<AddSongsSheet> {
  String _searchQuery = '';
  final FocusNode _searchFocusNode = FocusNode();
  final DraggableScrollableController _dragController =
      DraggableScrollableController();
  final ValueNotifier<double> _sheetSize = ValueNotifier(0.85);
  final ValueNotifier<double> _scrollOffset = ValueNotifier(0.0);
  List<MediaItem> _filteredPlaylist = [];

  @override
  void initState() {
    super.initState();
    _updateFilter();
    _searchFocusNode.addListener(() {
      if (_searchFocusNode.hasFocus) {
        _dragController.animateTo(
          1.0,
          duration: const Duration(milliseconds: 400),
          curve: Curves.fastOutSlowIn,
        );
      }
    });

    _dragController.addListener(() {
      if (_dragController.isAttached) {
        _sheetSize.value = _dragController.size;
      }
    });
  }

  void _updateFilter() {
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

  @override
  void dispose() {
    _searchFocusNode.dispose();
    _dragController.dispose();
    _sheetSize.dispose();
    _scrollOffset.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
      },
      child: DraggableScrollableSheet(
        controller: _dragController,
        initialChildSize: 0.85,
        minChildSize: 0.0,
        maxChildSize: 1.0,
        expand: false,
        snap: true,
        snapSizes: const [0.85, 1.0],
        builder: (context, scrollController) {
          final topPadding = MediaQuery.of(context).padding.top;
          final headerHeight = 85.0 + topPadding;

          return ValueListenableBuilder<double>(
            valueListenable: _sheetSize,
            builder: (context, size, child) {
              final progress = ((size - 0.90) / 0.10).clamp(0.0, 1.0);
              final radius = progress > 0.99 ? 0.0 : 32.0 * (1.0 - progress);
              final borderAlpha = 0.1 * (1.0 - progress);

              return ClipRRect(
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(radius),
                ),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF121212).withValues(alpha: 0.35),
                        border: borderAlpha > 0.005
                            ? Border(
                                top: BorderSide(
                                  color: Colors.white.withValues(
                                    alpha: borderAlpha,
                                  ),
                                  width: 1,
                                ),
                              )
                            : null,
                      ),
                      child: child,
                    ),
                  ),
                ),
              );
            },
            child: NotificationListener<ScrollNotification>(
              onNotification: (ScrollNotification notification) {
                if (notification.metrics.axis == Axis.vertical) {
                  _scrollOffset.value = notification.metrics.pixels;
                }
                return false;
              },
              child: Stack(
                children: [
                  CustomScrollView(
                    controller: scrollController,
                    physics: const BouncingScrollPhysics(),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    slivers: [
                      SliverPadding(
                        padding: EdgeInsets.only(top: headerHeight),
                        sliver: SliverToBoxAdapter(
                          child: CustomSearchBar(
                            hintText: "Rechercher...",
                            focusNode: _searchFocusNode,
                            onChanged: (val) {
                              setState(() {
                                _searchQuery = val;
                                _updateFilter();
                              });
                            },
                          ),
                        ),
                      ),
                      if (_filteredPlaylist.isEmpty)
                        SliverToBoxAdapter(
                          child: Container(
                            alignment: Alignment.topCenter,
                            padding: const EdgeInsets.only(top: 40),
                            child: const Text(
                              "Aucun résultat pour cette recherche",
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: EdgeInsets.only(
                            bottom:
                                MediaQuery.of(context).viewInsets.bottom + 100,
                          ),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final item = _filteredPlaylist[index];

                                return ValueListenableBuilder<Map<String, Set<String>>>(
                                  valueListenable: playlistContentsNotifier,
                                  builder: (context, contents, _) {
                                    final pSet =
                                        contents[widget.playlistName] ?? <String>{};
                                    final baseId = getBaseId(item.id);
                                    final inPlaylist =
                                        pSet.contains(item.id) ||
                                        pSet.any((id) => getBaseId(id) == baseId);

                                  return ListTile(
                                    leading: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: getLocalOrNetworkImage(
                                        item,
                                        width: 45,
                                        height: 45,
                                      ),
                                    ),
                                    title: Stack(
                                      alignment: Alignment.centerLeft,
                                      children: [
                                        AnimatedOpacity(
                                          duration: const Duration(milliseconds: 300),
                                          opacity: inPlaylist ? 0.0 : 1.0,
                                          child: Text(
                                            item.title,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        AnimatedOpacity(
                                          duration: const Duration(milliseconds: 300),
                                          opacity: inPlaylist ? 1.0 : 0.0,
                                          child: ShaderMask(
                                            blendMode: BlendMode.srcIn,
                                            shaderCallback: (bounds) {
                                              return LinearGradient(
                                                colors: widget.activeThemeColors,
                                                begin: Alignment.centerLeft,
                                                end: Alignment.centerRight,
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
                                              item.title,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    subtitle: Text(
                                      formatArtist(item.artist),
                                      style: TextStyle(
                                        color: inPlaylist
                                            ? Colors.white.withValues(alpha: 0.7)
                                            : Colors.white54,
                                      ),
                                    ),
                                    trailing: IconButton(
                                      icon: inPlaylist
                                          ? ShaderMask(
                                              blendMode: BlendMode.srcIn,
                                              shaderCallback: (bounds) {
                                                return LinearGradient(
                                                  colors: widget.activeThemeColors,
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                ).createShader(
                                                  Rect.fromLTWH(
                                                    0,
                                                    0,
                                                    bounds.width,
                                                    bounds.height,
                                                  ),
                                                );
                                              },
                                              child: const Icon(
                                                CupertinoIcons.checkmark_circle_fill,
                                                color: Colors.white,
                                                size: 28,
                                              ),
                                            )
                                          : const Icon(
                                              CupertinoIcons.plus_circle,
                                              color: Colors.white70,
                                              size: 28,
                                            ),
                                      onPressed: () {
                                        final currentContents =
                                            Map<String, Set<String>>.from(
                                              playlistContentsNotifier.value,
                                            );
                                        final currentSet = Set<String>.from(
                                          currentContents[widget.playlistName] ??
                                              <String>{},
                                        );

                                        final baseId = getBaseId(item.id);
                                        if (inPlaylist) {
                                          currentSet.removeWhere((id) => getBaseId(id) == baseId);
                                        } else {
                                          currentSet.add(item.id);
                                        }

                                        currentContents[widget.playlistName] =
                                            currentSet;
                                        playlistContentsNotifier.value =
                                            currentContents;
                                      },
                                    ),
                                  );
                                },
                              );
                            },
                            childCount: _filteredPlaylist.length,
                          ),
                        ),
                      ),
                    ],
                  ),

                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: headerHeight,
                    child: Stack(
                      children: [
                        ValueListenableBuilder<double>(
                          valueListenable: _scrollOffset,
                          builder: (context, offset, child) {
                            final opacity = (offset / 25.0).clamp(0.0, 1.0);
                            if (opacity == 0.0) return const SizedBox.shrink();

                            return Opacity(opacity: opacity, child: child);
                          },
                          child: ClipRect(
                            child: ShaderMask(
                              shaderCallback: (bounds) {
                                return const LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.black,
                                    Colors.black,
                                    Colors.transparent,
                                  ],
                                  stops: [0.0, 0.70, 1.0],
                                ).createShader(bounds);
                              },
                              blendMode: BlendMode.dstIn,
                              child: BackdropFilter(
                                filter: ImageFilter.blur(
                                  sigmaX: 35,
                                  sigmaY: 35,
                                ),
                                child: Container(
                                  height: headerHeight,
                                  color: Colors.black.withValues(alpha: 0.98),
                                ),
                              ),
                            ),
                          ),
                        ),

                        RepaintBoundary(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(height: topPadding),
                              ValueListenableBuilder<double>(
                                valueListenable: _sheetSize,
                                builder: (context, size, child) {
                                  final opacity =
                                      (1.0 - ((size - 0.90) / 0.10)).clamp(
                                    0.0,
                                    1.0,
                                  );
                                  return Opacity(
                                    opacity: opacity,
                                    child: child,
                                  );
                                },
                                child: Center(
                                  child: Container(
                                    margin: const EdgeInsets.only(
                                      top: 12,
                                      bottom: 8,
                                    ),
                                    width: 40,
                                    height: 5,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.3,
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                              ),

                              Padding(
                                padding: const EdgeInsets.only(
                                  top: 10,
                                  left: 16,
                                  right: 16,
                                  bottom: 6,
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      "Ajouter des titres",
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    CupertinoButton(
                                      padding: EdgeInsets.zero,
                                      onPressed: () {
                                        Navigator.pop(context);
                                      },
                                      child: ShaderMask(
                                        blendMode: BlendMode.srcIn,
                                        shaderCallback: (bounds) {
                                          return LinearGradient(
                                            colors: widget.activeThemeColors,
                                            begin: Alignment.centerLeft,
                                            end: Alignment.centerRight,
                                            stops: getGradientStops(
                                              widget.activeThemeColors.length,
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
                                        child: const Text(
                                          "Terminé",
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),


                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
