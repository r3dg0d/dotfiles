#!/usr/bin/env python3
"""Fetch lyrics on demand from an ordered list of sources (lyrics.json); no credentials.

Default order: LRCLIB (synced, get then search) -> NetEase Cloud Music (synced LRC) -> lyrics.ovh (plain).
"""
import json
import re
import sys
from difflib import SequenceMatcher
from html.parser import HTMLParser
from urllib.parse import urlencode, urlparse
from urllib.request import Request, urlopen
from urllib.error import HTTPError, URLError


class LyricsParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.depth = 0
        self.parts = []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if self.depth:
            if tag == 'br':
                self.parts.append('\n')
            elif tag not in ('img', 'input', 'hr', 'meta', 'link', 'wbr'):
                self.depth += 1
        elif attrs.get('data-lyrics-container') == 'true' or 'Lyrics__Container' in attrs.get('class', '') or attrs.get('class') == 'lyrics':
            self.depth = 1

    def handle_endtag(self, tag):
        if self.depth and tag not in ('br', 'img', 'input', 'hr', 'meta', 'link', 'wbr'):
            self.depth -= 1
            if not self.depth:
                self.parts.append('\n\n')

    def handle_data(self, data):
        if self.depth:
            self.parts.append(data)


HOSTS = ('lrclib.net', 'music.163.com', 'api.lyrics.ovh')


def get(url, headers=None):
    if urlparse(url).hostname not in HOSTS:
        raise ValueError('Unexpected lyrics host')
    request = Request(url, headers={'User-Agent': 'Mozilla/5.0 GalaxyLyrics/1.1', **(headers or {})})
    with urlopen(request, timeout=8) as response:
        if urlparse(response.url).hostname not in HOSTS:
            raise ValueError('Unexpected redirect')
        return response.read(4_000_000).decode('utf-8')


# Remove publishing/video labels, never meaningful versions such as Live or Remix.
NOISE = re.compile(r"^(?:(?:official\s+)?(?:hd\s+|4k\s+)?(?:music\s+)?(?:video|audio|visuali[sz]er|lyric(?:s)?(?:\s+video)?|mv|m/v)(?:\s+(?:hd|4k|hq))?|official|hd|hq|4k|1080p|720p|explicit|clean|uncensored)(?:\s*[/|,]\s*(?:hd|hq|4k|1080p|720p))*$", re.I)
FEAT = re.compile(r"\s*[\(\[]?\s*\b(?:ft|feat|featuring|with)\b\.?\s+[^\)\]]*[\)\]]?", re.I)
UPLOADER = re.compile(r"(?:\s*-\s*topic|vevo|official|music|tv|records)$", re.I)


def clean_title(title):
    title = re.sub(r'\(([^()]*)\)|\[([^\[\]]*)\]',
                   lambda m: '' if NOISE.fullmatch((m[1] or m[2]).strip()) else m[0], title)
    title = re.sub(r'\[[^\]]*\]', '', title)                      # any leftover [..] tags
    title = re.sub(r'\s+[-|–—]\s+((?:official\s+)?(?:music\s+)?(?:video|audio|visuali[sz]er|lyrics?(?:\s+video)?))\s*$', '', title, flags=re.I)
    title = FEAT.sub('', title)
    title = re.sub(r'[“”"]', '', title)
    return re.sub(r'\s+', ' ', title).strip(' -|–—')


def clean_artist(artist):
    artist = re.sub(r'\s*-\s*Topic$', '', artist, flags=re.I)
    artist = re.sub(r'VEVO$', '', artist).strip()
    artist = FEAT.sub('', artist)
    artist = re.split(r'\s*(?:,|&|\bx\b|\band\b)\s*', artist, maxsplit=1)[0] if len(artist) > 3 else artist
    return artist.strip()


def clean_metadata(title, artist):
    uploader_like = bool(UPLOADER.search(artist.strip())) or not artist.strip()
    raw_artist = artist
    artist = clean_artist(artist)
    for sep in (' - ', ' – ', ' — ', ' | '):
        if sep in title:
            prefix, rest = title.split(sep, 1)
            if similarity(clean_artist(prefix), artist) >= 0.6 or uploader_like or similarity(prefix.replace(' ', ''), raw_artist.replace(' ', '')) >= 0.6:
                artist, title = clean_artist(prefix), rest
            break
    return clean_title(title), artist


