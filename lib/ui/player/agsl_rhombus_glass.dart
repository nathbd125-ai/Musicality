import 'dart:ui';
import 'package:flutter/material.dart';

class AGSLRhombusGlass extends StatefulWidget {
  final Widget child;
  final double cornerRadius;
  final double distance;
  final bool enabled;

  const AGSLRhombusGlass({
    super.key,
    required this.child,
    this.cornerRadius = 40.0,
    this.distance = 150.0,
    this.enabled = true,
  });

  @override
  State<AGSLRhombusGlass> createState() => _AGSLRhombusGlassState();
}

class _AGSLRhombusGlassState extends State<AGSLRhombusGlass> {
  FragmentProgram? _program;
  Offset _currentOffset = Offset.zero;

  @override
  void initState() {
    super.initState();
    if (widget.enabled) {
      _loadShader();
    }
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
    if (widget.enabled && !oldWidget.enabled && _program == null) {
      _loadShader();
    }
  }

  Future<void> _loadShader() async {
    try {
      final program = await FragmentProgram.fromAsset(
        'shaders/rhombus_glass.frag',
      );
      if (mounted) {
        setState(() {
          _program = program;
        });
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

    if (_program == null) {
      // Fallback
      return ClipRRect(
        borderRadius: BorderRadius.circular(widget.cornerRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 50.0, sigmaY: 50.0),
          child: widget.child,
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _updateOffset();
        });

        final shader = _program!.fragmentShader();

        // Get Device Pixel Ratio because FlutterFragCoord in BackdropFilter is in physical pixels on Impeller
        final dpr = MediaQuery.of(context).devicePixelRatio;

        // Size of the widget
        shader.setFloat(0, constraints.maxWidth * dpr);
        shader.setFloat(1, constraints.maxHeight * dpr);

        // Corner radius and distance
        shader.setFloat(2, widget.cornerRadius * dpr);
        shader.setFloat(3, widget.distance * dpr);

        shader.setFloat(4, _currentOffset.dx * dpr);
        shader.setFloat(5, _currentOffset.dy * dpr);

        // Screen size
        final screenSize = MediaQuery.of(context).size;
        shader.setFloat(6, screenSize.width * dpr);
        shader.setFloat(7, screenSize.height * dpr);

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
