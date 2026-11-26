#!/usr/bin/env python3
"""Tide — полноэкранный лаунчер в стиле игровой консоли прошлого поколения (PySide6 + QML)."""
import argparse
import configparser
import glob
import json
import os
import select
import shlex
import shutil
import struct
import subprocess
import sys
import threading
import time
from datetime import datetime, timedelta
from pathlib import Path
from urllib.parse import unquote

from PySide6.QtCore import QObject, Property, QSize, QTimer, QUrl, Signal, Slot
from PySide6.QtGui import QColor, QFont, QFontDatabase, QGuiApplication, QIcon, QPixmap
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuick import QQuickImageProvider
import PySide6.QtMultimedia  # noqa: F401 — чтобы сборщик включил QtMultimedia (звук, MediaPlayer в QML)

IS_WIN = sys.platform.startswith("win")
# в собранной версии (PyInstaller) файлы интерфейса лежат в sys._MEIPASS
APP_DIR = Path(getattr(sys, "_MEIPASS", Path(__file__).resolve().parent))
CFG_DIR = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "tide-launcher"
CACHE_DIR = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "tide-launcher"
STATE_FILE = CFG_DIR / "state.json"
# свои файлы оформления: видео-заставки, логотипы, мелодия экрана выбора пользователя, звук кнопки
MEDIA_DIR = CFG_DIR / "media"
VIDEO_EXT = (".mp4", ".webm", ".mkv", ".mov", ".avi", ".m4v")
IMAGE_EXT = (".png", ".svg", ".jpg", ".jpeg", ".webp")
AUDIO_EXT = (".mp3", ".ogg", ".opus", ".wav", ".flac", ".m4a")


def media_file(stem):
    """MEDIA_DIR/<stem>.<любое аудио-расширение> или None."""
    for e in AUDIO_EXT:
        p = MEDIA_DIR / (stem + e)
        if p.is_file():
            return p
    return None


def trimmed_logo(path):
    """Логотип без пустых прозрачных полей (иначе квадратная картинка с узкой надписью выглядит мелкой).
    Результат кэшируется; картинки без прозрачности возвращаются как есть."""
    from PySide6.QtGui import QImage
    st = path.stat()
    out = CACHE_DIR / "logos" / f"{path.stem}-{int(st.st_mtime)}-{st.st_size}.png"
    if out.exists():
        return out
    try:
        im = QImage(str(path))
        if im.isNull() or not im.hasAlphaChannel() or path.suffix.lower() == ".svg":
            return path
        a = im.convertToFormat(QImage.Format.Format_Alpha8)
        w, h, bpl = a.width(), a.height(), a.bytesPerLine()
        data = bytes(a.constBits())[:bpl * h]
        mask = bytes(1 if v > 10 else 0 for v in range(256))
        top = left = None
        bottom = right = -1
        for y in range(h):
            row = data[y * bpl:y * bpl + w].translate(mask)
            l = row.find(b"\x01")
            if l < 0:
                continue
            r = row.rfind(b"\x01")
            top = y if top is None else top
            bottom = y
            left = l if left is None else min(left, l)
            right = max(right, r)
        if top is None or (left == 0 and top == 0 and right == w - 1 and bottom == h - 1):
            return path
        pad = max(2, int(0.01 * max(w, h)))
        x0, y0 = max(0, left - pad), max(0, top - pad)
        x1, y1 = min(w - 1, right + pad), min(h - 1, bottom + pad)
        out.parent.mkdir(parents=True, exist_ok=True)
        im.copy(x0, y0, x1 - x0 + 1, y1 - y0 + 1).save(str(out))
        return out
    except Exception as ex:
        print("logo trim failed:", path, ex, file=sys.stderr)
        return path


def media_list(sub, exts):
    d = MEDIA_DIR / sub
    if not d.is_dir():
        return []
    return sorted((f.name for f in d.iterdir() if f.is_file() and f.suffix.lower() in exts), key=str.lower)
SELF_IDS = {"tide-launcher.desktop"}


# ───────────────────────────── .desktop scanning ─────────────────────────────

def _data_dirs():
    home = os.environ.get("XDG_DATA_HOME", str(Path.home() / ".local/share"))
    dirs = [home] + os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share").split(":")
    dirs += [str(Path.home() / ".local/share/flatpak/exports/share"), "/var/lib/flatpak/exports/share"]
    seen, out = set(), []
    for d in dirs:
        if d and d not in seen:
            seen.add(d)
            out.append(Path(d) / "applications")
    return out


def _localized(entry, key):
    lang = os.environ.get("LANG", "").split(".")[0]
    for k in (f"{key}[{lang}]", f"{key}[{lang.split('_')[0]}]", key):
        if entry.get(k):
            return entry[k]
    return ""


def scan_desktop_entries():
    desktops = {d.lower() for d in os.environ.get("XDG_CURRENT_DESKTOP", "").split(":") if d}
    found = {}
    for base in _data_dirs():
        if not base.is_dir():
            continue
        for path in sorted(base.rglob("*.desktop")):
            did = str(path.relative_to(base)).replace("/", "-")
            if did in found or did in SELF_IDS:
                continue
            cp = configparser.ConfigParser(interpolation=None, strict=False)
            cp.optionxform = str
            try:
                cp.read(path, encoding="utf-8")
                e = cp["Desktop Entry"]
            except Exception:
                continue
            found[did] = None  # mark as seen even if filtered (user overrides system)
            if e.get("Type") != "Application" or not e.get("Exec"):
                continue
            if e.get("NoDisplay", "").lower() == "true" or e.get("Hidden", "").lower() == "true":
                continue
            only = {x.lower() for x in e.get("OnlyShowIn", "").split(";") if x}
            nots = {x.lower() for x in e.get("NotShowIn", "").split(";") if x}
            if (only and not only & desktops) or (nots & desktops):
                continue
            tryexec = e.get("TryExec")
            if tryexec and not (shutil.which(tryexec) or os.path.exists(tryexec)):
                continue
            cats = [c for c in e.get("Categories", "").split(";") if c]
            found[did] = {
                "id": did,
                "name": _localized(e, "Name") or did,
                "comment": _localized(e, "Comment") or _localized(e, "GenericName"),
                "icon": e.get("Icon", "") or "application-x-executable",
                "exec": e.get("Exec"),
                "terminal": e.get("Terminal", "").lower() == "true",
                "path": e.get("Path", ""),
                "isGame": "Game" in cats,
            }
    return {k: v for k, v in found.items() if v}


def build_command(entry):
    tokens = []
    for tok in shlex.split(entry["exec"]):
        if tok in ("%f", "%F", "%u", "%U", "%d", "%D", "%n", "%N", "%v", "%m", "%k"):
            continue
        if tok == "%i":
            if entry["icon"]:
                tokens += ["--icon", entry["icon"]]
            continue
        tokens.append(tok.replace("%c", entry["name"]).replace("%%", "%"))
    if entry["terminal"]:
        term = shutil.which("konsole") or shutil.which("xterm")
        if term:
            tokens = [term, "-e"] + tokens
    return tokens


# ───────────────────────────── PS4 (shadPS4) ─────────────────────────────

SHADPS4_DATA = Path.home() / ".local/share/shadPS4"
PS4_DEFAULT_DIRS = ["~/Документы/Games", "~/Игры/PS4", "~/Games/PS4", "~/PS4", "~/.local/share/shadPS4/games"]


def find_shadps4(pref=""):
    cands = [pref, str(Path.home() / "Документы/Shadps4-sdl.AppImage"),
             str(Path.home() / "Загрузки/Shadps4-sdl.AppImage"),
             str(Path.home() / "Applications/Shadps4-sdl.AppImage"),
             shutil.which("shadps4") or "", shutil.which("shadPS4") or ""]
    if IS_WIN:
        for d in (Path.home() / "Documents", Path.home() / "Downloads", Path.home() / "Desktop",
                  Path(os.environ.get("ProgramFiles", "C:/Program Files")) / "shadPS4", Path.home() / "shadPS4"):
            cands += sorted(glob.glob(str(d / "shadPS4*.exe"))) + sorted(glob.glob(str(d / "*" / "shadPS4*.exe")))
    for c in cands:
        if c and os.path.isfile(os.path.expanduser(c)) and os.access(os.path.expanduser(c), os.X_OK):
            return os.path.expanduser(c)
    return ""


def read_sfo(path):
    """Разбор param.sfo: возвращает dict ключ → значение (str/int)."""
    out = {}
    try:
        data = Path(path).read_bytes()
        if data[:4] != b"\0PSF":
            return out
        key_start, data_start, n = struct.unpack_from("<III", data, 8)
        for i in range(n):
            koff, fmt, dlen, _dmax, doff = struct.unpack_from("<HHIII", data, 20 + i * 16)
            kend = data.index(b"\0", key_start + koff)
            key = data[key_start + koff:kend].decode("utf-8", "replace")
            raw = data[data_start + doff:data_start + doff + dlen]
            if fmt == 0x0404:
                out[key] = struct.unpack("<I", raw[:4])[0]
            else:
                out[key] = raw.split(b"\0")[0].decode("utf-8", "replace")
    except Exception:
        pass
    return out


def shadps4_config_dirs():
    dirs = []
    for f in list(SHADPS4_DATA.glob("*.toml")) + list(SHADPS4_DATA.glob("*.json")) + list(SHADPS4_DATA.glob("user/*.toml")):
        try:
            for line in f.read_text(errors="replace").splitlines():
                low = line.lower()
                if "installdir" in low or "game_folder" in low or "gamedir" in low:
                    import re
                    dirs += [d.replace("\\\\", "/") for d in re.findall(r'"(/[^"]+)"', line)]
        except Exception:
            pass
    return dirs


def scan_ps4_games(folders):
    lang = os.environ.get("LANG", "")[:2]
    title_key = {"ru": "TITLE_08", "de": "TITLE_04", "fr": "TITLE_02", "es": "TITLE_03"}.get(lang, "")
    games, seen = {}, set()

    def visit(d, depth):
        try:
            real = d.resolve()
        except OSError:
            return
        if real in seen or not d.is_dir():
            return
        seen.add(real)
        sfo = d / "sce_sys" / "param.sfo"
        if sfo.is_file() and (d / "eboot.bin").is_file():
            name = d.name.upper()
            if name.endswith(("-UPDATE", "-PATCH", "-DLC")):
                return
            info = read_sfo(sfo)
            cat = str(info.get("CATEGORY", "gd"))
            if cat.startswith(("gp", "ac")):
                return
            tid = str(info.get("TITLE_ID") or d.name)
            gid = "ps4-" + tid
            if gid in games:
                return
            title = (title_key and info.get(title_key)) or info.get("TITLE") or d.name
            icon = d / "sce_sys" / "icon0.png"
            pic = d / "sce_sys" / "pic1.png"
            if not pic.is_file():
                pic = d / "sce_sys" / "pic0.png"
            games[gid] = {
                "id": gid, "name": str(title).strip(), "comment": f"PS4 · {tid} · v{info.get('APP_VER', '?')}",
                "icon": str(icon) if icon.is_file() else "applications-games",
                "cover": str(icon) if icon.is_file() else "",
                "bg": str(pic) if pic.is_file() else "",
                "exec": "", "terminal": False, "path": str(d), "isGame": True,
                "ps4": True, "eboot": str(d / "eboot.bin"), "titleId": tid,
            }
            return
        if depth <= 0:
            return
        try:
            for sub in sorted(d.iterdir()):
                if sub.is_dir() and not sub.name.startswith("."):
                    visit(sub, depth - 1)
        except OSError:
            pass

    for f in folders:
        visit(Path(os.path.expanduser(f)), 3)
    return games


# ───────────────────────────── достижения ─────────────────────────────

# Достижения лаунчера — есть у каждой игры, считаются по запускам и времени.
# tier: 0 бронза, 1 серебро, 2 золото, 3 платина
GAME_ACHIEVEMENTS = [
    ("first",   "Первое погружение", "Запустите игру",                 0, lambda c, t: c >= 1),
    ("hour",    "Втянулся",          "Проведите в игре 1 час",         0, lambda c, t: t >= 3600),
    ("regular", "Постоянный гость",  "Запустите игру 10 раз",          0, lambda c, t: c >= 10),
    ("five",    "Вечер напролёт",    "Проведите в игре 5 часов",       1, lambda c, t: t >= 5 * 3600),
    ("twenty",  "Знаток",            "Проведите в игре 20 часов",      1, lambda c, t: t >= 20 * 3600),
    ("fifty",   "Верность",          "Запустите игру 50 раз",          2, lambda c, t: c >= 50),
    ("hundred", "Сотня часов",       "Проведите в игре 100 часов",     2, lambda c, t: t >= 100 * 3600),
]
PLATINUM = ("platinum", "Мастер игры", "Получите все остальные достижения этой игры", 3)
PS4_TIERS = {"B": 0, "S": 1, "G": 2, "P": 3}


def shadps4_trophy_key_set():
    try:
        k = json.loads((SHADPS4_DATA / "keys.json").read_text())
        return bool(str((k.get("TrophyKeySet") or {}).get("ReleaseTrophyKey", "")).strip())
    except Exception:
        return False


