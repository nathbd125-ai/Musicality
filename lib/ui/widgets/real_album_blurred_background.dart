import 'dart:ui';
import 'dart:math' as math;
import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:musicality/core/globals.dart';
import 'package:flutter/material.dart';

class RealAlbumBlurredBackground extends StatefulWidget {
  final MediaItem item;
  const RealAlbumBlurredBackground({super.key, required this.item});

  @override
  State<RealAlbumBlurredBackground> createState() =>
      _RealAlbumBlurredBackgroundState();
}

class _RealAlbumBlurredBackgroundState extends State<RealAlbumBlurredBackground>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _controller;
  late AnimationController _saverTransitionController;
  late Animation<double> _saverAnimation;
  Size? _fixedSize;
  StreamSubscription<PlaybackState>? _playbackSub;
  bool _isForeground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 300), // Ralenti considérablement
      value: math.Random().nextDouble(),
    );

    final initialSaver = isBatterySaverEnabledNotifier.value;
    _saverTransitionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
      value: initialSaver ? 1.0 : 0.0,
    );
    _saverAnimation = CurvedAnimation(
      parent: _saverTransitionController,
      curve: Curves.easeInOutCubic,
    );

    _playbackSub = globalAudioHandler.playbackState.listen((_) {
      _syncAnimation();
    });
    isBatterySaverEnabledNotifier.addListener(_onBatterySaverChanged);

    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        _syncAnimation();
      }
    });
  }

  void _onBatterySaverChanged() {
    if (!mounted) return;
    final isBatterySaver = isBatterySaverEnabledNotifier.value;

    if (isBatterySaver) {
      _saverTransitionController.forward().then((_) {
        if (mounted && isBatterySaverEnabledNotifier.value) {
          _controller.stop();
        }
      });
    } else {
      final isPlaying = globalAudioHandler.playbackState.value.playing;
      if (isPlaying && _isForeground && !_controller.isAnimating) {
        _controller.repeat();
      }
      _saverTransitionController.reverse();
    }
  }

  void _syncAnimation() {
    if (!mounted) return;
    final isBatterySaver = isBatterySaverEnabledNotifier.value;
    final isPlaying = globalAudioHandler.playbackState.value.playing;
    final shouldAnimate = !isBatterySaver && isPlaying && _isForeground;

    if (shouldAnimate) {
      if (!_controller.isAnimating) {
        _controller.repeat();
      }
    } else {
      if (_controller.isAnimating) {
        _controller.stop();
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_fixedSize == null) {
      final size = MediaQuery.of(context).size;
      _fixedSize = Size(size.width * 1.8, math.max(size.height * 1.8, 1500));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _playbackSub?.cancel();
    isBatterySaverEnabledNotifier.removeListener(_onBatterySaverChanged);
    _controller.dispose();
    _saverTransitionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = _fixedSize ?? MediaQuery.of(context).size * 1.8;

    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedBuilder(
          animation: Listenable.merge([_controller, _saverAnimation]),
          builder: (context, child) {
            final screen = MediaQuery.of(context).size;
            final maxDx = screen.width * 0.35;
            final maxDy = screen.height * 0.35;

            final t = _controller.value * 2 * math.pi;
            final driftScale = 1.05 + math.sin(t) * 0.05;

            final driftDx = (math.sin(t) * 0.7 + math.sin(t * 2) * 0.3) * maxDx;
            final driftDy =
                (math.cos(t + math.pi / 3) * 0.7 +
                    math.cos(t * 2 + math.pi / 4) * 0.3) *
                maxDy;

            final saverProgress = _saverAnimation.value;
            final dx = lerpDouble(driftDx, 0.0, saverProgress) ?? 0.0;
            final dy = lerpDouble(driftDy, 0.0, saverProgress) ?? 0.0;
            final scale = lerpDouble(driftScale, 1.05, saverProgress) ?? 1.05;

            return Transform.translate(
              offset: Offset(dx, dy),
              child: Transform.scale(
                scale: scale,
                alignment: Alignment.center,
                child: child,
              ),
            );
          },
          child: RepaintBoundary(
            child: OverflowBox(
              minWidth: size.width,
              maxWidth: size.width,
              minHeight: size.height,
              maxHeight: size.height,
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: size.width / 4,
                  height: size.height / 4,
                  child: RepaintBoundary(
                    child: ImageFiltered(
                      imageFilter: ImageFilter.blur(
                        sigmaX: 6,
                        sigmaY: 6,
                        tileMode: TileMode.mirror,
                      ),
                      child: getLocalOrNetworkImageSuperBlurred(widget.item),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Container(color: Colors.black.withValues(alpha: 0.15)),
      ],
    );
  }
}
