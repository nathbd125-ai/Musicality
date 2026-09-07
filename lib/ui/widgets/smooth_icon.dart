import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class SmoothIcon extends StatelessWidget {
  final IconData icon;
  final double size;
  final Color color;

  const SmoothIcon({
    super.key,
    required this.icon,
    required this.size,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 410),
      curve: Curves.fastOutSlowIn,
      tween: Tween<double>(end: size),
      builder: (context, animatedSize, child) {
        return Icon(icon, color: color, size: animatedSize);
      },
    );
  }
}