def ps4_trophies(title_id):
    """Трофеи PS4, которые shadPS4 распаковал и отмечает (game_data/<ID>/TrophyFiles, home/*/trophy).
    → список {id, name, desc, tier, hidden, got, time, icon} (пусто, если данных нет)."""
    import xml.etree.ElementTree as ET
    roots = [SHADPS4_DATA / "game_data" / title_id / "TrophyFiles"]
    roots += sorted((SHADPS4_DATA / "home").glob(f"*/trophy/{title_id}*")) + sorted((SHADPS4_DATA / "home").glob("*/trophy/*"))
    files = []
    for r in roots:
        if r.is_dir():
            files += sorted(r.rglob("TROP*.XML")) + sorted(r.rglob("TROP*.xml"))
    if not files:
        return []
    # названия — из русского файла (TROP_08), иначе из TROP.XML; отметки о получении — из любого файла
    lang = [f for f in files if f.name.upper() == "TROP_08.XML"]
    base = [f for f in files if f.name.upper() == "TROP.XML"]
    names_file = (lang or base or files)[0]
    trophies, order = {}, []

    def parse(f):
        try:
            return ET.parse(f).getroot()
        except Exception as ex:
            print("trophy xml failed:", f, ex, file=sys.stderr)
            return None

    root = parse(names_file)
    if root is None:
        return []
    # TROPCONF/TROP относятся к одной игре: проверим, что это нужный title (если файлы общие для home/*)
    for el in root.iter("trophy"):
        tid = el.get("id", "")
        trophies[tid] = {"id": tid, "name": (el.findtext("name") or "").strip(), "desc": (el.findtext("detail") or "").strip(),
                         "tier": PS4_TIERS.get(el.get("ttype", "B").upper(), 0), "hidden": el.get("hidden") == "yes",
                         "got": False, "time": 0, "icon": ""}
        order.append(tid)
    for f in files:
        r = root if f == names_file else parse(f)
        if r is None:
            continue
        for el in r.iter("trophy"):
            t = trophies.get(el.get("id", ""))
            if not t:
                continue
            st = (el.get("unlockstate") or el.get("unlocked") or "").lower()
            if st in ("true", "1", "yes"):
                t["got"] = True
                try:
                    t["time"] = int(el.get("timestamp") or 0)
                except ValueError:
                    pass
        icons = f.parent.parent / "Icons"
        if icons.is_dir():
            for tid, t in trophies.items():
                ic = icons / f"TROP{int(tid):03d}.PNG" if tid.isdigit() else None
                if ic and ic.exists() and not t["icon"]:
                    t["icon"] = QUrl.fromLocalFile(str(ic)).toString()
    return [trophies[i] for i in order]


# ───────────────────────────── магазин (каталоги + локальные архивы) ─────────────────────────────

ARCHIVE_EXT = (".zip", ".7z", ".rar", ".tar", ".tar.gz", ".tgz", ".tar.xz", ".txz", ".tar.zst", ".tar.bz2")
STORE_CACHE = CACHE_DIR / "store"


# bsdtar: в Linux — пакет libarchive, в Windows 10/11 встроенный tar.exe — это тоже bsdtar
TAR = shutil.which("bsdtar") or shutil.which("tar") or "bsdtar"


def _is_archive(name):
    n = name.lower()
    return any(n.endswith(e) for e in ARCHIVE_EXT)


def archive_list(path):
    try:
        out = subprocess.run([TAR, "-tf", str(path)], capture_output=True, text=True, timeout=60).stdout
        return [l for l in out.splitlines() if l]
    except Exception:
        return []


def archive_game_info(path):
    """Ищет внутри архива игру PS4 (eboot.bin + sce_sys/param.sfo). Возвращает dict или None."""
    names = archive_list(path)
    sfos = [n for n in names if n.lower().endswith("sce_sys/param.sfo")]
    roots = [n[:-len("sce_sys/param.sfo")] for n in sfos]
    roots = [r for r in roots if (r + "eboot.bin") in names]
    if not roots:
        return None
    root = min(roots, key=len)
    key = f"{Path(path).name}-{int(Path(path).stat().st_mtime)}".replace("/", "_")
    d = STORE_CACHE / "local" / key
    d.mkdir(parents=True, exist_ok=True)
    for member in ("sce_sys/param.sfo", "sce_sys/icon0.png", "sce_sys/pic1.png"):
        target = d / Path(member).name
        if not target.exists() and (root + member) in names:
            try:
                with open(target, "wb") as f:
                    subprocess.run([TAR, "-xOf", str(path), root + member], stdout=f, timeout=60)
            except Exception:
                pass
    info = read_sfo(d / "param.sfo")
    lang = os.environ.get("LANG", "")[:2]
    title = (lang == "ru" and info.get("TITLE_08")) or info.get("TITLE") or Path(path).stem
    return {"title": str(title), "titleId": str(info.get("TITLE_ID", "")), "version": str(info.get("APP_VER", "")),
            "icon": _nonempty(d / "icon0.png"), "bg": _nonempty(d / "pic1.png"),
            "files": len(names)}


# ── PS4 PKG ──
PKG_ENTRY_FILES = {0x1000: "param.sfo", 0x1200: "icon0.png", 0x1006: "pic1.png"}
PKG_CATEGORY = {"gd": "Игра", "gp": "Обновление", "ac": "Дополнение (DLC)"}
TOOLS_DIR = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "tide-launcher" / "tools"
PKG_EXTRACTOR_URL = "https://github.com/AzaharPlus/shadPS4Plus/releases"


