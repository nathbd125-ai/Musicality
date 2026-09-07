import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class HyperOSShuffleButton extends StatefulWidget {
  final bool isShuffle;
  final VoidCallback onTap;
  final List<Color> gradientColors;
  final double size;

  const HyperOSShuffleButton({
    super.key,
    required this.isShuffle,
    required this.onTap,
    required this.gradientColors,
    required this.size,
  });

  @override
  State<HyperOSShuffleButton> createState() => _HyperOSShuffleButtonState();
}

class _HyperOSShuffleButtonState extends State<HyperOSShuffleButton>
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
                child: widget.isShuffle
                    ? ShaderMask(
                        key: const ValueKey('shuffle_active'),
                        blendMode: BlendMode.srcIn,
                        shaderCallback: (bounds) {
                          return LinearGradient(
                            colors: widget.gradientColors,
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ).createShader(bounds);
                        },
                        child: Icon(CupertinoIcons.shuffle, size: animatedSize),
                      )
                    : Icon(
                        key: const ValueKey('shuffle_inactive'),
                        CupertinoIcons.shuffle,
                        color: Colors.white.withValues(alpha: 0.55),
                        size: animatedSize,
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}
