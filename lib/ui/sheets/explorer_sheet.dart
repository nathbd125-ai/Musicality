import 'package:flutter/material.dart';
import 'dart:ui';

class ExplorerSheet extends StatefulWidget {
  final String title;
  final List<Color> themeColors;
  final Widget content;

  const ExplorerSheet({
    super.key,
    required this.title,
    required this.themeColors,
    required this.content,
  });

  @override
  State<ExplorerSheet> createState() => _ExplorerSheetState();
}

class _ExplorerSheetState extends State<ExplorerSheet> {
  final DraggableScrollableController _dragController =
      DraggableScrollableController();
  final ValueNotifier<double> _sheetSize = ValueNotifier(0.85);
  final ValueNotifier<double> _scrollOffset = ValueNotifier(0.0);

  @override
  void initState() {
    super.initState();
    _dragController.addListener(() {
      if (_dragController.isAttached) {
        _sheetSize.value = _dragController.size;
      }
    });
  }

  @override
  void dispose() {
    _dragController.dispose();
    _sheetSize.dispose();
    _scrollOffset.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      controller: _dragController,
      initialChildSize: 0.85,
      minChildSize: 0.0,
      maxChildSize: 1.0,
      expand: false,
      snap: true,
      snapSizes: const [0.85, 1.0],
      builder: (context, scrollController) {
        final topPadding = MediaQuery.of(context).padding.top;
        final headerHeight = 115.0 + topPadding;

        return ValueListenableBuilder<double>(
          valueListenable: _sheetSize,
          builder: (context, size, child) {
            final progress = ((size - 0.90) / 0.10).clamp(0.0, 1.0);
            // On s'assure que le radius tombe parfaitement à zéro si on est très proche du bord
            final radius = progress > 0.99 ? 0.0 : 32.0 * (1.0 - progress);
            final borderAlpha = 0.1 * (1.0 - progress);

            return ClipRRect(
              borderRadius: BorderRadius.vertical(top: Radius.circular(radius)),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF121212).withValues(alpha: 0.35),
                      // Supprime complètement la bordure si on est collé en haut
                      border: borderAlpha > 0.005
                          ? Border(
                              top: BorderSide(
                                color: Colors.white.withValues(
                                  alpha: borderAlpha,
                                ),
                                width: 1,
                              ),
                            )
                          : null,
                    ),
                    child: child,
                  ),
                ),
              ),
            );
          },
          child: NotificationListener<ScrollNotification>(
            onNotification: (ScrollNotification notification) {
              if (notification.metrics.axis == Axis.vertical) {
                _scrollOffset.value = notification.metrics.pixels;
              }
              return false;
            },
            child: Stack(
              children: [
                ListView(
                  controller: scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.only(
                    top: headerHeight,
                    bottom: MediaQuery.of(context).viewInsets.bottom + 100,
                  ),
                  children: [widget.content],
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: headerHeight,
                  child: IgnorePointer(
                    child: Stack(
                      children: [
                        ValueListenableBuilder<double>(
                          valueListenable: _scrollOffset,
                          builder: (context, offset, child) {
                            final opacity = (offset / 25.0).clamp(0.0, 1.0);
                            if (opacity == 0.0) return const SizedBox.shrink();

                            return Opacity(opacity: opacity, child: child);
                          },
                          child: ClipRect(
                            child: ShaderMask(
                              shaderCallback: (bounds) {
                                return const LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.black,
                                    Colors.black,
                                    Colors.transparent,
                                  ],
                                  stops: [0.0, 0.60, 1.0],
                                ).createShader(bounds);
                              },
                              blendMode: BlendMode.dstIn,
                              child: BackdropFilter(
                                filter: ImageFilter.blur(
                                  sigmaX: 35,
                                  sigmaY: 35,
                                ),
                                child: Container(
                                  height: headerHeight,
                                  color: Colors.black.withValues(alpha: 0.98),
                                ),
                              ),
                            ),
                          ),
                        ),
                        RepaintBoundary(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(height: topPadding),
                              ValueListenableBuilder<double>(
                                valueListenable: _sheetSize,
                                builder: (context, size, child) {
                                  final opacity = (1.0 - ((size - 0.90) / 0.10))
                                      .clamp(0.0, 1.0);
                                  return Opacity(
                                    opacity: opacity,
                                    child: child,
                                  );
                                },
                                child: Center(
                                  child: Container(
                                    margin: const EdgeInsets.only(
                                      top: 12,
                                      bottom: 8,
                                    ),
                                    width: 40,
                                    height: 5,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.3,
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: 15,
                                  left: 20,
                                  right: 20,
                                ),
                                child: ShaderMask(
                                  blendMode: BlendMode.srcIn,
                                  shaderCallback: (bounds) =>
                                      LinearGradient(
                                        colors: widget.themeColors.length >= 2
                                            ? widget.themeColors
                                            : (widget.themeColors.isNotEmpty
                                                  ? [
                                                      widget.themeColors[0],
                                                      widget.themeColors[0]
                                                          .withValues(
                                                            alpha: 0.8,
                                                          ),
                                                    ]
                                                  : [
                                                      Colors.blue,
                                                      Colors.purple,
                                                    ]),
                                        begin: Alignment.centerLeft,
                                        end: Alignment.centerRight,
                                      ).createShader(
                                        Rect.fromLTWH(
                                          0,
                                          0,
                                          bounds.width,
                                          bounds.height,
                                        ),
                                      ),
                                  child: Text(
                                    widget.title,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
