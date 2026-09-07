import 'package:flutter/cupertino.dart';
import 'package:musicality/ui/widgets/marquee_widget.dart';
import 'dart:ui';
import 'package:musicality/ui/sheets/song_options_overlay.dart';
import 'package:audio_service/audio_service.dart';
import 'package:musicality/core/globals.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SongTile extends StatelessWidget {
  final MediaItem item;
  final bool isSelected;
  final VoidCallback onTap;
  final List<Color> activeThemeColors;
  final String heroTag;
  final VoidCallback? onRemoveFromHistory;
  final bool showPlayCount;

  const SongTile({
    super.key,
    required this.item,
    required this.isSelected,
    required this.onTap,
    required this.activeThemeColors,
    required this.heroTag,
    this.onRemoveFromHistory,
    this.showPlayCount = false,
  });

  void _showSongOptions(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        transitionDuration: const Duration(milliseconds: 350),
        reverseTransitionDuration: const Duration(milliseconds: 350),
        pageBuilder: (context, animation, secondaryAnimation) {
          return SongOptionsOverlay(
            item: item,
            activeThemeColors: activeThemeColors,
            heroTag: heroTag,
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return Stack(
            children: [
              FadeTransition(
                opacity: animation,
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(color: Colors.black.withValues(alpha: 0.6)),
                ),
              ),
              child,
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final trackColors = getAlbumGradientColors(item);

    return RepaintBoundary(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.white.withValues(alpha: 0.15)
              : Colors.black.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
            width: 0.5,
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            onLongPress: () {
              _showSongOptions(context);
            },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 45,
                    height: 45,
                    child: Hero(
                      tag: heroTag,
                      child: Material(
                        type: MaterialType.transparency,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: activeThemeColors[0].withValues(
                                  alpha: 0.0,
                                ),
                                blurRadius: 0,
                                spreadRadius: 0,
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: getLocalOrNetworkImage(
                              item,
                              width: 45,
                              height: 45,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        MarqueeWidget(
                          resetKey:
                              '${isSelected ? 'sel' : 'unsel'}_${item.id}',
                          child: isSelected
                              ? ShaderMask(
                                  blendMode: BlendMode.srcIn,
                                  shaderCallback: (bounds) {
                                    return LinearGradient(
                                      colors: trackColors,
                                      begin: Alignment.centerLeft,
                                      end: Alignment.centerRight,
                                      stops: getGradientStops(
                                        trackColors.length,
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
                                    item.title,
                                    maxLines: 1,
                                    softWrap: false,
                                    overflow: TextOverflow.visible,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                )
                              : Text(
                                  item.title,
                                  maxLines: 1,
                                  softWrap: false,
                                  overflow: TextOverflow.visible,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                        const SizedBox(height: 4),
                        MarqueeWidget(
                          resetKey:
                              'artist_${isSelected ? 'sel' : 'unsel'}_${item.id}',
                          child: isSelected
                              ? ShaderMask(
                                  blendMode: BlendMode.srcIn,
                                  shaderCallback: (bounds) {
                                    return LinearGradient(
                                      colors: trackColors,
                                      begin: Alignment.centerLeft,
                                      end: Alignment.centerRight,
                                      stops: getGradientStops(
                                        trackColors.length,
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
                                    formatArtist(item.artist),
                                    maxLines: 1,
                                    softWrap: false,
                                    overflow: TextOverflow.visible,
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.85,
                                      ),
                                      fontSize: 14,
                                      height: 1.0,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                )
                              : Text(
                                  formatArtist(item.artist),
                                  maxLines: 1,
                                  softWrap: false,
                                  overflow: TextOverflow.visible,
                                  style: const TextStyle(
                                    color: Color(0xFF9E9E9E),
                                    fontSize: 14,
                                    height: 1.0,
                                    fontWeight: FontWeight.normal,
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (showPlayCount)
                    ValueListenableBuilder<Map<String, int>>(
                      valueListenable: songPlayCountNotifier,
                      builder: (context, playCounts, child) {
                        final count = playCounts[item.id] ?? 0;
                        final textStr = "$count écoute${count > 1 ? 's' : ''}";

                        return Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: isSelected
                              ? ShaderMask(
                                  blendMode: BlendMode.srcIn,
                                  shaderCallback: (bounds) {
                                    return LinearGradient(
                                      colors: activeThemeColors,
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
                                    textStr,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                )
                              : Text(
                                  textStr,
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        );
                      },
                    )
                  else
                    ValueListenableBuilder<Set<String>>(
                      valueListenable: likedSongsNotifier,
                      builder: (context, likedSongs, child) {
                        final itemBaseId = getBaseId(item.id);
                        final isLiked = likedSongs.contains(item.id) ||
                            likedSongs.any((id) => getBaseId(id) == itemBaseId);
                        return GestureDetector(
                          onTap: () {
                            if (isHapticFeedbackEnabledNotifier.value) {
                              HapticFeedback.mediumImpact();
                            }
                            final currentLikes = Set<String>.from(
                              likedSongsNotifier.value,
                            );
                            if (isLiked) {
                              currentLikes.removeWhere(
                                (id) => getBaseId(id) == itemBaseId,
                              );
                              updateArtistScore(item.artist ?? '', -10);
                            } else {
                              currentLikes.add(item.id);
                              updateArtistScore(item.artist ?? '', 10);
                            }
                            likedSongsNotifier.value = currentLikes;
                          },
                          child: Container(
                            color: Colors.transparent,
                            padding: const EdgeInsets.only(
                              left: 0.0,
                              right: 4.0,
                              top: 12.0,
                              bottom: 12.0,
                            ),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 300),
                              child: isLiked
                                  ? ShaderMask(
                                      key: const ValueKey('liked'),
                                      blendMode: BlendMode.srcIn,
                                      shaderCallback: (bounds) {
                                        return LinearGradient(
                                          colors: activeThemeColors,
                                          begin: Alignment.centerLeft,
                                          end: Alignment.centerRight,
                                          stops: getGradientStops(
                                            activeThemeColors.length,
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
                                      child: const Icon(
                                        CupertinoIcons.heart_fill,
                                        size: 24,
                                      ),
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
                    ),
                  if (onRemoveFromHistory != null)
                    GestureDetector(
                      onTap: onRemoveFromHistory,
                      child: Container(
                        color: Colors.transparent,
                        padding: const EdgeInsets.only(
                          left: 4.0,
                          right: 8.0,
                          top: 12.0,
                          bottom: 12.0,
                        ),
                        child: ShaderMask(
                          blendMode: BlendMode.srcIn,
                          shaderCallback: (bounds) {
                            return LinearGradient(
                              colors: activeThemeColors,
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ).createShader(bounds);
                          },
                          child: const Icon(
                            CupertinoIcons.clear,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
