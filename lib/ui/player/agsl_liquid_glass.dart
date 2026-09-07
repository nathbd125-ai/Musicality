import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class AGSLLiquidGlass extends StatefulWidget {
  final Widget child;
  final double distortionStrength;
  final double chromaticAberration;
  final double blurSigma;
  final bool enabled;

  const AGSLLiquidGlass({
    super.key,
    required this.child,
    this.distortionStrength = 0.02,
    this.chromaticAberration = 0.005,
    this.blurSigma = 20.0,
    this.enabled = true,
  });

  @override
  State<AGSLLiquidGlass> createState() => _AGSLLiquidGlassState();
}

class _AGSLLiquidGlassState extends State<AGSLLiquidGlass>
    with SingleTickerProviderStateMixin {
  ui.FragmentProgram? _program;
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();
    _loadShader();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadShader() async {
    try {
      final program = await ui.FragmentProgram.fromAsset(
        'shaders/liquid_glass.frag',
      );
      if (mounted) {
        setState(() {
          _program = program;
        });
      }
    } catch (e) {
      debugPrint("Failed to load liquid glass shader: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_program == null || !widget.enabled) {
      return ClipRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(
            sigmaX: widget.blurSigma,
            sigmaY: widget.blurSigma,
          ),
          child: widget.child,
        ),
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final shader = _program!.fragmentShader();

        // 1) The first uniform is a vec2 for the texture size.
        // We MUST initialize the float array with at least 2 values to satisfy Flutter's ImageFilter.shader check.
        shader.setFloat(
          0,
          0.0,
        ); // Will be overwritten by engine with texture width
        shader.setFloat(
          1,
          0.0,
        ); // Will be overwritten by engine with texture height

        // 2) Custom uniforms
        shader.setFloat(2, widget.distortionStrength);
        shader.setFloat(3, widget.chromaticAberration);
        shader.setFloat(4, DateTime.now().millisecondsSinceEpoch / 1000.0);

        // Compose: First blur the background, then distort it with our shader!
        // (Or vice-versa, but blurring first usually looks better for liquid glass)
        final compositeFilter = ui.ImageFilter.compose(
          outer: ui.ImageFilter.shader(shader),
          inner: ui.ImageFilter.blur(
            sigmaX: widget.blurSigma,
            sigmaY: widget.blurSigma,
          ),
        );

        return ClipRect(
          child: BackdropFilter(filter: compositeFilter, child: widget.child),
        );
      },
    );
  }
}
