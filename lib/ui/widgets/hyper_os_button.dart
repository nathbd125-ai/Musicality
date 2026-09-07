import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:musicality/core/globals.dart';

class HyperOSButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final double padding;
  final bool isPlayPause;

  const HyperOSButton({
    super.key,
    required this.child,
    required this.onTap,
    this.padding = 4.0,
    this.isPlayPause = false,
  });

  @override
  State<HyperOSButton> createState() => _HyperOSButtonState();
}

class _HyperOSButtonState extends State<HyperOSButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
      lowerBound: 0.85,
      upperBound: 1.0,
    )..value = 1.0;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _controller.animateTo(0.85, curve: Curves.easeInOut),
      onTapUp: (_) {
        _controller.animateTo(1.0, curve: Curves.easeInOut);
        if (isHapticFeedbackEnabledNotifier.value) {
          if (widget.isPlayPause) {
            HapticFeedback.mediumImpact();
          } else {
            HapticFeedback.lightImpact();
          }
        }
        widget.onTap();
      },
      onTapCancel: () => _controller.animateTo(1.0, curve: Curves.easeInOut),
      child: Padding(
        padding: EdgeInsets.all(widget.padding),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Transform.scale(
              scale: _controller.value,
              child: widget.child,
            );
          },
        ),
      ),
    );
  }
}
