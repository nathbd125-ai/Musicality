import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:musicality/core/string_utils.dart';

List<double>? getGradientStops(int count) {
  if (count <= 1) return null;
  if (count == 2) return const [0.0, 1.0];
  if (count == 3) return const [0.25, 0.5, 0.75];
  if (count == 4) return const [0.15, 0.38, 0.61, 0.85];
  if (count == 5) return const [0.1, 0.3, 0.5, 0.7, 0.9];
  final step = 1.0 / (count - 1);
  return List<double>.generate(count, (i) => (i * step).clamp(0.0, 1.0));
}

List<Color> getAlbumGradientColors(MediaItem item) {
  final artUriStr = item.artUri?.toString().toLowerCase() ?? '';
  final a = getSafeFileName(item.album ?? '');
  final albumNorm = normalizeString(item.album ?? '');
  final idStr = item.id.toLowerCase();
  final titleNorm = normalizeString(item.title);

  // 1. EXCEPTIONS TITRES / SINGLES SPÉCIAUX (qui gardent leur gradient spécifique)
  // Ariana Grande - 7 Rings (Rose fin pastel/néon sans violet)
  if (titleNorm.contains('7 rings') || idStr.contains('7_rings') || idStr.contains('7 rings')) {
    return const [
      Color(0xFFFFB6C1), // Rose poudré clair
      Color(0xFFFF7DA7), // Rose fin
      Color(0xFFFF4D88), // Rose pochette
    ];
  }

  // Frou Frou - A New Kind of Love (demo) (Violet à rosé)
  if (titleNorm.contains('new kind of love') || idStr.contains('new_kind_of_love') || idStr.contains('kind_of_love')) {
    return const [
      Color(0xFF7B1FA2), // Violet profond
      Color(0xFFAB47BC), // Violet intermédiaire
      Color(0xFFEC407A), // Rosé
    ];
  }

  // MHD - Afro Trap Part. 11 (King Kong) (Noir à blanc)
  if (titleNorm.contains('king kong') || idStr.contains('king_kong') || (titleNorm.contains('afro trap') && titleNorm.contains('11'))) {
    return const [
      Color(0xFF111111), // Noir
      Color(0xFF555555), // Gris anthracite
      Color(0xFFCCCCCC), // Gris clair
      Color(0xFFFFFFFF), // Blanc
    ];
  }

  // MHD - Afro Trap Part. 7 (La puissance) (Noir à blanc à rouge)
  if (titleNorm.contains('la puissance') || idStr.contains('la_puissance') || (titleNorm.contains('afro trap') && titleNorm.contains('7'))) {
    return const [
      Color(0xFF1A1A1A), // Noir
      Color(0xFFFFFFFF), // Blanc
      Color(0xFFE53935), // Rouge
    ];
  }

  // All I Need (Jaune clair à bleu à orange à vert à jaune foncé à rouge à bleu cyan)
  if (titleNorm.contains('all i need') || idStr.contains('all_i_need')) {
    return const [
      Color(0xFFFFF59D), // Jaune clair
      Color(0xFF1E88E5), // Bleu
      Color(0xFFFF9800), // Orange
      Color(0xFF43A047), // Vert
      Color(0xFFFBC02D), // Jaune foncé
      Color(0xFFE53935), // Rouge
      Color(0xFF00E5FF), // Bleu cyan
    ];
  }

  // Metro Boomin, A$AP Rocky, Roisee - Am I Dreaming (Exception : 10% jaune, 10% vert, 30% rouge, 50% violet)
  if (titleNorm.contains('am i dreaming') || idStr.contains('am_i_dreaming')) {
    return const [
      Color(0xFF00E676), // 10% Vert néon
      Color(0xFFFFEA00), // 10% Jaune
      Color(0xFFE53935), // 30% Rouge (3 paliers)
      Color(0xFFE53935),
      Color(0xFFE53935),
      Color(0xFF7B1FA2), // 50% Violet (5 paliers)
      Color(0xFF7B1FA2),
      Color(0xFF7B1FA2),
      Color(0xFF7B1FA2),
      Color(0xFF7B1FA2),
    ];
  }

  // Heuss L'enfoiré - Bar-Mitzvah (Jaune doré à blanc)
  if (titleNorm.contains('bar-mitzvah') ||
      titleNorm.contains('bar mitzvah') ||
      idStr.contains('bar-mitzvah') ||
      a.contains('bar-mitzvah')) {
    return const [
      Color(0xFFFFD700), // Jaune doré
      Color(0xFFFFE082), // Jaune doré clair
      Color(0xFFFFF9C4), // Blanc cassé doré
      Color(0xFFFFFFFF), // Blanc
    ];
  }

  // Lacrim - Barbade (Blanc à gris à rouge)
  if (titleNorm.contains('barbade') || idStr.contains('barbade')) {
    return const [
      Color(0xFFFFFFFF), // Blanc
      Color(0xFF9E9E9E), // Gris
      Color(0xFFE53935), // Rouge
    ];
  }

  // Niska - Bâtiment (Vert gris à blanc à orange)
  if (titleNorm.contains('batiment') || idStr.contains('batiment')) {
    return const [
      Color(0xFF607D8B), // Vert gris
      Color(0xFFFFFFFF), // Blanc
      Color(0xFFFF6D00), // Orange
    ];
  }

  // Michael Jackson - Billie Jean (Blanc à doré à marron)
  if (titleNorm.contains('billie jean') || idStr.contains('billie_jean')) {
    return const [
      Color(0xFFFFFFFF), // Blanc
      Color(0xFFFFD700), // Doré
      Color(0xFF5D4037), // Marron
    ];
  }

  // Phantogram - Black Out Days (Blanc à doré)
  if (titleNorm.contains('black out days') || idStr.contains('black_out_days')) {
    return const [
      Color(0xFFFFFFFF), // Blanc
      Color(0xFFFFF8E1), // Blanc doré
      Color(0xFFFFE082), // Doré clair
      Color(0xFFFFD700), // Doré
    ];
  }

  // Jok'Air - Bonbon à la menthe (Bleu à jaune à rouge à rose)
  if (titleNorm.contains('bonbon') || idStr.contains('bonbon_a_la_menthe') || a.contains('jok_travolta') || albumNorm.contains('jok')) {
    return const [
      Color(0xFF1E88E5), // Bleu
      Color(0xFFFFEA00), // Jaune
      Color(0xFFE53935), // Rouge
      Color(0xFFE91E63), // Rose
    ];
  }

  // Daddy Yankee - Con Calma (Rose rouge plus rouge)
  if (titleNorm.contains('con calma') ||
      idStr.contains('con_calma') ||
      a.contains('con_calma') ||
      albumNorm.contains('con calma')) {
    return const [
      Color(0xFFE91E63), // Rose rouge vif
      Color(0xFFD32F2F), // Rouge framboise profond
      Color(0xFFB71C1C), // Rouge carmin intense
    ];
  }

  // Luis Fonsi - Despacito / VIDA (Jaune doré)
  if (titleNorm.contains('despacito') ||
      idStr.contains('despacito') ||
      a.contains('vida')) {
    return const [
      Color(0xFFFFF59D), // Jaune clair doré
      Color(0xFFFFEA00), // Jaune éclatant
      Color(0xFFFFD700), // Doré
      Color(0xFFFFA000), // Doré ambré
    ];
  }

  // do i clench my fists? (Gris noir à marron gris à blanc)
  if (titleNorm.contains('do i clench my fists') ||
      idStr.contains('do_i_clench_my_fists') ||
      a.contains('do_i_clench_my_fists')) {
    return const [
      Color(0xFF1C1C1C), // Gris noir
      Color(0xFF5D534E), // Marron gris
      Color(0xFF9E948F), // Marron gris clair
      Color(0xFFFFFFFF), // Blanc
    ];
  }

  // Imany - Don't Be So Shy / The Wrong Kind of War (Blanc à rouge à noir)
  if (titleNorm.contains("don't be so shy") ||
      titleNorm.contains("dont be so shy") ||
      idStr.contains('shy') ||
      a.contains('the_wrong_kind_of_war')) {
    return const [
      Color(0xFFFFFFFF), // Blanc
      Color(0xFFE53935), // Rouge
      Color(0xFFB71C1C), // Rouge foncé
      Color(0xFF111111), // Noir
    ];
  }

  // Jul - Drôle de dame / Album Gratuit Vol.4 (Blanc à doré)
  if (titleNorm.contains('drole de dame') ||
      idStr.contains('drole_de_dame') ||
      a.contains('album_gratuit_vol4') ||
      a.contains('album_gratuit_vol_4')) {
    return const [
      Color(0xFFFFFFFF), // Blanc
      Color(0xFFFFF8E1), // Blanc doré
      Color(0xFFFFD54F), // Doré clair
      Color(0xFFFFC107), // Doré
    ];
  }

  // Snoop Dogg - Drop It Like It's Hot / R&G: The Masterpiece (Noir clair à marron à gris vert)
  if (titleNorm.contains('drop it like') ||
      idStr.contains('drop_it_like') ||
      a.contains('masterpiece') ||
      a.contains('rg_the_masterpiece')) {
    return const [
      Color(0xFF262626), // Noir clair
      Color(0xFF6D4C41), // Marron
      Color(0xFF8D6E63), // Marron intermédiaire
      Color(0xFF5A6860), // Gris vert
    ];
  }

  // Lil Peep & XXXTENTACION - Falling Down / Come Over When You're Sober Pt. 2 (Rouge à bleu grisâtre à vert clair)
  if (titleNorm.contains('falling down') ||
      idStr.contains('falling_down') ||
      a.contains('sober') ||
      a.contains('come_over_when_youre_sober_pt_2')) {
    return const [
      Color(0xFFE53935), // Rouge
      Color(0xFF607D8B), // Bleu grisâtre
      Color(0xFFA5D6A7), // Vert clair
    ];
  }

  // The Weeknd - Can't Feel My Face (Blanc à gris à noir)
  if (titleNorm.contains("can't feel my face") ||
      titleNorm.contains("cant feel my face") ||
      idStr.contains("can't_feel_my_face") ||
      idStr.contains("cant_feel_my_face")) {
    return const [
      Color(0xFFFFFFFF), // Blanc
      Color(0xFFB0BEC5), // Gris clair
      Color(0xFF616161), // Gris
      Color(0xFF111111), // Noir
    ];
  }

  // DJ Kawest & Attachingboy - Chambre 04 (Bleu à marron)
  if (titleNorm.contains('chambre 04') ||
      idStr.contains('chambre_04') ||
      a.contains('chambre_04')) {
    return const [
      Color(0xFF1976D2), // Bleu
      Color(0xFF0D47A1), // Bleu nuit
      Color(0xFF6D4C41), // Marron chaud
      Color(0xFF4E342E), // Marron
    ];
  }

  // Blood Orange - Champagne Coast (Blanc à gris à noir, comme Can't Feel My Face)
  if (titleNorm.contains('champagne coast') ||
      idStr.contains('champagne_coast')) {
    return const [
      Color(0xFFFFFFFF), // Blanc
      Color(0xFFB0BEC5), // Gris clair
      Color(0xFF616161), // Gris
      Color(0xFF111111), // Noir
    ];
  }

  // TRIANGLE DES BERMUDES - Charger (Noir à rouge)
  if (titleNorm.contains('charger') || idStr.contains('charger')) {
    return const [
      Color(0xFF111111), // Noir
      Color(0xFF212121), // Noir anthracite
      Color(0xFFB71C1C), // Rouge foncé
      Color(0xFFE53935), // Rouge
    ];
  }

  // TV Girl - Who Really Cares / Cigarettes Out the Window (Bleu foncé à rose dégradé fluide)
  if (titleNorm.contains('cigarettes out the window') ||
      idStr.contains('cigarettes_out_the_window') ||
      a.contains('who_really_cares') ||
      albumNorm.contains('who really cares') ||
      titleNorm.contains('tv girl') ||
      idStr.contains('tv_girl')) {
    return const [
      Color(0xFF0D47A1), // Bleu foncé
      Color(0xFF1E88E5), // Bleu moyen
      Color(0xFFAB47BC), // Transition violet rosé
      Color(0xFFE91E63), // Rose
    ];
  }

  // Hatik - Angela (Blanc à beige)
  if (titleNorm.contains('angela') || idStr.contains('angela')) {
    return const [
      Color(0xFFFFFFFF), // Blanc
      Color(0xFFF5EBE1), // Blanc cassé / beige très clair
      Color(0xFFD4B896), // Beige chaleureux
    ];
  }

  // PLK - Attentat (Beige foncé à jaune doré à rouge)
  if (titleNorm.contains('attentat') || idStr.contains('attentat')) {
    return const [
      Color(0xFFBA966C), // Beige foncé
      Color(0xFFFFC107), // Jaune doré
      Color(0xFFD32F2F), // Rouge
    ];
  }

  if (titleNorm.contains('levitating') && (titleNorm.contains('dababy') || idStr.contains('dababy') || artUriStr.contains('levitating_dababy'))) {
    return const [
      Color(0xFFFFFFFF), // Blanc
      Color(0xFF2196F3), // Bleu
      Color(0xFFC89B3C), // Jaune/Marron (Chaise)
    ];
  }

  if (titleNorm.contains('fever') || idStr.contains('fever') || artUriStr.contains('fever')) {
    return const [
      Color(0xFFFF9800), // Orange
      Color(0xFFD32F2F), // Rouge
      Color(0xFFB71C1C), // Rouge foncé
      Color(0xFF212121), // Noir
    ];
  }

  // 2. GRADIENTS ASSOCIÉS AUX NOMS DES ALBUMS
  // C418 - Minecraft Volume Beta (Jaune à orange foncé)
  if (a.contains('volume_beta') ||
      albumNorm.contains('volume beta') ||
      titleNorm.contains('biome fest') ||
      idStr.contains('biome_fest') ||
      titleNorm.contains('dreiton') ||
      idStr.contains('dreiton')) {
    return const [
      Color(0xFFFFEA00), // Jaune
      Color(0xFFFF9800), // Orange
      Color(0xFFE65100), // Orange foncé
    ];
  }

  // The Weeknd - After Hours / Blinding Lights (Vert gris à beige marron à rouge)
  if (a.contains('after_hours') ||
      albumNorm.contains('after hours') ||
      titleNorm.contains('blinding lights') ||
      idStr.contains('blinding_lights')) {
    return const [
      Color(0xFF455A64), // Vert gris
      Color(0xFF8D6E63), // Beige marron
      Color(0xFFD32F2F), // Rouge
    ];
  }

  // Kanye West - Graduation / Flashing Lights (Orangé à jaune à violet)
  if (a.contains('graduation') ||
      albumNorm.contains('graduation') ||
      titleNorm.contains('flashing lights') ||
      idStr.contains('flashing_lights')) {
    return const [
      Color(0xFFFF7043), // Orangé
      Color(0xFFFFCA28), // Jaune
      Color(0xFF8E24AA), // Violet
    ];
  }

  // Riton x Nightcrawlers - Friday (Vert à orange profond à jaune clair)
  if (titleNorm.contains('friday') ||
      idStr.contains('friday') ||
      a.contains('friday') ||
      albumNorm.contains('friday')) {
    return const [
      Color(0xFF2E7D32), // Vert
      Color(0xFFE65100), // Orange profond
      Color(0xFFFFF59D), // Jaune clair
    ];
  }

  // Travis Scott - Birds in the Trap Sing McKnight / goosebumps (Noir à bleu foncé à marron rosé)
  if (a.contains('birds_in_the_trap') ||
      albumNorm.contains('birds in the trap') ||
      titleNorm.contains('goosebumps') ||
      idStr.contains('goosebumps')) {
    return const [
      Color(0xFF111111), // Noir
      Color(0xFF0D233A), // Bleu foncé
      Color(0xFF9E716B), // Marron rosé
    ];
  }

  // Crystal Waters - Surprise / Gypsy Woman (Violet noir à violet gris à blanc)
  if (a.contains('surprise') ||
      albumNorm.contains('surprise') ||
      titleNorm.contains('gypsy woman') ||
      idStr.contains('gypsy_woman')) {
    return const [
      Color(0xFF1E1035), // Violet noir
      Color(0xFF75658C), // Violet gris
      Color(0xFFFFFFFF), // Blanc
    ];
  }

  // Camila Cabello - Camila / Havana (Vert à orange à beige foncé à blanc)
  if (a.contains('camila') ||
      albumNorm.contains('camila') ||
      titleNorm.contains('havana') ||
      idStr.contains('havana')) {
    return const [
      Color(0xFF2E5A36), // Vert
      Color(0xFFE65100), // Orange
      Color(0xFF8D6E63), // Beige foncé
      Color(0xFFFFFFFF), // Blanc
    ];
  }

  // Gambi - LA VIE EST BELLE / HÉ OH (Bleu foncé à violet clair à marron clair à jaune orangé à blanc)
  if (a.contains('la_vie_est_belle') ||
      albumNorm.contains('la vie est belle') ||
      titleNorm.contains('he oh') ||
      idStr.contains('he_oh')) {
    return const [
      Color(0xFF101935), // Bleu foncé
      Color(0xFF9C6B98), // Violet clair
      Color(0xFF8D6E63), // Marron clair
      Color(0xFFFFB74D), // Jaune orangé
      Color(0xFFFFFFFF), // Blanc
    ];
  }

  // Childish Gambino - Camp / Heartbeat (Blanc à jaune à vert)
  if (a.contains('camp') ||
      albumNorm == 'camp' ||
      titleNorm.contains('heartbeat') ||
      idStr.contains('heartbeat')) {
    return const [
      Color(0xFFFFFFFF), // Blanc
      Color(0xFFFFEE58), // Jaune
      Color(0xFF43A047), // Vert
    ];
  }

  // Travis Scott - HIGHEST IN THE ROOM (Blanc à bleu clair à marron clair orangé à orange feu)
  if (a.contains('highest_in_the_room') ||
      albumNorm.contains('highest in the room') ||
      titleNorm.contains('highest in the room') ||
      idStr.contains('highest_in_the_room')) {
    return const [
      Color(0xFFFFFFFF), // Blanc
      Color(0xFF4FC3F7), // Bleu clair
      Color(0xFFA16B47), // Marron clair orangé
      Color(0xFFFF5722), // Orange feu
    ];
  }

  // The Weeknd - House of Balloons (Blanc à gris à noir)
  if (a.contains('house_of_balloons') ||
      albumNorm.contains('house of balloons') ||
      titleNorm.contains('house of balloons') ||
      idStr.contains('house_of_balloons')) {
    return const [
      Color(0xFFFFFFFF), // Blanc
      Color(0xFF757575), // Gris
      Color(0xFF111111), // Noir
    ];
  }

  // Calvin Harris & Disciples - How Deep Is Your Love (Blanc à rouge)
  if (titleNorm.contains('how deep is your love') ||
      idStr.contains('how_deep_is_your_love') ||
      a.contains('how_deep_is_your_love') ||
      albumNorm.contains('how deep is your love')) {
    return const [
      Color(0xFFFFFFFF), // Blanc
      Color(0xFFFFEBEE), // Blanc rosé
      Color(0xFFE53935), // Rouge
      Color(0xFFC62828), // Rouge profond
    ];
  }

  // A$AP Rocky - I Smoked Away My Brain (Noir à gris à blanc)
  if (titleNorm.contains('i smoked away my brain') ||
      idStr.contains('i_smoked_away_my_brain') ||
      a.contains('dont_be_dumb') ||
      albumNorm.contains('dont be dumb')) {
    return const [
      Color(0xFF111111), // Noir
      Color(0xFF757575), // Gris
      Color(0xFFFFFFFF), // Blanc
    ];
  }

  // Romeo Santos - Golden / Imitadora (Doré)
  if (a.contains('golden') ||
      albumNorm == 'golden' ||
      titleNorm.contains('imitadora') ||
      idStr.contains('imitadora')) {
    return const [
      Color(0xFFFFF8E1), // Blanc doré
      Color(0xFFFFD54F), // Doré scintillant
      Color(0xFFFFC107), // Doré
      Color(0xFFFFA000), // Or profond
    ];
  }

  // Ice Cube - The Predator / It Was a Good Day (Gris noir à marron blanc à blanc gris à blanc)
  if (a.contains('the_predator') ||
      albumNorm.contains('the predator') ||
      titleNorm.contains('it was a good day') ||
      idStr.contains('it_was_a_good_day')) {
    return const [
      Color(0xFF1C1C1C), // Gris noir
      Color(0xFFA89F91), // Marron blanc (sépia délavé)
      Color(0xFFCFD8DC), // Blanc gris
      Color(0xFFFFFFFF), // Blanc
    ];
  }

  // Tesher x Jason Derulo - Jalebi Baby (Bleu exubérance à orange)
  if (titleNorm.contains('jalebi baby') ||
      idStr.contains('jalebi_baby') ||
      a.contains('jalebi_baby') ||
      albumNorm.contains('jalebi baby')) {
    return const [
      Color(0xFF00838F), // Bleu exubérance (sarcelle vibrant)
      Color(0xFF00ACC1), // Bleu cyan chaud
      Color(0xFFFF6D00), // Orange
      Color(0xFFFF8F00), // Orange vif
    ];
  }

  // Ninho - Destin / La vie qu'on mène (Blanc à gris à bleu à jaune)
  if (a.contains('destin') ||
      albumNorm == 'destin' ||
      titleNorm.contains('la vie quon mene') ||
      titleNorm.contains("la vie qu'on mene") ||
      idStr.contains('la_vie_qu')) {
    return const [
      Color(0xFFFFFFFF), // Blanc
      Color(0xFF9E9E9E), // Gris
      Color(0xFF0288D1), // Bleu
      Color(0xFFFFC107), // Jaune
    ];
  }

  // Major Lazer & DJ Snake - Peace Is the Mission / Lean On (Violet foncé à rose)
  if (a.contains('peace_is_the_mission') ||
      albumNorm.contains('peace is the mission') ||
      titleNorm.contains('lean on') ||
      idStr.contains('lean_on')) {
    return const [
      Color(0xFF311B92), // Violet foncé
      Color(0xFF6A1B9A), // Violet moyen
      Color(0xFFD81B60), // Rose framboise
      Color(0xFFE91E63), // Rose
    ];
  }

  // DJ Snake - Encore / Let Me Love You (Vert à jaune sable à bleu clair clair)
  if (a.contains('encore') ||
      albumNorm == 'encore' ||
      titleNorm.contains('let me love you') ||
      idStr.contains('let_me_love_you')) {
    return const [
      Color(0xFF1B5E20), // Vert
      Color(0xFF2E7D32), // Vert moyen
      Color(0xFFD7B168), // Jaune sable
      Color(0xFFE1F5FE), // Bleu clair clair
    ];
  }

  // MGMT - Little Dark Age (Noir clair grisâtre à jaune)
  if (a.contains('little_dark_age') ||
      albumNorm.contains('little dark age') ||
      titleNorm.contains('little dark age') ||
      idStr.contains('little_dark_age')) {
    return const [
      Color(0xFF2B2B2B), // Noir clair grisâtre
      Color(0xFF424242), // Gris anthracite
      Color(0xFFFFD600), // Jaune
      Color(0xFFFFEA00), // Jaune vif
    ];
  }

  // Odetari & Cade Clair - XIII SORROWS / LOOK DON'T TOUCH (Noir à blanc à rose à violet)
  if (a.contains('xiii_sorrows') ||
      albumNorm.contains('xiii sorrows') ||
      titleNorm.contains('look dont touch') ||
      titleNorm.contains("look don't touch") ||
      idStr.contains('look_don')) {
    return const [
      Color(0xFF111111), // Noir
      Color(0xFFFFFFFF), // Blanc
      Color(0xFFEC407A), // Rose
      Color(0xFF8E24AA), // Violet
    ];
  }

  // Juice WRLD - Goodbye & Good Riddance / Lucid Dreams (Noir à rouge à bleu dominant à jaune)
  if (a.contains('goodbye_and_good_riddance') ||
      a.contains('goodbye') ||
      albumNorm.contains('goodbye') ||
      titleNorm.contains('lucid dreams') ||
      idStr.contains('lucid_dreams')) {
    return const [
      Color(0xFF111111), // Noir
      Color(0xFFE53935), // Rouge (prend moins de place)
      Color(0xFF0288D1), // Bleu profond
      Color(0xFF03A9F4), // Bleu vif (prend plus de place)
      Color(0xFF4FC3F7), // Bleu ciel
      Color(0xFFFFEA00), // Jaune
    ];
  }

  // Giga Papaskiri - Lucie from Paris (Noir à gris à blanc)
  if (titleNorm.contains('lucie from paris') ||
      idStr.contains('lucie_from_paris') ||
      a.contains('lucie_from_paris') ||
      albumNorm.contains('lucie from paris')) {
    return const [
      Color(0xFF111111), // Noir
      Color(0xFF757575), // Gris
      Color(0xFFFFFFFF), // Blanc
    ];
  }

  // Moha La Squale - Bendero / Luna (Vert foncé à vert à bleu à jaune sable)
  if (a.contains('bendero') ||
      albumNorm == 'bendero' ||
      titleNorm == 'luna' ||
      idStr.endsWith('/luna.flac') ||
      idStr == 'luna') {
    return const [
      Color(0xFF1B5E20), // Vert foncé
      Color(0xFF388E3C), // Vert
      Color(0xFF0288D1), // Bleu
      Color(0xFFE0BB76), // Jaune sable
    ];
  }

  // Maître Gims - Ma beauté / Mon coeur avait raison (Bleu grisé à jaune très clair)
  if (a.contains('ma_beaute') ||
      albumNorm.contains('ma beaute') ||
      titleNorm.contains('ma beaute') ||
      idStr.contains('ma_beaute')) {
    return const [
      Color(0xFF607D8B), // Bleu grisé
      Color(0xFF90A4AE), // Bleu gris clair
      Color(0xFFFFFDE7), // Jaune très clair
    ];
  }

  // DJ Snake - Carte Blanche / Magenta Riddim (Bleu ciel à gris à blanc)
  if (a.contains('carte_blanche') ||
      albumNorm.contains('carte blanche') ||
      titleNorm.contains('magenta riddim') ||
      idStr.contains('magenta_riddim')) {
    return const [
      Color(0xFF03A9F4), // Bleu ciel
      Color(0xFFB0BEC5), // Gris
      Color(0xFFFFFFFF), // Blanc
    ];
  }

  // 6ix9ine - DUMMY BOY / MALA (Noir à blanc à rouge à rose à violet à bleu à jaune à vert - 8 couleurs)
  if (a.contains('dummy_boy') ||
      albumNorm.contains('dummy boy') ||
      titleNorm.contains('mala') ||
      idStr.contains('mala')) {
    return const [
      Color(0xFF111111), // Noir
      Color(0xFFFFFFFF), // Blanc
      Color(0xFFE53935), // Rouge
      Color(0xFFEC407A), // Rose
      Color(0xFF8E24AA), // Violet
      Color(0xFF1E88E5), // Bleu
      Color(0xFFFFEA00), // Jaune
      Color(0xFF43A047), // Vert
    ];
  }

  // RK - 15 / Malya (Gris à jaune à orange feu)
  if (a.contains('15') ||
      albumNorm == '15' ||
      titleNorm.contains('malya') ||
      idStr.contains('malya')) {
    return const [
      Color(0xFF424242), // Gris
      Color(0xFFFFD600), // Jaune
      Color(0xFFFF5722), // Orange feu
    ];
  }

  // MHD - MHD / Maman j'ai mal (Rouge à jaune à vert à bleu à blanc à rouge)
  if (a.contains('mhd') ||
      albumNorm == 'mhd' ||
      titleNorm.contains('maman jai mal') ||
      titleNorm.contains("maman j'ai mal") ||
      idStr.contains('maman_j_ai_mal')) {
    return const [
      Color(0xFFE53935), // Rouge
      Color(0xFFFFEA00), // Jaune
      Color(0xFF2E7D32), // Vert
      Color(0xFF1976D2), // Bleu
      Color(0xFFFFFFFF), // Blanc
      Color(0xFFD32F2F), // Rouge
    ];
  }

  // Soolking - Vintage / Meleğim (Orangé à bleu foncé à violet)
  if (a.contains('vintage') ||
      albumNorm == 'vintage' ||
      titleNorm.contains('melegim') ||
      idStr.contains('melegim')) {
    return const [
      Color(0xFFFF7043), // Orangé
      Color(0xFF0D1B3E), // Bleu foncé
      Color(0xFF7B1FA2), // Violet
    ];
  }

  // Lorde - Melodrama / Melodrama (Violet à très peu de orangé à gris bleu à blanc gris)
  if (a.contains('melodrama') ||
      albumNorm.contains('melodrama') ||
      titleNorm.contains('melodrama') ||
      idStr.contains('melodrama')) {
    return const [
      Color(0xFF5E35B1), // Violet
      Color(0xFFFFAB91), // Très peu d'orangé
      Color(0xFF7986CB), // Gris bleu
      Color(0xFFE8EAF6), // Blanc gris
    ];
  }

  // Hamza - H-24 / Mi Amor (Bleu cyan avec plusieurs teintes)
  if (a.contains('h_24') ||
      a.contains('h-24') ||
      albumNorm.contains('h-24') ||
      albumNorm.contains('h 24') ||
      titleNorm.contains('mi amor') ||
      idStr.contains('mi_amor')) {
    return const [
      Color(0xFF00363A), // Bleu cyan très foncé
      Color(0xFF006064), // Bleu cyan profond
      Color(0xFF00838F), // Bleu cyan moyen
      Color(0xFF00ACC1), // Bleu cyan éclatant
      Color(0xFF4DD0E1), // Bleu cyan clair
      Color(0xFFE0F7FA), // Bleu cyan très clair
    ];
  }

  // J Balvin & Willy William - Vibras / Mi Gente (Vert à jaune à orangé à violet clair à violet foncé)
  if (a.contains('vibras') ||
      albumNorm.contains('vibras') ||
      titleNorm.contains('mi gente') ||
      idStr.contains('mi_gente')) {
    return const [
      Color(0xFF2E7D32), // Vert
      Color(0xFFFFEA00), // Jaune
      Color(0xFFFF5722), // Orangé
      Color(0xFFAB47BC), // Violet clair
      Color(0xFF4A148C), // Violet foncé
    ];
  }

  // C418 - Minecraft - Volume Alpha / Mice on Venus (Marron foncé à marron clair à vert clair à vert foncé)
  if (a.contains('minecraft_volume_alpha') ||
      albumNorm.contains('minecraft') ||
      titleNorm.contains('mice on venus') ||
      idStr.contains('mice_on_venus')) {
    return const [
      Color(0xFF3E2723), // Marron foncé
      Color(0xFF8D6E63), // Marron clair
      Color(0xFF7CB342), // Vert clair
      Color(0xFF1B5E20), // Vert foncé
    ];
  }

  // vs self - Everything Seems Better Now / Mourn (Blanc à jaune marron à 10% de bleu à 10% de rouge)
  if (a.contains('everything_seems_better_now') ||
      albumNorm.contains('everything seems better now') ||
      titleNorm.contains('mourn') ||
      idStr.contains('mourn')) {
    return const [
      Color(0xFFFFFFFF), // Blanc
      Color(0xFFC7B198), // Jaune marron (sépia sable)
      Color(0xFFA8947C), // Jaune marron soutenu
      Color(0xFF455A64), // Bleu (10%)
      Color(0xFFA94442), // Rouge (10%)
    ];
  }

  // Travis Scott - UTOPIA / MY EYES (Marron à noir)
  if (a.contains('utopia') ||
      albumNorm.contains('utopia') ||
      titleNorm.contains('my eyes') ||
      idStr.contains('my_eyes')) {
    return const [
      Color(0xFF5D4037), // Marron
      Color(0xFF2E1C14), // Marron très foncé
      Color(0xFF111111), // Noir
    ];
  }

  // Franglish & Tory Lanez - My Salsa (Jaune à orange à marron à bleu)
  if (titleNorm.contains('my salsa') ||
      idStr.contains('my_salsa') ||
      a.contains('my_salsa')) {
    return const [
      Color(0xFFFFEA00), // Jaune
      Color(0xFFFF6D00), // Orange
      Color(0xFF5D4037), // Marron
      Color(0xFF03A9F4), // Bleu
    ];
  }

  // Sufjan Stevens - Mystery of Love (Jaune à bleu légèrement foncé)
  if (titleNorm.contains('mystery of love') ||
      idStr.contains('mystery_of_love') ||
      a.contains('mystery_of_love') ||
      albumNorm.contains('mystery of love') ||
      albumNorm.contains('call me by your name')) {
    return const [
      Color(0xFFFFEA00), // Jaune vif
      Color(0xFFFFD54F), // Jaune ambré
      Color(0xFF1976D2), // Bleu
      Color(0xFF0D47A1), // Bleu légèrement foncé
    ];
  }

  // Sean Paul & Dua Lipa - Mad Love: The Prequel / No Lie (Rose néon à bleu néon)
  if (a.contains('mad_love') ||
      albumNorm.contains('mad love') ||
      titleNorm.contains('no lie') ||
      idStr.contains('no_lie')) {
    return const [
      Color(0xFFFF1493), // Rose néon vif
      Color(0xFFFF4081), // Rose néon
      Color(0xFF80D8FF), // Bleu néon clair
      Color(0xFF00E5FF), // Bleu néon
    ];
  }

  // Lacrim - VENI VIDI VICI / No lo sé (Rouge orangé vif à rouge éclatant à rouge carmin profond)
  if (a.contains('veni_vidi_vici') ||
      albumNorm.contains('veni vidi vici') ||
      titleNorm.contains('no lo se') ||
      idStr.contains('no_lo_se')) {
    return const [
      Color(0xFFFF3D00), // Rouge orangé vif (ex-orange jauné rendu rougeoyant)
      Color(0xFFE53935), // Rouge éclatant (ex-orange rendu rouge)
      Color(0xFFB71C1C), // Rouge carmin profond (ex-rouge orangé rendu rouge sombre)
    ];
  }

  // The Marías - Submarine / No One Noticed (Bleu foncé à bleu violet très clair à blanc grisâtre)
  if (a.contains('submarine') ||
      albumNorm.contains('submarine') ||
      titleNorm.contains('no one noticed') ||
      idStr.contains('no_one_noticed')) {
    return const [
      Color(0xFF0D1B3E), // Bleu foncé
      Color(0xFF9FA8DA), // Bleu violet très clair
      Color(0xFFECEFF1), // Blanc grisâtre
    ];
  }

  // TLC - FanMail / No Scrubs (Gris verdâtre à gris légèrement blanc)
  if (a.contains('fanmail') ||
      albumNorm.contains('fanmail') ||
      titleNorm.contains('no scrubs') ||
      idStr.contains('no_scrubs')) {
    return const [
      Color(0xFF4A5D4E), // Gris verdâtre foncé
      Color(0xFF6B7F6F), // Gris verdâtre
      Color(0xFFCFD8DC), // Gris légèrement blanc
    ];
  }

  // PLK - 2069' / Nouvelles (Rouge orangé à orange à beige à blanc à noir)
  if (a.contains('2069') ||
      albumNorm.contains('2069') ||
      titleNorm.contains('nouvelles') ||
      idStr.contains('nouvelles')) {
    return const [
      Color(0xFFE64A19), // Rouge orangé
      Color(0xFFFF9800), // Orange
      Color(0xFFD2B48C), // Beige
      Color(0xFFFFFFFF), // Blanc
      Color(0xFF111111), // Noir
    ];
  }

  // Lil Peep - LIVE FOREVER / nuts (Gris à orange à blanc orangé)
  if (a.contains('live_forever') ||
      albumNorm.contains('live forever') ||
      titleNorm.contains('nuts') ||
      idStr.contains('nuts')) {
    return const [
      Color(0xFF5D534E), // Gris
      Color(0xFFFF7043), // Orange
      Color(0xFFFFF3E0), // Blanc orangé
    ];
  }

  // Drake - Views / One Dance (Rouge à gris à blanc)
  if (a.contains('views') ||
      albumNorm == 'views' ||
      titleNorm.contains('one dance') ||
      idStr.contains('one_dance')) {
    return const [
      Color(0xFFD32F2F), // Rouge
      Color(0xFF607D8B), // Gris
      Color(0xFFECEFF1), // Blanc
    ];
  }

  // Mauvais Djo - L'undertaker Part.1 / Pilé (Bleu à jaune à marron bois)
  if (a.contains('undertaker') ||
      albumNorm.contains('undertaker') ||
      titleNorm.contains('pile') ||
      idStr.contains('pile')) {
    return const [
      Color(0xFF1565C0), // Bleu
      Color(0xFFFFEA00), // Jaune
      Color(0xFF8D5B3A), // Marron bois
    ];
  }

  // Pour deux âmes solitaires (Part.1) (Jaune blanc à jaune verdâtre à vert)
  if ((titleNorm.contains('ames solitaires') || idStr.contains('ames_solitaires')) &&
      (idStr.contains('part.1') || idStr.contains('part_1') || titleNorm.contains('part.1') || titleNorm.contains('part 1'))) {
    return const [
      Color(0xFFFFF9C4), // Jaune blanc
      Color(0xFFDCE775), // Jaune verdâtre
      Color(0xFF43A047), // Vert
    ];
  }

  // Pour deux âmes solitaires (Part.2) (Blanc à gris à gris foncé)
  if ((titleNorm.contains('ames solitaires') || idStr.contains('ames_solitaires')) &&
      (idStr.contains('part.2') || idStr.contains('part_2') || titleNorm.contains('part.2') || titleNorm.contains('part 2'))) {
    return const [
      Color(0xFFFFFFFF), // Blanc
      Color(0xFF9E9E9E), // Gris
      Color(0xFF37474F), // Gris foncé
    ];
  }

  // Niro - Les autres / Printemps blanc (Rouge à gris foncé à blanc)
  if (a.contains('les_autres') ||
      albumNorm.contains('les autres') ||
      titleNorm.contains('printemps blanc') ||
      idStr.contains('printemps_blanc')) {
    return const [
      Color(0xFFD32F2F), // Rouge
      Color(0xFF263238), // Gris foncé
      Color(0xFFFFFFFF), // Blanc
    ];
  }

  // Major Lazer & J Balvin - Music Is the Weapon / Que calor (Bleu clair à vert jaunâtre à orange dominant à jaune blanchâtre)
  if (a.contains('music_is_the_weapon') ||
      albumNorm.contains('music is the weapon') ||
      titleNorm.contains('que calor') ||
      idStr.contains('que_calor')) {
    return const [
      Color(0xFF4FC3F7), // Bleu clair
      Color(0xFFC0CA33), // Vert jaunâtre
      Color(0xFFFF6D00), // Orange (dominant 1)
      Color(0xFFFF5722), // Orange (dominant 2)
      Color(0xFFFFF9C4), // Jaune blanchâtre
    ];
  }

  // Dadju - Gentleman 2.0 / Reine (Rouge à blanc à gris foncé à noir)
  if (a.contains('gentleman') ||
      albumNorm.contains('gentleman') ||
      titleNorm.contains('reine') ||
      idStr.contains('reine')) {
    return const [
      Color(0xFFE53935), // Rouge
      Color(0xFFFFFFFF), // Blanc
      Color(0xFF37474F), // Gris foncé
      Color(0xFF111111), // Noir
    ];
  }

  // Niska - Commando / Réseaux (Jaune marron à vert à bleu grisâtre)
  if (a.contains('commando') ||
      albumNorm.contains('commando') ||
      titleNorm.contains('reseaux') ||
      idStr.contains('reseaux')) {
    return const [
      Color(0xFFC59B27), // Jaune marron
      Color(0xFF558B2F), // Vert
      Color(0xFF546E7A), // Bleu grisâtre
    ];
  }

  // Clean Bandit - What Is Love? / Rockabye (Blanc nuage à gris à bleu ciel à bleu foncé)
  if (titleNorm.contains('rockabye') ||
      idStr.contains('rockabye') ||
      a.contains('what_is_love') ||
      albumNorm.contains('what is love')) {
    return const [
      Color(0xFFFFFFFF), // Blanc nuage
      Color(0xFF90A4AE), // Gris
      Color(0xFF03A9F4), // Bleu ciel
      Color(0xFF0D47A1), // Bleu foncé
    ];
  }

  // Bilal Hassani - Euphories / Roi (Rose pastel à 70% et bleu clair pastel à 30%)
  if (titleNorm == 'roi' ||
      titleNorm.startsWith('roi ') ||
      idStr == 'roi' ||
      a.contains('euphories') ||
      albumNorm.contains('euphories')) {
    return const [
      Color(0xFFF48FB1), // Rose pastel
      Color(0xFFF06292), // Rose pastel moyen
      Color(0xFFEC407A), // Rose pastel profond
      Color(0xFF80D8FF), // Bleu clair pastel (30%)
    ];
  }

  // The Weeknd & Anitta - Hurry Up Tomorrow / São Paulo (Blanc à marron jaunâtre à noir)
  if (titleNorm.contains('sao paulo') ||
      idStr.contains('sao_paulo') ||
      a.contains('hurry_up_tomorrow') ||
      albumNorm.contains('hurry up tomorrow')) {
    return const [
      Color(0xFFFFFFFF), // Blanc
      Color(0xFFB08958), // Marron jaunâtre
      Color(0xFF111111), // Noir
    ];
  }

  // Maître Gims - Mon coeur avait raison / Sapés comme jamais (Bleu foncé grisâtre à marron clair à noir)
  if (titleNorm.contains('sapes comme jamais') ||
      idStr.contains('sapes_comme_jamais') ||
      a.contains('sapes_comme_jamais')) {
    return const [
      Color(0xFF2E3A46), // Bleu foncé grisâtre
      Color(0xFF8D6E63), // Marron clair
      Color(0xFF111111), // Noir
    ];
  }

  // David Guetta - 7 / Say My Name (Vert à bleu foncé à marron orangé à blanc)
  if (titleNorm.contains('say my name') ||
      idStr.contains('say_my_name') ||
      a == '7' ||
      albumNorm == '7') {
    return const [
      Color(0xFF2E7D32), // Vert
      Color(0xFF0D47A1), // Bleu foncé
      Color(0xFFD84315), // Marron orangé
      Color(0xFFFFFFFF), // Blanc
    ];
  }

  // Chimbala x Omega - Se Me Nota (Agarrame) (Blanc à jaune à orange à orange foncé)
  if (titleNorm.contains('se me nota') ||
      idStr.contains('se_me_nota') ||
      a.contains('se_me_nota') ||
      albumNorm.contains('se me nota')) {
    return const [
      Color(0xFFFFFFFF), // Blanc
      Color(0xFFFFEA00), // Jaune
      Color(0xFFFF9800), // Orange
      Color(0xFFE65100), // Orange foncé
    ];
  }

  // Tyler, The Creator - Flower Boy / See You Again (Vert à jaune à jaune orangé à orange profond)
  if (titleNorm.contains('see you again') ||
      idStr.contains('see_you_again') ||
      a.contains('flower_boy') ||
      albumNorm.contains('flower boy')) {
    return const [
      Color(0xFF2E7D32), // Vert
      Color(0xFFFFEB3B), // Jaune
      Color(0xFFFFB300), // Jaune orangé
      Color(0xFFE64A19), // Orange profond
    ];
  }

  // Travis Scott - ASTROWORLD / SICKO MODE (Bleu à jaune doré à orange doré à rouge 10%)
  if (titleNorm.contains('sicko mode') ||
      idStr.contains('sicko_mode') ||
      a.contains('astroworld') ||
      albumNorm.contains('astroworld')) {
    return const [
      Color(0xFF0288D1), // Bleu
      Color(0xFFFFD54F), // Jaune doré
      Color(0xFFFF9800), // Orange doré
      Color(0xFFFF6D00), // Orange doré profond
      Color(0xFFE53935), // Rouge (10%)
    ];
  }

  // The Neighbourhood - The Neighbourhood / Softcore (Blanc à noir)
  if (titleNorm.contains('softcore') ||
      idStr.contains('softcore') ||
      a == 'the_neighbourhood' ||
      albumNorm == 'the neighbourhood') {
    return const [
      Color(0xFFFFFFFF), // Blanc
      Color(0xFF757575), // Gris intermédiaire
      Color(0xFF111111), // Noir
    ];
  }

  // ThxSoMch - SPIT IN MY FACE! (Beige foncé à marron clair à noir clair)
  if (titleNorm.contains('spit in my face') ||
      idStr.contains('spit_in_my_face') ||
      a.contains('spit_in_my_face') ||
      albumNorm.contains('spit in my face')) {
    return const [
      Color(0xFFBCAAA4), // Beige foncé
      Color(0xFF8D6E63), // Marron clair
      Color(0xFF2C2C2C), // Noir clair
    ];
  }

  // twenty one pilots - Blurryface / Stressed Out (Blanc à gris à rouge à noir)
  if (titleNorm.contains('stressed out') ||
      idStr.contains('stressed_out') ||
      a.contains('blurryface') ||
      albumNorm.contains('blurryface')) {
    return const [
      Color(0xFFFFFFFF), // Blanc
      Color(0xFF757575), // Gris
      Color(0xFFE53935), // Rouge
      Color(0xFF111111), // Noir
    ];
  }

  // Post Malone & Swae Lee - Sunflower (Rouge à blanc à noir)
  if (titleNorm.contains('sunflower') || idStr.contains('sunflower')) {
    return const [
      Color(0xFFE53935), // Rouge
      Color(0xFFFFFFFF), // Blanc
      Color(0xFF111111), // Noir
    ];
  }

  // Kendrick Lamar - good kid, m.A.A.d city / Swimming Pools (Blanc à vert grisâtre à marron à bleu ciel)
  if (titleNorm.contains('swimming pools') ||
      idStr.contains('swimming_pools') ||
      a.contains('good_kid') ||
      albumNorm.contains('good kid')) {
    return const [
      Color(0xFFFFFFFF), // Blanc
      Color(0xFF78909C), // Vert grisâtre
      Color(0xFF4E342E), // Marron
      Color(0xFF03A9F4), // Bleu ciel
    ];
  }

  // Luidji - Tristesse Business : Saison 1 / Système (Bleu foncé à bleu turquoise à jaune légèrement orangé)
  if (titleNorm.contains('systeme') ||
      idStr.contains('systeme') ||
      a.contains('tristesse_business') ||
      albumNorm.contains('tristesse business')) {
    return const [
      Color(0xFF0D47A1), // Bleu foncé
      Color(0xFF00E5FF), // Bleu turquoise
      Color(0xFFFFB74D), // Jaune légèrement orangé
    ];
  }

  // Glass Animals - How to Be a Human Being / Take a Slice (Vert à bleu à jaune à orange)
  if (titleNorm.contains('take a slice') ||
      idStr.contains('take_a_slice') ||
      a.contains('how_to_be_a_human_being') ||
      albumNorm.contains('how to be a human being')) {
    return const [
      Color(0xFF43A047), // Vert
      Color(0xFF0288D1), // Bleu
      Color(0xFFFFEB3B), // Jaune
      Color(0xFFFF6D00), // Orange
    ];
  }

  // Koba LaD - Ténébreux / Ténébreux #1 (Rouge à gris foncé à noir clair)
  if (titleNorm.contains('tenebreux') ||
      idStr.contains('tenebreux') ||
      a.contains('tenebreux') ||
      albumNorm.contains('tenebreux')) {
    return const [
      Color(0xFFD32F2F), // Rouge
      Color(0xFF37474F), // Gris foncé
      Color(0xFF262626), // Noir clair
    ];
  }

  // Seekae - Test & Recognise (Flume Re-work) (Blanc à noir)
  if ((titleNorm.contains('test') && titleNorm.contains('recognise')) ||
      (idStr.contains('test') && idStr.contains('recognise')) ||
      a.contains('test_and_recognise') ||
      albumNorm.contains('test & recognise')) {
    return const [
      Color(0xFFFFFFFF), // Blanc
      Color(0xFF757575), // Gris intermédiaire
      Color(0xFF111111), // Noir
    ];
  }

  // The Weeknd - Beauty Behind the Madness / The Hills (Gris à noir)
  if (titleNorm.contains('the hills') ||
      idStr.contains('the_hills') ||
      a.contains('beauty_behind_the_madness') ||
      albumNorm.contains('beauty behind the madness')) {
    return const [
      Color(0xFFB0BEC5), // Gris clair
      Color(0xFF546E7A), // Gris
      Color(0xFF111111), // Noir
    ];
  }

  // Tame Impala - Currents / The Less I Know the Better (Gris à jaune orangé à rose à rouge rosé à violet)
  if (titleNorm.contains('less i know') ||
      idStr.contains('less_i_know') ||
      a.contains('currents') ||
      albumNorm.contains('currents')) {
    return const [
      Color(0xFF9E9E9E), // Gris
      Color(0xFFFFB300), // Jaune orangé
      Color(0xFFEC407A), // Rose
      Color(0xFFE91E63), // Rouge rosé
      Color(0xFF6A1B9A), // Violet
    ];
  }

  // Maître Gims - À contrecoeur (Pilule Violette) / Tout donner (Blanc grisâtre à violet foncé)
  if (titleNorm.contains('tout donner') ||
      idStr.contains('tout_donner') ||
      a.contains('contrecoeur') ||
      albumNorm.contains('contrecoeur')) {
    return const [
      Color(0xFFECEFF1), // Blanc grisâtre
      Color(0xFF512DA8), // Violet moyen
      Color(0xFF240046), // Violet foncé
    ];
  }

  // Burak Yeter - Tuesday (Violet clair à rose violet)
  if (titleNorm.contains('tuesday') ||
      idStr.contains('tuesday') ||
      a.contains('tuesday') ||
      albumNorm.contains('tuesday')) {
    return const [
      Color(0xFFBA68C8), // Violet clair
      Color(0xFFAB47BC), // Violet moyen
      Color(0xFFD81B60), // Rose violet
    ];
  }

  // French Montana - Jungle Rules / Unforgettable (Bleu verdâtre à jaune beige à orange blanc fourrure)
  if (titleNorm.contains('unforgettable') ||
      idStr.contains('unforgettable') ||
      a.contains('jungle_rules') ||
      albumNorm.contains('jungle rules')) {
    return const [
      Color(0xFF4DB6AC), // Bleu verdâtre
      Color(0xFFE0C39E), // Jaune beige
      Color(0xFFE89858), // Orange
      Color(0xFFFFF3E0), // Blanc fourrure
    ];
  }

  // Sexion d'Assaut - L'École des points vitaux / Wati by Night (Blanc à rouge à noir)
  if (titleNorm.contains('wati by night') ||
      idStr.contains('wati_by_night') ||
      a.contains('points_vitaux') ||
      albumNorm.contains('points vitaux')) {
    return const [
      Color(0xFFFFFFFF), // Blanc
      Color(0xFFD32F2F), // Rouge
      Color(0xFF111111), // Noir
    ];
  }

  // ridgeclub - where am i supposed to go? (Jaune à gris à gris de route à bleu du ciel)
  if (titleNorm.contains('where am i supposed to go') ||
      idStr.contains('where_am_i_supposed_to_go') ||
      a.contains('where_am_i_supposed_to_go') ||
      albumNorm.contains('where am i supposed to go')) {
    return const [
      Color(0xFFFFD54F), // Jaune
      Color(0xFF90A4AE), // Gris
      Color(0xFF455A64), // Gris de route (béton)
      Color(0xFF81D4FA), // Bleu du ciel
    ];
  }

  // Eminem - Curtain Call: The Hits / Without Me (Noir à jaune doré à rouge)
  if (titleNorm.contains('without me') ||
      idStr.contains('without_me') ||
      a.contains('curtain_call') ||
      albumNorm.contains('curtain call')) {
    return const [
      Color(0xFF111111), // Noir
      Color(0xFFFFD54F), // Jaune doré
      Color(0xFFD32F2F), // Rouge
    ];
  }

  // Nicky Jam & J Balvin - X (Spanglish Version) (Vert à jaune à rouge orangé)
  if (titleNorm == 'x' ||
      titleNorm.startsWith('x ') ||
      titleNorm.startsWith('x(') ||
      idStr.startsWith('x_') ||
      a == 'x' ||
      albumNorm.startsWith('x ')) {
    return const [
      Color(0xFF43A047), // Vert
      Color(0xFFFFEA00), // Jaune
      Color(0xFFE64A19), // Rouge orangé
    ];
  }

  // Don Miguelo - Y que fue? (Blanc à marron à noir)
  if (titleNorm.contains('y que fue') ||
      idStr.contains('y_que_fue') ||
      a.contains('y_que_fue') ||
      albumNorm.contains('y que fue')) {
    return const [
      Color(0xFFFFFFFF), // Blanc
      Color(0xFF8D6E63), // Marron
      Color(0xFF111111), // Noir
    ];
  }

  // JAY-Z - The Blueprint 2 / '03 Bonnie & Clyde (Bleu à gris clair à gris foncé à noir clair)
  if ((titleNorm.contains('bonnie') && titleNorm.contains('clyde')) ||
      idStr.contains('bonnie') ||
      a.contains('blueprint_2') ||
      albumNorm.contains('blueprint')) {
    return const [
      Color(0xFF1565C0), // Bleu
      Color(0xFFCFD8DC), // Gris clair
      Color(0xFF455A64), // Gris foncé
      Color(0xFF212121), // Noir clair
    ];
  }

  // The Neighbourhood - I Love You.
  if (a.contains('i_love_you') || albumNorm.contains('i love you') || titleNorm.contains('sweater weather') || idStr.contains('sweater_weather')) {
    return const [
      Color(0xFFFFFFFF), // Blanc
      Color(0xFF9E9E9E), // Gris
      Color(0xFF000000), // Noir
    ];
  }

  // Tyler, The Creator - IGOR
  if (a.contains('igor') || albumNorm.contains('igor') || titleNorm.contains('gone, gone') || titleNorm.contains('gone gone') || idStr.contains('gone')) {
    return const [
      Color(0xFFFFC0CB), // Rose clair
      Color(0xFFFFC0CB),
      Color(0xFFFFC0CB),
    ];
  }

  // Nirvana - Nevermind
  if (a.contains('nevermind') || albumNorm.contains('nevermind') || titleNorm.contains('smells like teen spirit') || idStr.contains('smells_like_teen_spirit')) {
    return const [
      Color(0xFFFFF59D), // Jaune (peu)
      Color(0xFF00E5FF), // Cyan
      Color(0xFF1976D2), // Bleu
    ];
  }

  // Damso - Bēyāh
  if (a.contains('beyah') || albumNorm.contains('beyah') || a.contains('bēyāh') || idStr.contains('pa_pa_paw') || titleNorm.contains('pa pa paw')) {
    return const [
      Color(0xFFFFFFFF), // Blanc
      Color(0xFFBDBDBD), // Gris moyen
      Color(0xFF424242), // Gris foncé
    ];
  }

  // PNL - Dans la légende
  if (a.contains('dans_la_legende') ||
      albumNorm.contains('dans la legende') ||
      titleNorm.contains('onizuka') ||
      idStr.contains('onizuka') ||
      titleNorm.contains('luz de luna') ||
      idStr.contains('luz_de_luna') ||
      titleNorm.contains('qlf') ||
      idStr.contains('qlf')) {
    return const [
      Color(0xFFFFEB3B), // Jaune
      Color(0xFFFF9800), // Orange
      Color(0xFF9C27B0), // Violet
    ];
  }

  // PNL - Deux frères
  if (a.contains('deux_freres') || albumNorm.contains('deux freres') || titleNorm.contains('misere') || idStr.contains('misere')) {
    return const [
      Color(0xFF2196F3), // Bleu
      Color(0xFF8E24AA), // Violet (transition)
      Color(0xFFF44336), // Rouge
    ];
  }

  // Dua Lipa - Future Nostalgia
  if (a.contains('future_nostalgia') || albumNorm.contains('future nostalgia')) {
    return const [
      Color(0xFF2196F3), // Bleu
      Color(0xFFE91E63), // Rose
      Color(0xFFFFFFFF), // Blanc
      Color(0xFFFFEB3B), // Jaune
    ];
  }

  // Ninho - M.I.L.S
  if (a.contains('mils') || albumNorm.contains('mils')) {
    return const [
      Color(0xFFFFF8E7), // Blanc légèrement doré (Cosmic Latte)
      Color(0xFFFFF8E7),
      Color(0xFFD4AF37), // Or classique (Metallic Gold)
      Color(0xFFD4AF37),
    ];
  }

  // Kaaris - Or Noir
  if (a.contains('or_noir') || albumNorm.contains('or noir')) {
    return const [
      Color(0xFFFBE18D), // Or clair scintillant (pailleté)
      Color(0xFFFBE18D),
      Color(0xFFC5A059), // Or profond
      Color(0xFFC5A059),
    ];
  }

  // Damso - Batterie Faible
  if (a.contains('batterie_faible') || albumNorm.contains('batterie faible')) {
    return const [
      Color(0xFFFF7597),
      Color(0xFFFF7597),
      Color(0xFFC2185B),
      Color(0xFFC2185B),
    ];
  }

  // Damso - Lithopédion
  if (a.contains('lithopedion') || albumNorm.contains('lithopedion')) {
    return const [
      Color(0xFFB0BEC5),
      Color(0xFFB0BEC5),
      Color(0xFF2C3E50),
      Color(0xFF2C3E50),
    ];
  }

  // Nekfeu - Feu
  if (a == 'feu' || albumNorm == 'feu') {
    return const [
      Color(0xFFFF5722),
      Color(0xFFFF5722),
      Color(0xFFFFD700),
      Color(0xFFFFD700),
    ];
  }

  // Nekfeu - Cyborg
  if (a.contains('cyborg') || albumNorm.contains('cyborg')) {
    return const [
      Color(0xFFE53935),
      Color(0xFFE53935),
      Color(0xFF4A148C),
      Color(0xFF4A148C),
    ];
  }

  // Damso - Ipséité
  if (a.contains('ipseite') || albumNorm.contains('ipseite')) {
    return const [
      Color(0xFFF39C12),
      Color(0xFFF39C12),
      Color(0xFFFFD700),
      Color(0xFFFFD700),
    ];
  }

  // Angèle - Nonante-Cinq
  if (a.contains('nonante') || albumNorm.contains('nonante')) {
    return const [
      Color(0xFF0D47A1), // Bleu foncé
      Color(0xFF0D47A1), // Bleu foncé
      Color(0xFFD32F2F), // Rouge
      Color(0xFFFFC107), // Jaune
    ];
  }

  // Dadju - Poison ou Antidote
  if (a.contains('poison_ou_antidote') || (albumNorm.contains('poison') && albumNorm.contains('antidote'))) {
    return const [
      Color(0xFF1B5E20), // Vert très sombre
      Color(0xFF2E7D32), // Vert
      Color(0xFFFFB300), // Jaune
      Color(0xFFE040FB), // Violet (tirant vers le magenta pour bien se mélanger au jaune)
    ];
  }

  // Dégradé par défaut
  return const [
    Color(0xFF9C27B0),
    Color(0xFF9C27B0),
    Color(0xFF311B92),
    Color(0xFF311B92),
  ];
}

