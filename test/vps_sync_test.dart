import 'package:flutter_test/flutter_test.dart';
import 'package:musicality/core/models.dart';
import 'package:musicality/core/vps_sync_service.dart';
import 'package:musicality/core/lyrics_service.dart';

void main() {
  group('VpsSyncService tests', () {
    test('formatTimestamp formate correctement les durées en [mm:ss.xx]', () {
      expect(
        VpsSyncService.formatTimestamp(Duration.zero),
        equals('[00:00.00]'),
      );
      expect(
        VpsSyncService.formatTimestamp(const Duration(milliseconds: 14250)),
        equals('[00:14.25]'),
      );
      expect(
        VpsSyncService.formatTimestamp(
          const Duration(minutes: 2, seconds: 5, milliseconds: 70),
        ),
        equals('[02:05.07]'),
      );
      expect(
        VpsSyncService.formatTimestamp(const Duration(milliseconds: -100)),
        equals('[00:00.00]'),
      );
    });

    test('formatLrc trie et formate les lignes de paroles au format standard LRC', () {
      final lines = [
        LyricLine(
          time: const Duration(seconds: 15),
          text: 'Deuxième phrase',
        ),
        LyricLine(
          time: const Duration(seconds: 5),
          text: ' Première phrase ',
        ),
        LyricLine(
          time: const Duration(minutes: 1, seconds: 2),
          text: 'Troisième phrase',
        ),
      ];

      final lrc = VpsSyncService.formatLrc(lines);
      final expected =
          '[00:05.00] Première phrase\n'
          '[00:15.00] Deuxième phrase\n'
          '[01:02.00] Troisième phrase';

      expect(lrc, equals(expected));
    });

    test('LyricsService.getBaseName extrait correctement le nom de base', () {
      expect(
        LyricsService.getBaseName('https://example.com/media/Autotune.mp3'),
        equals('Autotune'),
      );
      expect(
        LyricsService.getBaseName('songs/Levitating-hires.flac'),
        equals('Levitating'),
      );
    });
  });
}
