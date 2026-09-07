import 'package:musicality/core/globals.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:musicality/ui/player/liquid_glass_container.dart';
import 'package:audio_service/audio_service.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';

class SongOptionsOverlay extends StatefulWidget {
  final MediaItem item;
  final List<Color> activeThemeColors;
  final String heroTag;

  const SongOptionsOverlay({
    super.key,
    required this.item,
    required this.activeThemeColors,
    required this.heroTag,
  });

  @override
  State<SongOptionsOverlay> createState() => _SongOptionsOverlayState();
}

class _SongOptionsOverlayState extends State<SongOptionsOverlay> {
  bool _showCreatePlaylist = false;
  String _newPlaylistName = '';
  String? _newPlaylistImage;
  final Set<String> _selectedPlaylists = {};
  final Set<String> _initialPlaylists = {};
  final FocusNode globalPlaylistFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    final baseId = getBaseId(widget.item.id);
    final contents = playlistContentsNotifier.value;
    for (var entry in contents.entries) {
      if (entry.value.contains(widget.item.id) ||
          entry.value.any((id) => getBaseId(id) == baseId)) {
        _selectedPlaylists.add(entry.key);
        _initialPlaylists.add(entry.key);
      }
    }
  }

  bool get _hasChanges {
    if (_selectedPlaylists.length != _initialPlaylists.length) return true;
    return !_selectedPlaylists.containsAll(_initialPlaylists);
  }

  @override
  void dispose() {
    globalPlaylistFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () {
                if (_showCreatePlaylist) {
                  globalPlaylistFocusNode.unfocus();
                  setState(() {
                    _showCreatePlaylist = false;
                  });
                } else {
                  Navigator.pop(context);
                }
              },
              child: Container(color: Colors.transparent),
            ),
          ),

          IgnorePointer(
            ignoring: _showCreatePlaylist,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 300),
              opacity: _showCreatePlaylist ? 0.0 : 1.0,
              child: _buildOptions(),
            ),
          ),

          IgnorePointer(
            ignoring: !_showCreatePlaylist,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 300),
              opacity: _showCreatePlaylist ? 1.0 : 0.0,
              child: AnimatedScale(
                duration: const Duration(milliseconds: 300),
                scale: _showCreatePlaylist ? 1.0 : 0.9,
                curve: Curves.easeOutCubic,
                child: _buildCreatePlaylist(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptions() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 220,
            height: 220,
            child: Hero(
              tag: widget.heroTag,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: widget.activeThemeColors[0].withValues(alpha: 0.4),
                      blurRadius: 50,
                      spreadRadius: 10,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: getLocalOrNetworkImage(widget.item),
                ),
              ),
            ),
          ),

          AnimatedBuilder(
            animation: ModalRoute.of(context)!.animation!,
            builder: (context, child) {
              final animation = ModalRoute.of(context)!.animation!;
              return Opacity(
                opacity: CurvedAnimation(
                  parent: animation,
                  curve: const Interval(0.0, 1.0, curve: Curves.easeOut),
                  reverseCurve: const Interval(0.5, 1.0, curve: Curves.easeIn),
                ).value,
                child: child,
              );
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    widget.item.title,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    formatArtist(widget.item.artist),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white.withValues(alpha: 0.7),
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
                const SizedBox(height: 40),

                const Text(
                  "AJOUTER À UNE PLAYLIST",
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.bold,
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 12),

                ValueListenableBuilder<List<String>>(
                  valueListenable: customPlaylistsNotifier,
                  builder: (context, playlists, child) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (playlists.isNotEmpty)
                          LiquidGlassContainer(
                            borderRadius: 16,
                            child: Container(
                              width: MediaQuery.of(context).size.width * 0.75,
                              constraints: const BoxConstraints(maxHeight: 250),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.4),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Material(
                                type: MaterialType.transparency,
                                child: ListView.builder(
                                  shrinkWrap: true,
                                  padding: EdgeInsets.zero,
                                  itemCount: playlists.length,
                                  itemBuilder: (context, index) {
                                    final pName = playlists[index];
                                    final isSelected =
                                        _selectedPlaylists.contains(pName);

                                    return Container(
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? widget.activeThemeColors[0]
                                                .withValues(alpha: 0.18)
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(12),
                                        border: isSelected
                                            ? Border.all(
                                                color: widget
                                                    .activeThemeColors[0]
                                                    .withValues(alpha: 0.4),
                                                width: 1,
                                              )
                                            : null,
                                      ),
                                      child: ListTile(
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        leading: Icon(
                                          CupertinoIcons.music_albums_fill,
                                          color: isSelected
                                              ? widget.activeThemeColors[0]
                                              : Colors.white70,
                                        ),
                                        title: Text(
                                          pName,
                                          style: TextStyle(
                                            color: isSelected
                                                ? Colors.white
                                                : Colors.white70,
                                            fontWeight: isSelected
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                          ),
                                        ),
                                        trailing: isSelected
                                            ? ShaderMask(
                                                blendMode: BlendMode.srcIn,
                                                shaderCallback: (bounds) {
                                                  return LinearGradient(
                                                    colors: widget
                                                        .activeThemeColors,
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
                                                  CupertinoIcons
                                                      .checkmark_circle_fill,
                                                  color: Colors.white,
                                                  size: 24,
                                                ),
                                              )
                                            : const Icon(
                                                CupertinoIcons.circle,
                                                color: Colors.white30,
                                                size: 22,
                                              ),
                                        onTap: () {
                                          setState(() {
                                            if (_selectedPlaylists.contains(
                                              pName,
                                            )) {
                                              _selectedPlaylists.remove(pName);
                                            } else {
                                              _selectedPlaylists.add(pName);
                                            }
                                          });
                                        },
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),

                      const SizedBox(height: 16),

                      AnimatedSize(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeInOut,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CupertinoButton(
                              padding: EdgeInsets.zero,
                              onPressed: () {
                                setState(() {
                                  _showCreatePlaylist = true;
                                });
                                globalPlaylistFocusNode.requestFocus();
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      CupertinoIcons.add,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                    SizedBox(width: 6),
                                    Text(
                                      "Nouvelle playlist",
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            if (_hasChanges) ...[
                              const SizedBox(width: 12),
                              CupertinoButton(
                                padding: EdgeInsets.zero,
                                onPressed: () {
                                  final currentContents =
                                      Map<String, Set<String>>.from(
                                        playlistContentsNotifier.value,
                                      );
                                  final baseId = getBaseId(widget.item.id);

                                  for (var pName
                                      in customPlaylistsNotifier.value) {
                                    final currentSet = Set<String>.from(
                                      currentContents[pName] ?? <String>{},
                                    );
                                    final shouldBeIn = _selectedPlaylists
                                        .contains(pName);
                                    final isCurrentlyIn =
                                        currentSet.contains(widget.item.id) ||
                                        currentSet.any((id) => getBaseId(id) == baseId);

                                    if (shouldBeIn && !isCurrentlyIn) {
                                      currentSet.add(widget.item.id);
                                      currentContents[pName] = currentSet;
                                    } else if (!shouldBeIn && isCurrentlyIn) {
                                      currentSet.removeWhere((id) => getBaseId(id) == baseId);
                                      currentContents[pName] = currentSet;
                                    }
                                  }

                                  playlistContentsNotifier.value =
                                      currentContents;
                                  Navigator.pop(context);
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: widget.activeThemeColors,
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(20),
                                    boxShadow: [
                                      BoxShadow(
                                        color: widget.activeThemeColors[0]
                                            .withValues(alpha: 0.4),
                                        blurRadius: 10,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        CupertinoIcons.checkmark_alt,
                                        color: Colors.white,
                                        size: 18,
                                      ),
                                      SizedBox(width: 6),
                                      Text(
                                        "Valider",
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCreatePlaylist() {
    final hasValidImage =
        _newPlaylistImage != null &&
        _newPlaylistImage!.isNotEmpty &&
        File(_newPlaylistImage!).existsSync();

    return Align(
      alignment: const Alignment(0.0, -0.4),
      child: Material(
        type: MaterialType.transparency,
        child: LiquidGlassContainer(
          borderRadius: 24,
          child: Container(
            width: MediaQuery.of(context).size.width * 0.85,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ShaderMask(
                  blendMode: BlendMode.srcIn,
                  shaderCallback: (bounds) {
                    return LinearGradient(
                      colors: widget.activeThemeColors,
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ).createShader(
                      Rect.fromLTWH(0, 0, bounds.width, bounds.height),
                    );
                  },
                  child: const Text(
                    "Nouvelle Playlist",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    GestureDetector(
                      onTap: () async {
                        final picker = ImagePicker();
                        final xfile = await picker.pickImage(
                          source: ImageSource.gallery,
                        );
                        if (xfile != null) {
                          setState(() {
                            _newPlaylistImage = xfile.path;
                          });
                        }
                      },
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.2),
                          ),
                        ),
                        child: hasValidImage
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: Image.file(
                                  File(_newPlaylistImage!),
                                  fit: BoxFit.cover,
                                ),
                              )
                            : const Icon(
                                CupertinoIcons.camera_fill,
                                color: Colors.white54,
                                size: 32,
                              ),
                      ),
                    ),
                    if (hasValidImage)
                      Positioned(
                        top: -10,
                        right: -10,
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _newPlaylistImage = null;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: widget.activeThemeColors,
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black54,
                                  blurRadius: 4,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Icon(
                              CupertinoIcons.minus,
                              color: Colors.white,
                              size: 16,
                              weight: 800,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 20),
                ShaderMask(
                  blendMode: BlendMode.srcIn,
                  shaderCallback: (bounds) {
                    return LinearGradient(
                      colors: widget.activeThemeColors,
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ).createShader(
                      Rect.fromCenter(
                        center: bounds.center,
                        width: 120,
                        height: bounds.height,
                      ),
                    );
                  },
                  child: Theme(
                    data: Theme.of(context).copyWith(
                      textSelectionTheme: TextSelectionThemeData(
                        selectionHandleColor: widget.activeThemeColors[0],
                        selectionColor: widget.activeThemeColors[0].withValues(
                          alpha: 0.3,
                        ),
                      ),
                    ),
                    child: TextField(
                      focusNode: globalPlaylistFocusNode,
                      onChanged: (val) {
                        _newPlaylistName = val;
                      },
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      cursorColor: Colors.white,
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        hintText: "Nom de la playlist...",
                        hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.3),
                          fontSize: 20,
                        ),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 30),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () {
                          globalPlaylistFocusNode.unfocus();
                          setState(() {
                            _showCreatePlaylist = false;
                          });
                        },
                        child: const Text(
                          "Annuler",
                          style: TextStyle(color: Colors.white54, fontSize: 16),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: widget.activeThemeColors,
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: CupertinoButton(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          onPressed: () {
                            globalPlaylistFocusNode.unfocus();

                            if (_newPlaylistName.trim().isNotEmpty) {
                              final pName = _newPlaylistName.trim();

                              if (!customPlaylistsNotifier.value.contains(
                                pName,
                              )) {
                                final currentList = List<String>.from(
                                  customPlaylistsNotifier.value,
                                );
                                currentList.add(pName);
                                customPlaylistsNotifier.value = currentList;
                              }

                              final currentContents =
                                  Map<String, Set<String>>.from(
                                    playlistContentsNotifier.value,
                                  );
                              final currentSet = Set<String>.from(
                                currentContents[pName] ?? <String>{},
                              );
                              currentSet.add(widget.item.id);
                              currentContents[pName] = currentSet;
                              playlistContentsNotifier.value = currentContents;

                              if (_newPlaylistImage != null &&
                                  _newPlaylistImage!.isNotEmpty) {
                                final currentImages = Map<String, String>.from(
                                  playlistImagesNotifier.value,
                                );
                                currentImages[pName] = _newPlaylistImage!;
                                playlistImagesNotifier.value = currentImages;
                              }
                            }

                            setState(() {
                              _showCreatePlaylist = false;
                            });
                            Navigator.pop(context);
                          },
                          child: const Text(
                            "Créer",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
