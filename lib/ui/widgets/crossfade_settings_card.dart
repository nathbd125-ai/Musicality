import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:musicality/core/globals.dart';

class CrossfadeSettingsCard extends StatelessWidget {
  final List<Color> dynamicGradientColors;

  const CrossfadeSettingsCard({
    super.key,
    required this.dynamicGradientColors,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                CupertinoIcons.waveform_path,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 16),
            const Expanded(
              child: Text(
                "Fondu enchaîné",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            ValueListenableBuilder<bool>(
              valueListenable: isCrossfadeEnabledNotifier,
              builder: (context, isCrossfadeEnabled, _) {
                return CupertinoSwitch(
                  value: isCrossfadeEnabled,
                  activeTrackColor: dynamicGradientColors[0],
                  onChanged: (val) {
                    isCrossfadeEnabledNotifier.value = val;
                  },
                );
              },
            ),
          ],
        ),
        ValueListenableBuilder<bool>(
          valueListenable: isCrossfadeEnabledNotifier,
          builder: (context, isCrossfadeEnabled, _) {
            if (!isCrossfadeEnabled) return const SizedBox();
            return Padding(
              padding: const EdgeInsets.only(top: 20),
              child: ValueListenableBuilder<int>(
                valueListenable: crossfadeDurationNotifier,
                builder: (context, crossfadeSecs, _) {
                  final badgeColors = dynamicGradientColors.length >= 2
                      ? dynamicGradientColors.take(2).toList()
                      : [dynamicGradientColors[0], dynamicGradientColors[0]];
                  final avgLuminance =
                      badgeColors
                          .map((c) => c.computeLuminance())
                          .reduce((a, b) => a + b) /
                      badgeColors.length;
                  final badgeTextColor =
                      avgLuminance > 0.55
                          ? const Color(0xFF1E1E1E)
                          : Colors.white;

                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.05),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              "Durée de la transition",
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: badgeColors,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                "$crossfadeSecs s",
                                style: TextStyle(
                                  color: badgeTextColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 6,
                            activeTrackColor: Colors.transparent,
                            inactiveTrackColor: Colors.white.withValues(
                              alpha: 0.1,
                            ),
                            thumbColor: Colors.white,
                            overlayColor: dynamicGradientColors[0].withValues(
                              alpha: 0.2,
                            ),
                            trackShape: GradientSliderTrackShape(
                              gradient: LinearGradient(
                                colors: dynamicGradientColors,
                              ),
                            ),
                          ),
                          child: Slider(
                            value: crossfadeSecs.toDouble(),
                            min: 1.0,
                            max: 12.0,
                            divisions: 11,
                            onChanged: (val) {
                              final newSecs = val.round();
                              if (newSecs != crossfadeSecs) {
                                if (isHapticFeedbackEnabledNotifier.value) {
                                  HapticFeedback.selectionClick();
                                }
                                crossfadeDurationNotifier.value = newSecs;
                              }
                            },
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: const [
                            Text(
                              "1 s",
                              style: TextStyle(
                                color: Colors.white38,
                                fontSize: 11,
                              ),
                            ),
                            Text(
                              "12 s",
                              style: TextStyle(
                                color: Colors.white38,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }
}

class GradientSliderTrackShape extends RoundedRectSliderTrackShape {
  final LinearGradient gradient;

  const GradientSliderTrackShape({required this.gradient});

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
  }) {
    if (sliderTheme.trackHeight == null || sliderTheme.trackHeight! <= 0) {
      return;
    }

    final Rect trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );

    final activeRect = Rect.fromLTRB(
      trackRect.left,
      trackRect.top,
      thumbCenter.dx,
      trackRect.bottom,
    );

    final inactiveRect = Rect.fromLTRB(
      thumbCenter.dx,
      trackRect.top,
      trackRect.right,
      trackRect.bottom,
    );

    final Paint activePaint = Paint()
      ..shader = gradient.createShader(trackRect);

    final Paint inactivePaint = Paint()
      ..color = sliderTheme.inactiveTrackColor ?? Colors.white12;

    final trackRadius = Radius.circular(trackRect.height / 2);

    if (activeRect.width > 0) {
      context.canvas.drawRRect(
        RRect.fromRectAndCorners(
          activeRect,
          topLeft: trackRadius,
          bottomLeft: trackRadius,
          topRight: inactiveRect.width <= 0 ? trackRadius : Radius.zero,
          bottomRight: inactiveRect.width <= 0 ? trackRadius : Radius.zero,
        ),
        activePaint,
      );
    }

    if (inactiveRect.width > 0) {
      context.canvas.drawRRect(
        RRect.fromRectAndCorners(
          inactiveRect,
          topRight: trackRadius,
          bottomRight: trackRadius,
          topLeft: activeRect.width <= 0 ? trackRadius : Radius.zero,
          bottomLeft: activeRect.width <= 0 ? trackRadius : Radius.zero,
        ),
        inactivePaint,
      );
    }
  }
}
