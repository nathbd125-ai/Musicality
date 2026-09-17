import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:musicality/core/globals.dart';
import 'package:musicality/ui/player/agsl_slider_glass.dart';

class HyperOSSlider extends StatefulWidget {
  final Duration position;
  final Duration duration;
  final Function(Duration) onSeek;
  final List<Color> gradientColors;
  final bool showMilliseconds;

  const HyperOSSlider({
    super.key,
    required this.position,
    required this.duration,
    required this.onSeek,
    required this.gradientColors,
    this.showMilliseconds = false,
  });

  @override
  State<HyperOSSlider> createState() => _HyperOSSliderState();
}

class _HyperOSSliderState extends State<HyperOSSlider>
    with TickerProviderStateMixin {
  double? _dragValue;
  double _baseMsForDrag = 0.0;
  bool _isInteracting = false;
  bool _hasDragStarted = false;

  // Bloqué à la demande de l'utilisateur pour garantir 0% de charge GPU/CPU
  static const bool _forceDisableSliderLiquidGlass = true;

  late final AnimationController _pressController;
  late final Animation<double> _pressAnimation;
  final GlobalKey _trackKey = GlobalKey();
  Offset? _cachedTrackOffset;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 240),
      vsync: this,
    );
    _pressAnimation = CurvedAnimation(
      parent: _pressController,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeInOutCubic,
    );
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  void _onTapDown(Offset localPosition, double width, double maxMs) {
    if (width <= 0) return;
    _isInteracting = true;
    _pressController.forward();
    final double tapX = localPosition.dx.clamp(0.0, width);
    final double newMs = (tapX / width) * maxMs;
    setState(() {
      _dragValue = newMs;
    });
    widget.onSeek(Duration(milliseconds: newMs.toInt()));
  }

  void _onDragStart(double maxMs) {
    _hasDragStarted = true;
    _isInteracting = true;
    _pressController.forward();
    _baseMsForDrag =
        (_dragValue ?? widget.position.inMilliseconds.toDouble()).clamp(0.0, maxMs);
    setState(() {
      _dragValue = _baseMsForDrag;
    });
  }

  void _onDragUpdate(double deltaX, double width, double maxMs) {
    if (width <= 0) return;
    final double deltaMs = (deltaX / width) * maxMs;
    final double currentMs = (_dragValue ?? _baseMsForDrag);
    final double newMs = (currentMs + deltaMs).clamp(0.0, maxMs);

    setState(() {
      _dragValue = newMs;
    });
  }

  void _onInteractionEnd() async {
    if (_dragValue != null) {
      widget.onSeek(Duration(milliseconds: _dragValue!.toInt()));
    }
    _isInteracting = false;
    _hasDragStarted = false;
    _pressController.reverse();
    await Future.delayed(const Duration(milliseconds: 100));
    if (mounted && !_isInteracting) {
      setState(() {
        _dragValue = null;
      });
    }
  }

  void _onInteractionCancel() {
    _isInteracting = false;
    _hasDragStarted = false;
    _pressController.reverse();
    setState(() {
      _dragValue = null;
    });
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) {
      return n.toString().padLeft(2, "0");
    }

    final mins = twoDigits(duration.inMinutes.remainder(60));
    final secs = twoDigits(duration.inSeconds.remainder(60));

    if (widget.showMilliseconds) {
      final ms = (duration.inMilliseconds.remainder(1000))
          .toString()
          .padLeft(3, "0");
      return "$mins:$secs.$ms";
    }

    return "$mins:$secs";
  }

  Widget _buildLiquidGlassThumb({
    required double width,
    required double height,
    required double pressVal,
    required Color primaryColor,
    required bool isLiquidGlass,
    required Offset? thumbOffset,
  }) {
    if (!isLiquidGlass) {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.white.withValues(alpha: 0.8),
              blurRadius: 6,
              spreadRadius: 1,
            ),
          ],
        ),
      );
    }

    final borderRadius = height / 2;
    // Hide the white circle as soon as interaction begins
    final double whiteCircleOpacity =
        isLiquidGlass ? (1.0 - pressVal * 3.0).clamp(0.0, 1.0) : 1.0;

    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // 1. Dynamic ambient glow behind the thumb in liquid glass mode
          if (isLiquidGlass && pressVal > 0.05)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(borderRadius),
                  boxShadow: [
                    BoxShadow(
                      color: primaryColor.withValues(alpha: 0.45 * pressVal),
                      blurRadius: 22 * pressVal,
                      spreadRadius: 1.5 * pressVal,
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25 * pressVal),
                      blurRadius: 8 * pressVal,
                      offset: Offset(0, 3 * pressVal),
                    ),
                  ],
                ),
              ),
            ),

          // 2. Liquid Glass frosted capsule using dedicated slider_glass AGSL shader
          if (isLiquidGlass && pressVal > 0.01)
            Positioned.fill(
              child: AGSLSliderGlass(
                cornerRadius: borderRadius,
                distance: 12.0 * pressVal,
                blurSigma: 16.0 * pressVal,
                offset: thumbOffset,
                child: Container(
                  width: width,
                  height: height,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(borderRadius),
                    color: Colors.black.withValues(alpha: 0.08 * pressVal),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.25 * pressVal),
                      width: 1.0,
                    ),
                  ),
                ),
              ),
            ),

          // 3. White circle: visible when idle, completely hidden when interacting
          if (whiteCircleOpacity > 0.0)
            Opacity(
              opacity: whiteCircleOpacity,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.8),
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double maxMs = widget.duration.inMilliseconds.toDouble() == 0.0
        ? 1.0
        : widget.duration.inMilliseconds.toDouble();
    final double currentMs = (_dragValue != null)
        ? _dragValue!
        : widget.position.inMilliseconds.toDouble();
    final double pct = (currentMs / maxMs).clamp(0.0, 1.0);

    final List<Color> colors = widget.gradientColors.isNotEmpty
        ? widget.gradientColors
        : const [Colors.white, Colors.grey];
    final Color primaryColor = colors[0];

    return RepaintBoundary(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (details) {
          final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
          if (renderBox == null) return;
          _onTapDown(details.localPosition, renderBox.size.width, maxMs);
        },
        onTapUp: (details) {
          _onInteractionEnd();
        },
        onTapCancel: () {
          if (!_hasDragStarted) {
            _onInteractionCancel();
          }
        },
        onHorizontalDragStart: (details) {
          _onDragStart(maxMs);
        },
        onHorizontalDragUpdate: (details) {
          final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
          if (renderBox == null) return;
          _onDragUpdate(details.delta.dx, renderBox.size.width, maxMs);
        },
        onHorizontalDragEnd: (details) {
          _onInteractionEnd();
        },
        onHorizontalDragCancel: () {
          _onInteractionCancel();
        },
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final activeWidth = width * pct;

                  return ListenableBuilder(
                    listenable: _forceDisableSliderLiquidGlass
                        ? const AlwaysStoppedAnimation(0)
                        : Listenable.merge([
                            _pressAnimation,
                            isLiquidGlassEnabledNotifier,
                            isBatterySaverEnabledNotifier,
                          ]),
                    builder: (context, _) {
                      final bool isLiquidGlass = !_forceDisableSliderLiquidGlass &&
                          isLiquidGlassEnabledNotifier.value &&
                          !isBatterySaverEnabledNotifier.value;

                      final pressVal =
                          isLiquidGlass ? _pressAnimation.value : 0.0;
                      final trackHeight = ui.lerpDouble(4.0, 7.0, pressVal)!;
                      final trackRadius = trackHeight / 2;

                      // Thumb base dimensions:
                      // In Liquid Glass mode: expands ~10x (from 10x10 to 84x38 capsule!)
                      // Otherwise: remains classic 10x10
                      final baseThumbWidth = isLiquidGlass
                          ? ui.lerpDouble(10.0, 84.0, pressVal)!
                          : 10.0;
                      final baseThumbHeight = isLiquidGlass
                          ? ui.lerpDouble(10.0, 38.0, pressVal)!
                          : 10.0;

                      // Dynamic squash & stretch (uniquement si Liquid Glass actif)
                      const double velocity = 0.0;
                      final double stretchFactor =
                          (isLiquidGlass && _isInteracting)
                              ? (velocity * 0.08).clamp(0.0, 0.35)
                              : 0.0;
                      final currentThumbWidth =
                          baseThumbWidth * (1.0 + stretchFactor);
                      final currentThumbHeight =
                          baseThumbHeight * (1.0 - stretchFactor * 0.25);

                      final thumbLeft = (activeWidth - currentThumbWidth / 2)
                          .clamp(0.0, width - currentThumbWidth);
                      final thumbTop = (trackHeight - currentThumbHeight) / 2;

                      // Synchronous global offset calculation for AGSLSliderGlass shader (uniquement si Liquid Glass)
                      Offset? thumbOffset;
                      if (isLiquidGlass) {
                        final RenderBox? trackBox =
                            _trackKey.currentContext?.findRenderObject() as RenderBox?;
                        if (trackBox != null && trackBox.hasSize && trackBox.attached) {
                          _cachedTrackOffset = trackBox.localToGlobal(Offset.zero);
                        }
                        if (_cachedTrackOffset != null) {
                          thumbOffset = Offset(
                            _cachedTrackOffset!.dx + thumbLeft,
                            _cachedTrackOffset!.dy + thumbTop,
                          );
                        }
                      }

                      return Stack(
                        key: _trackKey,
                        alignment: Alignment.centerLeft,
                        clipBehavior: Clip.none,
                        children: [
                          // Inactive track (background)
                          Container(
                            width: width,
                            height: trackHeight,
                            decoration: BoxDecoration(
                              color: const Color(0xFF2C2C2C),
                              borderRadius:
                                  BorderRadius.circular(trackRadius),
                            ),
                          ),
                          // Glowing shadow behind active track
                          if (activeWidth > 0)
                            Container(
                              width: activeWidth,
                              height: trackHeight,
                              decoration: BoxDecoration(
                                borderRadius:
                                    BorderRadius.circular(trackRadius),
                                boxShadow: [
                                  BoxShadow(
                                    color: primaryColor.withValues(
                                      alpha: ui.lerpDouble(
                                          0.8, 0.9, pressVal)!,
                                    ),
                                    blurRadius: ui.lerpDouble(
                                        12.0, 18.0, pressVal)!,
                                    spreadRadius: ui.lerpDouble(
                                        2.0, 3.5, pressVal)!,
                                  ),
                                  BoxShadow(
                                    color: primaryColor.withValues(
                                      alpha: ui.lerpDouble(
                                          0.5, 0.65, pressVal)!,
                                    ),
                                    blurRadius: ui.lerpDouble(
                                        24.0, 32.0, pressVal)!,
                                    spreadRadius: ui.lerpDouble(
                                        4.0, 6.0, pressVal)!,
                                  ),
                                ],
                              ),
                            ),
                          // Active track (gradient)
                          if (activeWidth > 0)
                            Container(
                              width: activeWidth,
                              height: trackHeight,
                              decoration: BoxDecoration(
                                borderRadius:
                                    BorderRadius.circular(trackRadius),
                                gradient: LinearGradient(
                                  colors: colors,
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                ),
                              ),
                            ),
                          // Liquid Glass Thumb (Apple Music style with AGSLSliderGlass)
                          Positioned(
                            left: thumbLeft,
                            top: thumbTop,
                            child: _buildLiquidGlassThumb(
                              width: currentThumbWidth,
                              height: currentThumbHeight,
                              pressVal: pressVal,
                              primaryColor: primaryColor,
                              isLiquidGlass: isLiquidGlass,
                              thumbOffset: thumbOffset,
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatDuration(Duration(milliseconds: currentMs.toInt())),
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: widget.showMilliseconds ? 11.5 : 11,
                    fontFamily: widget.showMilliseconds ? 'monospace' : null,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    fontWeight: widget.showMilliseconds
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
                Text(
                  _formatDuration(widget.duration),
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: widget.showMilliseconds ? 11.5 : 11,
                    fontFamily: widget.showMilliseconds ? 'monospace' : null,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    fontWeight: widget.showMilliseconds
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

