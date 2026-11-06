#!/usr/bin/env python3
"""把一句名字解析成目标：应用 / 文件 / 文件夹。

单独查询:  python3 resolve_target.py "豆包"        ->  APP\t/path
列表模式:  python3 resolve_target.py --list "未"   ->  每行  TYPE\tPATH\t显示名
"""
import json
import os
import sys
import time

HOME = os.path.expanduser("~")
CACHE = os.path.join(HOME, "Library", "Caches", "quickopen-apps.json")
CACHE_VER = 5

APP_ROOTS = [
    "/Applications",
    "/Applications/Utilities",
    os.path.join(HOME, "Applications"),
    "/System/Applications",
    "/System/Applications/Utilities",
    "/System/Library/CoreServices",
]

ALIAS = {
    # —— 图形与设计 ——
    "ps": "photoshop", "photoshop": "photoshop",
    "ai": "illustrator", "illustrator": "illustrator",
    "id": "indesign", "indesign": "indesign",
    "pr": "premiere", "ae": "after effects", "lr": "lightroom",
    "acrobat": "acrobat", "pdf": "acrobat",
    "sketch": "sketch", "cursor": "cursor", "pureref": "pureref",
    "islide": "islide", "snipaste": "snipaste", "截图": "snipaste",
    "工具截图": "snipaste",
    # —— 办公 ——
    "excel": "microsoft excel", "表格": "microsoft excel",
    "word": "microsoft word", "文档": "microsoft word",
    "ppt": "microsoft powerpoint", "powerpoint": "microsoft powerpoint",
    "幻灯片": "microsoft powerpoint",
    "onenote": "microsoft onenote", "笔记": "microsoft onenote",
    "outlook": "microsoft outlook",
    # —— 浏览器 ——
    "谷歌": "google chrome", "谷歌浏览器": "google chrome",
    "chrome": "google chrome", "浏览器": "safari",
    "苹果浏览器": "safari", "safari": "safari",
    "火狐": "firefox", "edge": "microsoft edge",
    # —— 聊天/社交 ——
    "微信": "wechat", "wechat": "wechat", "qq": "qq",
    "豆包": "doubao", "抖音": "douyin", "小红书": "xiaohongshu",
    "知音楼": "知音楼", "飞书": "feishu", "钉钉": "dingtalk",
    "企业微信": "wecom", "腾讯会议": "tencentmeeting",
    # —— 影音 ——
    "网易云": "neteasemusic", "网易云音乐": "neteasemusic",
    "酷狗": "酷狗音乐", "酷狗音乐": "酷狗音乐",
    "qq音乐": "qqmusic", "音乐": "music",
    "喜马拉雅": "喜马拉雅", "剪映": "videofusion",
    "剪映专业版": "videofusion", "视频剪辑": "videofusion",
    "爱奇艺": "iqiyi", "优酷": "youku", "腾讯视频": "tencentvideo",
    # —— 系统自带 ——
    "访达": "finder", "文件管理器": "finder", "finder": "finder",
    "终端": "terminal", "命令行": "terminal", "terminal": "terminal",
    "计算器": "calculator", "日历": "calendar", "邮件": "mail",
    "地图": "maps", "备忘录": "notes", "提醒事项": "reminders",
    "提醒": "reminders", "预览": "preview", "看图": "preview",
    "照片": "photos", "音乐播放器": "music",
    "系统设置": "system settings", "系统偏好设置": "system settings",
    "设置": "system settings", "活动监视器": "activity monitor",
    "磁盘工具": "disk utility", "任务管理器": "activity monitor",
    "控制台": "console", "钥匙串": "keychain",
    "截图工具": "screenshot", "字体册": "font book",
    "便签": "sticky notepad", "贴纸": "sticky notepad",
    "sticky": "sticky notepad", "压缩": "archive utility",
    # —— 存储/工具 ——
    "百度网盘": "baidunetdisk", "网盘": "baidunetdisk",
    "向日葵": "sunlogin", "远程": "sunlogin", "todesk": "todesk",
    "代理": "clash", "clash": "clash", "翻墙": "clash",
    "harness": "deepseek harness", "deepseek": "deepseek harness",
    "未来盾": "yunshu", "yunshu": "yunshu", "tal": "yunshu",
}


def _plist(path):
    import plistlib
    import re
    try:
        with open(path, "rb") as f:
            d = plistlib.load(f)
        if isinstance(d, dict):
            return d
    except Exception:
        pass
    # 老式 .strings（UTF-16 文本，plistlib 读不了）→ 正则兜底
    try:
        raw = open(path, "rb").read()
        text = None
        for enc in ("utf-16", "utf-8", "utf-16-le"):
            try:
                text = raw.decode(enc)
                break
            except Exception:
                continue
        if not text:
            return {}
        out = {}
        for m in re.finditer(r'"([^"]+)"\s*=\s*"(.*?)"\s*;', text, re.S):
            out[m.group(1)] = m.group(2)
        return out
    except Exception:
        return {}


