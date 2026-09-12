import 'dart:async';
import 'package:rxdart/rxdart.dart';
import 'package:musicality/core/models.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'dart:ui';
import 'package:musicality/ui/widgets/marquee_widget.dart';
import 'package:musicality/ui/widgets/musicality_bottom_nav_bar.dart';
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
import 'package:musicality/ui/widgets/real_album_blurred_background.dart';
import 'package:musicality/landscape_player.dart';
import 'package:musicality/core/my_audio_handler.dart';
import 'package:musicality/ui/widgets/hyper_os_slider.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:musicality/core/globals.dart';
import 'package:musicality/core/app_config.dart';
import 'package:musicality/ui/editor/lrc_editor_view.dart';
import 'package:flutter/material.dart';

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
  StreamSubscription<MediaItem?>? _mediaItemSub;

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
    SongDownloadService.scanLocalFiles(globalPlaylist);
    _checkForUpdates();
    
    isBatterySaverEnabledNotifier.addListener(_onBatterySaverChanged);

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

    _mediaItemSub = globalAudioHandler.mediaItem.listen((item) {
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

  void _onBatterySaverChanged() {
    if (isBatterySaverEnabledNotifier.value && _isPlayerExpanded) {
      if (mounted) {
        setState(() {
          _isPlayerExpanded = false;
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() {
      _isAppInForeground = (state == AppLifecycleState.resumed);
    });
  }

  @override
  void dispose() {
    _mediaItemSub?.cancel();
    isBatterySaverEnabledNotifier.removeListener(_onBatterySaverChanged);
    WidgetsBinding.instance.removeObserver(this);
    _mainPageController.dispose();
    super.dispose();
  }

  Future<void> _fetchLyrics(MediaItem item) async {
    final songId = item.id;
    if (LyricsService.hasCached(songId)) {
      setState(() {
        _currentLyrics = LyricsService.getCached(songId)!;
        _isLoadingLyrics = false;
      });
      return;
    }
    setState(() {
      _isLoadingLyrics = true;
      _currentLyrics = [];
    });

    final lyrics = await LyricsService.fetchLyrics(item);
    if (mounted && _lastSongId == songId) {
      setState(() {
        _currentLyrics = lyrics;
        _isLoadingLyrics = false;
      });
    }
  }

  Future<void> _checkForUpdates() async {
    final updateInfo = await AppUpdateService.checkForUpdates();
    if (updateInfo != null && mounted) {
      AppUpdateService.showUpdateDialog(context, updateInfo);
    }
  }

  @override
  Widget build(BuildContext context) {
    final double topPadding = MediaQuery.of(context).viewPadding.top;
    final double bottomPadding = MediaQuery.of(context).viewPadding.bottom;
    final double extraBottom = bottomPadding > 35 ? bottomPadding : 0;
    final double screenHeight = MediaQuery.of(context).size.height;
    final double screenWidth = MediaQuery.of(context).size.width;

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

                            return ListenableBuilder(
                              listenable: Listenable.merge([
                                isLiquidGlassEnabledNotifier,
                                isBatterySaverEnabledNotifier,
                              ]),
                              builder: (context, _) {
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
                                              child: FocusScope(
                                                canRequestFocus:
                                                    !_isPlayerExpanded,
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
                                            final isBatterySaver =
                                                isBatterySaverEnabledNotifier.value;
                                            final isLiquidGlass =
                                                isLiquidGlassEnabledNotifier.value && !isBatterySaver;
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
                                                      end: (isLiquidGlass || isBatterySaver || _isPlayerExpanded)
                                                          ? 0.001
                                                          : 20.0,
                                                    ),
                                                    duration: const Duration(milliseconds: 600),
                                                    curve: Curves.easeInOutCubic,
                                                    builder: (context, currentSigma, child) {
                                                      if (currentSigma <= 0.01) {
                                                        return child!;
                                                      }
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

                                            return ListenableBuilder(
                                              listenable: Listenable.merge([
                                                isLiquidGlassEnabledNotifier,
                                                isBatterySaverEnabledNotifier,
                                                isDownloadHiResNotifier,
                                                isDownloadLosslessNotifier,
                                                SongDownloadService.downloadedSongsNotifier,
                                                SongDownloadService.downloadingSongsNotifier,
                                              ]),
                                              builder: (context, _) {
                                                final bool isBatterySaver = isBatterySaverEnabledNotifier.value;
                                                final bool isLiquidGlass = isLiquidGlassEnabledNotifier.value && !isBatterySaver;
                                                final bool isDownloaded = SongDownloadService.isDownloaded(safeItem.id);
                                                final bool isDownloading = SongDownloadService.isDownloading(safeItem.id);
                                                final bool needsUpgrade = SongDownloadService.checkNeedsUpgrade(safeItem);
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
                                                        clipBehavior: Clip.antiAlias,
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
                                                                              Row(
                                                                                mainAxisSize:
                                                                                    MainAxisSize.min,
                                                                                children: [
                                                                                  ValueListenableBuilder<bool>(
                                                                                    valueListenable: AppConfig.isStudioModeNotifier,
                                                                                    builder: (context, isStudio, _) {
                                                                                      if (!isStudio) return const SizedBox.shrink();
                                                                                      return IconButton(
                                                                                        icon: const Icon(
                                                                                          CupertinoIcons.pencil_ellipsis_rectangle,
                                                                                          size: 24,
                                                                                        ),
                                                                                        color: Colors.cyanAccent,
                                                                                        tooltip: "Éditeur LRC (Studio)",
                                                                                        onPressed: () {
                                                                                          if (isHapticFeedbackEnabledNotifier.value) {
                                                                                            HapticFeedback.lightImpact();
                                                                                          }
                                                                                          FocusManager.instance.primaryFocus?.unfocus();
                                                                                          Navigator.of(context).push(
                                                                                            MaterialPageRoute(
                                                                                              builder: (context) => LrcEditorView(
                                                                                                mediaItem: safeItem,
                                                                                                initialLyrics: _currentLyrics,
                                                                                                positionStream: _positionDataStream,
                                                                                                onSaved: () async {
                                                                                                  final reloaded = await LyricsService.fetchLyrics(safeItem);
                                                                                                  if (mounted) {
                                                                                                    setState(() {
                                                                                                      _currentLyrics = reloaded;
                                                                                                    });
                                                                                                  }
                                                                                                },
                                                                                              ),
                                                                                            ),
                                                                                          );
                                                                                        },
                                                                                      );
                                                                                    },
                                                                                  ),
                                                                                  IconButton(
                                                                                    icon: const Icon(
                                                                                      Icons.screen_rotation_rounded,
                                                                                      size: 24,
                                                                                    ),
                                                                                    color: Colors.white70,
                                                                                    tooltip: "Mode paysage",
                                                                                    onPressed: () {
                                                                                      if (isHapticFeedbackEnabledNotifier.value) {
                                                                                        HapticFeedback.lightImpact();
                                                                                      }
                                                                                      FocusManager.instance.primaryFocus?.unfocus();
                                                                                      Navigator.of(context).push(
                                                                                        PageRouteBuilder(
                                                                                          pageBuilder: (
                                                                                            context,
                                                                                            animation,
                                                                                            secondaryAnimation,
                                                                                          ) =>
                                                                                              LandscapeStereoPlayer(
                                                                                                audioHandler:
                                                                                                    globalAudioHandler,
                                                                                                lyrics:
                                                                                                    _currentLyrics,
                                                                                                positionStream:
                                                                                                    _positionDataStream,
                                                                                                item:
                                                                                                    safeItem,
                                                                                                localFilePath:
                                                                                                    SongDownloadService
                                                                                                        .getLocalFilePath(
                                                                                                          safeItem,
                                                                                                        ),
                                                                                                themeColors:
                                                                                                    smoothThemeColors,
                                                                                              ),
                                                                                          transitionsBuilder: (
                                                                                            context,
                                                                                            animation,
                                                                                            secondaryAnimation,
                                                                                            child,
                                                                                          ) {
                                                                                            return FadeTransition(
                                                                                              opacity:
                                                                                                  animation,
                                                                                              child:
                                                                                                  child,
                                                                                            );
                                                                                          },
                                                                                        ),
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
                                                                                      SongDownloadService.toggleDownload(
                                                                                        safeItem,
                                                                                      );
                                                                                    },
                                                                                  ),
                                                                                ],
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
                                                                                    key: ValueKey(safeItem.id),
                                                                                    songId: safeItem.id,
                                                                                    lyrics: _currentLyrics,
                                                                                    positionStream: _positionDataStream,
                                                                                    themeColors: smoothThemeColors,
                                                                                    isExpanded: _isPlayerExpanded,
                                                                                  ),
                                                                          ),
                                                                        ),
                                                                      ),

                                                                      // --- BOUTON ALÉATOIRE (SHUFFLE) ---
                                                                      AnimatedPositioned(
                                                                        key: const ValueKey('ctrl_shuffle'),
                                                                        duration: transitionDuration,
                                                                        curve: transitionCurve,
                                                                        left: _isPlayerExpanded ? 20 : -50,
                                                                        bottom: _isPlayerExpanded
                                                                            ? 95 + extraBottom
                                                                            : (isLiquidGlass ? 48 : navBarHeight + 48),
                                                                        width: _isPlayerExpanded ? 40 : 30,
                                                                        height: _isPlayerExpanded ? 40 : 30,
                                                                        child: AnimatedOpacity(
                                                                          duration: transitionDuration,
                                                                          curve: transitionCurve,
                                                                          opacity: _isPlayerExpanded ? 1.0 : 0.0,
                                                                          child: IgnorePointer(
                                                                            ignoring: !_isPlayerExpanded,
                                                                            child: StreamBuilder<bool>(
                                                                              stream: (globalAudioHandler as MyAudioHandler)
                                                                                  .shuffleModeEnabledStream,
                                                                              initialData: (globalAudioHandler is MyAudioHandler)
                                                                                  ? (globalAudioHandler as MyAudioHandler).shuffleModeEnabled
                                                                                  : false,
                                                                              builder: (context, snapshot) {
                                                                                final isShuffle = snapshot.data ?? false;
                                                                                return HyperOSShuffleButton(
                                                                                  isShuffle: isShuffle,
                                                                                  onTap: () {
                                                                                    (globalAudioHandler as MyAudioHandler)
                                                                                        .toggleShuffleMode();
                                                                                  },
                                                                                  gradientColors: smoothThemeColors,
                                                                                  size: _isPlayerExpanded ? 30 : 20,
                                                                                );
                                                                              },
                                                                            ),
                                                                          ),
                                                                        ),
                                                                      ),

                                                                      // --- BOUTON PRÉCÉDENT ---
                                                                      AnimatedPositioned(
                                                                        key: const ValueKey('ctrl_prev'),
                                                                        duration: transitionDuration,
                                                                        curve: transitionCurve,
                                                                        right: _isPlayerExpanded
                                                                            ? (screenWidth / 2 + 62)
                                                                            : 126,
                                                                        bottom: _isPlayerExpanded
                                                                            ? 85 + extraBottom
                                                                            : (isLiquidGlass ? 33 : navBarHeight + 33),
                                                                        width: _isPlayerExpanded ? 44 : 30,
                                                                        height: 60,
                                                                        child: Center(
                                                                          child: HyperOSButton(
                                                                            onTap: () {
                                                                              globalAudioHandler.skipToPrevious();
                                                                            },
                                                                            child: SmoothIcon(
                                                                              icon: CupertinoIcons.backward_fill,
                                                                              color: Colors.white,
                                                                              size: _isPlayerExpanded ? 36 : 22,
                                                                            ),
                                                                          ),
                                                                        ),
                                                                      ),

                                                                      // --- BOUTON LECTURE / PAUSE ---
                                                                      AnimatedPositioned(
                                                                        key: const ValueKey('ctrl_play_pause'),
                                                                        duration: transitionDuration,
                                                                        curve: transitionCurve,
                                                                        right: _isPlayerExpanded
                                                                            ? (screenWidth / 2 - 27)
                                                                            : 86,
                                                                        bottom: _isPlayerExpanded
                                                                            ? 85 + extraBottom
                                                                            : (isLiquidGlass ? 33 : navBarHeight + 33),
                                                                        width: _isPlayerExpanded ? 54 : 34,
                                                                        height: 60,
                                                                        child: Center(
                                                                          child: HyperOSButton(
                                                                            isPlayPause: true,
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
                                                                              size: _isPlayerExpanded ? 46 : 26,
                                                                            ),
                                                                          ),
                                                                        ),
                                                                      ),

                                                                      // --- BOUTON SUIVANT ---
                                                                      AnimatedPositioned(
                                                                        key: const ValueKey('ctrl_next'),
                                                                        duration: transitionDuration,
                                                                        curve: transitionCurve,
                                                                        right: _isPlayerExpanded
                                                                            ? (screenWidth / 2 - 106)
                                                                            : 50,
                                                                        bottom: _isPlayerExpanded
                                                                            ? 85 + extraBottom
                                                                            : (isLiquidGlass ? 33 : navBarHeight + 33),
                                                                        width: _isPlayerExpanded ? 44 : 30,
                                                                        height: 60,
                                                                        child: Center(
                                                                          child: HyperOSButton(
                                                                            onTap: () {
                                                                              globalAudioHandler.skipToNext();
                                                                            },
                                                                            child: SmoothIcon(
                                                                              icon: CupertinoIcons.forward_fill,
                                                                              color: Colors.white,
                                                                              size: _isPlayerExpanded ? 36 : 22,
                                                                            ),
                                                                          ),
                                                                        ),
                                                                      ),

                                                                      // --- BOUTON RÉPÉTER (REPEAT) ---
                                                                      AnimatedPositioned(
                                                                        key: const ValueKey('ctrl_repeat'),
                                                                        duration: transitionDuration,
                                                                        curve: transitionCurve,
                                                                        right: _isPlayerExpanded ? 20 : 12,
                                                                        bottom: _isPlayerExpanded
                                                                            ? 95 + extraBottom
                                                                            : (isLiquidGlass ? 48 : navBarHeight + 48),
                                                                        width: _isPlayerExpanded ? 40 : 30,
                                                                        height: _isPlayerExpanded ? 40 : 30,
                                                                        child: StreamBuilder<LoopMode>(
                                                                          stream: (globalAudioHandler as MyAudioHandler)
                                                                              .loopModeStream,
                                                                            initialData: (globalAudioHandler is MyAudioHandler)
                                                                                ? (globalAudioHandler as MyAudioHandler).loopMode
                                                                                : LoopMode.all,
                                                                          builder: (context, snapshot) {
                                                                            final loopMode = snapshot.data ?? LoopMode.all;
                                                                            return HyperOSRepeatButton(
                                                                              loopMode: loopMode,
                                                                              onTap: () {
                                                                                (globalAudioHandler as MyAudioHandler)
                                                                                    .toggleLoopMode();
                                                                              },
                                                                              gradientColors: smoothThemeColors,
                                                                              size: _isPlayerExpanded ? 30 : 20,
                                                                            );
                                                                          },
                                                                        ),
                                                                      ),

                                                                      // --- SLIDER DE PROGRESSION ---
                                                                      AnimatedPositioned(
                                                                        key: const ValueKey('player_slider'),
                                                                        duration: transitionDuration,
                                                                        curve: transitionCurve,
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
                                                                            : (isLiquidGlass
                                                                                ? Colors.black.withValues(
                                                                                    alpha: 0.08,
                                                                                  )
                                                                                : Colors.black.withValues(
                                                                                    alpha: 0.3,
                                                                                  )),
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
                                        ListenableBuilder(
                                          listenable: Listenable.merge([
                                            isLiquidGlassEnabledNotifier,
                                            isBatterySaverEnabledNotifier,
                                          ]),
                                          builder: (context, _) {
                                            final isBatterySaver = isBatterySaverEnabledNotifier.value;
                                            final isLiquidGlass = isLiquidGlassEnabledNotifier.value && !isBatterySaver;
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
                                                      clipBehavior: Clip.antiAlias,
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
                                                          Positioned.fill(
                                                            child: AnimatedOpacity(
                                                              duration: transitionDuration,
                                                              opacity: isLiquidGlass ? 1.0 : 0.0,
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
                                                                          alpha: 0.08,
                                                                        ),
                                                                  );
                                                                },
                                                              ),
                                                            ),
                                                          ),
                                                        MusicalityBottomNavBar(
                                                          currentIndex: _currentIndex,
                                                          onTap: (index) {
                                                            FocusScope.of(context).unfocus();
                                                            setState(() {
                                                              _currentIndex = index;
                                                            });
                                                            _mainPageController.animateToPage(
                                                              index,
                                                              duration: const Duration(
                                                                milliseconds: 400,
                                                              ),
                                                              curve: Curves.fastOutSlowIn,
                                                            );
                                                          },
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
