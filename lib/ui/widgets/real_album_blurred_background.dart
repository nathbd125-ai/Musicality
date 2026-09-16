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

  late final AnimationController _coverFadeController;
  late final AnimationController _colorFadeController;
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

    // Contrôleur de fondu de la pochette (changement de morceau)
    _coverFadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
      value: 1.0,
    );

    // Contrôleur de fondu des teintes / orbes
    _colorFadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
      value: 1.0,
    );

    // Ticker continu haute précision : le temps ne se réinitialise JAMAIS (zéro saut, zéro téléportation)
    _driftTicker = createTicker((Duration elapsed) {
      if (_lastTick != null) {
        final double dt = (elapsed - _lastTick!).inMicroseconds / 1000000.0;
        // Plafonnement de dt pour éviter tout à-coup lors de la reprise d'activité
        if (dt > 0.0 && dt < 0.1) {
          _driftTime += dt;
        }
      }
      _lastTick = elapsed;
      if (mounted) {
        setState(() {});
      }
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

      // Déclenchement propre du fondu croisé de la pochette
      _coverFadeController.forward(from: 0.0).then((_) {
        if (mounted) {
          setState(() {
            _previousItem = null;
          });
        }
      });

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
    final currentProgress = _colorFadeController.value;
    _previousColors = [
      Color.lerp(_previousColors[0], _targetColors[0], currentProgress)!,
      Color.lerp(_previousColors[1], _targetColors[1], currentProgress)!,
      Color.lerp(_previousColors[2], _targetColors[2], currentProgress)!,
    ];
    _targetColors = newColors;
    _colorFadeController.forward(from: 0.0);
  }

  void _onBatterySaverChanged() {
    _syncAnimation();
  }

  void _syncAnimation() {
    if (!mounted) return;
    final isBatterySaver = isBatterySaverEnabledNotifier.value;
    // Dérive liquide continue style Apple Music : reste vivante même en pause de lecture
    final shouldAnimate = !isBatterySaver && _isForeground;

    if (shouldAnimate) {
      if (!_driftTicker.isTicking) {
        _lastTick = null;
        _driftTicker.start();
      }
    } else {
      if (_driftTicker.isTicking) {
        _driftTicker.stop();
        _lastTick = null;
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
    final coverProgress = CurvedAnimation(
      parent: _coverFadeController,
      curve: Curves.easeInOutCubic,
    ).value;

    final colorProgress = CurvedAnimation(
      parent: _colorFadeController,
      curve: Curves.easeOutCubic,
    ).value;

    final c1 = Color.lerp(_previousColors[0], _targetColors[0], colorProgress)!;
    final c2 = Color.lerp(_previousColors[1], _targetColors[1], colorProgress)!;
    final c3 = Color.lerp(_previousColors[2], _targetColors[2], colorProgress)!;

    // Dérive continue fluide sans téléportation (temps perpétuellement croissant)
    // Harmonies multi-fréquences douces et non-périodiques (façon Apple Music)
    final driftX = math.sin(_driftTime * 0.22) * 16.0 + math.cos(_driftTime * 0.39) * 8.0;
    final driftY = math.cos(_driftTime * 0.17) * 22.0 + math.sin(_driftTime * 0.31) * 10.0;
    final driftScale = 1.15 + math.sin(_driftTime * 0.13) * 0.03;

    // Orbes liquides vibrants en orbites continues déphasées
    final orb1X = math.sin(_driftTime * 0.26) * 0.50 + math.cos(_driftTime * 0.11) * 0.15;
    final orb1Y = math.cos(_driftTime * 0.21) * 0.40 - 0.20;

    final orb2X = -math.cos(_driftTime * 0.24) * 0.45 + math.sin(_driftTime * 0.14) * 0.15;
    final orb2Y = -math.sin(_driftTime * 0.19) * 0.40 + 0.20;

    return RepaintBoundary(
      child: Stack(
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

          // 3. Orbe liquide animé 1 (lueur vibrante Apple Music en orbite)
          Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(orb1X, orb1Y),
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
                center: Alignment(orb2X, orb2Y),
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
      ),
    );
  }
}
