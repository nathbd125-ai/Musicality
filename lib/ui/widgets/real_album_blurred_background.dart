import 'dart:ui';
import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/scheduler.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:musicality/core/globals.dart';

class RealAlbumBlurredBackground extends StatefulWidget {
  final MediaItem item;
  const RealAlbumBlurredBackground({super.key, required this.item});

  @override
  State<RealAlbumBlurredBackground> createState() =>
      _RealAlbumBlurredBackgroundState();
}

class _RealAlbumBlurredBackgroundState extends State<RealAlbumBlurredBackground>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker _driftTicker;
  double _driftTime = 0.0;
  Duration? _lastTick;
  Duration? _lastRenderTime;

  StreamSubscription<PlaybackState>? _playbackSubscription;
  Timer? _pauseTimer;
  bool _isPlaying = true;

  late final AnimationController _coverFadeController;
  late final AnimationController _colorFadeController;
  bool _isForeground = true;

  MediaItem? _previousItem;
  MediaItem? _currentItem;

  // Cache mémoire des palettes pour 0 ms de calcul lors des réécoutes
  static final Map<String, List<Color>> _colorCache = {};

  Timer? _paletteDebounceTimer;
  int _paletteRequestId = 0;

  List<Color> _previousColors = const [
    Color(0xFF231A38),
    Color(0xFF1A1A24),
    Color(0xFF0D0D12),
  ];
  List<Color> _targetColors = const [
    Color(0xFF231A38),
    Color(0xFF1A1A24),
    Color(0xFF0D0D12),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _currentItem = widget.item;
    final initialColors = _getInitialColors(widget.item);
    _previousColors = initialColors;
    _targetColors = initialColors;

    // Contrôleur de fondu de la pochette (changement de morceau)
    _coverFadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
      value: 0.0,
    )..addListener(() {
        if (mounted) setState(() {});
      });

    // Contrôleur de fondu des teintes / orbes
    _colorFadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
      value: 1.0,
    )..addListener(() {
        if (mounted) setState(() {});
      });

    // Ticker continu throttlé à ~30 FPS pour une dérive 100% fluide sans aucune surchauffe GPU
    _driftTicker = createTicker((Duration elapsed) {
      if (_lastTick != null) {
        final double dt = (elapsed - _lastTick!).inMicroseconds / 1000000.0;
        // Plafonnement de dt pour éviter tout à-coup lors de la reprise d'activité
        if (dt > 0.0 && dt < 0.1) {
          _driftTime += dt;
        }
      }
      _lastTick = elapsed;

      // Throttle le rendu à ~30 FPS (32ms) : divise par 4 la charge de rendu sur 120/144Hz
      if (_lastRenderTime != null &&
          (elapsed - _lastRenderTime!).inMilliseconds < 32) {
        return;
      }
      _lastRenderTime = elapsed;

      if (mounted) {
        setState(() {});
      }
    });

    isBatterySaverEnabledNotifier.addListener(_onBatterySaverChanged);

    _isPlaying = globalAudioHandler.playbackState.value.playing;
    _playbackSubscription = globalAudioHandler.playbackState.listen((state) {
      final playing = state.playing;
      if (playing != _isPlaying) {
        _isPlaying = playing;
        _handlePlaybackStateChanged();
      }
    });

    _syncAnimation();
    _resolveAndFadeCover(widget.item, isInitial: true);
    _refineColorsAsync(widget.item);
  }

  void _resolveAndFadeCover(MediaItem newItem, {required bool isInitial}) {
    final provider = ResizeImage(
      getLocalOrNetworkImageProvider(newItem),
      width: 120,
      height: 120,
    );

    final stream = provider.resolve(ImageConfiguration.empty);
    late ImageStreamListener listener;

    listener = ImageStreamListener(
      (ImageInfo info, bool synchronousCall) {
        stream.removeListener(listener);
        if (!mounted || widget.item.id != newItem.id) return;

        if (isInitial) {
          if (synchronousCall) {
            _coverFadeController.value = 1.0;
          } else {
            _coverFadeController.forward(from: 0.0);
          }
        } else {
          // L'image entrante est maintenant décodée en mémoire VRAM.
          // On peut basculer _currentItem en toute sécurité et déclencher le fondu croisé sans aucun écran noir !
          setState(() {
            _currentItem = newItem;
          });
          _coverFadeController.forward(from: 0.0).then((_) {
            if (mounted && _currentItem?.id == newItem.id) {
              setState(() {
                _previousItem = null;
              });
            }
          });
        }
      },
      onError: (exception, stackTrace) {
        stream.removeListener(listener);
        if (!mounted || widget.item.id != newItem.id) return;
        if (isInitial) {
          _coverFadeController.value = 1.0;
        } else {
          setState(() {
            _currentItem = newItem;
            _previousItem = null;
          });
          _coverFadeController.value = 1.0;
        }
      },
    );

    stream.addListener(listener);
  }

  static bool _hasSameCover(MediaItem a, MediaItem b) {
    // 1. Même URL d'image exacte
    if (a.artUri != null && b.artUri != null && a.artUri == b.artUri) {
      return true;
    }
    // 2. Même nom de fichier de couverture résolu
    final coverA = resolveCoverName(
      id: a.id,
      albumName: a.album ?? '',
      coverName: a.extras?['coverName'] as String?,
    );
    final coverB = resolveCoverName(
      id: b.id,
      albumName: b.album ?? '',
      coverName: b.extras?['coverName'] as String?,
    );
    if (coverA.isNotEmpty && coverA == coverB) {
      return true;
    }
    // 3. Même album non vide et non inconnu
    final albumA = (a.album ?? '').trim().toLowerCase();
    final albumB = (b.album ?? '').trim().toLowerCase();
    if (albumA.isNotEmpty &&
        albumA != 'inconnu' &&
        albumA != 'singles' &&
        albumA == albumB) {
      return true;
    }
    return false;
  }

  static bool _areColorsEqual(List<Color> a, List<Color> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static String _getCoverCacheKey(MediaItem item) {
    final resolved = resolveCoverName(
      id: item.id,
      albumName: item.album ?? '',
      coverName: item.extras?['coverName'] as String?,
    );
    if (resolved.isNotEmpty) {
      return resolved;
    }
    return item.artUri?.toString() ?? item.id;
  }

  @override
  void didUpdateWidget(covariant RealAlbumBlurredBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id ||
        oldWidget.item.artUri != widget.item.artUri) {
      final sameCover = _hasSameCover(oldWidget.item, widget.item);
      final newColors = _getInitialColors(widget.item);

      if (sameCover) {
        // Même pochette : AUCUNE transition, la dérive physique continue sans aucune coupure
        _currentItem = widget.item;
        _previousItem = null;
        if (!_coverFadeController.isCompleted) {
          _coverFadeController.value = 1.0;
        }

        // Transition de couleur uniquement si les teintes diffèrent réellement
        if (!_areColorsEqual(_targetColors, newColors)) {
          _applyNewColors(newColors);
        }
      } else {
        // Pochette différente :
        // 1. L'ancienne pochette reste affichée (_previousItem) tant que la nouvelle télécharge/décode
        _previousItem = _currentItem ?? oldWidget.item;
        // 2. Lancer immédiatement le changement de teintes d'ambiance et orbes (0 ms)
        _applyNewColors(newColors);
        // 3. Pré-résoudre la nouvelle pochette et lancer le fondu croisé dès qu'elle est prête
        _resolveAndFadeCover(widget.item, isInitial: false);
      }

      // Raffinement asynchrone non-bloquant
      _refineColorsAsync(widget.item);
    }
  }

  List<Color> _getInitialColors(MediaItem item) {
    final cacheKey = _getCoverCacheKey(item);
    if (_colorCache.containsKey(cacheKey)) {
      return _colorCache[cacheKey]!;
    }

    // Couleurs instantanées du thème de l'album (0 ms de calcul)
    final preset = getAlbumGradientColors(item);
    if (preset.length >= 3) {
      return [preset[0], preset[1], preset[2]];
    } else if (preset.length == 2) {
      return [preset[0], preset[1], const Color(0xFF0E0E14)];
    } else if (preset.isNotEmpty) {
      return [preset[0], preset[0], const Color(0xFF0E0E14)];
    }
    return const [
      Color(0xFF2E1B4E),
      Color(0xFF181C2B),
      Color(0xFF0E0E14),
    ];
  }

  void _refineColorsAsync(MediaItem item) {
    final cacheKey = _getCoverCacheKey(item);
    if (_colorCache.containsKey(cacheKey)) return;

    _paletteDebounceTimer?.cancel();
    final currentId = ++_paletteRequestId;

    // Debounce de 250ms : si l'utilisateur zappe rapidement, on n'analyse que le morceau final
    _paletteDebounceTimer = Timer(const Duration(milliseconds: 250), () async {
      if (!mounted || currentId != _paletteRequestId || widget.item.id != item.id) return;
      try {
        final imageProvider = ResizeImage(
          getLocalOrNetworkImageProvider(item),
          width: 48,
          height: 48,
        );
        final palette = await PaletteGenerator.fromImageProvider(
          imageProvider,
          size: const Size(32, 32), // Échantillon ultra-léger pour 0 freeze
          maximumColorCount: 4,
        );

        if (!mounted || currentId != _paletteRequestId || widget.item.id != item.id) return;

        final dominant = palette.dominantColor?.color;
        final vibrant = palette.vibrantColor?.color ??
            palette.lightVibrantColor?.color ??
            dominant;
        final darkMuted = palette.darkMutedColor?.color ??
            palette.mutedColor?.color ??
            const Color(0xFF0E0E14);

        if (vibrant != null || dominant != null) {
          final c1 = vibrant ?? const Color(0xFF2E1B4E);
          final c2 = dominant ?? const Color(0xFF181C2B);
          final c3 = darkMuted;
          final refined = [c1, c2, c3];
          _colorCache[cacheKey] = refined;

          if (mounted && (widget.item.id == item.id)) {
            _applyNewColors(refined);
          }
        }
      } catch (_) {}
    });
  }

  void _applyNewColors(List<Color> newColors) {
    if (!mounted) return;
    final currentProgress = _colorFadeController.value;
    _previousColors = [
      Color.lerp(_previousColors[0], _targetColors[0], currentProgress)!,
      Color.lerp(_previousColors[1], _targetColors[1], currentProgress)!,
      Color.lerp(_previousColors[2], _targetColors[2], currentProgress)!,
    ];
    _targetColors = newColors;
    _colorFadeController.forward(from: 0.0);
  }

  void _handlePlaybackStateChanged() {
    _pauseTimer?.cancel();
    if (_isPlaying) {
      // Lecture reprise : réveiller immédiatement l'animation
      _syncAnimation();
    } else {
      // Pause : attendre 12s avant d'endormir l'animation pour économiser 100% de la batterie
      _pauseTimer = Timer(const Duration(seconds: 12), () {
        if (mounted && !_isPlaying) {
          _syncAnimation();
        }
      });
    }
  }

  void _onBatterySaverChanged() {
    _syncAnimation();
  }

  void _syncAnimation() {
    if (!mounted) return;
    final isBatterySaver = isBatterySaverEnabledNotifier.value;
    final isPausedLongTime = !_isPlaying && !(_pauseTimer?.isActive ?? false);
    final shouldAnimate = !isBatterySaver && _isForeground && !isPausedLongTime;

    if (shouldAnimate) {
      if (!_driftTicker.isTicking) {
        _lastTick = null;
        _lastRenderTime = null;
        _driftTicker.start();
      }
    } else {
      if (_driftTicker.isTicking) {
        _driftTicker.stop();
        _lastTick = null;
        _lastRenderTime = null;
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    _isForeground = (state == AppLifecycleState.resumed);
    _syncAnimation();
  }

  @override
  void dispose() {
    _paletteDebounceTimer?.cancel();
    _pauseTimer?.cancel();
    _playbackSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    isBatterySaverEnabledNotifier.removeListener(_onBatterySaverChanged);
    _driftTicker.dispose();
    _coverFadeController.dispose();
    _colorFadeController.dispose();
    super.dispose();
  }

  Widget _buildAmbientCover(MediaItem? item) {
    if (item == null) return const SizedBox.shrink();
    return RepaintBoundary(
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(
          sigmaX: 28,
          sigmaY: 28,
          tileMode: TileMode.mirror,
        ),
        child: SizedBox.expand(
          child: Image(
            image: ResizeImage(
              getLocalOrNetworkImageProvider(item),
              width: 120,
              height: 120,
            ),
            fit: BoxFit.cover,
            filterQuality: FilterQuality.low,
            errorBuilder: (context, error, stackTrace) =>
                const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final coverProgress = CurvedAnimation(
      parent: _coverFadeController,
      curve: Curves.easeInOutCubic,
    ).value;

    final colorProgress = CurvedAnimation(
      parent: _colorFadeController,
      curve: Curves.easeOutCubic,
    ).value;

    final c3 = Color.lerp(_previousColors[2], _targetColors[2], colorProgress)!;

    // Dérive continue fluide sans téléportation (temps perpétuellement croissant)
    // Harmonies multi-fréquences douces et non-périodiques
    final driftX = math.sin(_driftTime * 0.22) * 16.0 + math.cos(_driftTime * 0.39) * 8.0;
    final driftY = math.cos(_driftTime * 0.17) * 22.0 + math.sin(_driftTime * 0.31) * 10.0;
    final driftScale = 1.15 + math.sin(_driftTime * 0.13) * 0.03;

    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            fit: StackFit.expand,
            children: [
              // 1. Fond sombre de base ancré dans la palette de l'album
              Container(color: c3),

              // 2. Vraie pochette de l'album floutée avec dérive physique fluide (mise en cache GPU VRAM sans recalcul de flou)
              Transform.translate(
                offset: Offset(driftX, driftY),
                child: Transform.scale(
                  scale: driftScale,
                  alignment: Alignment.center,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (_previousItem != null && coverProgress < 1.0)
                        Opacity(
                          opacity: (1.0 - coverProgress).clamp(0.0, 1.0),
                          child: _buildAmbientCover(_previousItem),
                        ),
                      if (_currentItem != null)
                        Opacity(
                          opacity: coverProgress.clamp(0.0, 1.0),
                          child: _buildAmbientCover(_currentItem),
                        ),
                    ],
                  ),
                ),
              ),

              // 3. Voile sombre translucide pour garantir la lisibilité et le contraste
              Container(
                color: Colors.black.withValues(alpha: 0.26),
              ),
            ],
          );
        },
      ),
    );
  }
}