def normalized(value):
    return re.sub(r'[^\w]+', ' ', value.casefold()).strip()


def similarity(a, b):
    return SequenceMatcher(None, normalized(a), normalized(b)).ratio()


def parse_lrc(value):
    lines = []
    offset_match = re.search(r'\[offset:([+-]?\d+)\]', value, re.I)
    offset = int(offset_match.group(1)) / 1000 if offset_match else 0
    for raw in value.splitlines():
        stamps = list(re.finditer(r'\[(\d+):(\d{2}(?:\.\d+)?)\]', raw))
        if not stamps:
            continue
        text = raw[stamps[-1].end():].strip()
        for stamp in stamps:
            lines.append({'time': max(0, int(stamp[1]) * 60 + float(stamp[2]) + offset), 'text': text})
    return sorted(lines, key=lambda line: line['time'])


def load_sources():
    import os
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'lyrics.json')
    try:
        with open(path) as f:
            src = json.load(f).get('sources')
        if isinstance(src, list) and src:
            return [str(x).lower() for x in src]
    except (OSError, ValueError):
        pass
    return ['lrclib', 'netease', 'lyricsovh']


def lrclib_candidates(title, artist, album, duration):
    out_ = []
    params = {'track_name': title, 'artist_name': artist}
    if album:
        params['album_name'] = album
    try:
        r = json.loads(get('https://lrclib.net/api/get?' + urlencode(params)))
        if isinstance(r, dict) and 'trackName' in r:
            out_.append(r)
    except Exception:
        pass
    try:
        for r in json.loads(get('https://lrclib.net/api/search?' + urlencode({'track_name': title, 'artist_name': artist}))):
            if isinstance(r, dict) and similarity(title, clean_title(r.get('trackName', ''))) >= 0.8 \
                    and similarity(artist, clean_artist(r.get('artistName', ''))) >= 0.55:
                out_.append(r)
    except Exception:
        pass
    seen, res = set(), []
    for r in out_:
        if r.get('id') in seen:
            continue
        seen.add(r.get('id'))
        if r.get('instrumental'):
            res.append({'source': 'LRCLIB', 'lines': [], 'text': 'Instrumental · no lyrics', 'duration': float(r.get('duration') or 0), 'label': 'instrumental'})
            continue
        lines = parse_lrc(r.get('syncedLyrics') or '')
        res.append({'source': 'LRCLIB · synced' if lines else 'LRCLIB · plain', 'lines': lines,
                    'text': r.get('plainLyrics') or '', 'duration': float(r.get('duration') or 0),
                    'label': f"{r.get('artistName', '')} — {r.get('trackName', '')} · {r.get('albumName') or '?'}",
                    'url': f"https://lrclib.net/api/get/{r.get('id')}"})
    return res


def netease_candidates(title, artist, album, duration, limit=4):
    hdr = {'Referer': 'https://music.163.com/'}
    data = json.loads(get('https://music.163.com/api/cloudsearch/pc?' + urlencode({'s': f'{title} {artist}', 'type': 1, 'limit': 12}), hdr))
    songs = []
    for sg in (data.get('result') or {}).get('songs') or []:
        a = ' '.join(x.get('name', '') for x in (sg.get('ar') or []))
        if similarity(title, clean_title(sg.get('name', ''))) >= 0.7 and similarity(artist, a) >= 0.4:
            songs.append((sg, a))
    songs.sort(key=lambda x: abs((x[0].get('dt') or 0) / 1000 - duration) if duration else 0)
    res = []
    for sg, a in songs[:limit]:
        try:
            lyr = json.loads(get('https://music.163.com/api/song/lyric?' + urlencode({'id': sg['id'], 'lv': 1, 'kv': 1, 'tv': -1}), hdr))
        except Exception:
            continue
        lines = [l for l in parse_lrc((lyr.get('lrc') or {}).get('lyric') or '')
                 if l['text'] and not re.match(r'^(作词|作曲|编曲|制作人|混音|母带|和声|吉他|贝斯|鼓|Lyrics by|Composed by|Producer)\s*[:：]', l['text'], re.I)]
        if lines:
            res.append({'source': 'NetEase · synced', 'lines': lines, 'text': '\n'.join(l['text'] for l in lines),
                        'duration': (sg.get('dt') or 0) / 1000, 'label': f"{a} — {sg.get('name')} · {(sg.get('al') or {}).get('name', '?')}",
                        'url': f'https://music.163.com/#/song?id={sg["id"]}'})
    return res


