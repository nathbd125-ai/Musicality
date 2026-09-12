import 'package:flutter/material.dart';

class HyperOSSlider extends StatefulWidget {
  final Duration position;
  final Duration duration;
  final Function(Duration) onSeek;
  final List<Color> gradientColors;
  final bool showMilliseconds;

  const HyperOSSlider({
    super.key,
    required this.position,
    required this.duration,
    required this.onSeek,
    required this.gradientColors,
    this.showMilliseconds = false,
  });

  @override
  State<HyperOSSlider> createState() => _HyperOSSliderState();
}

class _HyperOSSliderState extends State<HyperOSSlider> {
  double? _dragValue;
  double _baseMsForDrag = 0.0;

  String _formatDuration(Duration duration) {
    String twoDigits(int n) {
      return n.toString().padLeft(2, "0");
    }

    final mins = twoDigits(duration.inMinutes.remainder(60));
    final secs = twoDigits(duration.inSeconds.remainder(60));

    if (widget.showMilliseconds) {
      final ms = (duration.inMilliseconds.remainder(1000))
          .toString()
          .padLeft(3, "0");
      return "$mins:$secs.$ms";
    }

    return "$mins:$secs";
  }

  @override
  Widget build(BuildContext context) {
    final double maxMs = widget.duration.inMilliseconds.toDouble() == 0.0
        ? 1.0
        : widget.duration.inMilliseconds.toDouble();
    final double currentMs = (_dragValue != null)
        ? _dragValue!
        : widget.position.inMilliseconds.toDouble();
    final double pct = (currentMs / maxMs).clamp(0.0, 1.0);

    return RepaintBoundary(
      child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (details) {
        final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
        if (renderBox == null) return;
        final width = renderBox.size.width;
        if (width <= 0) return;
        final double tapX = details.localPosition.dx;
        final double newMs = (tapX / width) * maxMs;
        widget.onSeek(Duration(milliseconds: newMs.toInt()));
      },
      onHorizontalDragStart: (details) {
        _baseMsForDrag = widget.position.inMilliseconds.toDouble();
        setState(() {
          _dragValue = _baseMsForDrag;
        });
      },
      onHorizontalDragUpdate: (details) {
        final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
        if (renderBox == null) return;

        final width = renderBox.size.width;
        if (width <= 0) return;

        final double deltaX = details.delta.dx;
        final double deltaMs = (deltaX / width) * maxMs;

        setState(() {
          if (_dragValue != null) {
            _dragValue = (_dragValue! + deltaMs).clamp(0.0, maxMs);
          }
        });
      },
      onHorizontalDragEnd: (details) async {
        if (_dragValue != null) {
          widget.onSeek(Duration(milliseconds: _dragValue!.toInt()));
          await Future.delayed(const Duration(milliseconds: 60));
          if (mounted) {
            setState(() {
              _dragValue = null;
            });
          }
        }
      },
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final activeWidth = width * pct;
                return Stack(
                  alignment: Alignment.centerLeft,
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: width,
                      height: 4,
                      decoration: const BoxDecoration(
                        color: Color(0xFF2C2C2C),
                        borderRadius: BorderRadius.all(Radius.circular(2)),
                      ),
                    ),
                    if (activeWidth > 0)
                      Container(
                        width: activeWidth,
                        height: 4,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(2),
                          boxShadow: [
                            BoxShadow(
                              color: widget.gradientColors[0].withValues(
                                alpha: 0.8,
                              ),
                              blurRadius: 12,
                              spreadRadius: 2,
                            ),
                            BoxShadow(
                              color: widget.gradientColors[0].withValues(
                                alpha: 0.5,
                              ),
                              blurRadius: 24,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                      ),
                    if (activeWidth > 0)
                      Container(
                        width: activeWidth,
                        height: 4,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(2),
                          gradient: LinearGradient(
                            colors: widget.gradientColors,
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                        ),
                      ),
                    Positioned(
                      left: (activeWidth - 5).clamp(0.0, width - 10),
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.white.withValues(alpha: 0.8),
                              blurRadius: 6,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(Duration(milliseconds: currentMs.toInt())),
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: widget.showMilliseconds ? 11.5 : 11,
                  fontFamily: widget.showMilliseconds ? 'monospace' : null,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  fontWeight: widget.showMilliseconds ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
              Text(
                _formatDuration(widget.duration),
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: widget.showMilliseconds ? 11.5 : 11,
                  fontFamily: widget.showMilliseconds ? 'monospace' : null,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  fontWeight: widget.showMilliseconds ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
}
