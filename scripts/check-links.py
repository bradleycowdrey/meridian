#!/usr/bin/env python3
"""Check every link Meridian publishes: in the repo's docs, store metadata and app source, and on
the live pages at bradcowdrey.com. Run by .github/workflows/links.yml.

  scripts/check-links.py OUT_DIR       collect, fetch the live pages, check everything; write
                                       OUT_DIR/report.txt and OUT_DIR/urls.txt. Exits 1 if any
                                       link is broken or any relative link points at a missing file.
  scripts/check-links.py --extract-only   just list what the repo holds (no network).

Status words in report.txt:
  OK       2xx, directly or after redirects
  BROKEN   anything else (4xx, 5xx, DNS failure, timeout), except BLOCKED below
  BLOCKED  401/403/429/999 from a third-party site, which usually means it refuses robots rather than
           that the page is gone; listed for a person to look at, not counted as a failure.
           Our own hosts (bradcowdrey.com, GitHub, Apple) never get this allowance.
  CITATION a research source cited only in docs/working-hours.md, on a third-party site, that
           did not answer 2xx (link rot, a slow or dead foreign site); listed for a person to
           look at, not counted as a failure, so the run fails only on Meridian's own links.
  SKIPPED  a source-code prefix that is only a URL once the app adds to it
A live page that yields no <a> links (its JavaScript didn't render) is listed as MISSING and fails.
Uses python3 and curl, and Google Chrome (headless) when present to read the live pages as
rendered: bradcowdrey.com is a single-page app whose links are built by JavaScript.
"""
import html
import os
import re
import shutil
import subprocess
import sys
import threading
import time
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor
from html.parser import HTMLParser
from urllib.parse import quote, unquote, urljoin, urlsplit

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIVE_PAGES = [
    "https://bradcowdrey.com/",
    "https://bradcowdrey.com/meridian",
    "https://bradcowdrey.com/meridian-app.html",
    "https://bradcowdrey.com/legal",
]
STRICT_HOSTS = ("bradcowdrey.com", "github.com", "githubusercontent.com", "apple.com")
CITATION_FILES = ("docs/working-hours.md",)  # research sources: reported, never fatal
UA = "Mozilla/5.0 (compatible; MeridianLinkCheck/1.0; +https://github.com/bradleycowdrey/meridian)"

URL_RE = re.compile(r"https?://[^\s<>\"'`|\\]+")
LITERAL_RE = re.compile(r'"(https?://[^"\\]*)"(\s*\+)?')  # a string literal in Swift/Kotlin
MD_LINK_RE = re.compile(r"\]\(\s*<?([^)\s>]+)")
ATTR_RE = re.compile(r"""(?:src|href)\s*=\s*["']([^"']+)["']""", re.I)


def repo_files():
    try:
        out = subprocess.run(["git", "ls-files"], cwd=ROOT, capture_output=True, text=True, check=True).stdout
        files = out.splitlines()
    except Exception:
        files = [os.path.relpath(os.path.join(d, f), ROOT) for d, _, fs in os.walk(ROOT) if "/.git" not in d for f in fs]
    return sorted(files)


def wanted(path):
    if path in ("README.md", "CHANGELOG.md", "TERMS.md"):
        return "text"
    if path.startswith("docs/") and path.endswith((".md", ".html")):
        return "text"
    if path.startswith("ios/fastlane/metadata/") and path.endswith(".txt"):
        return "text"
    if path.startswith("android/") and path.endswith("/res/values/strings.xml"):
        return "text"
    if path.endswith((".swift", ".kt")):
        return "source"
    return None


def trim(url):
    """Drop punctuation that ends a sentence or a Markdown link rather than the URL."""
    while url:
        if url[-1] in ".,;:!?*_'\"]}":
            url = url[:-1]
        elif url[-1] == ")" and url.count(")") > url.count("("):
            url = url[:-1]
        else:
            break
    return url


