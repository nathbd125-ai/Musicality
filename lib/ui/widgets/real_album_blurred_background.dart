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

    // Animation très lente en boucle continue (effet liquide fluide sans saccade)
    _liquidController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 16),
      value: math.Random().nextDouble(),
    );

    // Transition fluide entre pochettes lors d'un changement de musique
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      value: 1.0,
    );

    _playbackSub = globalAudioHandler.playbackState.listen((_) {
      _syncAnimation();
    });
    isBatterySaverEnabledNotifier.addListener(_onBatterySaverChanged);

    _extractAndSetColors(widget.item);
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant RealAlbumBlurredBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id ||
        oldWidget.item.artUri != widget.item.artUri) {
      _extractAndSetColors(widget.item);
    }
  }

  Future<void> _extractAndSetColors(MediaItem item) async {
    final cacheKey = item.artUri?.toString() ?? item.id;
    if (_colorCache.containsKey(cacheKey)) {
      _applyNewColors(_colorCache[cacheKey]!);
      return;
    }

    try {
      final imageProvider = getLocalOrNetworkImageProvider(item);
      final palette = await PaletteGenerator.fromImageProvider(
        imageProvider,
        size: const Size(64, 64), // Réduit la zone d'analyse pour un calcul instantané (<5ms)
        maximumColorCount: 4,
      );

      final dominant = palette.dominantColor?.color;
      final vibrant = palette.vibrantColor?.color ??
          palette.lightVibrantColor?.color ??
          dominant;
      final darkMuted = palette.darkMutedColor?.color ??
          palette.mutedColor?.color ??
          const Color(0xFF0E0E14);

      final c1 = vibrant ?? const Color(0xFF2E1B4E);
      final c2 = dominant ?? const Color(0xFF181C2B);
      final c3 = darkMuted;

      final colors = [c1, c2, c3];
      _colorCache[cacheKey] = colors;
      if (mounted) {
        _applyNewColors(colors);
      }
    } catch (e) {
      debugPrint('PaletteGenerator extraction error: $e');
    }
  }

  void _applyNewColors(List<Color> newColors) {
    if (!mounted) return;
    setState(() {
      // Démarre la transition depuis les couleurs actuelles
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

          // Positions liquides orbitales très douces et organiques (façon Apple Music)
          final t = _liquidController.value * 2 * math.pi;
          final x1 = math.sin(t) * 0.55;
          final y1 = math.cos(t * 0.7) * 0.45;
          final x2 = -math.cos(t * 0.8) * 0.50;
          final y2 = -math.sin(t * 0.6) * 0.45;

          return Stack(
            fit: StackFit.expand,
            children: [
              // 1. Fond sombre de base ancré dans la palette de l'album
              Container(color: c3),

              // 2. Bulle radiale liquide 1 (couleur vibrante principale)
              Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(x1, y1),
                    radius: 1.4,
                    colors: [
                      c1.withValues(alpha: 0.85),
                      c1.withValues(alpha: 0.35),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.55, 1.0],
                  ),
                ),
              ),

              // 3. Bulle radiale liquide 2 en contre-mouvement (couleur dominante)
              Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(x2, y2),
                    radius: 1.5,
                    colors: [
                      c2.withValues(alpha: 0.80),
                      c2.withValues(alpha: 0.25),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.60, 1.0],
                  ),
                ),
              ),

              // 4. Voile sombre translucide pour garantir la lisibilité et le contraste
              Container(
                color: Colors.black.withValues(alpha: 0.25),
              ),
            ],
          );
        },
      ),
    );
  }
}
