import 'dart:ui';
import 'package:flutter/material.dart';

class AGSLRhombusGlass extends StatefulWidget {
  final Widget child;
  final double cornerRadius;
  final double distance;
  final double blurSigma;
  final bool enabled;

  const AGSLRhombusGlass({
    super.key,
    required this.child,
    this.cornerRadius = 40.0,
    this.distance = 15.0,
    this.blurSigma = 16.0,
    this.enabled = true,
  });

  @override
  State<AGSLRhombusGlass> createState() => _AGSLRhombusGlassState();
}

class _AGSLRhombusGlassState extends State<AGSLRhombusGlass> {
  static FragmentProgram? _cachedProgram;
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
    if (box != null && box.hasSize) {
      final newOffset = box.localToGlobal(Offset.zero);
      if (newOffset != _currentOffset) {
        setState(() {
          _currentOffset = newOffset;
        });
      }
    }
  }

  @override
  void didUpdateWidget(AGSLRhombusGlass oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.blurSigma != widget.blurSigma) {
      _updateBlurFilter();
    }
    if (widget.enabled && !oldWidget.enabled && _cachedProgram == null) {
      _loadShader();
    }
  }

  Future<void> _loadShader() async {
    if (_cachedProgram != null) return;
    try {
      final program = await FragmentProgram.fromAsset(
        'shaders/rhombus_glass.frag',
      );
      _cachedProgram = program;
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint("Erreur lors du chargement de rhombus_glass.frag: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return widget.child;
    }

    final program = _cachedProgram;
    if (program == null) {
      // Fallback
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
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _updateOffset();
        });

        final shader = program.fragmentShader();

        // Get Device Pixel Ratio because FlutterFragCoord in BackdropFilter is in physical pixels on Impeller
        final dpr = MediaQuery.of(context).devicePixelRatio;

        // 0, 1: Engine texture size placeholder (overwritten automatically by Flutter's ImageFilter.shader)
        shader.setFloat(0, 0.0);
        shader.setFloat(1, 0.0);

        // 2, 3: Real size of the widget
        shader.setFloat(2, constraints.maxWidth * dpr);
        shader.setFloat(3, constraints.maxHeight * dpr);

        // 4, 5: Corner radius and 3D refraction distance
        shader.setFloat(4, widget.cornerRadius * dpr);
        shader.setFloat(5, widget.distance * dpr);

        // 6, 7: Widget position on screen (offset)
        shader.setFloat(6, _currentOffset.dx * dpr);
        shader.setFloat(7, _currentOffset.dy * dpr);

        // 8, 9: Screen size
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