def _localized_names(app):
    names = set()
    res_dir = os.path.join(app, "Contents", "Resources")
    try:
        entries = os.listdir(res_dir)
    except OSError:
        return names
    for entry in entries:
        if not entry.endswith(".lproj"):
            continue
        p = os.path.join(res_dir, entry, "InfoPlist.strings")
        if not os.path.exists(p):
            continue
        d = _plist(p)
        for k in ("CFBundleDisplayName", "CFBundleName"):
            v = d.get(k)
            if isinstance(v, str) and v.strip():
                names.add(v.strip())
    return names


def _app_entry(app, stem):
    names = {stem}
    info = _plist(os.path.join(app, "Contents", "Info.plist"))
    for k in ("CFBundleName", "CFBundleDisplayName"):
        v = info.get(k)
        if isinstance(v, str) and v.strip():
            names.add(v.strip())
    names |= _localized_names(app)
    disp = stem
    for n in names:
        if any("\u4e00" <= ch <= "\u9fff" for ch in n):
            disp = n
            break
    return {"path": app, "stem": stem, "names": sorted(names), "display": disp}


def scan_apps():
    out = []
    for root in APP_ROOTS:
        if not os.path.isdir(root):
            continue
        try:
            entries = sorted(os.listdir(root))
        except OSError:
            continue
        for entry in entries:
            if entry.endswith(".app"):
                app = os.path.join(root, entry)
                if os.path.isdir(app):
                    out.append(_app_entry(app, entry[:-4]))
    # /Applications/<某目录>/<App>.app 一层
    for sub in ("/Applications",):
        if not os.path.isdir(sub):
            continue
        try:
            subs = sorted(os.listdir(sub))
        except OSError:
            continue
        for d in subs:
            dp = os.path.join(sub, d)
            if not os.path.isdir(dp) or d.endswith(".app"):
                continue
            try:
                inner = sorted(os.listdir(dp))
            except OSError:
                continue
            for entry in inner:
                if entry.endswith(".app"):
                    out.append(_app_entry(os.path.join(dp, entry), entry[:-4]))
    seen, uniq = set(), []
    for a in out:
        if a["path"] in seen:
            continue
        seen.add(a["path"])
        uniq.append(a)
    return uniq


PY_BIN = os.path.join(os.path.dirname(os.path.abspath(__file__)), "pinyin")


def attach_pinyin(apps):
    """给每个应用的每个名字补上拼音与首字母"""
    import subprocess
    names = []
    for a in apps:
        for n in a["names"]:
            names.append(n)
    if not names:
        return apps
    try:
        r = subprocess.run([PY_BIN], input="\n".join(names).encode("utf-8"),
                           capture_output=True, timeout=20)
        lines = r.stdout.decode("utf-8", "ignore").split("\n")
    except Exception:
        return apps
    table = {}
    for line in lines:
        parts = line.split("\t")
        if len(parts) == 3:
            table[parts[0]] = (parts[1], parts[2])
    for a in apps:
        py, ini = set(), set()
        for n in a["names"]:
            t = table.get(n)
            if t:
                py.add(t[0]); ini.add(t[1])
        a["py"] = sorted(x for x in py if x)
        a["ini"] = sorted(x for x in ini if x)
    return apps


def load_apps():
    try:
        stamp = os.stat("/Applications").st_mtime
    except OSError:
        stamp = 0
    try:
        with open(CACHE, "r", encoding="utf-8") as f:
            data = json.load(f)
        if data.get("ver") == CACHE_VER and data.get("stamp") == stamp and time.time() - data.get("ts", 0) < 86400:
            apps = data["apps"]
            if apps and "py" not in apps[0]:
                apps = attach_pinyin(apps)
            return apps
    except Exception:
        pass
    apps = attach_pinyin(scan_apps())
    try:
        os.makedirs(os.path.dirname(CACHE), exist_ok=True)
        with open(CACHE, "w", encoding="utf-8") as f:
            json.dump({"ver": CACHE_VER, "stamp": stamp, "ts": time.time(), "apps": apps}, f, ensure_ascii=False)
    except Exception:
        pass
    return apps


def score(name, q):
    n, k = name.lower(), q.lower()
    if n == k:
        return 100
    if k and n.startswith(k):
        return 82
    if k and k in n:
        return 64
    # 字符按序出现（中文逐字）
    i = 0
    for ch in n:
        if i < len(k) and ch == k[i]:
            i += 1
    if i == len(k) and len(k) >= 2:
        return 40
    return 0


