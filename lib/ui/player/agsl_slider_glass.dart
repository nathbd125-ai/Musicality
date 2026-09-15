import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:musicality/core/globals.dart';

/// Specialized AGSL Frosted Glass component tailored for dynamic moving UI elements (e.g. slider thumbs).
/// Uses 'shaders/slider_glass.frag' which eliminates SDF outer clipping discard to guarantee continuous,
/// zero-jitter, zero-flicker rendering at 120 FPS even during fast finger dragging.
class AGSLSliderGlass extends StatefulWidget {
  final Widget child;
  final double cornerRadius;
  final double distance;
  final double blurSigma;
  final bool enabled;
  final Offset? offset;

  const AGSLSliderGlass({
    super.key,
    required this.child,
    this.cornerRadius = 19.0,
    this.distance = 12.0,
    this.blurSigma = 16.0,
    this.enabled = true,
    this.offset,
  });

  static FragmentProgram? _cachedProgram;

  static bool _hasBoundListener = false;

  static void _bindListener() {
    if (_hasBoundListener) return;
    _hasBoundListener = true;
    isLiquidGlassEnabledNotifier.addListener(() {
      if (isLiquidGlassEnabledNotifier.value && !isBatterySaverEnabledNotifier.value) {
        preload();
      }
    });
  }

  /// Preload the shader program ONLY if Liquid Glass is currently enabled and battery saver is off.
  static Future<void> preload() async {
    _bindListener();
    if (!isLiquidGlassEnabledNotifier.value || isBatterySaverEnabledNotifier.value) {
      return;
    }
    if (_cachedProgram != null) return;
    try {
      _cachedProgram = await FragmentProgram.fromAsset(
        'shaders/slider_glass.frag',
      );
    } catch (e) {
      debugPrint("Erreur lors du prechargement de slider_glass.frag: $e");
    }
  }

  @override
  State<AGSLSliderGlass> createState() => _AGSLSliderGlassState();
}

class _AGSLSliderGlassState extends State<AGSLSliderGlass> {
  Offset _currentOffset = Offset.zero;
  late ImageFilter _blurFilter;

  @override
  void initState() {
    super.initState();
    _updateBlurFilter();
    if (widget.enabled) {
      _loadShader();
    }
  }

  void _updateBlurFilter() {
    _blurFilter = ImageFilter.blur(
      sigmaX: widget.blurSigma,
      sigmaY: widget.blurSigma,
    );
  }

  void _updateOffset() {
    if (!mounted || !widget.enabled) return;
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize && box.attached) {
      final newOffset = box.localToGlobal(Offset.zero);
      if (newOffset != _currentOffset) {
        setState(() {
          _currentOffset = newOffset;
        });
      }
    }
  }

  @override
  void didUpdateWidget(AGSLSliderGlass oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.blurSigma != widget.blurSigma) {
      _updateBlurFilter();
    }
    if (widget.enabled && !oldWidget.enabled && AGSLSliderGlass._cachedProgram == null) {
      _loadShader();
    }
  }

  Future<void> _loadShader() async {
    if (AGSLSliderGlass._cachedProgram != null) return;
    try {
      final program = await FragmentProgram.fromAsset(
        'shaders/slider_glass.frag',
      );
      AGSLSliderGlass._cachedProgram = program;
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint("Erreur lors du chargement de slider_glass.frag: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return widget.child;
    }

    final program = AGSLSliderGlass._cachedProgram;
    if (program == null) {
      // Fallback while the shader is compiling / loading
      return ClipRRect(
        borderRadius: BorderRadius.circular(widget.cornerRadius),
        child: BackdropFilter(
          filter: _blurFilter,
          child: widget.child,
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (widget.offset == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _updateOffset();
          });
        }

        final shader = program.fragmentShader();

        // Screen and device metrics for pixel-perfect coordinates
        final dpr = MediaQuery.of(context).devicePixelRatio;

        // 0, 1: Engine texture size placeholder (overwritten automatically by Flutter engine)
        shader.setFloat(0, 0.0);
        shader.setFloat(1, 0.0);

        // 2, 3: Real size of the widget in physical pixels
        shader.setFloat(2, constraints.maxWidth * dpr);
        shader.setFloat(3, constraints.maxHeight * dpr);

        // 4, 5: Corner radius and 3D refraction distance
        shader.setFloat(4, widget.cornerRadius * dpr);
        shader.setFloat(5, widget.distance * dpr);

        // 6, 7: Widget position on screen (offset in physical pixels)
        final effectiveOffset = widget.offset ?? _currentOffset;
        shader.setFloat(6, effectiveOffset.dx * dpr);
        shader.setFloat(7, effectiveOffset.dy * dpr);

        // 8, 9: Screen resolution in physical pixels
        final screenSize = MediaQuery.of(context).size;
        shader.setFloat(8, screenSize.width * dpr);
        shader.setFloat(9, screenSize.height * dpr);

        return ClipRRect(
          borderRadius: BorderRadius.circular(widget.cornerRadius),
          child: BackdropFilter(
            filter: ImageFilter.shader(shader),
            child: widget.child,
          ),
        );
      },
    );
  }
}
