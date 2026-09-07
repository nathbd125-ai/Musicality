# -*- coding: utf-8 -*-
"""
Script de synchronisation des VRAIES paroles mot par mot (Syllable / Enhanced LRC).
A executer sur votre VPS a cote de vos musiques.

Fonctionnalites :
1. Verifie la DUREE EXACTE de votre fichier audio (.flac / .mp3) pour eviter tout decalage
   (ex: evite de confondre une version Radio Edit 2:20 avec une version Album 2:30).
2. Interroge NetEase Cloud Music pour recuperer la VRAIE synchro syllabe par syllabe.
3. Secours automatique sur LRCLIB avec verification de la duree exacte.
4. Securite : Ne remplace un fichier existant QUE pour l'ameliorer en vrai mot-par-mot (avec backup .bak).
"""

import os
import sys
import re
import json
import time
import urllib.request
import urllib.parse
import urllib.error

try:
    from mutagen.flac import FLAC
    from mutagen.mp3 import MP3
    from mutagen.easyid3 import EasyID3
except ImportError:
    print("Module 'mutagen' manquant. Installez-le avec : pip3 install mutagen")
    sys.exit(1)

def ms_to_timestamp(ms):
    total_seconds = max(0, int(ms)) / 1000.0
    minutes = int(total_seconds // 60)
    seconds = total_seconds % 60
    return f"{minutes:02d}:{seconds:05.2f}"

def is_credit_line(text, line_seconds=0):
    """Detecte et ignore les lignes de credits parasites (by..., written by..., intro artiste - titre)."""
    clean = text.strip().lower()
    if not clean:
        return True

    credit_keywords = [
        "written by", "lyrics by", "synced by", "composed by", "produced by",
        "paroles par", "ecrit par", "écrit par", "compositeur", "auteur",
        "arranger", "arranged by", "mixed by", "mastered by", "sync by",
        "rentanadviser", "musixmatch", "genius.com", "lrclib"
    ]
    if any(k in clean for k in credit_keywords):
        return True

    # "by quelqu'un" ou "(by ...)"
    if re.search(r'\bby\s+[a-z0-9_\-\. ]+', clean) and len(clean) < 60:
        return True

    # Tags chinois NetEase
    chinese_tags = ["作词", "作曲", "编曲", "制作", "录音", "混音", "吉他", "贝斯", "鼓", "和声", "母带", "发行"]
    if any(tag in text for tag in chinese_tags):
        return True

    # Ligne d'intro dans les 6 premieres secondes du type "Artiste - Titre"
    if line_seconds <= 6.0 and (" - " in text or " : " in text) and len(clean.split()) <= 8:
        return True

    return False

def filter_lrc_credits(lrc_text):
    """Nettoie un texte LRC de toute ligne de credit."""
    if not lrc_text:
        return None
    time_regex = re.compile(r'\[(\d+):(\d+(?:\.\d+)?)\]')
    clean_lines = []
    for line in lrc_text.split('\n'):
        raw = line.strip()
        if not raw:
            continue
        m = time_regex.search(raw)
        sec = 0.0
        if m:
            mins = int(m.group(1))
            secs = float(m.group(2))
            sec = mins * 60.0 + secs
        text_only = time_regex.sub('', raw)
        # Supprime les tags mot-par-mot pour verifier le contenu
        text_only = re.sub(r'<\d+:\d+(?:\.\d+)?>', '', text_only).strip()
        if is_credit_line(text_only, sec):
            continue
        clean_lines.append(raw)
    return "\n".join(clean_lines) if clean_lines else None

def fetch_netease_syllable_lyrics(title, artist, local_duration=0):
    """
    Recupere les VRAIES paroles syllabe par syllabe / mot par mot
    en verifiant que la duree du morceau correspond a votre fichier audio (marge max: 1.5s).
    Recherche TOUJOURS le titre complet en priorite absolue.
    """
    clean_artist = re.sub(r'\(.*?\)|\[.*?\]', '', artist).strip()

    queries = []
    # 1. TOUJOURS le titre complet avec artiste (ex: "Afro Trap Part 11 King Kong MHD")
    t_full = re.sub(r'[\(\)\[\],_\-\.]', ' ', title).strip()
    t_full_clean = " ".join(t_full.split())
    queries.append(f"{t_full_clean} {clean_artist}".strip())

    # 2. Titre original nettoye des underscores
    queries.append(f"{title.replace('_', ' ')} {clean_artist}".strip())

    # 3. Titre sans le contenu entre parentheses s'il y a un remix/feat
    t_no_paren = re.sub(r'\(.*?\)|\[.*?\]', '', title).replace('_', ' ').replace(',', ' ').strip()
    queries.append(f"{' '.join(t_no_paren.split())} {clean_artist}".strip())

    headers = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"}

    # Eliminer les doublons de requetes
    queries = list(dict.fromkeys([q for q in queries if q]))

    for query in queries:
        search_url = f"https://music.163.com/api/search/get?s={urllib.parse.quote(query)}&type=1&limit=5"
        try:
            req = urllib.request.Request(search_url, headers=headers)
            with urllib.request.urlopen(req, timeout=8) as resp:
                data = json.loads(resp.read().decode('utf-8'))
                songs = data.get("result", {}).get("songs", [])
                if not songs:
                    continue

                if local_duration > 0:
                    songs.sort(key=lambda s: abs(local_duration - (s.get("dt", 0) / 1000.0)))

                for song in songs:
                    song_id = song.get("id")
                    if not song_id:
                        continue

                    remote_duration_sec = song.get("dt", 0) / 1000.0
                    if local_duration > 0 and remote_duration_sec > 0:
                        diff = abs(local_duration - remote_duration_sec)
                        if diff > 1.5:
                            continue

                    lyric_url = f"https://music.163.com/api/song/lyric?id={song_id}&lv=-1&yv=1"
                    lreq = urllib.request.Request(lyric_url, headers=headers)
                    with urllib.request.urlopen(lreq, timeout=8) as lresp:
                        ldata = json.loads(lresp.read().decode('utf-8'))
                        yrc = ldata.get("yrc", {}).get("lyric")
                        if yrc and "(" in yrc:
                            enhanced_lrc = convert_yrc_to_enhanced_lrc(yrc)
                            if enhanced_lrc:
                                clean_lrc = filter_lrc_credits(enhanced_lrc)
                                if clean_lrc:
                                    return clean_lrc
        except Exception:
            pass

    return None

def convert_yrc_to_enhanced_lrc(yrc_text):
    """
    Convertit le format YRC (syllabes) en Enhanced LRC standard (<mm:ss.xx>mot).
    """
    lines = []
    line_regex = re.compile(r'^\[(\d+),(\d+)\](.*)$')
    word_regex = re.compile(r'\((?:(\d+),(\d+)(?:,\d+)?)\)([^\(\[]+)')

    for raw in yrc_text.split('\n'):
        raw = raw.strip()
        if not raw:
            continue
        m = line_regex.match(raw)
        if not m:
            continue
        line_start = int(m.group(1))
        content = m.group(3)

        # Verification rapide de credit
        if is_credit_line(content, line_start / 1000.0):
            continue

        words = word_regex.findall(content)
        if words:
            formatted_words = []
            for w_start, w_dur, w_text in words:
                text_clean = w_text.strip().replace("\uff08", "(").replace("\uff09", ")")
                if not text_clean or text_clean in [",", ".", "!", "?", "'", "’"]:
                    continue
                formatted_words.append(f"<{ms_to_timestamp(w_start)}>{text_clean}")
            if formatted_words:
                lines.append(f"[{ms_to_timestamp(line_start)}] " + " ".join(formatted_words))
        else:
            clean = re.sub(r'\(.*?\)', '', content).strip().replace("\uff08", "(").replace("\uff09", ")")
            if clean and not is_credit_line(clean, line_start / 1000.0):
                lines.append(f"[{ms_to_timestamp(line_start)}] {clean}")

    return "\n".join(lines) if lines else None

def get_lrclib_lyrics(title, artist, local_duration=0):
    """Secours sur LRCLIB avec parametre de duree pour garantir la version exacte"""
    clean_title = re.sub(r'\(.*?\)|\[.*?\]', '', title).replace('_', ' ').strip()
    clean_artist = re.sub(r'\(.*?\)|\[.*?\]', '', artist).strip()
    url = f"https://lrclib.net/api/get?track_name={urllib.parse.quote(clean_title)}&artist_name={urllib.parse.quote(clean_artist)}"
    if local_duration > 0:
        url += f"&duration={int(local_duration)}"

    headers = {"User-Agent": "MusicalityLrcSync/1.0"}
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=8) as resp:
            data = json.loads(resp.read().decode('utf-8'))
            synced = data.get("syncedLyrics")
            return filter_lrc_credits(synced)
    except Exception:
        return None

