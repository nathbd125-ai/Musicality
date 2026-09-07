class LyricWord {
  final String text;
  final Duration start;
  final Duration end;

  const LyricWord({
    required this.text,
    required this.start,
    required this.end,
  });
}

class LyricLine {
  final Duration time;
  final String text;
  final Duration? endTime;
  final List<LyricWord> words;

  LyricLine({
    required this.time,
    required this.text,
    this.endTime,
    this.words = const [],
  });
}

class PositionData {
  final Duration position;
  final Duration bufferedPosition;
  final Duration duration;
  PositionData(this.position, this.bufferedPosition, this.duration);
}