def pkg_read_meta(path, out_dir):
    """Достаёт из заголовка .pkg незашифрованные param.sfo / icon0.png / pic1.png (без распаковки всего пакета)."""
    with open(path, "rb") as f:
        h = f.read(0x40)
        if h[:4] != b"\x7fCNT":
            return False
        cnt, = struct.unpack_from(">I", h, 0x10)
        toff, = struct.unpack_from(">I", h, 0x18)
        if not 0 < cnt < 10000:
            return False
        f.seek(toff)
        table = f.read(cnt * 32)
        for i in range(len(table) // 32):
            eid, _noff, fl1, _fl2, off, size, _pad = struct.unpack_from(">IIIIIIQ", table, i * 32)
            name = PKG_ENTRY_FILES.get(eid)
            if not name or fl1 & 0x80000000 or size > 64 << 20:
                continue
            target = out_dir / name
            if target.exists() and target.stat().st_size == size:
                continue
            f.seek(off)
            target.write_bytes(f.read(size))
    return (out_dir / "param.sfo").exists()


def pkg_game_info(path):
    """Название/ID/иконка игры из .pkg. Возвращает dict (как archive_game_info) или None."""
    path = Path(path)
    key = f"{path.name}-{int(path.stat().st_mtime)}".replace("/", "_")
    d = STORE_CACHE / "local" / key
    d.mkdir(parents=True, exist_ok=True)
    try:
        if not pkg_read_meta(path, d):
            return None
    except Exception as ex:
        print("pkg read failed:", path, ex, file=sys.stderr)
        return None
    info = read_sfo(d / "param.sfo")
    lang = os.environ.get("LANG", "")[:2]
    title = (lang == "ru" and info.get("TITLE_08")) or info.get("TITLE") or path.stem
    return {"title": str(title), "titleId": str(info.get("TITLE_ID", "")), "version": str(info.get("APP_VER", "")),
            "category": str(info.get("CATEGORY", "gd"))[:2],
            "icon": _nonempty(d / "icon0.png"), "bg": _nonempty(d / "pic1.png"), "files": 0}


def find_pkg_extractor(pref=""):
    """Ищет консольный распаковщик PKG (ShadPs4Plus PKG Extractor или совместимый: `<tool> <file.pkg> <папка>`)."""
    cands = [os.path.expanduser(pref)] if pref else []
    pats = ["*[Pp]kg*[Ee]xtractor*", "pkg_extractor*", "pkg-extractor*"]
    for d in (TOOLS_DIR, Path.home() / "Загрузки", Path.home() / "Downloads", Path.home() / "Документы",
              Path.home() / "Applications", Path.home() / ".local/bin"):
        for pat in pats:
            cands += sorted(glob.glob(str(d / pat))) + sorted(glob.glob(str(d / "*" / pat)))
    cands += [shutil.which(n) or "" for n in ("pkg_extractor", "pkg-extractor", "shadps4-pkg-extractor")]
    for c in cands:
        if not c or not os.path.isfile(c) or c.lower().endswith((".zip", ".7z", ".tar.gz", ".txt", ".md", ".sh", ".bat")):
            continue
        if not os.access(c, os.X_OK):
            try:  # AppImage из «Загрузок» обычно без +x
                os.chmod(c, os.stat(c).st_mode | 0o755)
            except OSError:
                continue
        return c
    return ""


def dir_size(p):
    total = 0
    for root, _dirs, files in os.walk(p):
        for n in files:
            try:
                total += os.lstat(os.path.join(root, n)).st_size
            except OSError:
                pass
    return total


def _nonempty(p):
    return str(p) if p.exists() and p.stat().st_size > 0 else ""


def fmt_size(n):
    try:
        n = float(n)
    except (TypeError, ValueError):
        return str(n or "")
    for u in ("Б", "КБ", "МБ", "ГБ", "ТБ"):
        if n < 1024 or u == "ТБ":
            return f"{n:.1f} {u}" if u not in ("Б", "КБ") else f"{n:.0f} {u}"
        n /= 1024


# ── каталоги со ссылками на файлообменники ({"name", "page_url", "download_links": {...}}) ──

UA = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"
HOST_ORDER = ("mediafire", "1file")  # порядок перебора зеркал; остальные — после
HOST_NAMES = {"mediafire": "MediaFire", "1file": "1File", "other": "Другие"}


def mirror_groups(links):
    """download_links → [{"host": ..., "urls": [...]}, ...] в порядке предпочтения."""
    if not isinstance(links, dict):
        return []
    keys = [k for k in HOST_ORDER if k in links] + [k for k in links if k not in HOST_ORDER]
    out = []
    for k in keys:
        v = links.get(k)
        urls = [u.strip() for u in (v if isinstance(v, list) else [v]) if isinstance(u, str) and u.strip()]
        if urls:
            out.append({"host": k, "urls": urls})
    return out


def _http_open(url, timeout=30, referer=None):
    import urllib.request
    h = {"User-Agent": UA}
    if referer:
        h["Referer"] = referer
    return urllib.request.urlopen(urllib.request.Request(url, headers=h), timeout=timeout)


def _find_direct_link(html, page_url):
    """Ищет на HTML-странице файлообменника прямую ссылку на файл."""
    import base64
    import re
    from html import unescape
    from urllib.parse import urljoin
    # MediaFire: кнопка «Download» (обычная или с base64 в data-scrambled-url)
    m = re.search(r'data-scrambled-url="([^"]+)"', html)
    if m:
        try:
            return base64.b64decode(m.group(1)).decode()
        except Exception:
            pass
    m = re.search(r'href="(https?://download\d*\.mediafire\.com/[^"]+)"', html)
    if m:
        return unescape(m.group(1))
    # прочее: первая ссылка на архив или явная кнопка скачивания
    hrefs = [unescape(h) for h in re.findall(r'href="([^"#]+)"', html)]
    for h in hrefs:
        if _is_archive(unquote(h.split("?")[0])) or re.search(r"\.(r\d\d|z\d\d|\d{3})$", h.split("?")[0], re.I):
            return urljoin(page_url, h)
    m = re.search(r'<a[^>]+href="([^"#]+)"[^>]*(?:id|class)="[^"]*download[^"]*"', html, re.I) or \
        re.search(r'<a[^>]+(?:id|class)="[^"]*download[^"]*"[^>]*href="([^"#]+)"', html, re.I)
    if m:
        return urljoin(page_url, unescape(m.group(1)))
    return None


def _filename_from(resp, url):
    import re
    cd = resp.headers.get("Content-Disposition") or ""
    m = re.search(r"filename\*=(?:UTF-8'')?([^;]+)", cd, re.I) or re.search(r'filename="?([^";]+)"?', cd, re.I)
    name = unquote(m.group(1).strip()) if m else unquote(url.split("?")[0].rstrip("/").rsplit("/", 1)[-1])
    if name.lower() == "file":  # mediafire.com/file/<id>/<name>/file
        parts = url.split("?")[0].rstrip("/").split("/")
        name = unquote(parts[-2]) if len(parts) > 1 else name
    return Path(name).name or "download.bin"


def open_download(url):
    """Открывает URL; если это страница файлообменника — переходит по прямой ссылке. → (response, filename)."""
    for _ in range(3):
        r = _http_open(url)
        ctype = (r.headers.get("Content-Type") or "").lower()
        if "text/html" not in ctype:
            return r, _filename_from(r, r.geturl())
        html = r.read(4 << 20).decode("utf-8", "replace")
        r.close()
        direct = _find_direct_link(html, r.geturl())
        if not direct or direct == url:
            break
        url = direct
    raise RuntimeError("Не удалось получить прямую ссылку (возможно, нужна капча или файл удалён)")


def parse_size(s):
    import re
    m = re.search(r"([\d]+(?:[.,]\d+)?)\s*([KMGT]?)i?B\b", s or "", re.I)
    if not m:
        return 0
    mul = {"": 1, "K": 1 << 10, "M": 1 << 20, "G": 1 << 30, "T": 1 << 40}[m.group(2).upper()]
    return int(float(m.group(1).replace(",", ".")) * mul)


DEAD_MARKERS = ("invalid or deleted file", "file has been removed", "file was removed", "file not found",
                "file does not exist", "has been deleted", "no longer available", "файл удален", "файл удалён",
                "файл не найден")


class LinkError(Exception):
    """Не удалось проверить ссылку из-за сети (а не потому, что файл удалён)."""


def mediafire_key(url):
    import re
    m = re.match(r"https?://(?:www\.)?mediafire\.com/(?:file|file_premium|download|view)/([a-z0-9]+)", url, re.I) or \
        re.match(r"https?://(?:www\.)?mediafire\.com/\?([a-z0-9]+)", url, re.I)
    return m.group(1) if m else ""


def check_mediafire(key):
    """Страницы MediaFire закрыты проверкой Cloudflare, а публичный API — нет: по нему видно, жив ли файл и его размер."""
    import urllib.error
    import socket
    try:
        with _http_open(f"https://www.mediafire.com/api/1.5/file/get_info.php?quick_key={key}&response_format=json", 8) as r:
            resp = json.loads(r.read().decode()).get("response") or {}
    except urllib.error.HTTPError as ex:
        try:  # на удалённый файл API отвечает 404 с JSON внутри
            resp = json.loads(ex.read().decode()).get("response") or {}
        except Exception:
            raise LinkError(f"MediaFire API: HTTP {ex.code}")
    except (urllib.error.URLError, socket.timeout, TimeoutError, ConnectionError, ValueError) as ex:
        raise LinkError(str(ex))
    if resp.get("result") != "Success":
        if str(resp.get("error")) in ("110", "111", "112", "113", "114"):  # нет такого файла / удалён
            return False, 0
        raise LinkError(f"MediaFire API: {resp.get('message')}")
    fi = resp.get("file_info") or {}
    ok = fi.get("ready", "yes") == "yes" and fi.get("password_protected") != "yes" and fi.get("privacy", "public") == "public"
    try:
        size = int(fi.get("size") or 0)
    except ValueError:
        size = 0
    return ok, size


def check_mediafire_batch(keys):
    """Проверка сразу многих файлов MediaFire одним запросом API. → {key: (ok, size)}."""
    import urllib.error
    import socket
    url = f"https://www.mediafire.com/api/1.5/file/get_info.php?quick_key={','.join(keys)}&response_format=json"
    try:
        with _http_open(url, 20) as r:
            resp = json.loads(r.read().decode()).get("response") or {}
    except urllib.error.HTTPError as ex:
        try:
            resp = json.loads(ex.read().decode()).get("response") or {}
        except Exception:
            raise LinkError(f"MediaFire API: HTTP {ex.code}")
    except (urllib.error.URLError, socket.timeout, TimeoutError, ConnectionError, ValueError) as ex:
        raise LinkError(str(ex))
    if resp.get("result") != "Success":
        if str(resp.get("error")) in ("110", "111", "112", "113", "114"):
            return {k: (False, 0) for k in keys}  # в пакете нет ни одного живого файла
        raise LinkError(f"MediaFire API: {resp.get('message')}")
    out = {k: (False, 0) for k in keys}  # чего нет в ответе — удалено (API кладёт такие в «skipped»)
    infos = resp.get("file_infos") or ([resp["file_info"]] if resp.get("file_info") else [])
    for fi in infos:
        try:
            size = int(fi.get("size") or 0)
        except ValueError:
            size = 0
        ok = fi.get("ready", "yes") == "yes" and fi.get("password_protected") != "yes" and fi.get("privacy", "public") == "public"
        out[fi.get("quickkey", "")] = (ok, size)
    return out


def check_link(url):
    """Проверяет, что по ссылке действительно отдаётся файл (переходит со страницы файлообменника на прямую
    ссылку, сам файл не качает). → (ok, size_bytes). Сетевые сбои → LinkError."""
    import re
    import socket
    import urllib.error
    if mediafire_key(url):
        return check_mediafire(mediafire_key(url))
    size = 0
    for _ in range(4):
        try:
            r = _http_open(url, timeout=8)
        except urllib.error.HTTPError as ex:
            if ex.code in (404, 410, 451) or 400 <= ex.code < 500 and ex.code not in (403, 429):
                return False, 0
            raise LinkError(f"HTTP {ex.code}")
        except (urllib.error.URLError, socket.timeout, TimeoutError, ConnectionError) as ex:
            raise LinkError(str(ex))
        with r:
            final = r.geturl()
            ctype = (r.headers.get("Content-Type") or "").lower()
            if "text/html" not in ctype:
                return True, int(r.headers.get("Content-Length") or 0) or size
            html = r.read(4 << 20).decode("utf-8", "replace")
        low = html.lower()
        if "error.php" in final or "/error" in final.split("?")[0]:
            return False, 0
        # MediaFire и похожие пишут размер прямо на странице
        for pat in (r"Download\s*\(([\d.,]+\s*[KMGT]?B)\)", r"File size:\s*<span>([^<]+)</span>",
                    r"(?:Размер|Size)\s*:?\s*(?:<[^>]+>\s*)*([\d.,]+\s*[KMGT]i?B)"):
            m = re.search(pat, html, re.I)
            if m and parse_size(m.group(1)):
                size = size or parse_size(m.group(1))
                break
        if not size and any(mk in low for mk in DEAD_MARKERS):
            return False, 0
        direct = _find_direct_link(html, final)
        if direct and re.match(r"https?://download\d*\.mediafire\.com/", direct):
            return True, size  # кнопка скачивания есть — файл на месте, второй запрос не нужен
        if not direct or direct == url:
            # прямой ссылки нет (капча, ожидание, файл удалён) — лаунчер такой файл всё равно не скачает
            return False, 0
        url = direct
    return False, 0


def clean_game_name(name):
    """«God of War III Remastered [CUSA01623] PS4 v1.03 + DLC» → «God of War III Remastered»."""
    import re
    n = re.sub(r"[\[({][^\])}]*[\])}]", " ", name or "")
    n = re.split(r"\s[+|]\s|\s[-–—]\s(?=.*\b(?:PS4|PKG|v\d|CUSA|Update|DLC|FW|Fix)\b)", n)[0]
    n = re.sub(r"\b(CUSA\d+|PS[45]|F?PKG|v\d+(\.\d+)*|\d\.\d\d|EUR|USA|JPN|ASIA|Backport|Update|DLC|Fix|"
               r"Repack|Multi\d*|FW|Proper|Complete\s+Edition\s+Bundle)\b", " ", n, flags=re.I)
    n = re.sub(r"[_.]+", " ", n)
    return re.sub(r"\s+", " ", n).strip(" -–—:") or (name or "").strip()


def _norm_words(s):
    import re
    roman = {"ii": "2", "iii": "3", "iv": "4", "v": "5", "vi": "6", "vii": "7", "viii": "8", "ix": "9", "x": "10"}
    w = re.findall(r"[a-zа-я0-9]+", s.lower().replace("&", " and "))
    return [roman.get(x, x) for x in w if x not in ("the", "a", "of", "edition", "remastered", "definitive")]


def _name_match(a, b):
    wa, wb = set(_norm_words(a)), set(_norm_words(b))
    if not wa or not wb:
        return 0
    return len(wa & wb) / len(wa | wb)


def find_art(name):
    """Обложка и фон по названию игры: Steam, затем Wikipedia. → {"icon": url, "bg": url}."""
    from urllib.parse import quote
    q = clean_game_name(name)
    try:
        with _http_open(f"https://store.steampowered.com/api/storesearch/?term={quote(q)}&cc=us&l=en", 15) as r:
            res = json.loads(r.read().decode())
        best = max(res.get("items") or [], key=lambda x: _name_match(q, x.get("name", "")), default=None)
        if best and _name_match(q, best["name"]) >= 0.5:
            base = f"https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/{best['id']}/"
            return {"icon": [base + "library_600x900.jpg", base + "header.jpg"],
                    "bg": [base + "library_hero.jpg", base + "header.jpg"]}
    except Exception as ex:
        print("steam art failed:", q, ex, file=sys.stderr)
    try:
        url = ("https://en.wikipedia.org/w/api.php?action=query&format=json&generator=search&gsrlimit=3"
               f"&gsrsearch={quote(q + ' video game')}&prop=pageimages&piprop=thumbnail&pithumbsize=800&pilicense=any")
        with _http_open(url, 15) as r:
            pages = (json.loads(r.read().decode()).get("query") or {}).get("pages") or {}
        for p in sorted(pages.values(), key=lambda p: p.get("index", 99)):
            if p.get("thumbnail") and _name_match(q, p.get("title", "")) >= 0.4:
                return {"icon": [p["thumbnail"]["source"]], "bg": []}
    except Exception as ex:
        print("wiki art failed:", q, ex, file=sys.stderr)
    return {"icon": [], "bg": []}


def cache_image(urls, dest_stem):
    """Скачивает первую доступную картинку из списка в кэш. → локальный путь или ''."""
    import hashlib
    for u in urls:
        p = STORE_CACHE / "art" / (dest_stem + "-" + hashlib.sha1(u.encode()).hexdigest()[:10] + ".jpg")
        if p.exists() and p.stat().st_size > 0:
            return str(p)
        try:
            with _http_open(u, 20) as r:
                if not (r.headers.get("Content-Type") or "").startswith("image/"):
                    continue
                data = r.read()
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_bytes(data)
            return str(p)
        except Exception:
            continue
    return ""


def first_volume(files):
    """Из частей многотомного архива выбирает ту, с которой начинается распаковка."""
    import re
    names = sorted(files, key=lambda p: p.name.lower())
    for pat in (r"\.part0*1\.rar$", r"\.0*1$", r"\.(zip|rar|7z)$", r"\.tar(\.\w+)?$|\.t[gx]z$"):
        for p in names:
            if re.search(pat, p.name, re.I):
                return p
    return names[0]


    marker.touch()


# ───────────────────────────── gamepad (/dev/input/js*) ─────────────────────────────

class Gamepad(threading.Thread):
    """Геймпады через /dev/input/js*: DualSense (PS5), DualSense Edge, DualShock 4, Xbox и др.
    Читает все подключённые геймпады одновременно, подхватывает новые на ходу."""
    # hid-playstation (DualSense / DualShock 4 на современных ядрах) и большинство драйверов:
    # 0 ✕, 1 ○, 2 △, 3 □, 4 L1, 5 R1, 6 L2, 7 R2, 8 Create/Share, 9 Options, 10 PS, 11 L3, 12 R3
    BUTTONS = {0: "accept", 1: "back", 2: "triangle", 3: "square", 4: "tabprev", 5: "tabnext", 8: "share", 9: "options", 10: "ps"}
    # старый режим hid-generic у геймпадов Sony: 0 □, 1 ✕, 2 ○, 3 △, ..., 8 Share, 9 Options, 12 PS, 13 тачпад
    BUTTONS_SONY_GENERIC = {0: "square", 1: "accept", 2: "back", 3: "triangle", 4: "tabprev", 5: "tabnext", 8: "share", 9: "options", 12: "ps", 13: "options"}
    # Xbox / xpad / виртуальный геймпад Steam: 0 A, 1 B, 2 X, 3 Y, 4 LB, 5 RB, 6 Back, 7 Start, 8 Guide
    BUTTONS_XBOX = {0: "accept", 1: "back", 2: "square", 3: "triangle", 4: "tabprev", 5: "tabnext", 6: "share", 7: "options", 8: "ps"}
    SKIP_NAMES = ("mouse", "keyboard", "touchpad", "virtualhid", "motion sensors", "accelerometer", "consumer control")
    JSIOCGBUTTONS = 0x80016A12

    def __init__(self, emit, raw=None):
        super().__init__(daemon=True)
        self.emit = emit
        self.raw = raw or (lambda s: None)

    @staticmethod
    def name_of(dev):
        try:
            return Path(f"/sys/class/input/{Path(dev).name}/device/name").read_text().strip()
        except OSError:
            return Path(dev).name

    @classmethod
    def _buttons_count(cls, dev):
        import fcntl
        try:
            with open(dev, "rb", buffering=0) as f:
                buf = bytearray(1)
                fcntl.ioctl(f, cls.JSIOCGBUTTONS, buf)
                return buf[0]
        except OSError:
            return -1  # нет доступа — не отбрасываем, решим по имени

    # XInput (Windows): Xbox и совместимые; DualSense/DualShock — через Steam Input или DS4Windows
    XI_BUTTONS = {0x1000: "accept", 0x2000: "back", 0x8000: "triangle", 0x4000: "square", 0x0100: "tabprev",
                  0x0200: "tabnext", 0x0020: "share", 0x0010: "options", 0x0400: "ps"}
    XI_DIRS = {0x0001: "up", 0x0002: "down", 0x0004: "left", 0x0008: "right"}
    _xi = None

    @classmethod
    def _xinput(cls):
        """→ (функция чтения состояния, тип структуры) или None."""
        if cls._xi is not None:
            return cls._xi or None
        import ctypes
        from ctypes import wintypes

        class GP(ctypes.Structure):
            _fields_ = [("wButtons", wintypes.WORD), ("bLeftTrigger", ctypes.c_ubyte), ("bRightTrigger", ctypes.c_ubyte),
                        ("sThumbLX", ctypes.c_short), ("sThumbLY", ctypes.c_short),
                        ("sThumbRX", ctypes.c_short), ("sThumbRY", ctypes.c_short)]

        class ST(ctypes.Structure):
            _fields_ = [("dwPacketNumber", wintypes.DWORD), ("Gamepad", GP)]
        for name in ("xinput1_4", "xinput1_3", "xinput9_1_0"):
            try:
                dll = ctypes.WinDLL(name)
            except OSError:
                continue
            try:
                fn = dll[100]  # XInputGetStateEx — с кнопкой Guide
            except (AttributeError, OSError):
                fn = dll.XInputGetState
            cls._xi = (fn, ST)
            return cls._xi
        cls._xi = False
        return None

    @classmethod
    def _xi_state(cls, i):
        import ctypes
        xi = cls._xinput()
        if not xi:
            return None
        fn, ST = xi
        st = ST()
        return st if fn(i, ctypes.byref(st)) == 0 else None

    @classmethod
    def controllers(cls):
        if IS_WIN:
            return [(f"xinput{i}", f"Геймпад {i + 1} (XInput)") for i in range(4) if cls._xi_state(i)]
        out = []
        for d in sorted(glob.glob("/dev/input/js*")):
            n = cls.name_of(d)
            if any(w in n.lower() for w in cls.SKIP_NAMES):
                continue
            if cls._buttons_count(d) == 0:  # датчики движения и т. п. — без кнопок
                continue
            out.append((d, n))
        return out

    @classmethod
    def mapping(cls, name):
        n = name.lower()
        if n.startswith(("sony interactive entertainment", "sony computer entertainment")):
            return cls.BUTTONS_SONY_GENERIC
        if any(w in n for w in ("x-box", "xbox", "steam virtual", "steam deck", "8bitdo")):
            return cls.BUTTONS_XBOX
        return cls.BUTTONS  # DualSense, DualSense Edge, DualShock 4 (hid-playstation) и прочие

    def _run_xinput(self):
        if not self._xinput():
            return
        prev = [0] * 4
        held, held_since, last_rep = None, 0.0, 0.0
        while True:
            time.sleep(0.016)
            now = time.monotonic()
            for i in range(4):
                st = self._xi_state(i)
                if not st:
                    prev[i] = 0
                    continue
                g = st.Gamepad
                b = g.wButtons
                # левый стик → как крестовина
                if g.sThumbLY > 16000: b |= 0x0001
                if g.sThumbLY < -16000: b |= 0x0002
                if g.sThumbLX < -16000: b |= 0x0004
                if g.sThumbLX > 16000: b |= 0x0008
                pressed = b & ~prev[i]
                released = prev[i] & ~b
                prev[i] = b
                for bit, name in self.XI_BUTTONS.items():
                    if pressed & bit:
                        self.raw(f"Кнопка {bit:#06x}")
                        self.emit(name)
                for bit, name in self.XI_DIRS.items():
                    if pressed & bit:
                        held, held_since, last_rep = name, now, now
                        self.emit(name)
                    elif released & bit and held == name:
                        held = None
            if held and now - held_since > 0.38 and now - last_rep > 0.11:
                self.emit(held)
                last_rep = now

    def run(self):
        if IS_WIN:
            return self._run_xinput()
        open_pads = {}  # dev → [file, name, mapping, axes]
        held, held_since, last_rep = None, 0.0, 0.0
        next_scan = 0.0
        while True:
            now = time.monotonic()
            if now >= next_scan:  # подключение/отключение геймпадов
                next_scan = now + 2.0
                for d, n in self.controllers():
                    if d not in open_pads:
                        try:
                            f = open(d, "rb", buffering=0)
                            open_pads[d] = [f, n, self.mapping(n), {}]
                            print(f"gamepad: {n} ({d})", file=sys.stderr)
                        except OSError:
                            pass
            if not open_pads:
                time.sleep(0.5)
                continue
            try:
                r, _, _ = select.select([p[0] for p in open_pads.values()], [], [], 0.04)
            except (OSError, ValueError):
                r = []
            now = time.monotonic()
            if held and now - held_since > 0.38 and now - last_rep > 0.11:
                self.emit(held)
                last_rep = now
            for f in r:
                dev = next(k for k, v in open_pads.items() if v[0] is f)
                try:
                    data = f.read(8)
                except OSError:
                    data = b""
                if len(data) < 8:  # геймпад отключили
                    f.close()
                    open_pads.pop(dev, None)
                    held = None
                    continue
                _, val, typ, num = struct.unpack("IhBB", data)
                if typ & 0x80:  # начальное состояние при открытии
                    continue
                _f, _n, buttons, axes = open_pads[dev]
                if typ == 1 and val == 1:
                    self.raw(f"Кнопка {num}")
                    if num in buttons:
                        self.emit(buttons[num])
                elif typ == 2:
                    if abs(val) > 16000:
                        self.raw(f"Ось {num}: {'−' if val < 0 else '+'}")
                    if num in (0, 6):      # левый стик X, крестовина X
                        names = ("left", "right")
                    elif num in (1, 7):    # левый стик Y, крестовина Y
                        names = ("up", "down")
                    else:
                        continue
                    state = -1 if val < -16000 else (1 if val > 16000 else 0)
                    if state != axes.get(num, 0):
                        axes[num] = state
                        if state:
                            held = names[0] if state < 0 else names[1]
                            held_since = last_rep = now
                            self.emit(held)
                        else:
                            held = None

    @staticmethod
    def battery():
        """Заряд геймпада Sony (DualSense / DualShock 4) в %, или -1."""
        for p in sorted(glob.glob("/sys/class/power_supply/ps-controller-battery-*/capacity")):
            try:
                return int(Path(p).read_text().strip())
            except (OSError, ValueError):
                pass
        return -1


# ───────────────────────────── icons ─────────────────────────────

def load_icon(name):
    if os.path.isabs(name) and os.path.exists(name):
        return QIcon(name)
    icon = QIcon.fromTheme(name)
    if icon.isNull():
        for ext in ("png", "svg", "xpm"):
            p = f"/usr/share/pixmaps/{name}.{ext}"
            if os.path.exists(p):
                return QIcon(p)
        icon = QIcon.fromTheme("application-x-executable")
    return icon


class IconProvider(QQuickImageProvider):
    def __init__(self):
        super().__init__(QQuickImageProvider.ImageType.Pixmap)

    def requestPixmap(self, id_, size, requested):
        name = unquote(id_)
        px = 256
        if requested.width() > 0:
            px = requested.width()
        pm = load_icon(name).pixmap(QSize(px, px))
        if pm.isNull():
            pm = QPixmap(px, px)
            pm.fill(QColor(0, 0, 0, 0))
        if size is not None:
            size.setWidth(pm.width())
            size.setHeight(pm.height())
        return pm


SYM_DIRS = ["/usr/share/icons/breeze-dark"]


def find_sym(name):
    for base in SYM_DIRS:
        for sub in ("actions", "status", "devices", "applets", "categories", "places", "apps", "preferences"):
            for size in ("22", "24", "32", "symbolic", "16"):
                p = Path(base, sub, size, name + ".svg")
                if p.exists():
                    return str(p)
    return None


class SymProvider(QQuickImageProvider):
    """Монохромные светлые значки (breeze-dark) для системных элементов интерфейса."""
    def __init__(self):
        super().__init__(QQuickImageProvider.ImageType.Pixmap)
        self._cache = {}

    def requestPixmap(self, id_, size, requested):
        name = unquote(id_)
        px = requested.width() if requested.width() > 0 else 96
        if name not in self._cache:
            self._cache[name] = find_sym(name)
        path = self._cache[name]
        icon = QIcon(path) if path else load_icon(name)
        pm = icon.pixmap(QSize(px, px))
        if size is not None:
            size.setWidth(pm.width())
            size.setHeight(pm.height())
        return pm


def accent_color(name):
    img = load_icon(name).pixmap(QSize(40, 40)).toImage()
    bins = [[0.0, 0.0, 0.0, 0.0] for _ in range(12)]
    for y in range(img.height()):
        for x in range(img.width()):
            c = img.pixelColor(x, y)
            if c.alpha() < 128:
                continue
            h, s, v = c.hsvHueF(), c.hsvSaturationF(), c.valueF()
            if h < 0 or s < 0.2 or v < 0.2:
                continue
            w = s * v
            b = bins[int(h * 12) % 12]
            b[0] += c.redF() * w
            b[1] += c.greenF() * w
            b[2] += c.blueF() * w
            b[3] += w
    best = max(bins, key=lambda b: b[3])
    if best[3] < 1.5:
        return "#0b2a5c"
    c = QColor.fromRgbF(best[0] / best[3], best[1] / best[3], best[2] / best[3])
    return QColor.fromHsvF(max(c.hsvHueF(), 0), min(c.hsvSaturationF(), 0.85), 0.42).name()


# ───────────────────────────── backend ─────────────────────────────

DEFAULT_SETTINGS = {
    "sounds": True,
    "intro": True,
    # логотипы меню: "" — стандартный, иначе имя файла из media/logos
    "logo_boot": "", "logo_users": "", "logo_home": "", "logo_library": "", "logo_store": "", "logo_settings": "",
    "usersMusic": True,   # мелодия media/startup.* на экране выбора пользователя после заставки
    "theme": "blue",        # blue / night / purple / red / green / gold
    "clock24": True,
    "autostart": False,
    "lastUser": 0,
    "ps4Emu": "",
    "ps4Dirs": [],
    "ps4Fullscreen": True,
    "ps4Fps": False,
    "storeSources": [],
    "pkgExtractor": "",
}
AUTOSTART_FILE = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "autostart" / "tide-launcher.desktop"


def fmt_duration(sec):
    sec = int(sec)
    if sec <= 0:
        return "—"
    if sec < 60:
        return "< 1 мин"
    h, m = divmod(sec // 60, 60)
    return f"{h} ч {m} мин" if h else f"{m} мин"


class Backend(QObject):
    padInput = Signal(str)
    padRaw = Signal(str)
    appFinished = Signal()
    netTested = Signal(str)
    storeLoaded = Signal()
    achievementUnlocked = Signal(str, str, int)  # название, игра, уровень
    storeProgress = Signal(str, float, str)
    storeDone = Signal(str, bool, str)

    def __init__(self, args):
        super().__init__()
        self._args = args
        self._state = {"last": {}, "games": [], "notgames": [], "hidden": [], "count": {}, "time": {}, "settings": {}}
        try:
            self._state.update(json.loads(STATE_FILE.read_text()))
        except Exception:
            pass
        for k, v in DEFAULT_SETTINGS.items():
            self._state["settings"].setdefault(k, v)
        self._entries = {}
        self._store = []
        self._store_jobs = {}
        self._store_loading = False
        self._store_gen = 0
        self._links = {}  # url → {"ok", "size"}: результаты проверки ссылок на время работы лаунчера
        self._links_lock = threading.Lock()
        self._links_inflight = {}
        self._mf_events = {}      # ключ MediaFire → событие «пакет с ним проверен»
        self._link_dead = set()   # игры, у которых перепробованы все зеркала
        self._checking = 0        # сколько проходов проверки идёт сейчас
        self._art = None
        self._emit_lock = threading.Lock()
        self._last_emit = 0.0
        self._scan()
        self._seed_achievements()
        self._accent = {}
        self._procs = []
        self._timer = QTimer(self)
        self._timer.timeout.connect(self._poll)
        self._timer.start(1000)
        Gamepad(self.padInput.emit, self.padRaw.emit).start()
        self.storeRefresh()  # каталоги и проверка ссылок — сразу при запуске, в фоне

    # ── PS4 ──
    def _ps4_emu(self):
        return find_shadps4(self._state["settings"].get("ps4Emu", ""))

    def _ps4_dirs(self):
        out = []
        for d in list(self._state["settings"].get("ps4Dirs") or []) + PS4_DEFAULT_DIRS + shadps4_config_dirs():
            full = os.path.expanduser(d)
            if full not in out:
                out.append(full)
        return out

    def _scan(self):
        entries = scan_desktop_entries()
        emu = self._ps4_emu()
        if emu:
            entries["ps4-emulator"] = {
                "id": "ps4-emulator", "name": "shadPS4", "comment": "Эмулятор PS4 (Big Picture)",
                "icon": "applications-games", "exec": "", "terminal": False, "path": str(Path(emu).parent),
                "isGame": False, "ps4emu": True}
            entries.update(scan_ps4_games(self._ps4_dirs()))
        for c in self._state.get("customApps", []):
            entries[c["id"]] = {"id": c["id"], "name": c["name"], "comment": "Добавлено с ПК: " + c["file"].replace(str(Path.home()), "~"),
                                "icon": c.get("icon") or "application-x-executable", "exec": shlex.quote(c["file"]),
                                "terminal": False, "path": str(Path(c["file"]).parent), "isGame": False, "custom": True}
        self._entries = entries

    def _command(self, e):
        if e.get("ps4") or e.get("ps4emu"):
            emu = self._ps4_emu()
            if not emu:
                return []
            st = self._state["settings"]
            cmd = [emu, "-f", "true" if st.get("ps4Fullscreen", True) else "false"]
            if st.get("ps4Fps"):
                cmd.append("--show-fps")
            if e.get("ps4emu"):
                return [emu, "-b"]
            return cmd + [e["eboot"]]
        return build_command(e)

    def _save(self):
        CFG_DIR.mkdir(parents=True, exist_ok=True)
        STATE_FILE.write_text(json.dumps(self._state, ensure_ascii=False, indent=1))

    def _is_game(self, e):
        if e["id"] in self._state["games"]:
            return True
        if e["id"] in self._state["notgames"]:
            return False
        return e["isGame"]

    @staticmethod
    def _last_text(ts):
        if not ts:
            return "Ещё не запускалось"
        d = datetime.fromtimestamp(ts)
        today = datetime.now().date()
        if d.date() == today:
            return f"Последний запуск: сегодня, {d:%H:%M}"
        if d.date() == today - timedelta(days=1):
            return f"Последний запуск: вчера, {d:%H:%M}"
        return f"Последний запуск: {d:%d.%m.%Y}"

    def _item(self, e):
        did = e["id"]
        ts = self._state["last"].get(did, 0)
        t = self._state["time"].get(did, 0)
        return {"id": did, "name": e["name"], "comment": e["comment"], "icon": e["icon"],
                "last": ts, "lastText": self._last_text(ts), "isGame": self._is_game(e),
                "count": self._state["count"].get(did, 0), "time": t, "timeText": fmt_duration(t),
                "cover": e.get("cover", ""), "bg": e.get("bg", ""), "ps4": bool(e.get("ps4")),
                "pinned": did in self._state.get("pinned", [])}

    def _visible(self, e):
        """В лаунчере видны игры, эмулятор и приложения, которые пользователь добавил сам («Добавить приложение»)."""
        return self._is_game(e) or e.get("ps4emu") or e["id"] in self._state.get("pinned", [])

    def _list(self, games):
        hidden = set(self._state["hidden"])
        out = [self._item(e) for e in self._entries.values()
               if e["id"] not in hidden and self._visible(e) and (games is None or self._is_game(e) == games)]
        out.sort(key=lambda x: (not x["isGame"] if games is None else 0, -x["last"], x["name"].lower()))
        return out

    @Slot(result="QVariantList")
    def games(self):
        return self._list(True)

    @Slot(result="QVariantList")
    def apps(self):
        return self._list(False)

    @Slot(result="QVariantList")
    def allItems(self):
        return self._list(None)

    @Slot(result="QVariantList")
    def homeItems(self):
        items = self._list(None)   # только игры и добавленные приложения
        items.sort(key=lambda x: (-x["last"], not x["ps4"], not x["isGame"], x["name"].lower()))
        return items[:24]

    @Slot(str, result=str)
    def accent(self, icon):
        if icon not in self._accent:
            self._accent[icon] = accent_color(icon)
        return self._accent[icon]

    @Slot(str, result=bool)
    def launch(self, did):
        e = self._entries.get(did)
        if not e:
            return False
        try:
            cmd = self._command(e)
            if not cmd:
                return False
            p = subprocess.Popen(cmd, cwd=e["path"] or str(Path.home()),
                                 stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                 stderr=subprocess.DEVNULL, start_new_session=True)
        except Exception as ex:
            print("launch failed:", ex, file=sys.stderr)
            return False
        self._procs.append((p, time.monotonic(), did))
        self._state["last"][did] = time.time()
        self._state["count"][did] = self._state["count"].get(did, 0) + 1
        self._check_achievements(did)
        self._save()
        return True

    def _poll(self):
        if not self._procs:
            return
        alive, restore = [], False
        for p, started, did in self._procs:
            if p.poll() is None:
                alive.append((p, started, did))
                continue
            elapsed = time.monotonic() - started
            if elapsed > 5:  # quick exits = app forked/delegated, not a real session
                restore = True
                self._state["time"][did] = self._state["time"].get(did, 0) + int(elapsed)
                self._check_achievements(did)
                self._save()
        self._procs = alive
        if restore and not alive:
            self.appFinished.emit()

    # ── достижения ──
    def _ach_list(self, did):
        """Достижения лаунчера для игры, с отметками и датами получения."""
        c, t = self._state["count"].get(did, 0), self._state["time"].get(did, 0)
        got = self._state.setdefault("ach", {}).setdefault(did, {})
        out = []
        for key, name, desc, tier, cond in GAME_ACHIEVEMENTS:
            out.append({"id": key, "name": name, "desc": desc, "tier": tier, "got": key in got or cond(c, t),
                        "time": got.get(key, 0), "hidden": False, "icon": ""})
        allg = all(x["got"] for x in out)
        out.append({"id": PLATINUM[0], "name": PLATINUM[1], "desc": PLATINUM[2], "tier": PLATINUM[3],
                    "got": allg or PLATINUM[0] in got, "time": got.get(PLATINUM[0], 0), "hidden": False, "icon": ""})
        return out

    def _check_achievements(self, did):
        """Отмечает новые достижения (лаунчера и PS4-трофеи из shadPS4) и сообщает о них."""
        e = self._entries.get(did)
        if not e:
            return
        got = self._state.setdefault("ach", {}).setdefault(did, {})
        now = int(time.time())
        for a in self._ach_list(did):
            if a["got"] and a["id"] not in got:
                got[a["id"]] = now
                self.achievementUnlocked.emit(a["name"], e.get("name", ""), a["tier"])
        if e.get("ps4") and e.get("titleId"):
            seen = self._state.setdefault("ps4seen", {}).setdefault(did, [])
            for tr in ps4_trophies(e["titleId"]):
                if tr["got"] and tr["id"] not in seen:
                    seen.append(tr["id"])
                    self.achievementUnlocked.emit(tr["name"] or "Трофей", e.get("name", ""), tr["tier"])
        self._save()

    def _seed_achievements(self):
        """Тихо отмечает то, что уже заработано (статистика была и до системы достижений), чтобы не было лавины уведомлений."""
        now = int(time.time())
        ach = self._state.setdefault("ach", {})
        seen_all = self._state.setdefault("ps4seen", {})
        for did, e in self._entries.items():
            got = ach.setdefault(did, {})
            for a in self._ach_list(did):
                if a["got"] and a["id"] not in got:
                    got[a["id"]] = now
            if not got:
                ach.pop(did, None)
            if e.get("ps4") and e.get("titleId") and did not in seen_all:
                seen_all[did] = [t["id"] for t in ps4_trophies(e["titleId"]) if t["got"]]

    @Slot(result="QVariantList")
    def achievementGames(self):
        """Игры для экрана достижений: все игры в лаунчере (и только что установленные, ещё не запускавшиеся)."""
        out = []
        for did, e in self._entries.items():
            if did in self._state.get("hidden", []) or not self._is_game(e) or not self._visible(e):
                continue
            ps4 = ps4_trophies(e["titleId"]) if e.get("ps4") and e.get("titleId") else []
            la = self._ach_list(did)
            items = la + ps4
            out.append({"id": did, "name": e.get("name", ""), "icon": e.get("icon", ""),
                        "got": sum(1 for x in items if x["got"]), "total": len(items),
                        "tiers": [sum(1 for x in items if x["got"] and x["tier"] == k) for k in range(4)],
                        "ps4Total": len(ps4), "last": max([x["time"] for x in items] + [0])})
        out.sort(key=lambda x: (-x["last"], -x["got"], x["name"].lower()))
        return out

    @Slot(str, result="QVariantMap")
    def gameAchievements(self, did):
        e = self._entries.get(did) or {}
        ps4, note = [], ""
        if e.get("ps4"):
            tid = e.get("titleId", "")
            ps4 = ps4_trophies(tid) if tid else []
            if not ps4:
                game_dir = Path(e.get("path", "") or "")
                has_trp = any(game_dir.glob("sce_sys/trophy/*.trp")) if game_dir.is_dir() else False
                if not shadps4_trophy_key_set():
                    note = "Трофеи PS4 появятся, когда в shadPS4 будет задан ключ трофеев (keys.json)"
                elif has_trp:
                    note = "Трофеи PS4 появятся после первого запуска игры в shadPS4"
                else:
                    note = "У этой игры нет трофеев PS4"
        for t in ps4:
            if t["hidden"] and not t["got"]:
                t["name"], t["desc"] = "Скрытый трофей", "Описание откроется после получения"
        return {"name": e.get("name", ""), "launcher": self._ach_list(did), "ps4": ps4, "note": note}

    @Slot(str)
    def toggleGame(self, did):
        e = self._entries.get(did)
        if not e:
            return
        g, ng = self._state["games"], self._state["notgames"]
        for lst in (g, ng):
            if did in lst:
                lst.remove(did)
        if self._is_game(e):
            ng.append(did)
        else:
            g.append(did)
        self._save()

    # ── «Добавить приложение» ──
    @Slot(result="QVariantList")
    def pcApps(self):
        """Приложения на ПК, которые можно добавить на главную (ещё не добавленные и не игры)."""
        pinned = set(self._state.get("pinned", []))
        out = [{"id": e["id"], "name": e["name"], "icon": e["icon"], "comment": e.get("comment", "")}
               for e in self._entries.values()
               if not e.get("ps4") and not e.get("ps4emu") and not e.get("custom")
               and e["id"] not in pinned and not self._is_game(e)]
        out.sort(key=lambda x: x["name"].lower())
        return out

    def _pin(self, did):
        pinned = self._state.setdefault("pinned", [])
        if did not in pinned:
            pinned.append(did)
        if did in self._state["hidden"]:
            self._state["hidden"].remove(did)
        self._state["last"].setdefault(did, int(time.time()))  # новое — в начало ленты
        self._save()

    @Slot(str, result=bool)
    def addApp(self, did):
        if did not in self._entries:
            return False
        self._pin(did)
        return True

    @Slot(str, result=str)
    def addAppFile(self, path):
        """Добавить программу по пути к файлу (AppImage, скрипт, исполняемый файл). → id или ''."""
        import hashlib
        f = Path(os.path.expanduser(path.strip().strip('"').strip("'")))
        if not f.is_file():
            return ""
        if not os.access(f, os.X_OK):
            if f.suffix.lower() not in (".appimage", ".sh", ".run", ".x86_64", ".bin") and f.suffix:
                return ""
            try:
                os.chmod(f, f.stat().st_mode | 0o755)
            except OSError:
                return ""
        did = "custom-" + hashlib.sha1(str(f).encode()).hexdigest()[:10]
        name = f.stem.replace("_", " ").replace("-", " ").strip() or f.name
        apps = self._state.setdefault("customApps", [])
        if not any(c["id"] == did for c in apps):
            apps.append({"id": did, "name": name, "file": str(f)})
        self._scan()
        self._pin(did)
        return did

    @Slot(str)
    def removeApp(self, did):
        """Убрать добавленное приложение с главной (само приложение на ПК не трогается)."""
        if did in self._state.get("pinned", []):
            self._state["pinned"].remove(did)
        self._state["customApps"] = [c for c in self._state.get("customApps", []) if c["id"] != did]
        self._save()
        self._scan()

    @Slot(str)
    def hide(self, did):
        if did not in self._state["hidden"]:
            self._state["hidden"].append(did)
            self._save()

    @Slot()
    def unhideAll(self):
        self._state["hidden"] = []
        self._save()

    @Slot(result=int)
    def hiddenCount(self):
        return len(self._state["hidden"])

    @Slot()
    def rescan(self):
        self._scan()

    # ── магазин ──
    def _install_dir(self):
        user = self._state["settings"].get("ps4Dirs") or []
        d = os.path.expanduser(user[0]) if user else str(Path.home() / "Документы/Games")
        os.makedirs(d, exist_ok=True)
        return d

    def _installed_ids(self):
        return {e.get("titleId") for e in self._entries.values() if e.get("ps4")}

    def _store_view(self, it):
        x = dict(it)
        job = self._store_jobs.get(it["id"])
        # обновление (gp) с тем же Title ID, что и у игры, не считается «установленным» — его можно поставить поверх
        x["installed"] = bool(it.get("titleId")) and it.get("category") != "gp" and it["titleId"] in self._installed_ids()
        x["busy"] = bool(job and job.get("busy"))
        x["progress"] = job.get("frac", 0) if job else 0
        x["status"] = job.get("text", "") if job else ""
        return x

    @Slot(result="QVariantList")
    def storeItems(self):
        # игры с непроверенными или нерабочими ссылками не показываем
        return [self._store_view(it) for it in self._store if it.get("linkOk", it.get("kind") != "catalog") is True]

    @Slot(result=bool)
    def storeLoading(self):
        return self._store_loading

    @Slot(result="QVariantList")
    def storeSources(self):
        return list(self._state["settings"].get("storeSources") or [])

    @Slot(str, result=bool)
    def addStoreSource(self, src):
        src = src.strip()
        if not src:
            return False
        if not src.startswith(("http://", "https://", "file://")):
            src = os.path.expanduser(src)
            if not os.path.exists(src):
                return False
        lst = self.storeSources()
        if src not in lst:
            lst.append(src)
        self._state["settings"]["storeSources"] = lst
        self._save()
        self.storeRefresh()
        return True

    @Slot(str)
    def removeStoreSource(self, src):
        self._state["settings"]["storeSources"] = [x for x in self.storeSources() if x != src]
        self._save()
        self.storeRefresh()

    @Slot()
    def storeRefresh(self):
        if self._store_loading:
            return
        self._store_loading = True
        sources = self.storeSources()
        local_dirs = [Path.home() / "Документы/Games", Path.home() / "Загрузки", Path.home() / "Downloads"]

        def work():
            try:
                self._store = collect()
            except Exception as ex:
                print("store refresh failed:", ex, file=sys.stderr)
            finally:
                self._store_loading = False
                self._store_gen += 1
                self._store_enrich(self._store_gen, self._store, apply_only=True)  # уже проверенное — сразу в магазин
                self.storeLoaded.emit()
                threading.Thread(target=self._store_enrich_safe, args=(self._store_gen, self._store), daemon=True).start()

        def collect():
            items = []
            # 1) каталоги
            for si, src in enumerate(sources):
                try:
                    if src.startswith(("http://", "https://")):
                        import urllib.request
                        req = urllib.request.Request(src, headers={"User-Agent": "TideLauncher/1.0"})
                        raw = urllib.request.urlopen(req, timeout=20).read()
                    else:
                        raw = Path(unquote(src[7:]) if src.startswith("file://") else src).read_bytes()
                    cat = json.loads(raw.decode("utf-8"))
                    games = cat.get("games", []) if isinstance(cat, dict) else cat
                    sname = cat.get("name", "") if isinstance(cat, dict) else ""
                    base = src.rsplit("/", 1)[0] + "/"
                    for gi, g in enumerate(games):
                        if isinstance(g, dict) and "download_links" in g:
                            mirrors = mirror_groups(g.get("download_links"))
                            if not mirrors:
                                continue
                            hosts = ", ".join(HOST_NAMES.get(m["host"], m["host"]) +
                                              (f" ×{len(m['urls'])}" if len(m["urls"]) > 1 else "") for m in mirrors)
                            nparts = len(mirrors[0]["urls"])
                            items.append({
                                "id": f"c{si}-{gi}", "kind": "catalog",
                                "title": (g.get("name") or "").strip() or "Без названия", "titleId": "",
                                "desc": f"Зеркала: {hosts}" + (f". Архив из {nparts} частей." if nparts > 1 else ".")
                                        + (f"\n{g['page_url']}" if g.get("page_url") else ""),
                                "publisher": "", "genre": "", "version": "", "size": "",
                                "icon": "", "bg": "", "url": mirrors[0]["urls"][0], "mirrors": mirrors,
                                "pageUrl": g.get("page_url", ""), "sha256": "", "source": sname or Path(src).name})
                            continue
                        if not isinstance(g, dict) or not g.get("url"):
                            continue
                        def absu(u):
                            if not u or "://" in u or u.startswith("/"):
                                return u
                            return base + u
                        items.append({
                            "id": f"c{si}-{g.get('titleId') or gi}", "kind": "catalog",
                            "title": g.get("title", "Без названия"), "titleId": g.get("titleId", ""),
                            "desc": g.get("description", g.get("desc", "")), "publisher": g.get("publisher", ""),
                            "genre": g.get("genre", ""), "version": str(g.get("version", "")),
                            "size": fmt_size(g.get("size")) if g.get("size") else "",
                            "icon": absu(g.get("icon", "")), "bg": absu(g.get("background", g.get("bg", ""))),
                            "url": absu(g["url"]), "sha256": g.get("sha256", ""), "source": sname or src})
                except Exception as ex:
                    print("store source failed:", src, ex, file=sys.stderr)
            # 2) архивы в «Загрузках» (с кэшем: каждый архив проверяется один раз)
            idx_file = STORE_CACHE / "local-index.json"
            try:
                index = json.loads(idx_file.read_text())
            except Exception:
                index = {}
            new_index = {}
            for d in local_dirs:
                if not d.is_dir():
                    continue
                # файлы в самой папке и на один уровень глубже (например «Загрузки/Grand Theft Auto V/*.pkg»);
                # скрытые папки и папки уже установленных игр (с sce_sys) пропускаем
                cand = []
                for x in d.iterdir():
                    try:
                        if x.is_file():
                            cand.append(x)
                        elif x.is_dir() and not x.name.startswith(".") and not (x / "sce_sys").is_dir():
                            cand += [y for y in x.iterdir() if y.is_file()]
                    except OSError:
                        pass
                for f in sorted(cand, key=lambda x: -x.stat().st_mtime):
                    is_pkg = f.name.lower().endswith(".pkg")
                    if not f.is_file() or not (is_pkg or _is_archive(f.name)):
                        continue
                    stt = f.stat()
                    key = f"{f}|{stt.st_size}|{int(stt.st_mtime)}"
                    if key in index:
                        info = index[key]
                    else:
                        info = pkg_game_info(f) if is_pkg else archive_game_info(f)
                    new_index[key] = info
                    if not info:
                        continue
                    if is_pkg:
                        cat_name = PKG_CATEGORY.get(info.get("category", "gd"), "Пакет")
                        desc = f"{cat_name} PS4 · пакет PKG в папке «{d.name}»: {f.relative_to(d)}"
                    else:
                        desc = f"Архив в папке «{d.name}»: {f.name}"
                    items.append({
                        "id": "l-" + str(f.relative_to(d)), "kind": "local", "title": info["title"], "titleId": info["titleId"],
                        "pkg": is_pkg, "category": info.get("category", "gd"),
                        "desc": desc, "publisher": "", "genre": "",
                        "version": info["version"], "size": fmt_size(f.stat().st_size),
                        "icon": ("file://" + info["icon"]) if info["icon"] else "",
                        "bg": ("file://" + info["bg"]) if info["bg"] else "",
                        "url": "file://" + str(f), "sha256": "", "source": "Загрузки"})
            try:
                STORE_CACHE.mkdir(parents=True, exist_ok=True)
                idx_file.write_text(json.dumps(new_index, ensure_ascii=False))
            except Exception:
                pass
            return items

        threading.Thread(target=work, daemon=True).start()

    LINK_WORKERS = 24

    @staticmethod
    def _item_links(it):
        """Группы ссылок, которые надо проверить, или None, если проверять нечего (локальный файл)."""
        if it.get("allMirrors"):
            return it["allMirrors"]
        u = it.get("url", "")
        return [{"host": "url", "urls": [u]}] if u.startswith(("http://", "https://")) else None

    def _check_url(self, u):
        """Проверка одной ссылки с кэшем на время работы лаунчера; одна и та же ссылка не проверяется дважды,
        даже если её одновременно запросили несколько потоков. → {"ok", "size"} или None (сеть недоступна)."""
        mk = mediafire_key(u)
        mev = self._mf_events.get(mk) if mk else None
        if mev:
            mev.wait(90)
        with self._links_lock:
            if u in self._links:
                return self._links[u]
            ev = self._links_inflight.get(u)
            owner = ev is None
            if owner:
                ev = self._links_inflight[u] = threading.Event()
        if not owner:
            ev.wait(120)
            return self._links.get(u)
        try:
            for attempt in range(2):
                try:
                    ok, size = check_link(u)
                    with self._links_lock:
                        self._links[u] = {"ok": ok, "size": size}
                    return self._links[u]
                except LinkError as ex:
                    if attempt == 0:
                        time.sleep(1.0)
                        continue
                    print("link check failed:", u, ex, file=sys.stderr)
                except Exception as ex:
                    print("link check failed:", u, ex, file=sys.stderr)
                    break
            return None  # сбой сети не кэшируем — при следующем обновлении попробуем снова
        finally:
            with self._links_lock:
                self._links_inflight.pop(u, None)
            ev.set()

    def _store_enrich_safe(self, gen, items):
        try:
            self._store_enrich(gen, items)
        except RuntimeError as ex:  # лаунчер закрывается посреди проверки — пул потоков уже остановлен
            if "shutdown" not in str(ex):
                raise

    def _art_meta(self):
        """Кэш картинок по названию (meta.json), общий для всех проходов."""
        if self._art is None:
            try:
                self._art = {k: v for k, v in json.loads((STORE_CACHE / "meta.json").read_text()).items() if k.startswith("art:")}
            except Exception:
                self._art = {}
        return self._art

    def _save_art_meta(self):
        try:
            STORE_CACHE.mkdir(parents=True, exist_ok=True)
            (STORE_CACHE / "meta.json").write_text(json.dumps(self._art_meta(), ensure_ascii=False))
        except Exception:
            pass

    def _apply_item(self, it):
        """Переносит в игру всё, что уже известно: результаты проверки ссылок, размер, картинки."""
        art = self._art_meta().get("art:" + clean_game_name(it["title"]).lower())
        if art and not it.get("icon") and art.get("icon"):
            it["icon"] = "file://" + art["icon"]
        if art and not it.get("bg") and art.get("bg"):
            it["bg"] = "file://" + art["bg"]
        if it.get("mirrors") and "allMirrors" not in it:
            it["allMirrors"] = it["mirrors"]
        groups = self._item_links(it)
        if groups is None:
            it["linkOk"] = True
            return
        working, unknown = [], []
        for g in groups:
            st = [self._links.get(u) for u in g["urls"]]
            if any(e is not None and not e["ok"] for e in st):
                continue  # хотя бы одна часть мертва — зеркало не годится
            (working if all(e is not None for e in st) else unknown).append((g, st))
        if working:
            it["linkOk"] = True
            sizes = [e.get("size", 0) for e in working[0][1]]
            if not it.get("size") and all(sizes):
                it["size"] = fmt_size(sum(sizes))
        elif not unknown or it["id"] in self._link_dead:
            it["linkOk"] = False
        else:
            it["linkOk"] = None
        if it.get("allMirrors"):
            it["mirrors"] = [g for g, _ in working + unknown] or it["allMirrors"]
            it["url"] = it["mirrors"][0]["urls"][0]

    def _sync_store(self):
        """Применяет известные результаты ко всем играм, которые сейчас в магазине (в т.ч. от прошлых проходов)."""
        for it in list(self._store):
            if it.get("kind") == "catalog":
                self._apply_item(it)

    def _store_changed(self, force=False):
        """Обновить магазин на экране — не чаще раза в 0,5 с."""
        with self._emit_lock:
            now = time.monotonic()
            if not force and now - self._last_emit < 0.5:
                return
            self._last_emit = now
        self._sync_store()
        self.storeLoaded.emit()

    def _store_enrich(self, gen, items, apply_only=False):
        """Проверка ссылок, размер файлов, иконки/фон по названию для игр из каталогов.
        Игра показывается в магазине, как только подтвердилось, что её ссылка работает.
        Ссылки проверяются один раз за запуск лаунчера (кэш в памяти), картинки кэшируются в meta.json."""
        from concurrent.futures import ThreadPoolExecutor, as_completed
        cat = [it for it in items if it.get("kind") == "catalog"]
        for it in cat:
            self._apply_item(it)
        if apply_only:
            return
        with self._emit_lock:
            self._checking += 1
        try:
            self._enrich_run(gen, cat)
        finally:
            with self._emit_lock:
                self._checking -= 1
            self._save_art_meta()
            self._store_changed(force=True)

    def _enrich_run(self, gen, cat):
        from concurrent.futures import ThreadPoolExecutor, as_completed
        meta = self._art_meta()
        pending = [it for it in cat if it.get("linkOk") is None]

        # 1) MediaFire: все ссылки пакетами по 200 через API; результат каждого пакета сразу виден в магазине.
        #    Ключи, которые уже проверяет другой проход, повторно не отправляем.
        keys, mine = {}, []
        for it in pending:
            for g in self._item_links(it) or []:
                for u in g["urls"]:
                    k = mediafire_key(u)
                    if k and u not in self._links:
                        keys.setdefault(k, []).append(u)
        with self._links_lock:
            for k in keys:
                if k not in self._mf_events:
                    self._mf_events[k] = threading.Event()
                    mine.append(k)
        chunks = [mine[i:i + 200] for i in range(0, len(mine), 200)]

        def batch(ks):
            try:
                res = check_mediafire_batch(ks)
                with self._links_lock:
                    for k, (ok, size) in res.items():
                        for u in keys.get(k, []):
                            self._links[u] = {"ok": ok, "size": size}
            except Exception as ex:
                print("mediafire batch failed:", ex, file=sys.stderr)
            finally:
                with self._links_lock:
                    for k in ks:
                        ev = self._mf_events.pop(k, None)
                        if ev:
                            ev.set()

        # пакеты MediaFire идут параллельно с проверкой остальных ссылок
        bp = ThreadPoolExecutor(6)
        for c in chunks:
            bp.submit(batch, c).add_done_callback(lambda f: self._store_changed())

        def do_art(it):
            key = "art:" + clean_game_name(it["title"]).lower()
            if not it.get("icon") and key not in meta:
                urls = find_art(it["title"])
                stem = "".join(c if c.isalnum() else "_" for c in key[4:])[:60]
                art = {"icon": cache_image(urls["icon"], stem + "-icon"),
                       "bg": cache_image(urls["bg"], stem + "-bg")}
                if not (art["icon"] or art["bg"]):
                    return  # не нашли — не кэшируем, попробуем при следующем обновлении
                art["bg"] = art["bg"] or art["icon"]
                meta[key] = art
            self._store_changed()

        # 2) остальные ссылки: сначала первые зеркала всех игр разом, для оставшихся — следующие зеркала, и т. д.
        with ThreadPoolExecutor(self.LINK_WORKERS) as pool, ThreadPoolExecutor(6) as art_pool:
            arts = [art_pool.submit(do_art, it) for it in cat if it.get("linkOk")]
            rnd = 0
            while pending:
                batch_items = []
                for it in pending:
                    groups = self._item_links(it)
                    if rnd < len(groups):
                        batch_items.append((it, groups[rnd]))
                    else:  # все зеркала перепробованы — нерабочая (до следующего запуска лаунчера)
                        self._link_dead.add(it["id"])
                        it["linkOk"] = False
                        print("store: скрыта игра с нерабочими ссылками:", it["title"], file=sys.stderr)
                if not batch_items:
                    break
                url_items = {}
                for it, g in batch_items:
                    for u in g["urls"]:
                        url_items.setdefault(u, []).append(it)
                # сначала ссылки других хостингов; ссылки MediaFire — в конце (они ждут свой пакет, а не проверяются отдельно)
                order = sorted(url_items, key=lambda u: bool(mediafire_key(u)))
                futs = {pool.submit(self._check_url, u): u for u in order}
                for f in as_completed(futs):
                    for it in url_items[futs[f]]:
                        was = it.get("linkOk")
                        self._apply_item(it)
                        if was is None and it.get("linkOk"):
                            arts.append(art_pool.submit(do_art, it))
                    self._store_changed()
                pending = [it for it, _ in batch_items if it.get("linkOk") is None]
                rnd += 1
            for f in arts:
                try:
                    f.result()
                except Exception as ex:
                    print("store art failed:", ex, file=sys.stderr)
        bp.shutdown(wait=True)

    @Slot(result=str)
    def storeStatus(self):
        """«Проверка ссылок: N из M» — по играм, которые сейчас в магазине."""
        if not self._checking:
            return ""
        total = done = 0
        for it in list(self._store):
            if it.get("kind") != "catalog" or self._item_links(it) is None:
                continue
            total += 1
            if it.get("linkOk") is not None:
                done += 1
        return f"Проверка ссылок: {done} из {total}" if total and done < total else ""

    def _job(self, sid, frac, text):
        self._store_jobs[sid] = {"busy": True, "frac": frac, "text": text}
        self.storeProgress.emit(sid, frac, text)

    @Slot(str, result=bool)
    def storeInstall(self, sid):
        it = next((x for x in self._store if x["id"] == sid), None)
        if not it or (sid in self._store_jobs and self._store_jobs[sid].get("busy")):
            return False
        dest_root = self._install_dir()
        cancel = threading.Event()
        self._store_jobs[sid] = {"busy": True, "frac": 0, "text": "Подготовка…", "cancel": cancel}
        stage = Path(dest_root) / f".tide-install-{os.getpid()}-{abs(hash(sid))}"

        def fetch(url, dest_dir, label, f0, f1):
            r, name = open_download(url)
            tmp = dest_dir / name
            with r, open(tmp, "wb") as f:
                total = int(r.headers.get("Content-Length") or 0)
                got, t0, last = 0, time.monotonic(), 0
                while True:
                    if cancel.is_set():
                        raise RuntimeError("Отменено")
                    chunk = r.read(1 << 20)
                    if not chunk:
                        break
                    f.write(chunk)
                    got += len(chunk)
                    now = time.monotonic()
                    if now - last > 0.3:
                        last = now
                        speed = got / max(0.1, now - t0)
                        txt = f"{label}{fmt_size(got)}" + (f" из {fmt_size(total)}" if total else "") + f" · {fmt_size(speed)}/с"
                        self._job(sid, f0 + (f1 - f0) * got / total if total else f0, txt)
            if total and got < total:
                raise RuntimeError("Загрузка прервалась")
            return tmp

        def fetch_mirrors(mirrors, dest_dir):
            errors = []
            for m in mirrors:
                host = HOST_NAMES.get(m["host"], m["host"])
                shutil.rmtree(dest_dir, ignore_errors=True)
                dest_dir.mkdir(parents=True, exist_ok=True)
                try:
                    n, files = len(m["urls"]), []
                    for i, u in enumerate(m["urls"]):
                        label = f"{host}" + (f" · часть {i + 1}/{n}" if n > 1 else "") + " · "
                        self._job(sid, 0.8 * i / n, label + "получение ссылки…")
                        files.append(fetch(u, dest_dir, label, 0.8 * i / n, 0.8 * (i + 1) / n))
                    return files
                except Exception as ex:
                    if cancel.is_set():
                        raise RuntimeError("Отменено")
                    print("mirror failed:", host, ex, file=sys.stderr)
                    errors.append(f"{host}: {ex}")
            raise RuntimeError("Ни одно зеркало не сработало — " + "; ".join(errors))

        def extract_pkg(src, f0):
            if it.get("category") == "ac":
                raise RuntimeError("Установка дополнений (DLC) из PKG пока не поддерживается")
            tool = find_pkg_extractor(self._state["settings"].get("pkgExtractor", ""))
            if not tool:
                raise RuntimeError("Нужен распаковщик PKG — скачайте ShadPs4Plus PKG Extractor (AppImage) "
                                   "в «Загрузки» или укажите путь: Настройки › Эмулятор PS4")
            pkg_size = src.stat().st_size
            free = shutil.disk_usage(stage).free
            if free < pkg_size * 1.05:
                raise RuntimeError(f"Мало места: нужно ~{fmt_size(pkg_size)}, свободно {fmt_size(free)}")
            out = stage / "pkg"
            out.mkdir(parents=True, exist_ok=True)
            log = []
            p = subprocess.Popen([tool, str(src), str(out)], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                 text=True, errors="replace", env={**os.environ, "APPIMAGE_EXTRACT_AND_RUN": "1"})
            reader = threading.Thread(target=lambda: [log.append(l.rstrip()) for l in p.stdout], daemon=True)
            reader.start()
            while p.poll() is None:
                if cancel.is_set():
                    p.kill()
                    raise RuntimeError("Отменено")
                done = dir_size(out)
                frac = min(0.99, done / max(1, pkg_size))
                self._job(sid, f0 + (0.97 - f0) * frac, f"Распаковка PKG… {fmt_size(done)} из {fmt_size(pkg_size)}")
                time.sleep(1.0)
            reader.join(5)
            if p.returncode != 0:
                tail = " / ".join(l for l in log[-3:] if l) or f"код {p.returncode}"
                raise RuntimeError("Не удалось распаковать PKG (зашифрованный retail-PKG?): " + tail)

        def work():
            tmp_file = None
            parts_dir = None
            try:
                url = it["url"]
                parts = []
                # 1) получение файла
                if it.get("mirrors"):
                    parts_dir = CACHE_DIR / "downloads" / f"parts-{abs(hash(sid))}"
                    parts = fetch_mirrors(it["mirrors"], parts_dir)
                    src = first_volume(parts)
                elif url.startswith("file://") or url.startswith("/"):
                    src = Path(unquote(url[7:]) if url.startswith("file://") else url)
                else:
                    import urllib.request
                    (CACHE_DIR / "downloads").mkdir(parents=True, exist_ok=True)
                    name = unquote(url.split("?")[0].rsplit("/", 1)[-1]) or "game.zip"
                    tmp_file = CACHE_DIR / "downloads" / name
                    req = urllib.request.Request(url, headers={"User-Agent": "TideLauncher/1.0"})
                    with urllib.request.urlopen(req, timeout=30) as r, open(tmp_file, "wb") as f:
                        total = int(r.headers.get("Content-Length") or 0)
                        got, t0, last = 0, time.monotonic(), 0
                        while True:
                            if cancel.is_set():
                                raise RuntimeError("Отменено")
                            chunk = r.read(1 << 20)
                            if not chunk:
                                break
                            f.write(chunk)
                            got += len(chunk)
                            now = time.monotonic()
                            if now - last > 0.3:
                                last = now
                                speed = got / max(0.1, now - t0)
                                txt = f"Загрузка {fmt_size(got)}" + (f" из {fmt_size(total)}" if total else "") + f" · {fmt_size(speed)}/с"
                                self._job(sid, 0.8 * got / total if total else 0.0, txt)
                    src = tmp_file
                    if it.get("sha256"):
                        import hashlib
                        self._job(sid, 0.8, "Проверка файла…")
                        h = hashlib.sha256()
                        with open(src, "rb") as f:
                            for chunk in iter(lambda: f.read(1 << 22), b""):
                                h.update(chunk)
                        if h.hexdigest().lower() != it["sha256"].lower():
                            raise RuntimeError("Контрольная сумма не совпала")
                if not src.exists():
                    raise RuntimeError("Файл не найден")
                # 2) распаковка
                is_local_pkg = src.suffix.lower() == ".pkg" and not (tmp_file or parts)
                self._job(sid, 0.0 if is_local_pkg else 0.8, "Распаковка…")
                stage.mkdir(parents=True, exist_ok=True)
                import re
                if len(parts) > 1 and re.search(r"\.0*1$", src.name):
                    # split-архив .001/.002/… → склеиваем в один файл
                    joined = src.with_name(re.sub(r"\.\d+$", "", src.name))
                    with open(joined, "wb") as out:
                        for p in sorted(parts, key=lambda x: x.name):
                            with open(p, "rb") as f:
                                shutil.copyfileobj(f, out, 1 << 22)
                            p.unlink()
                    src = joined
                if src.is_dir():
                    shutil.copytree(src, stage / src.name)
                elif src.suffix.lower() == ".pkg":
                    extract_pkg(src, 0.8 if (tmp_file or parts) else 0.0)
                elif len(parts) > 1 and src.suffix.lower() == ".rar":
                    if not shutil.which("unrar"):
                        raise RuntimeError("Для многотомного RAR нужен unrar")
                    p = subprocess.Popen(["unrar", "x", "-o+", "-y", str(src), str(stage) + "/"],
                                         stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
                    for line in p.stdout:
                        if cancel.is_set():
                            p.kill()
                            raise RuntimeError("Отменено")
                        m = re.search(r"(\d+)%", line)
                        if m:
                            self._job(sid, 0.8 + 0.18 * int(m.group(1)) / 100, f"Распаковка… {m.group(1)}%")
                    if p.wait() != 0:
                        raise RuntimeError("Ошибка распаковки RAR")
                else:
                    total = max(1, len(archive_list(src)))
                    p = subprocess.Popen([TAR, "-xvf", str(src), "-C", str(stage)],
                                         stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
                    n = 0
                    for _ in p.stderr:
                        n += 1
                        if cancel.is_set():
                            p.kill()
                            raise RuntimeError("Отменено")
                        if n % 20 == 0:
                            self._job(sid, 0.8 + 0.18 * min(1, n / total), f"Распаковка… {min(100, n * 100 // total)}%")
                    if p.wait() != 0 and src.suffix.lower() == ".rar" and shutil.which("unrar"):
                        subprocess.run(["unrar", "x", "-o+", str(src), str(stage) + "/"], capture_output=True)
                # 3) установка: каждая папка с param.sfo → в папку игр
                found = []
                for sfo in stage.rglob("sce_sys/param.sfo"):
                    gdir = sfo.parent.parent
                    if any(gdir.is_relative_to(f) for f in found):
                        continue
                    found.append(gdir)
                if not found:
                    raise RuntimeError("В архиве нет игры PS4 (eboot.bin + sce_sys)")
                installed = []
                for gdir in found:
                    info = read_sfo(gdir / "sce_sys" / "param.sfo")
                    tid = str(info.get("TITLE_ID") or gdir.name)
                    cat = str(info.get("CATEGORY", "gd"))
                    name = tid + ("-UPDATE" if cat.startswith("gp") else "")
                    target = Path(dest_root) / name
                    if target.exists():
                        if cat.startswith("gp"):
                            shutil.rmtree(target)
                        else:
                            raise RuntimeError(f"Уже установлено: {target}")
                    shutil.move(str(gdir), str(target))
                    installed.append(name)
                self._store_jobs[sid] = {"busy": False, "frac": 1, "text": ""}
                self.storeDone.emit(sid, True, "Установлено в " + dest_root.replace(str(Path.home()), "~"))
            except Exception as ex:
                self._store_jobs[sid] = {"busy": False, "frac": 0, "text": ""}
                self.storeDone.emit(sid, False, str(ex))
            finally:
                shutil.rmtree(stage, ignore_errors=True)
                if tmp_file and tmp_file.exists():
                    tmp_file.unlink()
                if parts_dir:
                    shutil.rmtree(parts_dir, ignore_errors=True)

        threading.Thread(target=work, daemon=True).start()
        return True

    @Slot(str)
    def storeCancel(self, sid):
        job = self._store_jobs.get(sid)
        if job and job.get("cancel"):
            job["cancel"].set()

    @Slot(result="QVariantMap")
    def ps4Info(self):
        emu = self._ps4_emu()
        games = [e for e in self._entries.values() if e.get("ps4")]
        return {"emu": emu, "found": bool(emu), "games": len(games),
                "pkgTool": find_pkg_extractor(self._state["settings"].get("pkgExtractor", "")),
                "dirs": self._ps4_dirs(), "userDirs": list(self._state["settings"].get("ps4Dirs") or [])}

    @Slot(str, result=bool)
    def addPs4Dir(self, d):
        d = os.path.expanduser(d.strip())
        if not os.path.isdir(d):
            return False
        lst = list(self._state["settings"].get("ps4Dirs") or [])
        if d not in lst:
            lst.append(d)
        self._state["settings"]["ps4Dirs"] = lst
        self._save()
        self._scan()
        return True

    @Slot(str)
    def removePs4Dir(self, d):
        lst = [x for x in (self._state["settings"].get("ps4Dirs") or []) if x != d]
        self._state["settings"]["ps4Dirs"] = lst
        self._save()
        self._scan()

    # ── settings ──
    @Slot(result="QVariantMap")
    def settings(self):
        return dict(self._state["settings"])

    @Slot(str, "QVariant")
    def setSetting(self, key, value):
        self._state["settings"][key] = value
        self._save()
        if key == "autostart":
            if value:
                AUTOSTART_FILE.parent.mkdir(parents=True, exist_ok=True)
                AUTOSTART_FILE.write_text(
                    "[Desktop Entry]\nType=Application\nName=Tide\n"
                    f"Exec={Path.home() / ".local/bin/tide"}\nX-GNOME-Autostart-enabled=true\n")
            elif AUTOSTART_FILE.exists():
                AUTOSTART_FILE.unlink()

    @Slot(result="QVariantMap")
    def stats(self):
        visible = self._list(None)
        total_t = sum(self._state["time"].values())
        top = max(visible, key=lambda x: (x["time"], x["count"]), default=None)
        return {"games": sum(1 for x in visible if x["isGame"]),
                "apps": sum(1 for x in visible if not x["isGame"]),
                "launches": sum(self._state["count"].values()),
                "timeText": fmt_duration(total_t), "seconds": total_t,
                "distinct": sum(1 for x in visible if x["count"]),
                "distinctGames": sum(1 for x in visible if x["count"] and x["isGame"]),
                "top": top["name"] if top and (top["count"] or top["time"]) else "—"}

    @Slot(result="QVariantList")
    def sysinfo(self):
        import platform
        u = platform.uname()
        cpu = ram = "—"
        up = 0
        if IS_WIN:
            import ctypes
            cpu = platform.processor() or "—"
            try:
                class MS(ctypes.Structure):
                    _fields_ = [("len", ctypes.c_ulong), ("load", ctypes.c_ulong), ("total", ctypes.c_ulonglong),
                                ("avail", ctypes.c_ulonglong), ("tp", ctypes.c_ulonglong), ("ap", ctypes.c_ulonglong),
                                ("tv", ctypes.c_ulonglong), ("av", ctypes.c_ulonglong), ("ave", ctypes.c_ulonglong)]
                ms = MS(); ms.len = ctypes.sizeof(MS)
                ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(ms))
                ram = f"{ms.total / 1073741824:.1f} ГБ"
                ctypes.windll.kernel32.GetTickCount64.restype = ctypes.c_ulonglong
                up = ctypes.windll.kernel32.GetTickCount64() / 1000
            except Exception:
                pass
        else:
          try:
            for line in open("/proc/cpuinfo"):
                if line.startswith("model name"):
                    cpu = line.split(":", 1)[1].strip()
                    break
            for line in open("/proc/meminfo"):
                if line.startswith("MemTotal"):
                    ram = f"{int(line.split()[1]) / 1048576:.1f} ГБ"
                    break
            up = float(open("/proc/uptime").read().split()[0])
          except Exception:
            up = 0
        from PySide6 import __version__ as pyside_ver
        return [["Имя устройства", u.node], ["Система", f"{u.system} {u.release}"], ["Процессор", cpu],
                ["Память", ram], ["Время работы", fmt_duration(up)],
                ["Версия Tide", "1.0"], ["Qt / PySide", pyside_ver], ["Python", sys.version.split()[0]]]


    # ── users ──
    def _users(self):
        u = self._state.setdefault("users", [])
        if not u:
            u.append({"name": (os.environ.get("USER") or os.environ.get("USERNAME") or "Игрок").capitalize(), "color": 0})
        return u

    @Slot(result="QVariantList")
    def users(self):
        return [dict(x) for x in self._users()]

    @Slot(str, int, result=int)
    def addUser(self, name, color):
        u = self._users()
        u.append({"name": name.strip() or f"Пользователь {len(u) + 1}", "color": color})
        self._save()
        return len(u) - 1

    @Slot(int, str)
    def renameUser(self, i, name):
        u = self._users()
        if 0 <= i < len(u) and name.strip():
            u[i]["name"] = name.strip()
            self._save()

    @Slot(int, int)
    def setUserColor(self, i, color):
        u = self._users()
        if 0 <= i < len(u):
            u[i]["color"] = color
            self._save()

    @Slot(int)
    def removeUser(self, i):
        u = self._users()
        if 0 <= i < len(u) and len(u) > 1:
            u.pop(i)
            self._save()

    @Slot(result="QVariantList")
    def activity(self):
        out = []
        for did, ts in sorted(self._state["last"].items(), key=lambda kv: -kv[1])[:12]:
            e = self._entries.get(did)
            if not e:
                continue
            d = datetime.fromtimestamp(ts)
            today = datetime.now().date()
            when = (f"сегодня, {d:%H:%M}" if d.date() == today else
                    f"вчера, {d:%H:%M}" if d.date() == today - timedelta(days=1) else f"{d:%d.%m.%Y}")
            out.append({"id": did, "name": e["name"], "icon": e["icon"], "when": when,
                        "isGame": self._is_game(e), "timeText": fmt_duration(self._state["time"].get(did, 0)),
                        "count": self._state["count"].get(did, 0)})
        return out

    # ── running apps ──
    @Slot(result="QVariantList")
    def running(self):
        out = []
        for p, started, did in self._procs:
            e = self._entries.get(did)
            if e and p.poll() is None:
                out.append({"id": did, "name": e["name"], "icon": e["icon"],
                            "since": fmt_duration(time.monotonic() - started)})
        return out

    @Slot(str)
    def closeApp(self, did):
        import signal
        for p, _, d in self._procs:
            if d == did and p.poll() is None:
                try:
                    os.killpg(p.pid, signal.SIGTERM)
                except OSError:
                    p.terminate()

    @Slot(str, result="QVariantMap")
    def appInfo(self, did):
        e = self._entries.get(did)
        if not e:
            return {}
        return {"name": e["name"], "id": did, "cmd": " ".join(shlex.quote(x) for x in self._command(e)),
                "count": self._state["count"].get(did, 0),
                "time": fmt_duration(self._state["time"].get(did, 0)),
                "last": self._last_text(self._state["last"].get(did, 0))}

    # ── system state (звук, сеть, батарея, диски, контроллеры) ──
    @staticmethod
    def _run(cmd, timeout=3):
        try:
            return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout).stdout
        except Exception:
            return ""

    @Slot(result="QVariantMap")
    def sysState(self):
        st = {"volume": 0, "muted": False, "sink": "", "sinks": [], "net": "Нет подключения", "netType": "",
              "ip": "—", "battery": -1, "charging": False, "disks": [], "pads": [], "padBattery": -1}
        out = self._run(["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"])
        if out.startswith("Volume:"):
            parts = out.split()
            st["volume"] = int(round(float(parts[1]) * 100))
            st["muted"] = "[MUTED]" in out
        try:
            sinks = json.loads(self._run(["pactl", "-f", "json", "list", "sinks"]) or "[]")
            st["sinks"] = [[s["name"], s.get("description") or s["name"]] for s in sinks]
        except Exception:
            pass
        st["sink"] = self._run(["pactl", "get-default-sink"]).strip()
        for line in self._run(["nmcli", "-t", "-f", "NAME,TYPE,DEVICE", "connection", "show", "--active"]).splitlines():
            name, typ, dev = (line.rsplit(":", 2) + ["", ""])[:3]
            if "wireless" in typ or "ethernet" in typ:
                st["net"] = name
                st["netType"] = "Wi‑Fi" if "wireless" in typ else "Ethernet"
                try:
                    for a in json.loads(self._run(["ip", "-j", "-4", "addr", "show", dev]) or "[]"):
                        for ai in a.get("addr_info", []):
                            st["ip"] = ai["local"]
                except Exception:
                    pass
                break
        for bat in sorted(glob.glob("/sys/class/power_supply/BAT*")):
            try:
                st["battery"] = int(Path(bat, "capacity").read_text())
                st["charging"] = Path(bat, "status").read_text().strip() in ("Charging", "Full")
            except OSError:
                pass
            break
        seen = set()
        for line in self._run(["findmnt", "-rno", "SOURCE,TARGET", "-t", "ext4,btrfs,xfs,vfat,exfat,ntfs3,ntfs,f2fs"]).splitlines():
            src, tgt = line.split(" ", 1)
            dev = src.split("[")[0]
            if dev in seen or tgt.startswith(("/var", "/srv", "/root")):
                continue
            seen.add(dev)
            try:
                u = shutil.disk_usage(tgt.replace("\\x20", " "))
            except OSError:
                continue
            st["disks"].append({"mount": tgt, "used": u.used, "total": u.total,
                                "text": f"{u.used / 1e9:.0f} из {u.total / 1e9:.0f} ГБ"})
        st["pads"] = [n for _, n in Gamepad.controllers()]
        st["padBattery"] = Gamepad.battery()
        return st

    @Slot(str, "QVariant")
    def setSys(self, key, value):
        if key == "volume":
            self._run(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", f"{max(0, min(100, int(value)))}%"])
        elif key == "muted":
            self._run(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "1" if value else "0"])
        elif key == "sink":
            self._run(["pactl", "set-default-sink", str(value)])

    @Slot()
    def testNetwork(self):
        def work():
            t0 = time.monotonic()
            ok = subprocess.run(["ping", "-c", "1", "-W", "3", "1.1.1.1"], capture_output=True).returncode == 0
            ms = int((time.monotonic() - t0) * 1000)
            self.netTested.emit(f"Интернет доступен · {ms} мс" if ok else "Нет доступа к интернету")
        threading.Thread(target=work, daemon=True).start()

    @Slot(str)
    def power(self, action):
        cmds = {"suspend": ["systemctl", "suspend"], "reboot": ["systemctl", "reboot"],
                "poweroff": ["systemctl", "poweroff"]}
        if IS_WIN:
            cmds = {"suspend": ["rundll32.exe", "powrprof.dll,SetSuspendState", "0,1,0"],
                    "reboot": ["shutdown", "/r", "/t", "0"], "poweroff": ["shutdown", "/s", "/t", "0"]}
        if action == "quit":
            QGuiApplication.quit()
        elif action in cmds:
            subprocess.Popen(cmds[action], start_new_session=True)

    @Slot(str, result=str)
    def sound(self, name):
        # только свои звуки из media/: select.* — любая кнопка (в т.ч. «Назад»/Esc), scroll.* — перемещение, login.* — после выбора пользователя.
        # Встроенных звуков нет: если своего файла нет, звука нет.
        stem = {"accept": "select", "open": "select", "back": "select", "launch": "select",
                "move": "scroll", "login": "login"}.get(name)
        custom = self._custom_wav(stem) if stem else None
        return QUrl.fromLocalFile(str(custom)).toString() if custom else ""

    def _custom_wav(self, stem):
        """Свой звук из media/ → WAV в кэше (SoundEffect играет только WAV, зато без задержки)."""
        src = media_file(stem)
        if not src:
            return None
        if src.suffix.lower() == ".wav":
            return src
        out = CACHE_DIR / "sounds" / f"custom-{stem}-{int(src.stat().st_mtime)}-{src.stat().st_size}.wav"
        if not out.exists():
            try:
                out.parent.mkdir(parents=True, exist_ok=True)
                subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(src), "-ac", "2", "-ar", "44100", str(out)],
                               check=True, timeout=30)
            except Exception as ex:
                print("custom sound failed:", src, ex, file=sys.stderr)
                return None
        return out

    @Slot(result="QVariantMap")
    def mediaInfo(self):
        for sub in ("videos", "logos"):
            (MEDIA_DIR / sub).mkdir(parents=True, exist_ok=True)
        music = media_file("startup")
        return {"dir": str(MEDIA_DIR), "videos": media_list("videos", VIDEO_EXT), "logos": media_list("logos", IMAGE_EXT),
                "music": QUrl.fromLocalFile(str(music)).toString() if music else "",
                "musicName": music.name if music else "",
                "hasSelect": any(media_file(n) for n in ("select", "scroll", "login"))}

    @Slot(str, str, result=str)
    def mediaUrl(self, sub, name):
        p = MEDIA_DIR / sub / Path(name).name if name else None
        if not (p and p.is_file()):
            return ""
        if sub == "logos":
            p = trimmed_logo(p)
        return QUrl.fromLocalFile(str(p)).toString()


    @Property(bool, constant=True)
    def windowed(self):
        return self._args.windowed

    @Property(bool, constant=True)
    def skipIntro(self):
        return self._args.skip_intro

    @Property(str, constant=True)
    def debugKeys(self):
        return self._args.keys or ""

    @Property(str, constant=True)
    def debugPage(self):
        return self._args.page or ""