def main():
    dossier = "."
    print("=" * 70)
    print("   Synchroniseur de VRAIES Paroles Mot par Mot (Musicality)")
    print("=" * 70)

    fichiers_audio = set()
    for f in os.listdir(dossier):
        lower = f.lower()
        if (lower.endswith(".flac") or lower.endswith(".mp3")) and not lower.endswith("-hires.flac"):
            nom_base = os.path.splitext(f)[0].replace("-hires", "")
            fichiers_audio.add(nom_base)

    print(f"\n[*] {len(fichiers_audio)} musiques detectees dans le dossier.")

    succes_mot_par_mot = 0
    succes_standard = 0

    for idx, nom_base in enumerate(sorted(fichiers_audio), 1):
        target_lrc = f"{nom_base}.lrc"

        flac_path = f"{nom_base}.flac"
        mp3_path = f"{nom_base}.mp3"
        source_file = flac_path if os.path.exists(flac_path) else (mp3_path if os.path.exists(mp3_path) else None)

        if not source_file:
            continue

        titre = nom_base.replace("_", " ")
        artiste = "Inconnu"
        duree = 0

        try:
            if source_file.endswith(".flac"):
                audio = FLAC(source_file)
            else:
                audio = MP3(source_file, ID3=EasyID3)

            if audio.tags:
                titre = audio.tags.get("title", [titre])[0]
                artiste = audio.tags.get("artist", [artiste])[0]
            duree = int(audio.info.length)
        except Exception:
            pass

        already_has_lrc = os.path.exists(target_lrc) and os.path.getsize(target_lrc) > 10
        already_has_word_by_word = False

        if already_has_lrc:
            try:
                with open(target_lrc, "r", encoding="utf-8") as f_check:
                    content_check = f_check.read()
                    if "<" in content_check and ">" in content_check:
                        already_has_word_by_word = True
            except Exception:
                pass

        if already_has_word_by_word:
            print(f"[{idx}/{len(fichiers_audio)}] {titre} -> Deja en VRAI mot par mot. Ignore.")
            succes_mot_par_mot += 1
            continue

        duree_str = f"{duree // 60}:{duree % 60:02d}" if duree > 0 else "?"
        print(f"[{idx}/{len(fichiers_audio)}] {titre} - {artiste} ({duree_str})")

        # 1. Recherche de la VRAIE synchro mot par mot en filtrant sur la duree exacte
        lrc_content = fetch_netease_syllable_lyrics(titre, artiste, local_duration=duree)
        is_real_word_by_word = False

        if lrc_content:
            is_real_word_by_word = True
        elif not already_has_lrc:
            # 2. Secours sur LRCLIB avec la duree exacte de votre fichier
            lrc_content = get_lrclib_lyrics(titre, artiste, local_duration=duree)

        if lrc_content:
            if is_real_word_by_word:
                if already_has_lrc:
                    try:
                        bak_file = f"{target_lrc}.bak"
                        if not os.path.exists(bak_file):
                            import shutil
                            shutil.copyfile(target_lrc, bak_file)
                    except Exception:
                        pass

                with open(target_lrc, "w", encoding="utf-8") as out:
                    out.write(lrc_content)
                print(f"    -> [UPGRADE VRAI MOT PAR MOT] Enregistre dans {target_lrc}")
                succes_mot_par_mot += 1
            else:
                with open(target_lrc, "w", encoding="utf-8") as out:
                    out.write(lrc_content)
                print(f"    -> [Synchro ligne] Enregistre dans {target_lrc}")
                succes_standard += 1
        else:
            if already_has_lrc:
                print("    -> [Conserve] Pas de mot par mot correspondant a la duree, ancien fichier conserve.")
            else:
                print("    -> [Non trouve]")

        time.sleep(0.3)

    print("\n" + "=" * 70)
    print(f"Termine ! {succes_mot_par_mot} en VRAI mot par mot | {succes_standard} en synchro ligne.")
    print("=" * 70)

if __name__ == "__main__":
    main()
