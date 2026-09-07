import 'package:rxdart/rxdart.dart';
import 'package:musicality/core/models.dart';
import 'package:musicality/core/lyrics_parser.dart';
import 'package:musicality/ui/widgets/update_dialog.dart';
import 'package:musicality/core/api_config.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:just_audio/just_audio.dart';
import 'dart:ui';
import 'package:musicality/ui/widgets/marquee_widget.dart';
import 'package:musicality/ui/widgets/smooth_icon.dart';
import 'package:musicality/ui/widgets/hyper_os_button.dart';
import 'package:musicality/ui/widgets/hyper_os_repeat_button.dart';
import 'package:musicality/ui/widgets/hyper_os_shuffle_button.dart';
import 'package:musicality/ui/player/musicality_lyrics_view.dart';
import 'package:musicality/ui/player/agsl_rhombus_glass.dart';
import 'package:musicality/ui/pages/search_page_view.dart';
import 'package:musicality/ui/pages/account_page_view.dart';
import 'package:musicality/ui/pages/library_page_view.dart';
import 'package:musicality/ui/pages/all_musics_view.dart';
import 'package:musicality/ui/pages/artist_page_view.dart';
import 'package:musicality/ui/player/liquid_glass_container.dart';
import 'package:musicality/ui/widgets/real_album_blurred_background.dart';
import 'package:musicality/core/my_audio_handler.dart';
import 'package:musicality/ui/widgets/hyper_os_slider.dart';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:musicality/core/globals.dart';
import 'package:flutter/material.dart';
// fallback

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final GlobalKey _miniPlayerKey = GlobalKey();
  final GlobalKey _bottomBarKey = GlobalKey();

  int _currentIndex = 0;
  bool _isPlayerExpanded = false;
  bool _isAppInForeground = true;
  final Set<String> _downloadedSongs = {};
  final Set<String> _downloadingSongs = {};
  late final Stream<PositionData> _positionDataStream;

  late final PageController _mainPageController;
  final GlobalKey<SearchPageViewState> _searchKey =
      GlobalKey<SearchPageViewState>();
  final GlobalKey<LibraryPageViewState> _libraryKey =
      GlobalKey<LibraryPageViewState>();
  final GlobalKey<ArtistPageViewState> _artistKey =
      GlobalKey<ArtistPageViewState>();
  final GlobalKey<AllMusicsViewState> _musicsKey =
      GlobalKey<AllMusicsViewState>();

  List<LyricLine> _currentLyrics = [];
  bool _isLoadingLyrics = false;
  String? _lastSongId;

  List<Color> _dynamicGradientColors = [
    const Color(0xFF9C27B0),
    const Color(0xFF9C27B0),
    const Color(0xFF311B92),
    const Color(0xFF311B92),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _mainPageController = PageController(initialPage: _currentIndex);
    _scanLocalFiles();
    _checkForUpdates();

    _positionDataStream =
        Rx.combineLatest3<Duration, Duration, Duration?, PositionData>(
          Rx.merge([
            globalAudioHandler.playbackState.map((state) => state.position),
            Stream.periodic(
              const Duration(milliseconds: 100),
            ).where((_) => _isAppInForeground && globalAudioHandler.playbackState.value.playing)
             .where((_) => !isBatterySaverEnabledNotifier.value || (DateTime.now().millisecondsSinceEpoch % 500 < 100))
             .map((_) => globalAudioHandler.playbackState.value.position),
          ]),
          globalAudioHandler.playbackState.map(
            (state) => state.bufferedPosition,
          ),
          globalAudioHandler.mediaItem.map((item) => item?.duration),
          (position, bufferedPosition, duration) => PositionData(
            position,
            bufferedPosition,
            duration ?? Duration.zero,
          ),
        ).asBroadcastStream();

    globalAudioHandler.mediaItem.listen((item) {
      if (item != null && item.id != _lastSongId) {
        _lastSongId = item.id;
        _fetchLyrics(item);
        if (mounted) {
          setState(() {
            _dynamicGradientColors = getAlbumGradientColors(item);
          });
        }
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() {
      _isAppInForeground = (state == AppLifecycleState.resumed);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _mainPageController.dispose();
    super.dispose();
  }

  Future<void> _fetchLyrics(MediaItem item) async {
    final songId = item.id;
    final decodedName = Uri.decodeComponent(item.id.split('/').last);
    final baseName = decodedName.replaceAll(RegExp(r'-hires\.(flac|mp3)$'), '').replaceAll(RegExp(r'\.(flac|mp3)$'), '');

    if (_lyricsCache.containsKey(songId)) {
      setState(() {
        _currentLyrics = _lyricsCache[songId]!;
        _isLoadingLyrics = false;
      });
      return;
    }
    setState(() {
      _isLoadingLyrics = true;
      _currentLyrics = [];
    });

    try {
      final docDir = await getApplicationDocumentsDirectory();
      final localTtml = File('${docDir.path}/$baseName.ttml');
      final localLrc = File('${docDir.path}/$baseName.lrc');
      String lyricsContent = "";

      if (localTtml.existsSync()) {
        try {
          lyricsContent = await localTtml.readAsString();
        } catch (e) {
          localTtml.deleteSync();
        }
      } else if (localLrc.existsSync()) {
        try {
          lyricsContent = await localLrc.readAsString();
          // Purge de sécurité si un cache local contient les mauvaises paroles (ex: Afro Trap 11 avec les paroles de Part 7)
          if (baseName.contains('11') && lyricsContent.toLowerCase().contains('puissance')) {
            lyricsContent = "";
            localLrc.deleteSync();
          }
        } catch (e) {
          localLrc.deleteSync();
        }
      }

      if (lyricsContent.contains('<!DOCTYPE')) {
        lyricsContent = "";
      }

      final bool hasWordSync = lyricsContent.contains('<');

      if (lyricsContent.isEmpty || !hasWordSync) {
        // 1. Essai de téléchargement du fichier officiel Apple Music .ttml
        try {
          final ttmlUrl = Uri.parse('${ApiConfig.baseUrl}/${Uri.encodeComponent('$baseName.ttml')}');
          final ttmlRes = await http.get(ttmlUrl).timeout(const Duration(seconds: 3));
          if (ttmlRes.statusCode == 200 && ttmlRes.bodyBytes.isNotEmpty && !ttmlRes.body.contains('<!DOCTYPE')) {
            lyricsContent = utf8.decode(ttmlRes.bodyBytes);
            await localTtml.writeAsString(lyricsContent);
          }
        } catch (_) {}

        // 2. Si pas de .ttml, téléchargement du fichier .lrc
        if (lyricsContent.isEmpty || !lyricsContent.contains('<')) {
          try {
            final lrcUrl = Uri.parse('${ApiConfig.baseUrl}/${Uri.encodeComponent('$baseName.lrc')}');
            final response = await http.get(lrcUrl).timeout(const Duration(seconds: 5));
            if (response.statusCode == 200 && response.bodyBytes.isNotEmpty && !response.body.contains('<!DOCTYPE')) {
              String downloaded = "";
              try {
                downloaded = utf8.decode(response.bodyBytes);
              } catch (_) {
                downloaded = latin1
                    .decode(response.bodyBytes)
                    .replaceAll('\u009C', 'œ')
                    .replaceAll('\u008C', 'Œ')
                    .replaceAll('\u0092', '’');
              }
              if (downloaded.isNotEmpty) {
                lyricsContent = downloaded;
                await localLrc.writeAsString(lyricsContent);
              }
            }
          } catch (_) {}
        }
      }

      if (!mounted || _lastSongId != songId) return;
      if (lyricsContent.isNotEmpty) {
        _parseLRC(lyricsContent, songId);
        return;
      }
    } catch (e) {
      debugPrint("Erreur de récupération des paroles: $e");
    }

    if (mounted && _lastSongId == songId) {
      setState(() {
        _currentLyrics = [
          LyricLine(
            time: Duration.zero,
            text: "Paroles indisponibles pour ce titre",
          ),
        ];
        _isLoadingLyrics = false;
      });
    }
  }

  final Map<String, List<LyricLine>> _lyricsCache = {};

  void _parseLRC(String lrcContent, String songId) {
    if (!mounted || _lastSongId != songId) return;
    final parsedLines = LyricsParser.parse(lrcContent);
    if (mounted && _lastSongId == songId) {
      _lyricsCache[songId] = parsedLines;
      setState(() {
        _currentLyrics = parsedLines;
        _isLoadingLyrics = false;
      });
    }
  }

  Future<void> _checkForUpdates() async {
    try {
      final response = await http
          .get(
            Uri.parse(
              '${ApiConfig.baseUrl}/version.json?t=${DateTime.now().millisecondsSinceEpoch}',
            ),
          )
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        String decodedBody;
        try {
          decodedBody = utf8.decode(response.bodyBytes);
        } catch (e) {
          decodedBody = latin1.decode(response.bodyBytes);
        }
        Map<String, dynamic>? data;
        try {
          data = jsonDecode(decodedBody) as Map<String, dynamic>;
        } catch (_) {
          // Fallback avec regex si le JSON contient des guillemets non échappés dans releaseNotes
          final versionMatch = RegExp(r'"version"\s*:\s*"([^"]+)"').firstMatch(decodedBody);
          final buildMatch = RegExp(r'"buildNumber"\s*:\s*(\d+)').firstMatch(decodedBody);
          final downloadMatch = RegExp(r'"downloadUrl"\s*:\s*"([^"]+)"').firstMatch(decodedBody);
          final notesMatch = RegExp(r'"releaseNotes"\s*:\s*"(.*)"\s*\}', dotAll: true).firstMatch(decodedBody);

          if (versionMatch != null && buildMatch != null) {
            data = {
              'version': versionMatch.group(1),
              'buildNumber': int.tryParse(buildMatch.group(1)!) ?? 0,
              'downloadUrl': downloadMatch?.group(1),
              'releaseNotes': notesMatch?.group(1),
            };
          }
        }

        if (data == null) return;

        final serverVersion = (data['version'] as String?) ?? 'Nouvelle version';
        final serverBuild = (data['buildNumber'] as int?) ?? 0;

        final packageInfo = await PackageInfo.fromPlatform();
        final localBuild = int.tryParse(packageInfo.buildNumber) ?? 0;

        if (serverBuild > localBuild) {
          if (mounted) {
            String downloadUrl = (data['downloadUrl'] as String?) ??
                '${ApiConfig.baseUrl}/app-release.apk';
            // S'assurer que le téléchargement passe en HTTPS
            if (downloadUrl.startsWith('http://164.132.104.67')) {
              downloadUrl = downloadUrl.replaceFirst(
                'http://164.132.104.67',
                'https://musicality.duckdns.org',
              );
            }

            _showUpdateDialog(
              serverVersion: serverVersion,
              releaseNotes:
                  data['releaseNotes'] ?? 'Nouvelle version disponible !',
              downloadUrl: downloadUrl,
            );
          }
        }
      }
    } catch (e) {
      debugPrint("Impossible de vérifier les mises à jour : $e");
    }
  }

  void _showUpdateDialog({
    required String serverVersion,
    required String releaseNotes,
    required String downloadUrl,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return UpdateDialog(
          serverVersion: serverVersion,
          releaseNotes: releaseNotes,
          downloadUrl: downloadUrl,
        );
      },
    );
  }

  Future<void> _scanLocalFiles() async {
    final docDir = await getApplicationDocumentsDirectory();
    final Set<String> localIds = {};
    for (var item in globalPlaylist) {
      final safeName = item.id.split('/').last.replaceAll('.flac', '');
      final hiResFile = File('${docDir.path}/$safeName-hires.flac');
      final flacFile = File('${docDir.path}/$safeName.flac');
      final mp3File = File('${docDir.path}/$safeName.mp3');

      if (hiResFile.existsSync() ||
          flacFile.existsSync() ||
          mp3File.existsSync()) {
        localIds.add(item.id);
      }
    }
    setState(() {
      _downloadedSongs.addAll(localIds);
    });
  }

  Future<void> _toggleDownload(MediaItem item) async {
    final docDir = await getApplicationDocumentsDirectory();
    final safeName = item.id.split('/').last.replaceAll('.flac', '');

    final localHiRes = File('${docDir.path}/$safeName-hires.flac');
    final localFlac = File('${docDir.path}/$safeName.flac');
    final localMp3 = File('${docDir.path}/$safeName.mp3');

    final cacheHiRes = File('${docDir.path}/cache/$safeName-hires.flac');
    final cacheFlac = File('${docDir.path}/cache/$safeName.flac');
    final cacheMp3 = File('${docDir.path}/cache/$safeName.mp3');

    bool wantHiRes = isDownloadHiResNotifier.value;
    bool wantFlac = isDownloadLosslessNotifier.value;
    bool hasFlac = item.extras?['hasFlac'] as bool? ?? true;
    bool hasHiRes = item.extras?['hasHiRes'] as bool? ?? false;

    bool targetHiRes = false;
    bool targetFlac = false;

    if (wantHiRes && hasHiRes) {
      targetHiRes = true;
    } else if ((wantHiRes || wantFlac) && hasFlac) {
      targetFlac = true;
    }

    bool hasLocalHiRes = localHiRes.existsSync();
    bool hasLocalFlac = localFlac.existsSync();
    bool hasLocalMp3 = localMp3.existsSync();

    int targetQuality = targetHiRes ? 3 : (targetFlac ? 2 : 1);
    int currentQuality = hasLocalHiRes ? 3 : (hasLocalFlac ? 2 : (hasLocalMp3 ? 1 : 0));

    bool needsUpgrade = (currentQuality > 0) && (targetQuality > currentQuality);

    bool downloadHiRes = targetHiRes;
    bool downloadFlac = targetFlac;

    if (_downloadedSongs.contains(item.id) && !needsUpgrade) {
      if (localHiRes.existsSync()) localHiRes.deleteSync();
      if (localFlac.existsSync()) localFlac.deleteSync();
      if (localMp3.existsSync()) localMp3.deleteSync();

      setState(() {
        _downloadedSongs.remove(item.id);
      });

      if (globalAudioHandler is MyAudioHandler) {
        (globalAudioHandler as MyAudioHandler).updateSourceForId(item.id);
      }
    } else {
      if (_downloadingSongs.contains(item.id)) return;
      
      if (needsUpgrade) {
        if (localHiRes.existsSync()) localHiRes.deleteSync();
        if (localFlac.existsSync()) localFlac.deleteSync();
        if (localMp3.existsSync()) localMp3.deleteSync();
        setState(() {
          _downloadedSongs.remove(item.id);
        });
      }

      setState(() {
        _downloadingSongs.add(item.id);
      });

      try {
        String downloadUrl;
        File fileToSave;
        File candidateCache;

        if (downloadHiRes) {
          downloadUrl = item.id.replaceAll('.flac', '-hires.flac');
          fileToSave = localHiRes;
          candidateCache = cacheHiRes;
          // Si téléchargement en Hi-Res, suppression automatique des caches de qualité inférieure
          if (cacheFlac.existsSync()) {
            try {
              cacheFlac.deleteSync();
            } catch (_) {}
          }
          if (cacheMp3.existsSync()) {
            try {
              cacheMp3.deleteSync();
            } catch (_) {}
          }
        } else if (downloadFlac) {
          downloadUrl = item.id;
          fileToSave = localFlac;
          if (cacheHiRes.existsSync()) {
            candidateCache = cacheHiRes;
            fileToSave = localHiRes;
          } else {
            candidateCache = cacheFlac;
          }
          // Si téléchargement en FLAC, suppression automatique du cache MP3 inférieur
          if (cacheMp3.existsSync()) {
            try {
              cacheMp3.deleteSync();
            } catch (_) {}
          }
        } else {
          downloadUrl = item.id.replaceAll('.flac', '.mp3');
          fileToSave = localMp3;
          candidateCache = cacheMp3;
        }

        bool extractedFromCache = false;

        // Extraction intelligente depuis le cache sans réseau si le fichier est complet
        if (candidateCache.existsSync()) {
          try {
            final client = HttpClient()
              ..connectionTimeout = const Duration(seconds: 3);
            final headReq = await client.headUrl(Uri.parse(downloadUrl.replaceAll('#', '%23')));
            final headRes = await headReq.close();
            final expectedLength = headRes.contentLength;

            if (expectedLength > 0 &&
                candidateCache.lengthSync() >= expectedLength) {
              await candidateCache.copy(fileToSave.path);
              try {
                candidateCache.deleteSync();
              } catch (_) {}
              extractedFromCache = true;
            }
          } catch (_) {
            if (candidateCache.lengthSync() > 3 * 1024 * 1024) {
              await candidateCache.copy(fileToSave.path);
              try {
                candidateCache.deleteSync();
              } catch (_) {}
              extractedFromCache = true;
            }
          }
        }

        // Si non extrait du cache (fichier absent ou partiel), téléchargement réseau
        if (!extractedFromCache) {
          if (candidateCache.existsSync()) {
            try {
              candidateCache.deleteSync();
            } catch (_) {}
          }

          final client = HttpClient();
          final request = await client.getUrl(Uri.parse(downloadUrl.replaceAll('#', '%23')));
          final response = await request.close();
          await response.pipe(fileToSave.openWrite());
        }

        if (fileToSave == localHiRes) {
          if (localFlac.existsSync()) localFlac.deleteSync();
          if (localMp3.existsSync()) localMp3.deleteSync();
        } else if (fileToSave == localFlac) {
          if (localHiRes.existsSync()) localHiRes.deleteSync();
          if (localMp3.existsSync()) localMp3.deleteSync();
        } else {
          if (localHiRes.existsSync()) localHiRes.deleteSync();
          if (localFlac.existsSync()) localFlac.deleteSync();
        }

        setState(() {
          _downloadingSongs.remove(item.id);
          _downloadedSongs.add(item.id);
        });

        if (globalAudioHandler is MyAudioHandler) {
          (globalAudioHandler as MyAudioHandler).updateSourceForId(item.id);
        }
      } catch (e) {
        debugPrint("Erreur téléchargement: $e");
        setState(() {
          _downloadingSongs.remove(item.id);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final double topPadding = MediaQuery.of(context).viewPadding.top;
    final double bottomPadding = MediaQuery.of(context).viewPadding.bottom;
    final double extraBottom = bottomPadding > 35 ? bottomPadding : 0;
    final double screenHeight = MediaQuery.of(context).size.height;

    final double navBarHeight = 66.0 + bottomPadding;

    const Duration transitionDuration = Duration(milliseconds: 410);
    const Curve transitionCurve = Curves.fastOutSlowIn;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;

        if (_isPlayerExpanded) {
          setState(() {
            _isPlayerExpanded = false;
          });
          return;
        }

        if (_currentIndex == 0) {
          final searchState = _searchKey.currentState;
          if (searchState != null && searchState.isSearching) {
            searchState.clearSearch();
            return;
          }
        }

        if (_currentIndex == 1) {
          final artistState = _artistKey.currentState;
          if (artistState != null && artistState.isSearching) {
            artistState.clearSearch();
            return;
          }
        }

        if (_currentIndex == 2) {
          final musicsState = _musicsKey.currentState;
          if (musicsState != null && musicsState.isSearching) {
            musicsState.clearSearch();
            return;
          }
        }

        if (_currentIndex == 3) {
          final libState = _libraryKey.currentState;
          if (libState != null && !libState.isOnMainPage) {
            libState.goBack();
            return;
          }
        }
        SystemNavigator.pop();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: Colors.black,
        body: StreamBuilder<MediaItem?>(
          stream: globalAudioHandler.mediaItem,
          builder: (context, mainSnapshot) {
            final currentItem = mainSnapshot.data;
            final hasMusic = currentItem != null;

            final safeItem =
                currentItem ??
                (globalPlaylist.isNotEmpty
                    ? globalPlaylist.first
                    : MediaItem(
                        id: 'dummy',
                        title: 'Aucune musique',
                        artist: 'Inconnu',
                      ));

            return TweenAnimationBuilder<Color?>(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOut,
              tween: ColorTween(
                end: _dynamicGradientColors.isNotEmpty
                    ? _dynamicGradientColors[0]
                    : Colors.black,
              ),
              builder: (context, color1, _) {
                return TweenAnimationBuilder<Color?>(
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOut,
                  tween: ColorTween(
                    end: _dynamicGradientColors.length > 1
                        ? _dynamicGradientColors[1]
                        : (_dynamicGradientColors.isNotEmpty
                            ? _dynamicGradientColors[0]
                            : Colors.black),
                  ),
                  builder: (context, color2, _) {
                    return TweenAnimationBuilder<Color?>(
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeOut,
                      tween: ColorTween(
                        end: _dynamicGradientColors.length > 2
                            ? _dynamicGradientColors[2]
                            : (_dynamicGradientColors.length > 1
                                ? _dynamicGradientColors[1]
                                : (_dynamicGradientColors.isNotEmpty
                                    ? _dynamicGradientColors[0]
                                    : Colors.black)),
                      ),
                      builder: (context, color3, _) {
                        return TweenAnimationBuilder<Color?>(
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeOut,
                          tween: ColorTween(
                            end: _dynamicGradientColors.length > 3
                                ? _dynamicGradientColors[3]
                                : (_dynamicGradientColors.isNotEmpty
                                    ? _dynamicGradientColors.last
                                    : Colors.black),
                          ),
                          builder: (context, color4, _) {
                            final List<Color> smoothThemeColors =
                                _dynamicGradientColors.length > 4
                                    ? _dynamicGradientColors
                                    : [
                                        color1 ??
                                            (_dynamicGradientColors.isNotEmpty
                                                ? _dynamicGradientColors[0]
                                                : Colors.black),
                                        color2 ??
                                            (_dynamicGradientColors.length > 1
                                                ? _dynamicGradientColors[1]
                                                : (_dynamicGradientColors
                                                        .isNotEmpty
                                                    ? _dynamicGradientColors[0]
                                                    : Colors.black)),
                                        color3 ??
                                            (_dynamicGradientColors.length > 2
                                                ? _dynamicGradientColors[2]
                                                : (_dynamicGradientColors
                                                        .isNotEmpty
                                                    ? _dynamicGradientColors
                                                        .last
                                                    : Colors.black)),
                                        color4 ??
                                            (_dynamicGradientColors.length > 3
                                                ? _dynamicGradientColors[3]
                                                : (_dynamicGradientColors
                                                        .isNotEmpty
                                                    ? _dynamicGradientColors
                                                        .last
                                                    : Colors.black)),
                                      ];

                            return ValueListenableBuilder<bool>(
                              valueListenable: isLiquidGlassEnabledNotifier,
                              builder: (context, isLiquidGlass, _) {
                                return TweenAnimationBuilder<double>(
                                  duration: transitionDuration,
                                  curve: transitionCurve,
                                  tween: Tween<double>(
                                    end: _isPlayerExpanded ? 0.0 : 32.0,
                                  ),
                                  builder: (context, currentRadius, _) {
                                    return Stack(
                                      children: [
                                        Stack(
                                          children: [
                                            Positioned.fill(
                                              child: AnimatedSwitcher(
                                                duration: const Duration(
                                                  milliseconds: 600,
                                                ),
                                                child: hasMusic
                                                    ? RealAlbumBlurredBackground(
                                                        key: ValueKey<String>(
                                                          safeItem.id,
                                                        ),
                                                        item: safeItem,
                                                      )
                                                    : Container(
                                                        color: Colors.black,
                                                      ),
                                              ),
                                            ),
                                            AnimatedOpacity(
                                              opacity: _isPlayerExpanded
                                                  ? 0.0
                                                  : 1.0,
                                              duration: const Duration(
                                                milliseconds: 300,
                                              ),
                                              child: IgnorePointer(
                                                ignoring: _isPlayerExpanded,
                                                child: Scaffold(
                                                  backgroundColor:
                                                      Colors.transparent,
                                                  extendBody: true,
                                                  resizeToAvoidBottomInset:
                                                      false,
                                                  body: PageView(
                                                    controller:
                                                        _mainPageController,
                                                    physics:
                                                        const NeverScrollableScrollPhysics(),
                                                    children: [
                                                      SearchPageView(
                                                        key: _searchKey,
                                                        currentItem:
                                                            currentItem,
                                                        dynamicGradientColors:
                                                            smoothThemeColors,
                                                      ),
                                                      ArtistPageView(
                                                        key: _artistKey,
                                                        dynamicThemeColors:
                                                            smoothThemeColors,
                                                        currentItem:
                                                            currentItem,
                                                      ),
                                                      AllMusicsView(
                                                        key: _musicsKey,
                                                        currentItem:
                                                            currentItem,
                                                        dynamicGradientColors:
                                                            smoothThemeColors,
                                                      ),
                                                      LibraryPageView(
                                                        key: _libraryKey,
                                                        currentItem:
                                                            currentItem,
                                                        dynamicGradientColors:
                                                            smoothThemeColors,
                                                      ),
                                                      AccountPageView(
                                                        dynamicGradientColors:
                                                            smoothThemeColors,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),

                                        // --- FOND UNIFIÉ POUR MINI LECTEUR ET BARRE DE NAVIGATION ---
                                        ListenableBuilder(
                                          listenable: Listenable.merge([
                                            isLiquidGlassEnabledNotifier,
                                            isBatterySaverEnabledNotifier,
                                          ]),
                                          builder: (context, _) {
                                            final isLiquidGlass =
                                                isLiquidGlassEnabledNotifier.value;
                                            final isBatterySaver =
                                                isBatterySaverEnabledNotifier.value;
                                            return AnimatedPositioned(
                                              duration: transitionDuration,
                                              curve: transitionCurve,
                                              bottom: _isPlayerExpanded
                                                  ? 0
                                                  : (isLiquidGlass
                                                        ? 12 + bottomPadding
                                                        : 0),
                                              left: _isPlayerExpanded
                                                  ? 0
                                                  : (isLiquidGlass ? 12 : 0),
                                              right: _isPlayerExpanded
                                                  ? 0
                                                  : (isLiquidGlass ? 12 : 0),
                                              height: _isPlayerExpanded
                                                  ? screenHeight
                                                  : (hasMusic
                                                        ? (isLiquidGlass
                                                              ? 184.0
                                                              : navBarHeight +
                                                                    116)
                                                        : navBarHeight),
                                              child: AnimatedOpacity(
                                                duration: transitionDuration,
                                                curve: transitionCurve,
                                                opacity: isLiquidGlass
                                                    ? 0.0
                                                    : 1.0,
                                                child: AnimatedContainer(
                                                  duration: transitionDuration,
                                                  curve: transitionCurve,
                                                  clipBehavior: Clip.antiAlias,
                                                  decoration: BoxDecoration(
                                                    borderRadius:
                                                        _isPlayerExpanded
                                                        ? BorderRadius.zero
                                                        : (isLiquidGlass
                                                              ? BorderRadius.circular(
                                                                  32,
                                                                )
                                                              : const BorderRadius.only(
                                                                  topLeft:
                                                                      Radius.circular(
                                                                        24,
                                                                      ),
                                                                  topRight:
                                                                      Radius.circular(
                                                                        24,
                                                                      ),
                                                                )),
                                                  ),
                                                  child: TweenAnimationBuilder<double>(
                                                    tween: Tween<double>(
                                                      end: (isLiquidGlass || isBatterySaver)
                                                          ? 0.001
                                                          : 20.0,
                                                    ),
                                                    duration: const Duration(milliseconds: 600),
                                                    curve: Curves.easeInOutCubic,
                                                    builder: (context, currentSigma, child) {
                                                      return BackdropFilter(
                                                        filter: ImageFilter.blur(
                                                          sigmaX: currentSigma,
                                                          sigmaY: currentSigma,
                                                        ),
                                                        child: child,
                                                      );
                                                    },
                                                    child: AnimatedContainer(
                                                      duration: transitionDuration,
                                                      curve: transitionCurve,
                                                      color: isBatterySaver
                                                          ? (_isPlayerExpanded
                                                              ? Colors.black
                                                                    .withValues(
                                                                      alpha: 0.1,
                                                                    )
                                                              : Colors.black
                                                                    .withValues(
                                                                      alpha: 0.75,
                                                                    ))
                                                          : (_isPlayerExpanded
                                                              ? Colors.black
                                                                    .withValues(
                                                                      alpha: 0.1,
                                                                    )
                                                              : Colors.black
                                                                    .withValues(
                                                                      alpha: 0.55,
                                                                    )),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            );
                                          },
                                        ),

                                        StreamBuilder<PlaybackState>(
                                          stream:
                                              globalAudioHandler.playbackState,
                                          builder: (context, playSnapshot) {
                                            final playbackState =
                                                playSnapshot.data;
                                            final playing =
                                                playbackState?.playing ?? false;

                                            final isDownloaded =
                                                _downloadedSongs.contains(
                                                  safeItem.id,
                                                );
                                            final isDownloading =
                                                _downloadingSongs.contains(
                                                  safeItem.id,
                                                );

                                            return ListenableBuilder(
                                              listenable: Listenable.merge([
                                                isLiquidGlassEnabledNotifier,
                                                isDownloadHiResNotifier,
                                                isDownloadLosslessNotifier,
                                              ]),
                                              builder: (context, _) {
                                                bool isLiquidGlass = isLiquidGlassEnabledNotifier.value;
                                                bool needsUpgrade = false;
                                                if (isDownloaded) {
                                                  final safeNameForUp = safeItem.id.split('/').last.replaceAll('.flac', '');
                                                  final File localHiResUp = File('$globalDocumentPath/$safeNameForUp-hires.flac');
                                                  final File localFlacUp = File('$globalDocumentPath/$safeNameForUp.flac');
                                                  final File localMp3Up = File('$globalDocumentPath/$safeNameForUp.mp3');
                                                  
                                                  bool wantHiResUp = isDownloadHiResNotifier.value;
                                                  bool wantFlacUp = isDownloadLosslessNotifier.value;
                                                  bool itemHasHiRes = safeItem.extras?['hasHiRes'] as bool? ?? false;
                                                  bool itemHasFlac = safeItem.extras?['hasFlac'] as bool? ?? true;
                                                  
                                                  bool targetHiRes = false;
                                                  bool targetFlac = false;
                                                  
                                                  if (wantHiResUp && itemHasHiRes) {
                                                    targetHiRes = true;
                                                  } else if ((wantHiResUp || wantFlacUp) && itemHasFlac) {
                                                    targetFlac = true;
                                                  }
                                                  
                                                  bool hasLocalHiRes = localHiResUp.existsSync();
                                                  bool hasLocalFlac = localFlacUp.existsSync();
                                                  bool hasLocalMp3 = localMp3Up.existsSync();
                                                  
                                                  int targetQuality = targetHiRes ? 3 : (targetFlac ? 2 : 1);
                                                  int currentQuality = hasLocalHiRes ? 3 : (hasLocalFlac ? 2 : (hasLocalMp3 ? 1 : 0));
                                                  
                                                  needsUpgrade = (currentQuality > 0) && (targetQuality > currentQuality);
                                                }
                                                return AnimatedPositioned(
                                                  key: _miniPlayerKey,
                                                  duration: transitionDuration,
                                                  curve: transitionCurve,
                                                  left: _isPlayerExpanded
                                                      ? 0
                                                      : (isLiquidGlass
                                                            ? 12
                                                            : 0),
                                                  right: _isPlayerExpanded
                                                      ? 0
                                                      : (isLiquidGlass
                                                            ? 12
                                                            : 0),
                                                  bottom: _isPlayerExpanded
                                                      ? 0
                                                      : (isLiquidGlass
                                                            ? (12 +
                                                                  56.0 +
                                                                  12 +
                                                                  bottomPadding)
                                                            : 0),
                                                  height: _isPlayerExpanded
                                                      ? screenHeight
                                                      : (hasMusic
                                                            ? (isLiquidGlass
                                                                  ? 116.0
                                                                  : navBarHeight +
                                                                        116)
                                                            : 0),
                                                  child: Material(
                                                    type: MaterialType
                                                        .transparency,
                                                    child: GestureDetector(
                                                      onTap: () {
                                                        if (hasMusic &&
                                                            !_isPlayerExpanded) {
                                                          FocusScope.of(
                                                            context,
                                                          ).unfocus();
                                                          setState(() {
                                                            _isPlayerExpanded =
                                                                true;
                                                          });
                                                        }
                                                      },
                                                      onVerticalDragEnd: (details) {
                                                        if (_isPlayerExpanded &&
                                                            details.primaryVelocity !=
                                                                null &&
                                                            details.primaryVelocity! >
                                                                300) {
                                                          setState(() {
                                                            _isPlayerExpanded =
                                                                false;
                                                          });
                                                        }
                                                      },
                                                      child: AnimatedContainer(
                                                        duration:
                                                            transitionDuration,
                                                        curve: transitionCurve,
                                                        clipBehavior:
                                                            isLiquidGlass
                                                                ? Clip.antiAlias
                                                                : Clip.none,
                                                        decoration: BoxDecoration(
                                                          borderRadius:
                                                              _isPlayerExpanded
                                                              ? BorderRadius
                                                                    .zero
                                                              : (isLiquidGlass
                                                                    ? BorderRadius.circular(
                                                                        32,
                                                                      )
                                                                    : const BorderRadius.only(
                                                                        topLeft:
                                                                            Radius.circular(
                                                                              24,
                                                                            ),
                                                                        topRight:
                                                                            Radius.circular(
                                                                              24,
                                                                            ),
                                                                      )),
                                                          border: null,
                                                        ),
                                                        child: Builder(
                                                          builder: (context) {
                                                            Widget
                                                            contentStack = Stack(
                                                              clipBehavior:
                                                                  Clip.none,
                                                              children: [
                                                                if (hasMusic)
                                                                  Stack(
                                                                    clipBehavior:
                                                                        Clip.none,
                                                                    children: [
                                                                      AnimatedPositioned(
                                                                        duration:
                                                                            transitionDuration,
                                                                        curve:
                                                                            transitionCurve,
                                                                        top:
                                                                            _isPlayerExpanded
                                                                            ? topPadding +
                                                                                  10
                                                                            : -60,
                                                                        left:
                                                                            20,
                                                                        right:
                                                                            20,
                                                                        child: AnimatedOpacity(
                                                                          duration: const Duration(
                                                                            milliseconds:
                                                                                200,
                                                                          ),
                                                                          opacity:
                                                                              _isPlayerExpanded
                                                                              ? 1.0
                                                                              : 0.0,
                                                                          child: Row(
                                                                            mainAxisAlignment:
                                                                                MainAxisAlignment.spaceBetween,
                                                                            children: [
                                                                              IconButton(
                                                                                icon: const Icon(
                                                                                  Icons.keyboard_arrow_down,
                                                                                  color: Colors.white,
                                                                                  size: 30,
                                                                                ),
                                                                                onPressed: () {
                                                                                  FocusScope.of(
                                                                                    context,
                                                                                  ).unfocus();
                                                                                  setState(
                                                                                    () {
                                                                                      _isPlayerExpanded = false;
                                                                                    },
                                                                                  );
                                                                                },
                                                                              ),
                                                                              IconButton(
                                                                                icon: Icon(
                                                                                  isDownloading
                                                                                      ? Icons.downloading
                                                                                      : (needsUpgrade
                                                                                          ? Icons.cloud_upload
                                                                                          : (isDownloaded
                                                                                              ? Icons.cloud_done
                                                                                              : Icons.cloud_download)),
                                                                                  size: 26,
                                                                                ),
                                                                                color: (isDownloaded || needsUpgrade)
                                                                                    ? Colors.white
                                                                                    : Colors.white70,
                                                                                onPressed: () {
                                                                                  _toggleDownload(
                                                                                    safeItem,
                                                                                  );
                                                                                },
                                                                              ),
                                                                            ],
                                                                          ),
                                                                        ),
                                                                      ),

                                                                      AnimatedPositioned(
                                                                        duration:
                                                                            transitionDuration,
                                                                        curve:
                                                                            transitionCurve,
                                                                        top:
                                                                            _isPlayerExpanded
                                                                            ? topPadding +
                                                                                  65
                                                                            : 12,
                                                                        left:
                                                                            20,
                                                                        width:
                                                                            _isPlayerExpanded
                                                                            ? 60
                                                                            : 54,
                                                                        height:
                                                                            _isPlayerExpanded
                                                                            ? 60
                                                                            : 54,
                                                                        child: AnimatedContainer(
                                                                          duration:
                                                                              transitionDuration,
                                                                          curve:
                                                                              transitionCurve,
                                                                          clipBehavior:
                                                                              Clip.antiAlias,
                                                                          decoration: BoxDecoration(
                                                                            borderRadius: BorderRadius.circular(
                                                                              _isPlayerExpanded
                                                                                  ? 12.0
                                                                                  : 8.0,
                                                                            ),
                                                                          ),
                                                                          child: SizedBox.expand(
                                                                            child: getLocalOrNetworkImage(
                                                                              safeItem,
                                                                            ),
                                                                          ),
                                                                        ),
                                                                      ),

                                                                      AnimatedPositioned(
                                                                        duration:
                                                                            transitionDuration,
                                                                        curve:
                                                                            transitionCurve,
                                                                        top:
                                                                            _isPlayerExpanded
                                                                            ? topPadding +
                                                                                  68
                                                                            : 11,
                                                                        left:
                                                                            _isPlayerExpanded
                                                                            ? 95
                                                                            : 88,
                                                                        right:
                                                                            _isPlayerExpanded
                                                                            ? 20
                                                                            : 12, // Aligné avec le bord droit du bouton Répéter
                                                                        child: Column(
                                                                          crossAxisAlignment:
                                                                              CrossAxisAlignment.start,
                                                                          children: [
                                                                            MarqueeWidget(
                                                                              resetKey: 'title_${safeItem.id}',
                                                                              child: Row(
                                                                                mainAxisSize: MainAxisSize.min,
                                                                                crossAxisAlignment: CrossAxisAlignment.center,
                                                                                children: [
                                                                                  // 1. LE TITRE DE LA MUSIQUE (De retour avec son magnifique gradient !)
                                                                                  ShaderMask(
                                                                                    blendMode: BlendMode.srcIn,
                                                                                    shaderCallback:
                                                                                        (
                                                                                          bounds,
                                                                                        ) {
                                                                                          return LinearGradient(
                                                                                            colors: smoothThemeColors,
                                                                                            begin: Alignment.centerLeft,
                                                                                            end: Alignment.centerRight,
                                                                                          ).createShader(
                                                                                            Rect.fromLTWH(
                                                                                              0,
                                                                                              0,
                                                                                              bounds.width,
                                                                                              bounds.height,
                                                                                            ),
                                                                                          ); // Le Rect.fromLTWH évite le bug d'affichage lors du scroll !
                                                                                        },
                                                                                    child: AnimatedDefaultTextStyle(
                                                                                      duration: transitionDuration,
                                                                                      curve: transitionCurve,
                                                                                      style: TextStyle(
                                                                                        fontWeight: FontWeight.bold,
                                                                                        fontSize: _isPlayerExpanded
                                                                                            ? 20
                                                                                            : 16,
                                                                                        color: Colors.white,
                                                                                      ),
                                                                                      child: Text(
                                                                                        safeItem.title,
                                                                                        maxLines: 1,
                                                                                        softWrap: false,
                                                                                        overflow: TextOverflow.visible,
                                                                                      ),
                                                                                    ),
                                                                                  ),

                                                                                  // 2. LE BADGE LOSSLESS ALIGNÉ AVEC LE TITRE
                                                                                  if (safeItem.extras?['isFlac'] ==
                                                                                      true) ...[
                                                                                    const SizedBox(
                                                                                      width: 6,
                                                                                    ),
                                                                                    Transform.translate(
                                                                                      offset: const Offset(
                                                                                        0,
                                                                                        1.5,
                                                                                      ),
                                                                                      child: ShaderMask(
                                                                                        blendMode: BlendMode.srcIn,
                                                                                        shaderCallback:
                                                                                            (
                                                                                              bounds,
                                                                                            ) {
                                                                                              return LinearGradient(
                                                                                                colors: smoothThemeColors,
                                                                                                begin: Alignment.centerLeft,
                                                                                                end: Alignment.centerRight,
                                                                                              ).createShader(
                                                                                                bounds,
                                                                                              );
                                                                                            },
                                                                                        child: AnimatedDefaultTextStyle(
                                                                                          duration: transitionDuration,
                                                                                          curve: transitionCurve,
                                                                                          style: TextStyle(
                                                                                            fontSize: _isPlayerExpanded
                                                                                                ? 13
                                                                                                : 10,
                                                                                            fontWeight: FontWeight.w900,
                                                                                            letterSpacing: 0.5,
                                                                                            color: Colors.white,
                                                                                          ),
                                                                                          child: Text(
                                                                                            safeItem.extras?['isHiRes'] == true
                                                                                                ? "• HI-RES"
                                                                                                : "• LOSSLESS",
                                                                                          ),
                                                                                        ),
                                                                                      ),
                                                                                    ),
                                                                                  ],
                                                                                ],
                                                                              ),
                                                                            ),
                                                                            const SizedBox(
                                                                              height: 5,
                                                                            ),

                                                                            // 3. L'ARTISTE (Arrêt exact avant le bouton précédent : 12 + 144 = 156)
                                                                            AnimatedPadding(
                                                                              duration: transitionDuration,
                                                                              curve: transitionCurve,
                                                                              padding: EdgeInsets.only(
                                                                                right: _isPlayerExpanded
                                                                                    ? 0
                                                                                    : 144,
                                                                              ),
                                                                              child: MarqueeWidget(
                                                                                resetKey: 'artist_${safeItem.id}',
                                                                                threshold: 0.0,
                                                                                child:
                                                                                    TweenAnimationBuilder<
                                                                                      double
                                                                                    >(
                                                                                      duration: transitionDuration,
                                                                                      curve: transitionCurve,
                                                                                      tween:
                                                                                          Tween<
                                                                                            double
                                                                                          >(
                                                                                            end: _isPlayerExpanded
                                                                                                ? 15.0
                                                                                                : 13.0,
                                                                                          ),
                                                                                      builder:
                                                                                          (
                                                                                            context,
                                                                                            fontSize,
                                                                                            child,
                                                                                          ) {
                                                                                            return Text(
                                                                                              formatArtist(
                                                                                                safeItem.artist,
                                                                                              ),
                                                                                              maxLines: 1,
                                                                                              softWrap: false,
                                                                                              overflow: TextOverflow.visible,
                                                                                              style: TextStyle(
                                                                                                color: Color.lerp(
                                                                                                  const Color(
                                                                                                    0xFFCCCCCC,
                                                                                                  ),
                                                                                                  smoothThemeColors[0],
                                                                                                  0.35,
                                                                                                ),
                                                                                                fontSize: fontSize,
                                                                                                height: 1.0,
                                                                                                fontWeight: FontWeight.w500,
                                                                                              ),
                                                                                            );
                                                                                          },
                                                                                    ),
                                                                              ),
                                                                            ),
                                                                          ],
                                                                        ),
                                                                      ),

                                                                      AnimatedPositioned(
                                                                        duration:
                                                                            transitionDuration,
                                                                        curve:
                                                                            transitionCurve,
                                                                        top:
                                                                            _isPlayerExpanded
                                                                            ? topPadding +
                                                                                  155
                                                                            : screenHeight,
                                                                        height: (screenHeight -
                                                                                (topPadding +
                                                                                    155) -
                                                                                (160 +
                                                                                    extraBottom))
                                                                            .clamp(
                                                                              0.0,
                                                                              double.infinity,
                                                                            ),
                                                                        left: 0,
                                                                        right:
                                                                            0,
                                                                        child: AnimatedOpacity(
                                                                          duration: const Duration(
                                                                            milliseconds:
                                                                                300,
                                                                          ),
                                                                          opacity:
                                                                              _isPlayerExpanded
                                                                              ? 1.0
                                                                              : 0.0,
                                                                          child: IgnorePointer(
                                                                            ignoring: !_isPlayerExpanded,
                                                                            child: _isLoadingLyrics
                                                                                ? const Center(
                                                                                    child: CircularProgressIndicator(
                                                                                      color: Colors.white,
                                                                                    ),
                                                                                  )
                                                                                : MusicalityLyricsView(
                                                                                    lyrics: _currentLyrics,
                                                                                    positionStream: _positionDataStream,
                                                                                    themeColors: smoothThemeColors,
                                                                                    isExpanded: _isPlayerExpanded,
                                                                                  ),
                                                                          ),
                                                                        ),
                                                                      ),

                                                                      AnimatedPositioned(
                                                                        duration:
                                                                            transitionDuration,
                                                                        curve:
                                                                            transitionCurve,
                                                                        left:
                                                                            _isPlayerExpanded
                                                                            ? 20
                                                                            : -50,
                                                                        bottom:
                                                                            _isPlayerExpanded
                                                                            ? 95 +
                                                                                  extraBottom
                                                                            : (isLiquidGlass
                                                                                  ? 48
                                                                                  : navBarHeight +
                                                                                        48),
                                                                        width:
                                                                            _isPlayerExpanded
                                                                            ? 40
                                                                            : 30,
                                                                        height:
                                                                            _isPlayerExpanded
                                                                            ? 40
                                                                            : 30,
                                                                        child: AnimatedOpacity(
                                                                          duration: const Duration(
                                                                            milliseconds:
                                                                                200,
                                                                          ),
                                                                          opacity:
                                                                              _isPlayerExpanded
                                                                              ? 1.0
                                                                              : 0.0,
                                                                          child: IgnorePointer(
                                                                            ignoring:
                                                                                !_isPlayerExpanded,
                                                                            child:
                                                                                StreamBuilder<
                                                                                  bool
                                                                                >(
                                                                                  stream:
                                                                                      (globalAudioHandler
                                                                                              as MyAudioHandler)
                                                                                          .shuffleModeEnabledStream,
                                                                                  initialData: false,
                                                                                  builder:
                                                                                      (
                                                                                        context,
                                                                                        snapshot,
                                                                                      ) {
                                                                                        final isShuffle =
                                                                                            snapshot.data ??
                                                                                            false;
                                                                                        return HyperOSShuffleButton(
                                                                                          isShuffle: isShuffle,
                                                                                          onTap: () {
                                                                                            (globalAudioHandler
                                                                                                    as MyAudioHandler)
                                                                                                .toggleShuffleMode();
                                                                                          },
                                                                                          gradientColors: smoothThemeColors,
                                                                                          size: _isPlayerExpanded
                                                                                              ? 30
                                                                                              : 20,
                                                                                        );
                                                                                      },
                                                                                ),
                                                                          ),
                                                                        ),
                                                                      ),

                                                                      AnimatedPositioned(
                                                                        duration:
                                                                            transitionDuration,
                                                                        curve:
                                                                            transitionCurve,
                                                                        left: 0,
                                                                        right:
                                                                            0,
                                                                        bottom:
                                                                            _isPlayerExpanded
                                                                            ? 85 +
                                                                                  extraBottom
                                                                            : (isLiquidGlass
                                                                                  ? 33
                                                                                  : navBarHeight +
                                                                                        33),
                                                                        height:
                                                                            60,
                                                                        child: AnimatedPadding(
                                                                          duration:
                                                                              transitionDuration,
                                                                          curve:
                                                                              transitionCurve,
                                                                          padding: EdgeInsets.only(
                                                                            right:
                                                                                _isPlayerExpanded
                                                                                ? 0
                                                                                : 50,
                                                                          ),
                                                                          child: AnimatedAlign(
                                                                            duration:
                                                                                transitionDuration,
                                                                            curve:
                                                                                transitionCurve,
                                                                            alignment:
                                                                                _isPlayerExpanded
                                                                                ? Alignment.center
                                                                                : Alignment.centerRight,
                                                                            child: Row(
                                                                              mainAxisSize: MainAxisSize.min,
                                                                              children: [
                                                                                SizedBox(
                                                                                  height: 60,
                                                                                  child: Center(
                                                                                    child: HyperOSButton(
                                                                                      onTap: () {
                                                                                        globalAudioHandler.skipToPrevious();
                                                                                      },
                                                                                      child: SmoothIcon(
                                                                                        icon: CupertinoIcons.backward_fill,
                                                                                        color: Colors.white,
                                                                                        size: _isPlayerExpanded
                                                                                            ? 36
                                                                                            : 22,
                                                                                      ),
                                                                                    ),
                                                                                  ),
                                                                                ),
                                                                                AnimatedContainer(
                                                                                  duration: transitionDuration,
                                                                                  curve: transitionCurve,
                                                                                  width: _isPlayerExpanded
                                                                                      ? 35
                                                                                      : 6,
                                                                                ),
                                                                                SizedBox(
                                                                                  height: 60,
                                                                                  child: Center(
                                                                                    child: HyperOSButton(
                                                                                      onTap: () {
                                                                                        if (playing) {
                                                                                          globalAudioHandler.pause();
                                                                                        } else {
                                                                                          globalAudioHandler.play();
                                                                                        }
                                                                                      },
                                                                                      child: SmoothIcon(
                                                                                        icon: playing
                                                                                            ? CupertinoIcons.pause_solid
                                                                                            : CupertinoIcons.play_arrow_solid,
                                                                                        color: Colors.white,
                                                                                        size: _isPlayerExpanded
                                                                                            ? 46
                                                                                            : 26,
                                                                                      ),
                                                                                    ),
                                                                                  ),
                                                                                ),
                                                                                AnimatedContainer(
                                                                                  duration: transitionDuration,
                                                                                  curve: transitionCurve,
                                                                                  width: _isPlayerExpanded
                                                                                      ? 35
                                                                                      : 6,
                                                                                ),
                                                                                SizedBox(
                                                                                  height: 60,
                                                                                  child: Center(
                                                                                    child: HyperOSButton(
                                                                                      onTap: () {
                                                                                        globalAudioHandler.skipToNext();
                                                                                      },
                                                                                      child: SmoothIcon(
                                                                                        icon: CupertinoIcons.forward_fill,
                                                                                        color: Colors.white,
                                                                                        size: _isPlayerExpanded
                                                                                            ? 36
                                                                                            : 22,
                                                                                      ),
                                                                                    ),
                                                                                  ),
                                                                                ),
                                                                              ],
                                                                            ),
                                                                          ),
                                                                        ),
                                                                      ),

                                                                      AnimatedPositioned(
                                                                        duration:
                                                                            transitionDuration,
                                                                        curve:
                                                                            transitionCurve,
                                                                        right:
                                                                            _isPlayerExpanded
                                                                            ? 20
                                                                            : 12,
                                                                        bottom:
                                                                            _isPlayerExpanded
                                                                            ? 95 +
                                                                                  extraBottom
                                                                            : (isLiquidGlass
                                                                                  ? 48
                                                                                  : navBarHeight +
                                                                                        48),
                                                                        width:
                                                                            _isPlayerExpanded
                                                                            ? 40
                                                                            : 30,
                                                                        height:
                                                                            _isPlayerExpanded
                                                                            ? 40
                                                                            : 30,
                                                                        child:
                                                                            StreamBuilder<
                                                                              LoopMode
                                                                            >(
                                                                              stream:
                                                                                  (globalAudioHandler
                                                                                          as MyAudioHandler)
                                                                                      .loopModeStream,
                                                                              initialData: LoopMode.all,
                                                                              builder:
                                                                                  (
                                                                                    context,
                                                                                    snapshot,
                                                                                  ) {
                                                                                    final loopMode =
                                                                                        snapshot.data ??
                                                                                        LoopMode.all;
                                                                                    final isLooping =
                                                                                        loopMode ==
                                                                                        LoopMode.one;
                                                                                    return HyperOSRepeatButton(
                                                                                      isLooping: isLooping,
                                                                                      onTap: () {
                                                                                        (globalAudioHandler
                                                                                                as MyAudioHandler)
                                                                                            .toggleLoopMode();
                                                                                      },
                                                                                      gradientColors: smoothThemeColors,
                                                                                      size: _isPlayerExpanded
                                                                                          ? 30
                                                                                          : 20,
                                                                                    );
                                                                                  },
                                                                            ),
                                                                      ),

                                                                      AnimatedPositioned(
                                                                        duration:
                                                                            transitionDuration,
                                                                        curve:
                                                                            transitionCurve,
                                                                        left:
                                                                            20,
                                                                        right:
                                                                            20,
                                                                        bottom:
                                                                            _isPlayerExpanded
                                                                            ? 25 +
                                                                                  extraBottom
                                                                            : (isLiquidGlass
                                                                                  ? 6
                                                                                  : navBarHeight +
                                                                                        6),
                                                                        child:
                                                                            StreamBuilder<
                                                                              PositionData
                                                                            >(
                                                                              stream: _positionDataStream,
                                                                              initialData: PositionData(
                                                                                Duration.zero,
                                                                                Duration.zero,
                                                                                Duration.zero,
                                                                              ),
                                                                              builder:
                                                                                  (
                                                                                    context,
                                                                                    posSnapshot,
                                                                                  ) {
                                                                                    final position = posSnapshot.data!.position;
                                                                                    final duration = posSnapshot.data!.duration;
                                                                                    return HyperOSSlider(
                                                                                      position: position,
                                                                                      duration: duration,
                                                                                      onSeek:
                                                                                          (
                                                                                            target,
                                                                                          ) {
                                                                                            globalAudioHandler.seek(
                                                                                              target,
                                                                                            );
                                                                                          },
                                                                                      gradientColors: smoothThemeColors,
                                                                                    );
                                                                                  },
                                                                            ),
                                                                      ),
                                                                    ],
                                                                  ),
                                                              ],
                                                            );
                                                            return AGSLRhombusGlass(
                                                              enabled:
                                                                  isLiquidGlass,
                                                              cornerRadius:
                                                                  _isPlayerExpanded
                                                                  ? 0
                                                                  : 32.0,
                                                              child: Stack(
                                                                children: [
                                                                  Positioned.fill(
                                                                    child: AnimatedOpacity(
                                                                      duration:
                                                                          transitionDuration,
                                                                      opacity:
                                                                          isLiquidGlass
                                                                          ? 1.0
                                                                          : 0.0,
                                                                      child: AnimatedContainer(
                                                                        duration:
                                                                            transitionDuration,
                                                                        color:
                                                                            _isPlayerExpanded
                                                                            ? Colors.black.withValues(
                                                                                alpha: 0.1,
                                                                              )
                                                                            : Colors.black.withValues(
                                                                                alpha: 0.3,
                                                                              ),
                                                                      ),
                                                                    ),
                                                                  ),
                                                                  contentStack,
                                                                ],
                                                              ),
                                                            );
                                                          },
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                );
                                              },
                                            );
                                          },
                                        ),
                                        ValueListenableBuilder<bool>(
                                          valueListenable:
                                              isLiquidGlassEnabledNotifier,
                                          builder: (context, isLiquidGlass, child) {
                                            return AnimatedPositioned(
                                              key: _bottomBarKey,
                                              duration: transitionDuration,
                                              curve: transitionCurve,
                                              bottom: isLiquidGlass
                                                  ? (_isPlayerExpanded
                                                        ? -navBarHeight
                                                        : 12 + bottomPadding)
                                                  : 0,
                                              left: isLiquidGlass ? 12 : 0,
                                              right: isLiquidGlass ? 12 : 0,
                                              height: isLiquidGlass
                                                  ? 56.0
                                                  : navBarHeight,
                                              child: AnimatedOpacity(
                                                duration: _isPlayerExpanded
                                                    ? const Duration(milliseconds: 180)
                                                    : const Duration(milliseconds: 250),
                                                curve: _isPlayerExpanded
                                                    ? Curves.easeOut
                                                    : Curves.easeIn,
                                                opacity: _isPlayerExpanded
                                                    ? 0.0
                                                    : 1.0,
                                                child: IgnorePointer(
                                                  ignoring: _isPlayerExpanded,
                                                  child: AGSLRhombusGlass(
                                                    enabled:
                                                        isLiquidGlass &&
                                                        !_isPlayerExpanded,
                                                    cornerRadius: 32.0,
                                                    child: AnimatedContainer(
                                                      duration:
                                                          transitionDuration,
                                                      clipBehavior:
                                                          isLiquidGlass
                                                              ? Clip.antiAlias
                                                              : Clip.none,
                                                      decoration: BoxDecoration(
                                                        borderRadius:
                                                            isLiquidGlass
                                                            ? BorderRadius.circular(
                                                                32,
                                                              )
                                                            : BorderRadius.zero,
                                                      ),
                                                      child: Stack(
                                                        children: [
                                                          if (isLiquidGlass)
                                                            Positioned.fill(
                                                              child: ValueListenableBuilder<bool>(
                                                                valueListenable:
                                                                    isBatterySaverEnabledNotifier,
                                                                builder:
                                                                    (context, isBatterySaver, _) {
                                                                  return AnimatedContainer(
                                                                    duration:
                                                                        transitionDuration,
                                                                    curve:
                                                                        transitionCurve,
                                                                    color:
                                                                        Colors.black.withValues(
                                                                          alpha: 0.3,
                                                                        ),
                                                                  );
                                                                },
                                                              ),
                                                            ),
                                                          if (isLiquidGlass)
                                                            Positioned.fill(
                                                              child: LiquidGlassContainer(
                                                                duration:
                                                                    transitionDuration,
                                                                curve:
                                                                    transitionCurve,
                                                                borderRadius: 32,
                                                                child:
                                                                    const SizedBox.expand(),
                                                              ),
                                                            ),
                                                        Align(
                                                          alignment: Alignment
                                                              .topCenter,
                                                          child: MediaQuery.removePadding(
                                                            context: context,
                                                            removeBottom: true,
                                                            child: Theme(
                                                              data:
                                                                  Theme.of(
                                                                    context,
                                                                  ).copyWith(
                                                                    splashColor:
                                                                        Colors
                                                                            .transparent,
                                                                    highlightColor:
                                                                        Colors
                                                                            .transparent,
                                                                  ),
                                                              child: StreamBuilder<User?>(
                                                                stream: FirebaseAuth
                                                                    .instance
                                                                    .authStateChanges(),
                                                                builder:
                                                                    (
                                                                      context,
                                                                      authSnapshot,
                                                                    ) {
                                                                      final user =
                                                                          authSnapshot
                                                                              .data;

                                                                      return ValueListenableBuilder<
                                                                        String?
                                                                      >(
                                                                        valueListenable:
                                                                            userProfileImageNotifier,
                                                                        builder:
                                                                            (
                                                                              context,
                                                                              localImagePath,
                                                                              _,
                                                                            ) {
                                                                              // Logique de l'icône (Locale > Google > Défaut)
                                                                              final hasLocalImage =
                                                                                  localImagePath !=
                                                                                      null &&
                                                                                  localImagePath.isNotEmpty &&
                                                                                  File(
                                                                                    localImagePath,
                                                                                  ).existsSync();
                                                                              final hasGoogleImage =
                                                                                  user !=
                                                                                      null &&
                                                                                  user.photoURL !=
                                                                                      null;

                                                                              final cachedGoogleAvatar = File(
                                                                                '$globalDocumentPath/cached_google_avatar.jpg',
                                                                              );
                                                                              final hasCachedGoogle = cachedGoogleAvatar.existsSync();

                                                                              Widget
                                                                              accountIcon;
                                                                              if (hasLocalImage) {
                                                                                accountIcon = ClipOval(
                                                                                  child: Image.file(
                                                                                    File(
                                                                                      localImagePath,
                                                                                    ),
                                                                                    width: 24,
                                                                                    height: 24,
                                                                                    fit: BoxFit.cover,
                                                                                  ),
                                                                                );
                                                                              } else if (hasCachedGoogle) {
                                                                                accountIcon = ClipOval(
                                                                                  child: Image.file(
                                                                                    cachedGoogleAvatar,
                                                                                    width: 24,
                                                                                    height: 24,
                                                                                    fit: BoxFit.cover,
                                                                                  ),
                                                                                );
                                                                              } else if (hasGoogleImage) {
                                                                                accountIcon = ClipOval(
                                                                                  child: Image.network(
                                                                                    user.photoURL!,
                                                                                    width: 24,
                                                                                    height: 24,
                                                                                    fit: BoxFit.cover,
                                                                                    errorBuilder:
                                                                                        (
                                                                                          context,
                                                                                          error,
                                                                                          stackTrace,
                                                                                        ) => const Icon(
                                                                                          CupertinoIcons.person_fill,
                                                                                          size: 24,
                                                                                        ),
                                                                                  ),
                                                                                );
                                                                              } else {
                                                                                accountIcon = const Icon(
                                                                                  CupertinoIcons.person_alt_circle,
                                                                                );
                                                                              }

                                                                              return BottomNavigationBar(
                                                                                backgroundColor: Colors.transparent,
                                                                                elevation: 0,
                                                                                selectedItemColor: Colors.white,
                                                                                unselectedItemColor: Colors.white54,
                                                                                selectedFontSize: 11,
                                                                                unselectedFontSize: 11,
                                                                                type: BottomNavigationBarType.fixed,
                                                                                currentIndex: _currentIndex,
                                                                                onTap:
                                                                                    (
                                                                                      index,
                                                                                    ) {
                                                                                      FocusScope.of(
                                                                                        context,
                                                                                      ).unfocus();
                                                                                      setState(
                                                                                        () {
                                                                                          _currentIndex = index;
                                                                                        },
                                                                                      );
                                                                                      _mainPageController.animateToPage(
                                                                                        index,
                                                                                        duration: const Duration(
                                                                                          milliseconds: 400,
                                                                                        ),
                                                                                        curve: Curves.fastOutSlowIn,
                                                                                      );
                                                                                    },
                                                                                items: [
                                                                                  const BottomNavigationBarItem(
                                                                                    icon: Icon(
                                                                                      Icons.home,
                                                                                    ),
                                                                                    label: 'Accueil',
                                                                                  ),
                                                                                  const BottomNavigationBarItem(
                                                                                    icon: Icon(
                                                                                      CupertinoIcons.person_2_fill,
                                                                                    ),
                                                                                    label: 'Artistes',
                                                                                  ),
                                                                                  const BottomNavigationBarItem(
                                                                                    icon: Icon(
                                                                                      CupertinoIcons.music_note,
                                                                                    ),
                                                                                    label: 'Musiques',
                                                                                  ),
                                                                                  const BottomNavigationBarItem(
                                                                                    icon: Icon(
                                                                                      CupertinoIcons.heart_fill,
                                                                                    ),
                                                                                    label: 'Bibliothèque',
                                                                                  ),
                                                                                  // 👇 L'ICÔNE DYNAMIQUE EST ICI 👇
                                                                                  BottomNavigationBarItem(
                                                                                    icon: accountIcon,
                                                                                    label: 'Compte',
                                                                                  ),
                                                                                ],
                                                                              );
                                                                            },
                                                                      );
                                                                    },
                                                              ),
                                                              // --- FIN DE LA NOUVELLE BARRE DE NAVIGATION ---
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          );
                                          },
                                        ),
                                      ],
                                    );
                                  },
                                );
                              },
                            );
                          },
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
    );
  }
}
