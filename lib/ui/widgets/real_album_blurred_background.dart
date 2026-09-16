import 'dart:ui';
import 'dart:math' as math;
import 'dart:async';
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
  late final AnimationController _liquidController;
  late final AnimationController _fadeController;
  StreamSubscription<PlaybackState>? _playbackSub;
  bool _isForeground = true;

  MediaItem? _previousItem;
  MediaItem? _currentItem;

  // Cache mémoire des palettes pour 0 ms de calcul lors des réécoutes
  static final Map<String, List<Color>> _colorCache = {};

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

    // Animation très lente en boucle continue (effet liquide fluide sans surchauffe)
    _liquidController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
      value: math.Random().nextDouble(),
    );

    // Transition fluide entre pochettes lors d'un changement de musique
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
      value: 1.0,
    );

    _playbackSub = globalAudioHandler.playbackState.listen((_) {
      _syncAnimation();
    });
    isBatterySaverEnabledNotifier.addListener(_onBatterySaverChanged);

    _syncAnimation();
    _refineColorsAsync(widget.item);
  }

  @override
  void didUpdateWidget(covariant RealAlbumBlurredBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id ||
        oldWidget.item.artUri != widget.item.artUri) {
      _previousItem = oldWidget.item;
      _currentItem = widget.item;

      // Récupération instantanée des couleurs de l'album (0 ms de freeze)
      final newColors = _getInitialColors(widget.item);
      _applyNewColors(newColors);

      // Raffinement asynchrone non-bloquant
      _refineColorsAsync(widget.item);
    }
  }

  List<Color> _getInitialColors(MediaItem item) {
    final cacheKey = item.artUri?.toString() ?? item.id;
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
    final cacheKey = item.artUri?.toString() ?? item.id;
    if (_colorCache.containsKey(cacheKey)) return;

    // Exécution en tâche de fond pour ne jamais bloquer le clic ou l'UI
    scheduleMicrotask(() async {
      if (!mounted) return;
      try {
        final imageProvider = getLocalOrNetworkImageProvider(item);
        final palette = await PaletteGenerator.fromImageProvider(
          imageProvider,
          size: const Size(32, 32), // Échantillon ultra-léger pour 0 freeze
          maximumColorCount: 4,
        );

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
    setState(() {
      final currentProgress = _fadeController.value;
      _previousColors = [
        Color.lerp(_previousColors[0], _targetColors[0], currentProgress)!,
        Color.lerp(_previousColors[1], _targetColors[1], currentProgress)!,
        Color.lerp(_previousColors[2], _targetColors[2], currentProgress)!,
      ];
      _targetColors = newColors;
    });
    _fadeController.forward(from: 0.0);
  }

  void _onBatterySaverChanged() {
    _syncAnimation();
  }

  void _syncAnimation() {
    if (!mounted) return;
    final isBatterySaver = isBatterySaverEnabledNotifier.value;
    final isPlaying = globalAudioHandler.playbackState.value.playing;
    final shouldAnimate = !isBatterySaver && isPlaying && _isForeground;

    if (shouldAnimate) {
      if (!_liquidController.isAnimating) {
        _liquidController.repeat();
      }
    } else {
      if (_liquidController.isAnimating) {
        _liquidController.stop();
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
    WidgetsBinding.instance.removeObserver(this);
    _playbackSub?.cancel();
    isBatterySaverEnabledNotifier.removeListener(_onBatterySaverChanged);
    _liquidController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  Widget _buildAmbientCover(MediaItem? item) {
    if (item == null) return const SizedBox.shrink();
    return RepaintBoundary(
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(
          sigmaX: 32,
          sigmaY: 32,
          tileMode: TileMode.mirror,
        ),
        child: SizedBox.expand(
          child: Image(
            image: getLocalOrNetworkImageProvider(item),
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
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: Listenable.merge([_liquidController, _fadeController]),
        builder: (context, child) {
          final fadeProgress = CurvedAnimation(
            parent: _fadeController,
            curve: Curves.easeInOutCubic,
          ).value;

          final c1 = Color.lerp(_previousColors[0], _targetColors[0], fadeProgress)!;
          final c2 = Color.lerp(_previousColors[1], _targetColors[1], fadeProgress)!;
          final c3 = Color.lerp(_previousColors[2], _targetColors[2], fadeProgress)!;

          // Paramétrage temporel fluide continu
          final t = _liquidController.value * 2 * math.pi;

          // Orbe 1 : Évolution orbitale haute (ne passe jamais au centre)
          final r1 = 0.42 + 0.18 * math.sin(t * 0.8);
          final theta1 = t * 0.7 + (math.pi / 4);
          final x1 = r1 * math.cos(theta1);
          final y1 = r1 * math.sin(theta1) * 0.85 - 0.18;

          // Orbe 2 : Évolution orbitale basse en contre-mouvement (ne passe jamais au centre)
          final r2 = 0.46 + 0.16 * math.cos(t * 0.9);
          final theta2 = -t * 0.6 + (5 * math.pi / 4);
          final x2 = r2 * math.cos(theta2);
          final y2 = r2 * math.sin(theta2) * 0.85 + 0.18;

          // Dérive physique de la pochette : trajectoire orbitale errante (rayon non-nul garanti)
          // Ne revient JAMAIS au milieu (0,0), flotte de manière continue et vivante
          final driftRadius = 20.0 + 12.0 * math.sin(t * 0.6 + 0.5); // Toujours entre 8 et 32 px
          final driftAngle = t * 0.75 + 0.35 * math.sin(t * 1.6);
          final driftDx = driftRadius * math.cos(driftAngle);
          final driftDy = driftRadius * math.sin(driftAngle) * 1.35; // Élongation portrait naturelle
          final driftScale = 1.16 + math.sin(t * 0.5 + 1.2) * 0.035;

          return Stack(
            fit: StackFit.expand,
            children: [
              // 1. Fond sombre de base ancré dans la palette de l'album
              Container(color: c3),

              // 2. Vraie pochette de l'album floutée avec dérive physique fluide (mise en cache GPU VRAM sans recalcul de flou)
              Transform.translate(
                offset: Offset(driftDx, driftDy),
                child: Transform.scale(
                  scale: driftScale,
                  alignment: Alignment.center,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (_previousItem != null && fadeProgress < 1.0)
                        Opacity(
                          opacity: (1.0 - fadeProgress).clamp(0.0, 1.0),
                          child: _buildAmbientCover(_previousItem),
                        ),
                      if (_currentItem != null)
                        Opacity(
                          opacity: fadeProgress.clamp(0.0, 1.0),
                          child: _buildAmbientCover(_currentItem),
                        ),
                    ],
                  ),
                ),
              ),

              // 3. Orbe liquide animé 1 (lueur vibrante Apple Music en orbite)
              Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(x1, y1),
                    radius: 1.3,
                    colors: [
                      c1.withValues(alpha: 0.65),
                      c1.withValues(alpha: 0.20),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.55, 1.0],
                  ),
                ),
              ),

              // 4. Orbe liquide animé 2 (lueur dominante en contre-orbite)
              Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(x2, y2),
                    radius: 1.4,
                    colors: [
                      c2.withValues(alpha: 0.60),
                      c2.withValues(alpha: 0.15),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.60, 1.0],
                  ),
                ),
              ),

              // 5. Voile sombre translucide pour garantir la lisibilité et le contraste
              Container(
                color: Colors.black.withValues(alpha: 0.32),
              ),
            ],
          );
        },
      ),
    );
  }
}