def app_hits(q):
    import difflib
    hits = []
    apps = load_apps()
    key = q.lower()
    alias = ALIAS.get(key) or ALIAS.get(q)
    ascii_q = all(ord(c) < 128 for c in q)
    for a in apps:
        best = 0
        for n in a["names"]:
            best = max(best, score(n, q))
        if ascii_q and len(q) >= 2:
            for pyn in a.get("py", []):
                if pyn == key:
                    best = max(best, 98)
                elif pyn.startswith(key):
                    best = max(best, 86)
                elif key in pyn:
                    best = max(best, 70)
            for ini in a.get("ini", []):
                if ini == key:
                    best = max(best, 92)
        if best == 0 and len(q) >= 2:
            cand = [n for n in a["names"]] + a.get("py", [])
            for n in cand:
                r = difflib.SequenceMatcher(None, n.lower(), key).ratio()
                if r >= 0.78:
                    best = max(best, int(40 + r * 20))
        if alias:
            sc = score(a["stem"], alias)
            if sc >= 64:
                bonus = 100 if a["stem"].lower() == alias.lower() else 95
                best = max(best, bonus)
        if best:
            name = a.get("display") or a["stem"]
            for n in a["names"]:
                if n.lower() == q.lower() or (alias and n.lower() == alias):
                    name = n
                    break
            hits.append((best, a["path"], name))
    return hits


def file_hits(q, depth=6, limit=30000):
    needle = q.lower()
    hits = []
    roots = [os.path.join(HOME, d) for d in ("Desktop", "Documents", "Downloads")]
    seen = 0

    def walk(d, left):
        nonlocal seen
        if seen > limit:
            return
        try:
            entries = list(os.scandir(d))
        except OSError:
            return
        for e in entries:
            if e.name.startswith(".") or e.name.startswith("~$"):
                continue
            seen += 1
            name = e.name
            stem = name.rsplit(".", 1)[0] if "." in name and not e.is_dir() else name
            s = max(score(name, q), score(stem, q))
            if s:
                hits.append((s, e.path, name))
            elif needle in name.lower():
                hits.append((50, e.path, name))
            if e.is_dir(follow_symlinks=False) and left > 0:
                walk(e.path, left - 1)

    for r in roots:
        if os.path.isdir(r):
            walk(r, depth)
    return hits


def spot_hits(q, limit=12):
    """用 Spotlight 兜底：索引里任何位置、任何深度都能找到"""
    import subprocess
    out = []
    try:
        r = subprocess.run(["mdfind", "-name", q], capture_output=True, timeout=4)
        lines = r.stdout.decode("utf-8", "ignore").split("\n")
    except Exception:
        return out
    for p in lines[:limit * 3]:
        p = p.strip()
        if not p or p.startswith("/System/Volumes") or "/.Trash/" in p:
            continue
        if any(x in p for x in ("/Library/", "/.git/", "/node_modules/", "/Caches/", "/Cache/")):
            continue
        if p.endswith(".app"):
            if "/Application Support/" in p or "/.Trash/" in p:
                continue
            stem = p.rstrip("/").split("/")[-1].replace(".app", "")
            names = _localized_names(p) | {stem}
            disp = stem
            for n in names:
                if any("\u4e00" <= ch <= "\u9fff" for ch in n):
                    disp = n
                    break
            out.append((58, "APP", p, disp))
        else:
            out.append((56, "FILE", p, os.path.basename(p)))
        if len(out) >= limit:
            break
    return out


def collect(q, limit=8):
    q = q.strip()
    if not q:
        return []
    hits = []
    hits += [(s + 3, "APP", p, d) for (s, p, d) in app_hits(q)]   # App 略微优先
    hits += [(s, "FILE", p, d) for (s, p, d) in file_hits(q)]

    if not hits and len(q) >= 2:
        prefix = q[:2]
        hits += [(s + 2, "APP", p, d) for (s, p, d) in app_hits(prefix)]
        hits += [(s - 5, "FILE", p, d) for (s, p, d) in file_hits(prefix)]
    if not hits and len(q) >= 1:
        prefix = q[:1]
        hits += [(s - 10, "APP", p, d) for (s, p, d) in app_hits(prefix)]
        hits += [(s - 15, "FILE", p, d) for (s, p, d) in file_hits(prefix)]

    if len(hits) < limit:
        hits += spot_hits(q)
    hits.sort(key=lambda x: -x[0])
    if hits and hits[0][0] >= 80:          # 有强匹配时丢掉弱噪声
        hits = [h for h in hits if h[0] >= 50]
    seen, out = set(), []
    for s, t, p, d in hits:
        if p in seen:
            continue
        seen.add(p)
        out.append((t, p, d))
        if len(out) >= limit:
            break
    return out


def main():
    args = sys.argv[1:]
    as_list = False
    if args and args[0] == "--list":
        as_list = True
        args = args[1:]
    q = " ".join(args).strip()
    if q.startswith("打开") and len(q) > 2:
        q = q[2:].strip()
    if not q:
        print("NONE" if not as_list else "")
        return

    res = collect(q)
    if as_list:
        for t, p, d in res:
            print(f"{t}\t{p}\t{d}")
        return
    if not res:
        print("NONE")
        return
    t, p, _ = res[0]
    print(f"{t}\t{p}")


if __name__ == "__main__":
    main()