def main():
    ap = argparse.ArgumentParser(description="Tide launcher")
    ap.add_argument("--windowed", action="store_true", help="запуск в окне, а не на весь экран")
    ap.add_argument("--skip-intro", action="store_true", help="сразу на главный экран")
    ap.add_argument("--shot", help=argparse.SUPPRESS)
    ap.add_argument("--page", help=argparse.SUPPRESS)
    ap.add_argument("--keys", help=argparse.SUPPRESS)
    args, qt_args = ap.parse_known_args()

    app = QGuiApplication([sys.argv[0]] + qt_args)
    app.setApplicationName("Tide")
    app.setDesktopFileName("tide-launcher")
    # иконка приложения: своя картинка media/app-icon.* (если есть)
    for ext in (".png", ".svg", ".jpg", ".jpeg", ".webp"):
        icon_file = MEDIA_DIR / ("app-icon" + ext)
        if icon_file.is_file():
            app.setWindowIcon(QIcon(str(icon_file)))
            break
    else:
        app.setWindowIcon(QIcon(str(APP_DIR / "icons" / "tide.png")))
    if not QIcon.themeName():
        QIcon.setThemeName("breeze")
    QIcon.setFallbackThemeName("hicolor")
    fams = []
    for f in sorted((APP_DIR / "fonts").glob("*.ttf")):
        fid = QFontDatabase.addApplicationFont(str(f))
        if fid >= 0:
            fams += QFontDatabase.applicationFontFamilies(fid)
    if fams:
        font = QFont(fams[0])
        font.setHintingPreference(QFont.HintingPreference.PreferNoHinting)
        app.setFont(font)

    backend = Backend(args)
    engine = QQmlApplicationEngine()
    engine.addImageProvider("icon", IconProvider())
    engine.addImageProvider("sym", SymProvider())
    engine.rootContext().setContextProperty("backend", backend)
    engine.load(QUrl.fromLocalFile(str(APP_DIR / "Main.qml")))
    if not engine.rootObjects():
        sys.exit(1)

    if args.shot:  # debug: screenshot after N ms -> path
        path, ms = args.shot.split(":")
        QTimer.singleShot(int(ms), lambda: (engine.rootObjects()[0].grabWindow().save(path), app.quit()))
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
