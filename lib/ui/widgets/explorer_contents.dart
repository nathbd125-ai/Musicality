import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audio_service/audio_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:musicality/core/globals.dart';
import 'package:musicality/core/my_audio_handler.dart';
import 'package:musicality/ui/widgets/marquee_widget.dart';
import 'package:musicality/ui/widgets/song_tile.dart';

class ExplorerFavoritesContent extends StatelessWidget {
  final MediaItem? currentItem;
  final List<Color> dynamicGradientColors;

  const ExplorerFavoritesContent({
    super.key,
    required this.currentItem,
    required this.dynamicGradientColors,
  });

  @override
  Widget build(BuildContext context) {
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
                  isSelected: currentItem?.id == item.id,
                  activeThemeColors: dynamicGradientColors,
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
}

class ExplorerRecommendationsContent extends StatelessWidget {
  final String targetArtist;
  final bool isDiscover;
  final MediaItem? currentItem;
  final List<Color> dynamicGradientColors;

  const ExplorerRecommendationsContent({
    super.key,
    required this.targetArtist,
    required this.isDiscover,
    required this.currentItem,
    required this.dynamicGradientColors,
  });

  Future<void> _launchYouTube(String title, String artist) async {
    final query = Uri.encodeComponent("$title $artist audio");
    final url = Uri.parse(
      'https://www.youtube.com/results?search_query=$query',
    );
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      debugPrint("Impossible d'ouvrir YouTube");
    }
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
            if (isHapticFeedbackEnabledNotifier.value) {
              HapticFeedback.mediumImpact();
            }
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
                      shaderCallback: (bounds) => LinearGradient(
                        colors: dynamicGradientColors,
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        stops: getGradientStops(dynamicGradientColors.length),
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
                    currentItem?.id == reco['localId']) ||
                (currentItem?.title.toLowerCase() == title.toLowerCase() &&
                    currentItem?.artist?.toLowerCase() == artist.toLowerCase());

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
                    child: isLocal &&
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
                                colors: dynamicGradientColors,
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                                stops: getGradientStops(
                                  dynamicGradientColors.length,
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
                                  colors: dynamicGradientColors,
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                  stops: getGradientStops(
                                    dynamicGradientColors.length,
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
}
