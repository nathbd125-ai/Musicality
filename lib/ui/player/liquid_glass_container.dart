import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class LiquidGlassContainer extends ImplicitlyAnimatedWidget {
  final Widget child;
  final double borderRadius;

  const LiquidGlassContainer({
    super.key,
    required this.child,
    this.borderRadius = 0.0,
    super.duration = const Duration(milliseconds: 300),
    super.curve = Curves.easeInOut,
  });

  @override
  AnimatedWidgetBaseState<LiquidGlassContainer> createState() =>
      _LiquidGlassContainerState();
}

class _LiquidGlassContainerState
    extends AnimatedWidgetBaseState<LiquidGlassContainer> {
  Tween<double>? _borderRadiusTween;

  @override
  void forEachTween(TweenVisitor<dynamic> visitor) {
    _borderRadiusTween =
        visitor(
              _borderRadiusTween,
              widget.borderRadius,
              (dynamic value) => Tween<double>(begin: value as double),
            )
            as Tween<double>?;
  }

  @override
  Widget build(BuildContext context) {
    final currentRadius = _borderRadiusTween?.evaluate(animation) ?? 0.0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(currentRadius),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: AnimatedContainer(
          duration: widget.duration,
          curve: widget.curve,
          child: widget.child,
        ),
      ),
    );
  }
}
