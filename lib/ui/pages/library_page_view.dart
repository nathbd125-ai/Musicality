import 'package:musicality/ui/widgets/song_tile.dart';
import 'package:musicality/core/my_audio_handler.dart';
import 'package:musicality/core/globals.dart';
import 'package:musicality/ui/sheets/add_songs_sheet.dart';
import 'package:musicality/ui/widgets/custom_search_bar.dart';
import 'package:musicality/ui/widgets/marquee_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:audio_service/audio_service.dart';
import 'dart:io';
import 'dart:math';
import 'dart:async';

class LibraryPageView extends StatefulWidget {
  final MediaItem? currentItem;
  final List<Color> dynamicGradientColors;

  const LibraryPageView({
    super.key,
    required this.currentItem,
    required this.dynamicGradientColors,
  });

  @override
  State<LibraryPageView> createState() => LibraryPageViewState();
}

class LibraryPageViewState extends State<LibraryPageView> {
  String _searchQuery = '';
  late final PageController _pageController;
  late ScrollController _scrollController;
  bool _isScrolled = false;

  String _activePlaylistName = 'LIKES';

  bool get isOnMainPage => _pageController.hasClients
      ? (_pageController.page?.round() ?? 0) == 0
      : true;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
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

  @override
  void dispose() {
    _pageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _openPlaylist(String name) {
    FocusScope.of(context).unfocus();
    setState(() {
      _activePlaylistName = name;
    });
    _pageController.animateToPage(
      1,
      duration: const Duration(milliseconds: 400),
      curve: Curves.fastOutSlowIn,
    );
  }

  void goBack() {
    FocusScope.of(context).unfocus();
    _pageController.animateToPage(
      0,
      duration: const Duration(milliseconds: 400),
      curve: Curves.fastOutSlowIn,
    );
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) {
        setState(() {
          _searchQuery = '';
          _isScrolled = false;
        });
      }
    });
  }

  void _showAddSongsSheet(
    BuildContext context,
    String playlistName,
    List<Color> themeColors,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return AddSongsSheet(
          playlistName: playlistName,
          activeThemeColors: themeColors,
        );
      },
    );
  }

  void _showEditPlaylistDialog(
    BuildContext context,
    String oldName,
    List<Color> themeColors,
  ) {
    showEditPlaylistDialog(
      context: context,
      oldName: oldName,
      themeColors: themeColors,
    );
  }

  Widget _buildCustomPlaylistTile(String title) {
    return ValueListenableBuilder<Map<String, String>>(
      valueListenable: playlistImagesNotifier,
      builder: (context, images, child) {
        return ValueListenableBuilder<Map<String, Set<String>>>(
          valueListenable: playlistContentsNotifier,
          builder: (context, contents, child) {
            final count = contents[title]?.length ?? 0;
            final customImgPath = images[title];

            Widget leadingIcon;
            if (customImgPath != null &&
                customImgPath.isNotEmpty &&
                File(customImgPath).existsSync()) {
              leadingIcon = ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  File(customImgPath),
                  width: 45,
                  height: 45,
                  cacheWidth: 135,
                  fit: BoxFit.cover,
                ),
              );
            } else {
              leadingIcon = Container(
                width: 45,
                height: 45,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  gradient: LinearGradient(
                    colors: widget.dynamicGradientColors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: const Icon(
                  CupertinoIcons.music_albums_fill,
                  color: Colors.white,
                  size: 24,
                ),
              );
            }

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                  width: 0.5,
                ),
              ),
              child: Material(
                type: MaterialType.transparency,
                child: ListTile(
                  leading: leadingIcon,
                  title: MarqueeWidget(
                    resetKey: 'title_$title',
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  subtitle: Text(
                    "$count titre${count > 1 ? 's' : ''}",
                    style: const TextStyle(color: Colors.white70),
                  ),
                  trailing: const Icon(
                    CupertinoIcons.chevron_right,
                    color: Colors.white54,
                    size: 20,
                  ),
                  onTap: () {
                    _openPlaylist(title);
                  },
                  onLongPress: () {
                    _showEditPlaylistDialog(
                      context,
                      title,
                      widget.dynamicGradientColors,
                    );
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildHub() {
    return ValueListenableBuilder<Set<String>>(
      valueListenable: likedSongsNotifier,
      builder: (context, likedSongs, child) {
        return ValueListenableBuilder<List<String>>(
          valueListenable: customPlaylistsNotifier,
          builder: (context, customPlaylists, child) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.only(
                      left: 20,
                      right: 16,
                      top: 20,
                      bottom: 10,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "Bibliothèque",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            CupertinoIcons.add,
                            color: Colors.white,
                            size: 28,
                          ),
                          onPressed: () {
                            showCreatePlaylistDialog(
                              context,
                              widget.dynamicGradientColors,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),

                if (likedSongs.isNotEmpty || customPlaylists.isNotEmpty)
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        children: [
                          if (likedSongs.isNotEmpty)
                            GestureDetector(
                              onTap: () {
                                _openPlaylist('LIKES');
                              },
                              child: Container(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 6,
                                ),
                                clipBehavior: Clip.antiAlias,
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.08),
                                    width: 0.5,
                                  ),
                                ),
                                child: Material(
                                  type: MaterialType.transparency,
                                  child: ListTile(
                                    leading: Container(
                                      width: 45,
                                      height: 45,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(8),
                                        gradient: LinearGradient(
                                          colors: widget.dynamicGradientColors,
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                      ),
                                      child: const Icon(
                                        CupertinoIcons.heart_fill,
                                        color: Colors.white,
                                        size: 24,
                                      ),
                                    ),
                                    title: const Text(
                                      "Titres likés",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                    subtitle: Text(
                                      "${likedSongs.length} titre${likedSongs.length > 1 ? 's' : ''}",
                                      style: const TextStyle(
                                        color: Colors.white70,
                                      ),
                                    ),
                                    trailing: const Icon(
                                      CupertinoIcons.chevron_right,
                                      color: Colors.white54,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ),
                            ),

                          ...customPlaylists.reversed.map(
                            (name) => _buildCustomPlaylistTile(name),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: Container(
                      alignment: Alignment.topCenter,
                      padding: const EdgeInsets.only(top: 100),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            CupertinoIcons.heart,
                            color: Colors.white.withValues(alpha: 0.2),
                            size: 60,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            "Votre bibliothèque est vide",
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            "Les titres que vous aimez apparaîtront ici",
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SafeArea(
          bottom: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(
                  top: 10,
                  left: 4,
                  bottom: 4,
                  right: 16,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(
                              CupertinoIcons.back,
                              color: Colors.white,
                              size: 28,
                            ),
                            onPressed: goBack,
                          ),
                          Expanded(
                            child: MarqueeWidget(
                              resetKey: 'header_$_activePlaylistName',
                              child: Text(
                                _activePlaylistName == 'LIKES'
                                    ? "Titres likés"
                                    : _activePlaylistName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_activePlaylistName != 'LIKES')
                      IconButton(
                        icon: const Icon(
                          CupertinoIcons.add,
                          color: Colors.white,
                          size: 28,
                        ),
                        onPressed: () {
                          _showAddSongsSheet(
                            context,
                            _activePlaylistName,
                            widget.dynamicGradientColors,
                          );
                        },
                      ),
                  ],
                ),
              ),
              CustomSearchBar(
                hintText: _activePlaylistName == 'LIKES'
                    ? "Rechercher dans vos coups de cœur..."
                    : "Rechercher dans cette playlist...",
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                  });
                },
              ),
            ],
          ),
        ),

        Expanded(
          child: TweenAnimationBuilder<Color?>(
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
            child: ValueListenableBuilder<Set<String>>(
              valueListenable: likedSongsNotifier,
              builder: (context, likedSongs, _) {
                return ValueListenableBuilder<Map<String, Set<String>>>(
                  valueListenable: playlistContentsNotifier,
                  builder: (context, playlistContents, _) {
                    final isLikes = _activePlaylistName == 'LIKES';
                    final currentSet = isLikes
                        ? likedSongs
                        : (playlistContents[_activePlaylistName] ?? <String>{});

                    if (isLikes &&
                        currentSet.isEmpty &&
                        _pageController.hasClients &&
                        (_pageController.page?.round() ?? 0) == 1) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) goBack();
                      });
                    }

                    final currentBaseIds = currentSet.map(getBaseId).toSet();
                    final query = normalizeString(_searchQuery);

                    final fullPlaylist = globalPlaylist.where((item) {
                      final baseId = getBaseId(item.id);
                      return currentSet.contains(item.id) ||
                          currentBaseIds.contains(baseId);
                    }).toList();
                    fullPlaylist.sort(
                      (a, b) => normalizeString(
                        a.title,
                      ).compareTo(normalizeString(b.title)),
                    );

                    final filteredPlaylist = query.isEmpty
                        ? fullPlaylist
                        : fullPlaylist.where((item) {
                            final titleMatch = normalizeString(
                              item.title,
                            ).contains(query);
                            final artistMatch = normalizeString(
                              item.artist ?? '',
                            ).contains(query);
                            return titleMatch || artistMatch;
                          }).toList();

                    String emptyText = _searchQuery.isEmpty
                        ? (isLikes
                            ? "Votre bibliothèque est vide"
                            : "Cette playlist est vide")
                        : "Aucun résultat pour cette recherche";

                    if (filteredPlaylist.isEmpty) {
                      return Container(
                        alignment: Alignment.topCenter,
                        padding: const EdgeInsets.only(top: 100),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isLikes
                                  ? CupertinoIcons.heart
                                  : CupertinoIcons.music_note_list,
                              color: Colors.white24,
                              size: 48,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              emptyText,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (!isLikes && _searchQuery.isEmpty) ...[
                              const SizedBox(height: 8),
                              const Text(
                                "Ajoutez des titres à l'aide du bouton + en haut à droite",
                                style: TextStyle(
                                  color: Colors.white38,
                                  fontSize: 13,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ],
                        ),
                      );
                    }

                    return ListView.builder(
                      controller: _scrollController,
                      itemCount: filteredPlaylist.length + 1,
                      padding: EdgeInsets.only(
                        bottom:
                            MediaQuery.of(context).viewInsets.bottom + 180.0,
                      ),
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return _buildPlaylistActionBar(
                            fullPlaylist,
                            filteredPlaylist,
                          );
                        }
                        final songIndex = index - 1;
                        final item = filteredPlaylist[songIndex];
                        final isSelected = widget.currentItem?.id == item.id;

                        return SongTile(
                          item: item,
                          isSelected: isSelected,
                          activeThemeColors: widget.dynamicGradientColors,
                          heroTag:
                              'lib_${_activePlaylistName}_${songIndex}_${item.id}',
                          onTap: () {
                            FocusScope.of(context).unfocus();
                            final targetIndex = fullPlaylist.indexWhere(
                              (m) => m.id == item.id,
                            );
                            (globalAudioHandler as MyAudioHandler).playFromList(
                              fullPlaylist,
                              targetIndex >= 0 ? targetIndex : 0,
                              contextTag: 'playlist:$_activePlaylistName',
                            );
                          },
                        );
                      },
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

  Widget _buildPlaylistActionBar(
    List<MediaItem> fullPlaylist,
    List<MediaItem> filteredPlaylist,
  ) {
    return ValueListenableBuilder<String?>(
      valueListenable: currentPlaybackContextNotifier,
      builder: (context, currentContext, _) {
        final bool isThisPlaylistActive =
            currentContext == 'playlist:$_activePlaylistName';

        return StreamBuilder<PlaybackState>(
          stream: globalAudioHandler.playbackState,
          builder: (context, snapshot) {
            final playbackState =
                snapshot.data ?? globalAudioHandler.playbackState.value;
            final isPlaying = isThisPlaylistActive && playbackState.playing;

            return StreamBuilder<bool>(
              stream: (globalAudioHandler as MyAudioHandler).shuffleModeEnabledStream,
              initialData: (globalAudioHandler is MyAudioHandler)
                  ? (globalAudioHandler as MyAudioHandler).shuffleModeEnabled
                  : false,
              builder: (context, shuffleSnap) {
                final isShuffle = shuffleSnap.data ?? false;

                final themeColors = widget.dynamicGradientColors.isNotEmpty
                    ? widget.dynamicGradientColors
                    : const [Color(0xFF7C4DFF), Color(0xFF536DFE)];

                final primaryColor = themeColors.first;

                return Padding(
                  padding: const EdgeInsets.only(
                    left: 20,
                    right: 20,
                    top: 2,
                    bottom: 10,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        _searchQuery.trim().isEmpty
                            ? "${filteredPlaylist.length} titre${filteredPlaylist.length > 1 ? 's' : ''}"
                            : "${filteredPlaylist.length} résultat${filteredPlaylist.length > 1 ? 's' : ''}",
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.65),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _PlaylistShuffleButton(
                            isShuffle: isShuffle,
                            primaryColor: primaryColor,
                            gradientColors: themeColors,
                            onTap: () async {
                              final handler = globalAudioHandler as MyAudioHandler;
                              if (isThisPlaylistActive && playbackState.playing) {
                                await handler.toggleShuffleMode();
                              } else {
                                await handler.setShuffleMode(
                                  AudioServiceShuffleMode.all,
                                );
                                if (fullPlaylist.isNotEmpty) {
                                  final randomIdx =
                                      Random().nextInt(fullPlaylist.length);
                                  await handler.playFromList(
                                    fullPlaylist,
                                    randomIdx,
                                    contextTag: 'playlist:$_activePlaylistName',
                                  );
                                }
                              }
                            },
                          ),
                          const SizedBox(width: 14),
                          _PlaylistBigPlayButton(
                            isPlaying: isPlaying,
                            gradientColors: themeColors,
                            onTap: () async {
                              final handler = globalAudioHandler as MyAudioHandler;
                              if (isThisPlaylistActive) {
                                if (playbackState.playing) {
                                  await handler.pause();
                                } else {
                                  await handler.play();
                                }
                              } else {
                                if (fullPlaylist.isNotEmpty) {
                                  await handler.setShuffleMode(
                                    AudioServiceShuffleMode.none,
                                  );
                                  await handler.playFromList(
                                    fullPlaylist,
                                    0,
                                    contextTag: 'playlist:$_activePlaylistName',
                                  );
                                }
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return PageView(
      controller: _pageController,
      physics: const NeverScrollableScrollPhysics(),
      children: [_buildHub(), _buildList()],
    );
  }
}

class _PlaylistBigPlayButton extends StatefulWidget {
  final bool isPlaying;
  final List<Color> gradientColors;
  final Future<void> Function() onTap;

  const _PlaylistBigPlayButton({
    required this.isPlaying,
    required this.gradientColors,
    required this.onTap,
  });

  @override
  State<_PlaylistBigPlayButton> createState() => _PlaylistBigPlayButtonState();
}

class _PlaylistBigPlayButtonState extends State<_PlaylistBigPlayButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 90),
      lowerBound: 0.88,
      upperBound: 1.0,
    )..value = 1.0;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = widget.gradientColors.isNotEmpty
        ? widget.gradientColors.first
        : const Color(0xFF7C4DFF);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _controller.animateTo(0.88, curve: Curves.easeInOut),
      onTapUp: (_) async {
        _controller.animateTo(1.0, curve: Curves.easeInOut);
        if (isHapticFeedbackEnabledNotifier.value) {
          HapticFeedback.mediumImpact();
        }
        await widget.onTap();
      },
      onTapCancel: () => _controller.animateTo(1.0, curve: Curves.easeInOut),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => Transform.scale(
          scale: _controller.value,
          child: child,
        ),
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: widget.gradientColors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: primaryColor.withValues(alpha: 0.40),
                blurRadius: 14,
                spreadRadius: 1,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(scale: animation, child: child),
              ),
              child: Padding(
                padding: EdgeInsets.only(left: widget.isPlaying ? 0.0 : 2.5),
                child: Icon(
                  widget.isPlaying
                      ? CupertinoIcons.pause_solid
                      : CupertinoIcons.play_arrow_solid,
                  key: ValueKey<bool>(widget.isPlaying),
                  color: Colors.white,
                  size: 26,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaylistShuffleButton extends StatefulWidget {
  final bool isShuffle;
  final Color primaryColor;
  final List<Color> gradientColors;
  final Future<void> Function() onTap;

  const _PlaylistShuffleButton({
    required this.isShuffle,
    required this.primaryColor,
    required this.gradientColors,
    required this.onTap,
  });

  @override
  State<_PlaylistShuffleButton> createState() => _PlaylistShuffleButtonState();
}

class _PlaylistShuffleButtonState extends State<_PlaylistShuffleButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 90),
      lowerBound: 0.88,
      upperBound: 1.0,
    )..value = 1.0;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _controller.animateTo(0.88, curve: Curves.easeInOut),
      onTapUp: (_) async {
        _controller.animateTo(1.0, curve: Curves.easeInOut);
        if (isHapticFeedbackEnabledNotifier.value) {
          HapticFeedback.lightImpact();
        }
        await widget.onTap();
      },
      onTapCancel: () => _controller.animateTo(1.0, curve: Curves.easeInOut),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => Transform.scale(
          scale: _controller.value,
          child: child,
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.isShuffle
                ? widget.primaryColor.withValues(alpha: 0.22)
                : Colors.white.withValues(alpha: 0.08),
            border: Border.all(
              color: widget.isShuffle
                  ? widget.primaryColor.withValues(alpha: 0.65)
                  : Colors.white.withValues(alpha: 0.12),
              width: 1.2,
            ),
            boxShadow: widget.isShuffle
                ? [
                    BoxShadow(
                      color: widget.primaryColor.withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: widget.isShuffle
                ? ShaderMask(
                    blendMode: BlendMode.srcIn,
                    shaderCallback: (bounds) => LinearGradient(
                      colors: widget.gradientColors,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ).createShader(bounds),
                    child: const Icon(
                      CupertinoIcons.shuffle,
                      size: 20,
                      color: Colors.white,
                    ),
                  )
                : Icon(
                    CupertinoIcons.shuffle,
                    size: 20,
                    color: Colors.white.withValues(alpha: 0.65),
                  ),
          ),
        ),
      ),
    );
  }
}