def collect_repo(found, skipped, missing):
    for path in repo_files():
        kind = wanted(path)
        if not kind:
            continue
        try:
            with open(os.path.join(ROOT, path), encoding="utf-8", errors="replace") as f:
                lines = f.read().splitlines()
        except OSError:
            continue
        unescape = path.endswith((".html", ".xml"))
        for n, line in enumerate(lines, 1):
            where = f"{path}:{n}"
            if kind == "source":
                for m in LITERAL_RE.finditer(line):
                    url = m.group(1)
                    # "https://host/path/" + name, "…?titles=" + …: only a prefix of a real URL.
                    if m.group(2) or (url.endswith(("/", ":", "=", "?", "&")) and urlsplit(url).path not in ("", "/")):
                        skipped[url].add(where)
                    else:
                        found[url].add(where)
                continue
            for raw in URL_RE.findall(line):
                url = trim(html.unescape(raw) if unescape else raw)
                if urlsplit(url).netloc:
                    found[url].add(where)
            # Relative links in README.md and docs/ must point at files that exist.
            if path == "README.md" or path.startswith("docs/"):
                for target in MD_LINK_RE.findall(line) + ATTR_RE.findall(line):
                    t = html.unescape(target)
                    if re.match(r"^(?:[a-z][a-z0-9+.-]*:|//|#)", t, re.I):
                        continue
                    rel = unquote(t.split("#")[0].split("?")[0])
                    if not rel:
                        continue
                    base = ROOT if rel.startswith("/") else os.path.dirname(os.path.join(ROOT, path))
                    if not os.path.exists(os.path.normpath(os.path.join(base, rel.lstrip("/")))):
                        missing.append(f"{where} -> {t}")


