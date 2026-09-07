import 'package:flutter/material.dart';
import 'dart:async';

class MarqueeWidget extends StatefulWidget {
  final Widget child;
  final String resetKey;
  final Alignment alignment;
  final double threshold;

  const MarqueeWidget({
    super.key,
    required this.child,
    required this.resetKey,
    this.alignment = Alignment.centerLeft,
    this.threshold = 0.0,
  });

  @override
  State<MarqueeWidget> createState() => _MarqueeWidgetState();
}

class _MarqueeWidgetState extends State<MarqueeWidget> {
  late ScrollController _scrollController;
  bool _isScrolling = false;
  bool _needsScroll = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAndScroll());
  }

  @override
  void didUpdateWidget(MarqueeWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resetKey != widget.resetKey) {
      _isScrolling = false;
      _needsScroll = false;
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkAndScroll());
    } else {
      final currentKey = widget.resetKey;
      WidgetsBinding.instance.addPostFrameCallback((_) => _recheckScroll());
      // Re-verify after layout transitions (e.g. expanding/collapsing player)
      Future.delayed(const Duration(milliseconds: 350), () {
        if (mounted && widget.resetKey == currentKey) {
          _recheckScroll();
        }
      });
    }
  }

  void _recheckScroll([int retryCount = 0]) async {
    final currentKey = widget.resetKey;
    if (!mounted) return;
    if (!_scrollController.hasClients) {
      if (retryCount < 5) {
        await Future.delayed(const Duration(milliseconds: 50));
        if (mounted && widget.resetKey == currentKey) {
          _recheckScroll(retryCount + 1);
        }
      }
      return;
    }
    final maxScroll = _scrollController.position.maxScrollExtent;
    if (maxScroll > widget.threshold && !_needsScroll) {
      setState(() {
        _needsScroll = true;
      });
      _startScrolling();
    } else if (maxScroll <= widget.threshold && _needsScroll) {
      setState(() {
        _needsScroll = false;
        _isScrolling = false;
      });
    }
  }

  void _checkAndScroll([int retryCount = 0]) async {
    final currentKey = widget.resetKey;
    if (!mounted) return;

    if (!_scrollController.hasClients) {
      if (retryCount < 8) {
        await Future.delayed(const Duration(milliseconds: 50));
        if (mounted && widget.resetKey == currentKey) {
          _checkAndScroll(retryCount + 1);
        }
      }
      return;
    }

    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted ||
        !_scrollController.hasClients ||
        widget.resetKey != currentKey) {
      return;
    }

    final maxScroll = _scrollController.position.maxScrollExtent;
    if (maxScroll > widget.threshold) {
      if (!_needsScroll) {
        setState(() {
          _needsScroll = true;
        });
      }
      _startScrolling();
    } else {
      if (_needsScroll) {
        setState(() {
          _needsScroll = false;
        });
      }
    }
  }

  void _startScrolling() async {
    final currentKey = widget.resetKey;
    if (_isScrolling) return;
    _isScrolling = true;

    while (_isScrolling && mounted && widget.resetKey == currentKey) {
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted ||
          !_scrollController.hasClients ||
          widget.resetKey != currentKey ||
          !_isScrolling) {
        break;
      }

      final maxScroll = _scrollController.position.maxScrollExtent;
      if (maxScroll <= widget.threshold) break;

      await _scrollController.animateTo(
        maxScroll,
        duration: Duration(milliseconds: (maxScroll * 35).toInt()),
        curve: Curves.linear,
      );

      if (!mounted || widget.resetKey != currentKey || !_isScrolling) break;
      await Future.delayed(const Duration(seconds: 2));

      if (!mounted ||
          !_scrollController.hasClients ||
          widget.resetKey != currentKey ||
          !_isScrolling) {
        break;
      }

      await _scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _isScrolling = false;
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_needsScroll) {
      return Align(
        alignment: widget.alignment,
        child: SingleChildScrollView(
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          clipBehavior: Clip.hardEdge,
          child: widget.child,
        ),
      );
    }

    Widget marquee = Padding(
      padding: const EdgeInsets.only(right: 4.0),
      child: Align(
        alignment: widget.alignment,
        child: SingleChildScrollView(
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          clipBehavior: Clip.hardEdge,
          child: Padding(
            padding: const EdgeInsets.only(right: 24.0),
            child: widget.child,
          ),
        ),
      ),
    );

    return AnimatedBuilder(
      animation: _scrollController,
      builder: (context, childWidget) {
        final double offset = _scrollController.hasClients
            ? _scrollController.offset
            : 0.0;

        return ClipRect(
          clipBehavior: Clip.hardEdge,
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (Rect bounds) {
              final double w = bounds.width;
              if (w <= 0) {
                return const LinearGradient(
                  colors: [Colors.white, Colors.white],
                ).createShader(bounds);
              }

              // Largeur du fondu progressif : 24 pixels
              final double fadePx = 24.0.clamp(12.0, w * 0.25);

              // Fondu à gauche (actif dès que le texte commence à défiler)
              final double leftFactor = (offset / 15.0).clamp(0.0, 1.0);

              // Points d'arrêt à droite (en coordonnées relatives 0.0 -> 1.0)
              // Le SingleChildScrollView s'arrête à (w - 4px).
              // Le fondu atteint 0 opacité à (w - 6px), garantissant une extinction totale 2px avant le clip.
              final double rightStart = ((w - 4.0 - fadePx) / w).clamp(0.5, 0.95);
              final double rightZero = ((w - 6.0) / w).clamp(rightStart + 0.01, 0.99);

              final List<Color> colors = [];
              final List<double> stops = [];

              if (leftFactor > 0.0) {
                final double leftStop = ((fadePx * leftFactor) / w).clamp(0.01, rightStart - 0.05);
                colors.add(Colors.transparent);
                stops.add(0.0);
                colors.add(Colors.white);
                stops.add(leftStop);
              } else {
                colors.add(Colors.white);
                stops.add(0.0);
              }

              colors.add(Colors.white);
              stops.add(rightStart);

              colors.add(Colors.transparent);
              stops.add(rightZero);

              colors.add(Colors.transparent);
              stops.add(1.0);

              return LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: colors,
                stops: stops,
              ).createShader(bounds);
            },
            child: childWidget,
          ),
        );
      },
      child: marquee,
    );
  }
}
