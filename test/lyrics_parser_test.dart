import 'package:flutter_test/flutter_test.dart';
import 'package:musicality/core/lyrics_parser.dart';

void main() {
  group('LyricsParser', () {
    test('parse un LRC classique et ignore les crédits', () {
      final lyrics = LyricsParser.parse('''
[00:01.50]Bonjour monde
[00:03.00]Written by Musicality
''');

      expect(lyrics, hasLength(1));
      expect(lyrics.single.time, const Duration(milliseconds: 1500));
      expect(lyrics.single.text, 'Bonjour monde');
      expect(lyrics.single.words.map((word) => word.text), [
        'Bonjour',
        'monde',
      ]);
      expect(
        lyrics.single.words.first.start,
        const Duration(milliseconds: 1500),
      );
    });

    test('parse les timings par mot TTML', () {
      final lyrics = LyricsParser.parse('''
<tt xmlns="http://www.w3.org/ns/ttml"><body><p begin="1.0s" end="3.0s"><span begin="1.0s" end="1.5s">Bon</span> <span begin="1.5s" end="2.0s">jour</span></p></body></tt>
''');

      expect(lyrics, hasLength(1));
      expect(lyrics.single.time, const Duration(seconds: 1));
      expect(lyrics.single.endTime, const Duration(seconds: 3));
      expect(lyrics.single.words.map((word) => word.text), ['Bon', 'jour']);
      expect(lyrics.single.words.last.end, const Duration(seconds: 2));
    });

    test('filtre les crédits de début Afro Trap Part. 7 et préserve les vraies paroles', () {
      final lyrics = LyricsParser.parse('''
[00:00.00] 作词 : Mohamed Sylla
[00:01.00] 作曲 : Dany Synthé
[00:03.42]AFRO TRAP Part.7（La Puissance ）-MHD
[00:08.13]La puissance que la puissance
[00:10.00]Parle en fran ç ais
''');

      expect(lyrics, hasLength(2));
      expect(lyrics[0].time, const Duration(milliseconds: 8130));
      expect(lyrics[0].text, 'La puissance que la puissance');
      expect(lyrics[1].text, 'Parle en français');
    });

    test('corrige mirándote et ses variantes en espagnol', () {
      final lyrics = LyricsParser.parse('''
[00:10.00]llevo un rato mirá ndote
[00:15.00]llevo un rato mir á ndote
[00:20.00]llevo un rato <00:20.20>mir <00:20.40>á <00:20.60>ndote
''');

      expect(lyrics, hasLength(3));
      expect(lyrics[0].text, 'llevo un rato mirándote');
      expect(lyrics[1].text, 'llevo un rato mirándote');
      expect(lyrics[2].text, 'llevo un rato mirándote');
    });

    test('corrige les cas complexes français et argot', () {
      final lyrics = LyricsParser.parse('''
[00:10.00]Tu veux tej'la bouteille àla mer
[00:15.00]au fond d'un carr éV I P
[00:20.00]Ceux qui pensent me conna î tre
''');

      expect(lyrics, hasLength(3));
      expect(lyrics[0].text, "Tu veux tej' la bouteille à la mer");
      expect(lyrics[1].text, "au fond d'un carré VIP");
      expect(lyrics[2].text, "Ceux qui pensent me connaître");
    });

    test('corrige les cas de collage et séparation signalés par l\'utilisateur', () {
      final lyrics = LyricsParser.parse('''
[00:10.00]<00:31.86>O <00:32.07>ù<00:32.28>sont <00:32.49>les <00:32.70>vrais
[00:15.00]<00:38.70>C'est <00:38.86>l <00:39.01>à<00:39.17>que <00:39.33>les <00:39.48>balles <00:39.64>se <00:39.80>perdent
[00:20.00]y a ma te-tê partout
[00:25.00]y a ma te-têpartout
[00:28.00]y a ma te-t\ufffd partout
[00:30.00]on règlerera ça au lit
[00:35.00]on règlereraça au lit
[00:38.00]on r\ufffdglera \ufffda au lit
''');

      expect(lyrics[0].text, 'Où sont les vrais');
      expect(lyrics[1].text, "C'est là que les balles se perdent");
      expect(lyrics[2].text, 'y a ma te-tê partout');
      expect(lyrics[3].text, 'y a ma te-tê partout');
      expect(lyrics[4].text, 'y a ma te-tê partout');
      expect(lyrics[5].text, 'on règlerera ça au lit');
      expect(lyrics[6].text, 'on règlerera ça au lit');
      expect(lyrics[7].text, 'on règlerera ça au lit');
    });
  });
}