class LinkParser(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.links = []
        self.anchors = 0

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag == "a":
            self.anchors += 1
        if tag in ("a", "area", "link") and a.get("href"):
            if tag == "link" and set((a.get("rel") or "").lower().split()) & {"preconnect", "dns-prefetch"}:
                return
            self.links.append(a["href"])
        if tag in ("img", "script", "iframe", "source", "video", "audio", "embed") and a.get("src"):
            self.links.append(a["src"])
        if tag == "meta" and (a.get("content") or "").startswith(("http://", "https://")):
            self.links.append(a["content"])


def curl(url, method):
    cmd = ["curl", "-sSL", "--max-time", "20", "--max-redirs", "10", "-A", UA, "-o", "/dev/null",
           "-w", "%{http_code} %{url_effective}"]
    if method == "HEAD":
        cmd.append("-I")
    p = subprocess.run(cmd + [url], capture_output=True, text=True)
    parts = (p.stdout or "000").split(" ", 1)
    code = int(parts[0]) if parts[0].isdigit() else 0
    err = p.stderr.strip().splitlines()[-1] if p.returncode and p.stderr.strip() else ""
    return code, (parts[1] if len(parts) > 1 else url), err


def is_strict(host):
    return any(host == h or host.endswith("." + h) for h in STRICT_HOSTS)


def chrome():
    for name in ("google-chrome", "google-chrome-stable", "chromium", "chromium-browser"):
        path = shutil.which(name)
        if path:
            return path
    return None


def fetch_page(url):
    """The page's HTTP status (from curl) and its DOM: rendered by headless Chrome when it's
    installed, else the HTML as served. Returns (code, body, how)."""
    p = subprocess.run(["curl", "-sSL", "--max-time", "30", "-A", UA, "-w", "\n%{http_code}", url],
                       capture_output=True, text=True, errors="replace")
    body, _, code = p.stdout.rpartition("\n")
    code = int(code) if code.isdigit() else 0
    browser = chrome()
    if browser:
        try:
            r = subprocess.run([browser, "--headless=new", "--disable-gpu", "--no-sandbox", "--no-first-run",
                                "--virtual-time-budget=15000", "--dump-dom", url],
                               capture_output=True, text=True, errors="replace", timeout=90)
            if r.returncode == 0 and r.stdout.strip():
                return code, r.stdout, "rendered by Chrome"
        except (OSError, subprocess.TimeoutExpired):
            pass
    return code, body, "as served (no Chrome)"


host_locks, host_locks_guard = {}, threading.Lock()


def host_lock(host):
    with host_locks_guard:  # at most two requests at a time to any one site
        return host_locks.setdefault(host, threading.BoundedSemaphore(2))


def check(url):
    target = quote(url.split("#")[0], safe=":/?[]@!$&'()*+,;=%~")  # curl wants non-ASCII escaped
    with host_lock(urlsplit(target).netloc.lower()):
        code, final, err = curl(target, "HEAD")
        if not 200 <= code < 300:  # many servers refuse or mishandle HEAD; ask properly
            code, final, err = curl(target, "GET")
        if code == 429:
            time.sleep(30)
            code, final, err = curl(target, "GET")
    host = urlsplit(target).netloc.lower().split(":")[0]
    strict = is_strict(host)
    if 200 <= code < 300:
        status = "OK"
    elif code in (401, 403, 429, 999) and not strict:  # 429 after a retry: rate-limits robots (Instagram)
        status = "BLOCKED"
    else:
        status = "BROKEN"
    detail = str(code) if code else "000"
    if err:
        detail += f" ({err})"
    if final and final.split("#")[0] != target:
        detail += f" -> {final}"
    return status, detail


def main():
    extract_only = "--extract-only" in sys.argv
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    out = args[0] if args else None
    found, skipped, missing = defaultdict(set), defaultdict(set), []
    collect_repo(found, skipped, missing)

    if extract_only:
        for url in sorted(found):
            print(f"{url}\t{', '.join(sorted(found[url]))}")
        for url in sorted(skipped):
            print(f"SKIPPED {url}\t{', '.join(sorted(skipped[url]))}")
        for m in missing:
            print(f"MISSING {m}")
        print(f"\n{len(found)} URLs, {len(skipped)} source prefixes skipped, {len(missing)} missing relative links",
              file=sys.stderr)
        return 0

    page_notes, empty_pages = [], []
    for page in LIVE_PAGES:
        found[page].add("live page")
        code, body, how = fetch_page(page)
        parser = LinkParser()
        try:
            parser.feed(body)
        except Exception as e:
            page_notes.append(f"{page}: could not parse ({e})")
        links = set()
        for href in parser.links:
            href = href.strip()
            if not href or href.startswith(("#", "mailto:", "tel:", "javascript:", "data:", "sms:")):
                continue
            url = urljoin(page, href)
            if url.startswith(("http://", "https://")):
                links.add(url)
                found[url].add(f"page {page}")
        page_notes.append(f"{page}: HTTP {code}, {len(links)} links found ({parser.anchors} <a> tags, {how})")
        if parser.anchors == 0:
            empty_pages.append(f"{page}: no <a> links ({how}), so its links went unchecked")

    urls = sorted(found)
    with ThreadPoolExecutor(max_workers=12) as pool:
        results = dict(zip(urls, pool.map(check, urls)))

    def citation_only(url):
        """Cited only in CITATION_FILES, on a third-party site."""
        host = urlsplit(url).netloc.lower().split(":")[0]
        return not is_strict(host) and all(w.startswith(tuple(f + ":" for f in CITATION_FILES)) for w in found[url])

    for url, (status, detail) in list(results.items()):
        if status == "BROKEN" and citation_only(url):
            results[url] = ("CITATION", detail)

    counts = defaultdict(int)
    for status, _ in results.values():
        counts[status] += 1
    order = {"BROKEN": 0, "BLOCKED": 1, "CITATION": 2, "OK": 3}
    lines = [
        f"Link check for {os.environ.get('GITHUB_SHA', 'local')} at {time.strftime('%Y-%m-%d %H:%M UTC', time.gmtime())}",
        f"{len(urls)} URLs: {counts['OK']} OK, {counts['BROKEN']} BROKEN, {counts['BLOCKED']} BLOCKED, "
        f"{counts['CITATION']} CITATION; {len(missing)} missing relative links; {len(empty_pages)} unrendered pages; "
        f"{len(skipped)} source prefixes skipped",
        "",
        "== Live pages",
        *page_notes,
        *[f"MISSING {e}" for e in empty_pages],
        "",
        "== Relative links in README.md and docs/",
        *([f"MISSING {m}" for m in missing] or ["all present"]),
        "",
        "== URLs",
    ]
    for url in sorted(urls, key=lambda u: (order[results[u][0]], u)):
        status, detail = results[url]
        lines.append(f"{status:8} {detail}  {url}")
        lines.append(f"        found in: {', '.join(sorted(found[url]))}")
    lines += ["", "== Skipped (source prefixes the app completes at run time)"]
    for url in sorted(skipped):
        lines.append(f"SKIPPED {url}  ({', '.join(sorted(skipped[url]))})")
    report = "\n".join(lines) + "\n"

    if out:
        os.makedirs(out, exist_ok=True)
        with open(os.path.join(out, "report.txt"), "w") as f:
            f.write(report)
        with open(os.path.join(out, "urls.txt"), "w") as f:
            f.write("".join(f"{u}\n" for u in urls))
    print(report)
    return 1 if counts["BROKEN"] or missing or empty_pages else 0


if __name__ == "__main__":
    sys.exit(main())
