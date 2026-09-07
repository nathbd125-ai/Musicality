import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
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

    return GlassContainer(
      useOwnLayer: true,
      settings: const LiquidGlassSettings(fresnelStrength: 0.0),
      shape: LiquidRoundedSuperellipse(borderRadius: currentRadius),
      child: AnimatedContainer(
        duration: widget.duration,
        curve: widget.curve,
        child: widget.child,
      ),
    );
  }
}
