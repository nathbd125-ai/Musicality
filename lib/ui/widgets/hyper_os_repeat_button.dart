import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:musicality/core/globals.dart';

class HyperOSRepeatButton extends StatefulWidget {
  final LoopMode loopMode;
  final VoidCallback onTap;
  final List<Color> gradientColors;
  final double size;

  const HyperOSRepeatButton({
    super.key,
    required this.loopMode,
    required this.onTap,
    required this.gradientColors,
    required this.size,
  });

  @override
  State<HyperOSRepeatButton> createState() => _HyperOSRepeatButtonState();
}

class _HyperOSRepeatButtonState extends State<HyperOSRepeatButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _scaleController;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
      lowerBound: 0.85,
      upperBound: 1.0,
    )..value = 1.0;
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 410),
      curve: Curves.fastOutSlowIn,
      tween: Tween<double>(end: widget.size),
      builder: (context, animatedSize, child) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) {
            _scaleController.animateTo(0.85, curve: Curves.easeInOut);
          },
          onTapUp: (_) {
            _scaleController.animateTo(1.0, curve: Curves.easeInOut);
            if (isHapticFeedbackEnabledNotifier.value) {
              HapticFeedback.lightImpact();
            }
            widget.onTap();
          },
          onTapCancel: () {
            _scaleController.animateTo(1.0, curve: Curves.easeInOut);
          },
          child: AnimatedBuilder(
            animation: _scaleController,
            builder: (context, child) {
              return Transform.scale(
                scale: _scaleController.value,
                child: child,
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(4.0),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                transitionBuilder: (child, animation) {
                  return FadeTransition(opacity: animation, child: child);
                },
                child: widget.loopMode == LoopMode.off
                    ? Icon(
                        key: const ValueKey('loop_off'),
                        CupertinoIcons.repeat,
                        color: Colors.white.withValues(alpha: 0.55),
                        size: animatedSize,
                      )
                    : (widget.loopMode == LoopMode.all
                        ? ShaderMask(
                            key: const ValueKey('loop_all'),
                            blendMode: BlendMode.srcIn,
                            shaderCallback: (bounds) {
                              return LinearGradient(
                                colors: widget.gradientColors,
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                              ).createShader(bounds);
                            },
                            child: Icon(
                              CupertinoIcons.repeat,
                              size: animatedSize,
                            ),
                          )
                        : ShaderMask(
                            key: const ValueKey('loop_one'),
                            blendMode: BlendMode.srcIn,
                            shaderCallback: (bounds) {
                              return LinearGradient(
                                colors: widget.gradientColors,
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                              ).createShader(bounds);
                            },
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Icon(
                                  CupertinoIcons.repeat,
                                  size: animatedSize,
                                ),
                                Transform.translate(
                                  offset: const Offset(0, 0),
                                  child: Text(
                                    '1',
                                    style: TextStyle(
                                      fontSize: animatedSize * 0.25,
                                      fontWeight: FontWeight.w900,
                                      decoration: TextDecoration.none,
                                      color: Colors.white,
                                      height: 1.0,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )),
              ),
            ),
          ),
        );
      },
    );
  }
}
