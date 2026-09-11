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
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static ui.FragmentProgram? _cachedProgram;
  late AnimationController _controller;
  late ui.ImageFilter _blurFilter;
  bool _isResumed = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    );
    if (widget.enabled) {
      _controller.repeat();
    }
    _updateBlurFilter();
    _loadShader();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isResumed = (state == AppLifecycleState.resumed);
    if (!_isResumed) {
      if (_controller.isAnimating) _controller.stop();
    } else if (widget.enabled) {
      if (!_controller.isAnimating) _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(AGSLLiquidGlass oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.blurSigma != widget.blurSigma) {
      _updateBlurFilter();
    }
    if (oldWidget.enabled != widget.enabled) {
      if (widget.enabled && _isResumed) {
        if (!_controller.isAnimating) _controller.repeat();
      } else {
        if (_controller.isAnimating) _controller.stop();
      }
    }
  }

  void _updateBlurFilter() {
    _blurFilter = ui.ImageFilter.blur(
      sigmaX: widget.blurSigma,
      sigmaY: widget.blurSigma,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadShader() async {
    if (_cachedProgram != null) return;
    try {
      final program = await ui.FragmentProgram.fromAsset(
        'shaders/liquid_glass.frag',
      );
      _cachedProgram = program;
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint("Failed to load liquid glass shader: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final program = _cachedProgram;
    if (program == null || !widget.enabled) {
      return ClipRect(
        child: BackdropFilter(
          filter: _blurFilter,
          child: widget.child,
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return AnimatedBuilder(
          animation: _controller,
          child: widget.child,
          builder: (context, cachedChild) {
            final shader = program.fragmentShader();

            final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
            final size = renderBox?.size ?? constraints.biggest;
            Offset offset = Offset.zero;
            if (renderBox != null && renderBox.attached) {
              offset = renderBox.localToGlobal(Offset.zero);
            }
            final screenSize = MediaQuery.of(context).size;

            // 1) The first uniform is a vec2 for the texture size.
            // We MUST initialize the float array with at least 2 values to satisfy Flutter's ImageFilter.shader check.
            shader.setFloat(0, size.width);
            shader.setFloat(1, size.height);

            // 2) Custom uniforms
            shader.setFloat(2, widget.distortionStrength);
            shader.setFloat(3, widget.chromaticAberration);
            shader.setFloat(4, _controller.value * 10.0);
            
            shader.setFloat(5, offset.dx);
            shader.setFloat(6, offset.dy);
            
            shader.setFloat(7, screenSize.width);
            shader.setFloat(8, screenSize.height);

            // Compose: First blur the background, then distort it with our shader!
            // (Or vice-versa, but blurring first usually looks better for liquid glass)
            final compositeFilter = ui.ImageFilter.compose(
              outer: ui.ImageFilter.shader(shader),
              inner: _blurFilter,
            );

            return ClipRect(
              child: BackdropFilter(filter: compositeFilter, child: cachedChild),
            );
          },
        );
      }
    );
  }
}