def lyricsovh_candidates(title, artist, album, duration):
    from urllib.parse import quote
    d = json.loads(get(f'https://api.lyrics.ovh/v1/{quote(artist)}/{quote(title)}'))
    text = re.sub(r'^Paroles de la chanson .*?\n', '', (d.get('lyrics') or '').replace('\r\n', '\n')).strip()
    return [{'source': 'lyrics.ovh · plain', 'lines': [], 'text': text, 'duration': 0, 'label': f'{artist} — {title}'}] if text else []


SOURCES = {'lrclib': lrclib_candidates, 'netease': netease_candidates, 'lyricsovh': lyricsovh_candidates}


def synced_lookup(title, artist, album, duration, _retry=True):
    raw_title = title
    title, artist = clean_metadata(title, artist)
    order = load_sources()
    cands = []
    for rank, name in enumerate(order):
        fn = SOURCES.get(name)
        if not fn:
            continue
        try:
            for c in fn(title, artist, album, duration):
                c['rank'] = rank
                cands.append(c)
        except Exception:
            pass
        # plain-only sources are only worth hitting when nothing synced turned up
        if name != order[-1] and any(c['lines'] for c in cands) and order[order.index(name) + 1:] == ['lyricsovh']:
            break
    if not cands and _retry:
        for sep in (' - ', ' – ', ' — '):
            if sep in raw_title:   # uploader isn't the artist: trust the 'Artist - Title' split
                pre, rest = raw_title.split(sep, 1)
                r = synced_lookup(rest, pre, album, duration, _retry=False)
                if r.get('ok'):
                    return r
                break
    if not cands:
        return {'text': f'No lyrics found for “{title}” by {artist} (' + ' → '.join(order) + ').', 'lines': [], 'source': 'Not found',
                'ok': False, 'candidates': [], 'query': f'{artist} — {title}'}
    # synced first, then closest duration, then configured source order
    def key(c):
        dd = abs(c['duration'] - duration) if duration and c['duration'] else 999
        return (not c['lines'], round(dd / 2), c['rank'])
    cands.sort(key=key)
    best = cands[0]
    return {'text': best['text'], 'lines': best['lines'], 'source': best['source'], 'url': best.get('url', ''),
            'ok': True, 'candidates': cands[:8], 'index': 0, 'query': f'{artist} — {title}'}


def cached_lookup(title, artist, album, duration, refresh=False):
    import hashlib, os, time
    cache_dir = os.path.join(os.environ.get('XDG_CACHE_HOME', os.path.expanduser('~/.cache')), 'galaxy-lyrics')
    os.makedirs(cache_dir, exist_ok=True)
    key = hashlib.sha1('\n'.join([title, artist, album, str(round(duration))]).encode()).hexdigest()
    path = os.path.join(cache_dir, key + '.json')
    if not refresh:
        try:
            with open(path) as f:
                hit = json.load(f)
            hit['source'] = hit.get('source', '') + ' · cached'
            return hit
        except (OSError, ValueError):
            pass
    result = synced_lookup(title, artist, album, duration)
    if result.get('ok'):
        with open(path + '.tmp', 'w') as f:
            json.dump(result, f)
        os.replace(path + '.tmp', path)
    return result


if __name__ == '__main__':
    try:
        result = cached_lookup(sys.argv[1], sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else '',
                               float(sys.argv[4]) if len(sys.argv) > 4 else 0,
                               refresh=len(sys.argv) > 6 and sys.argv[6] == 'refresh')
    except Exception:
        result = {'text': 'Lyrics are unavailable. Try Refetch.', 'lines': [], 'source': 'Unavailable', 'ok': False}
    result["request_key"] = sys.argv[5] if len(sys.argv) > 5 else ""
    print(json.dumps(result))
