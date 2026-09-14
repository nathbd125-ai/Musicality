import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:musicality/core/globals.dart';
import 'package:musicality/ui/player/agsl_rhombus_glass.dart';

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
  bool _isInteracting = false;
  bool _hasDragStarted = false;

  late final AnimationController _pressController;
  late final Animation<double> _pressAnimation;
  late final SingleSpringController _springController;

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

    final double maxMs = widget.duration.inMilliseconds.toDouble() == 0.0
        ? 1.0
        : widget.duration.inMilliseconds.toDouble();
    final double initialPct =
        (widget.position.inMilliseconds.toDouble() / maxMs).clamp(0.0, 1.0);

    _springController = SingleSpringController(
      vsync: this,
      spring: GlassSpring.snappy(
        duration: const Duration(milliseconds: 300),
      ),
      initialValue: initialPct,
    );
  }

  @override
  void didUpdateWidget(HyperOSSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isInteracting) {
      final double maxMs = widget.duration.inMilliseconds.toDouble() == 0.0
          ? 1.0
          : widget.duration.inMilliseconds.toDouble();
      final double pct =
          (widget.position.inMilliseconds.toDouble() / maxMs).clamp(0.0, 1.0);
      _springController.setValue(pct);
    }
  }

  @override
  void dispose() {
    _pressController.dispose();
    _springController.dispose();
    super.dispose();
  }

  void _onInteractionStart(Offset localPosition, double width, double maxMs) {
    HapticFeedback.lightImpact();
    _isInteracting = true;
    _pressController.forward();
    if (width > 0) {
      final double tapX = localPosition.dx.clamp(0.0, width);
      final double newMs = (tapX / width) * maxMs;
      final double normalizedX = (tapX / width).clamp(0.0, 1.0);
      setState(() {
        _dragValue = newMs;
      });
      _springController.animateTo(normalizedX);
    }
  }

  void _onInteractionUpdate(Offset localPosition, double width, double maxMs) {
    if (width <= 0) return;
    final double currentX = localPosition.dx.clamp(0.0, width);
    final double newMs = (currentX / width) * maxMs;
    final double normalizedX = (currentX / width).clamp(0.0, 1.0);

    _springController.animateTo(normalizedX);
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
          // Ambient colored glow behind the thumb lens (Liquid Glass mode only)
          if (isLiquidGlass && pressVal > 0.05)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(borderRadius),
                  boxShadow: [
                    BoxShadow(
                      color: primaryColor.withValues(alpha: 0.4 * pressVal),
                      blurRadius: 24 * pressVal,
                      spreadRadius: 2 * pressVal,
                    ),
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.2 * pressVal),
                      blurRadius: 14 * pressVal,
                      spreadRadius: 1 * pressVal,
                    ),
                  ],
                ),
              ),
            ),

          // Mini-player's exact shader: AGSLRhombusGlass
          if (isLiquidGlass && pressVal > 0.01)
            Positioned.fill(
              child: AGSLRhombusGlass(
                enabled: true,
                cornerRadius: borderRadius,
                distance: 15.0,
                blurSigma: 16.0,
                offset: thumbOffset,
                child: Container(
                  width: width,
                  height: height,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.08 * pressVal),
                    borderRadius: BorderRadius.circular(borderRadius),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.35 * pressVal),
                      width: 1.0,
                    ),
                  ),
                ),
              ),
            ),

          // White circle: visible when idle, completely hidden when interacting
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
          _onInteractionStart(details.localPosition, renderBox.size.width, maxMs);
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
          _hasDragStarted = true;
          final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
          if (renderBox == null) return;
          _onInteractionStart(details.localPosition, renderBox.size.width, maxMs);
        },
        onHorizontalDragUpdate: (details) {
          final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
          if (renderBox == null) return;
          _onInteractionUpdate(details.localPosition, renderBox.size.width, maxMs);
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
                    listenable: Listenable.merge([
                      _pressAnimation,
                      _springController,
                      isLiquidGlassEnabledNotifier,
                      isBatterySaverEnabledNotifier,
                    ]),
                    builder: (context, _) {
                      final bool isLiquidGlass =
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

                      // Dynamic squash & stretch based on spring velocity
                      final double velocity = _springController.velocity.abs();
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

                      // Calculate global offset for AGSLRhombusGlass shader
                      final RenderBox? sliderBox =
                          context.findRenderObject() as RenderBox?;
                      Offset? thumbOffset;
                      if (sliderBox != null &&
                          sliderBox.hasSize &&
                          sliderBox.attached) {
                        final sliderGlobal = sliderBox.localToGlobal(Offset.zero);
                        thumbOffset = Offset(
                          sliderGlobal.dx + thumbLeft,
                          sliderGlobal.dy + 6.0 + thumbTop,
                        );
                      }

                      return Stack(
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
                          // Liquid Glass Thumb (Apple Music style / AGSLRhombusGlass)
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

