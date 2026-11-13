#!/usr/bin/env python3
"""Code rules from AGENTS.md that a pattern can check, run by `mise run check-code` and `mise run test`.

The checks read Swift through a small tokenizer that blanks comments and string literals, so a rule never fires on
prose or on a string that happens to look like code. Places that broke a rule before the check existed are listed in
scripts/check-code-baseline.txt: they pass, a new place fails, and a listed place that is gone fails too until the list
is rewritten with `--update`, so the list only shrinks. Rewrite it only to drop fixed places or to follow a moved line,
never to let a new one in.

A line that is data rather than screen copy (a search keyword list, a sample transcript) carries `// strings: data,
<why>`; on a line that opens a block or a literal the mark covers the whole of it.
"""
import bisect
import os
import re
import sys
from collections import Counter

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
BASELINE = os.path.join(ROOT, "scripts", "check-code-baseline.txt")


# Comments and string text are blanked to spaces rather than cut, so an offset in `code` is the same line in the file;
# interpolated code inside a string stays code.
class Source:
    def __init__(self, path):
        self.path = path
        with open(os.path.join(ROOT, path), encoding="utf-8") as f:
            self.text = f.read()
        self.lines = self.text.split("\n")
        self.strings = []  # (offset, literal text with interpolations removed)
        self.comments = []  # (offset, comment text)
        self.code = self._scan()
        self.code_lines = self.code.split("\n")
        self.line_starts = [0] + [i + 1 for i, c in enumerate(self.text) if c == "\n"]

    def line_of(self, offset):
        return bisect.bisect_right(self.line_starts, offset)

    def _scan(self):
        t, n = self.text, len(self.text)
        out = list(t)
        i = 0
        # Each open string: (closing delimiter, raw hashes, parens open in the current interpolation, text so far, start)
        stack = []

        def blank(a, b):
            for k in range(a, b):
                if out[k] != "\n":
                    out[k] = " "

        def code_step(i):
            c = t[i]
            if t.startswith("//", i):
                j = t.find("\n", i)
                j = n if j < 0 else j
                self.comments.append((i, t[i:j]))
                blank(i, j)
                return j
            if t.startswith("/*", i):
                depth, j = 1, i + 2
                while j < n and depth:
                    if t.startswith("/*", j):
                        depth, j = depth + 1, j + 2
                    elif t.startswith("*/", j):
                        depth, j = depth - 1, j + 2
                    else:
                        j += 1
                self.comments.append((i, t[i:j]))
                blank(i, j)
                return j
            m = re.match(r'(#*)("""|")', t[i:i + 8])
            if m and (m.group(1) or c == '"'):
                hashes, quote = m.group(1), m.group(2)
                stack.append([quote + hashes, hashes, 0, [], i])
                return i + len(m.group(0))
            if c == "/" and self._regex_start(t, i):
                j = i + 1
                while j < n and t[j] != "\n":
                    if t[j] == "\\":
                        j += 2
                        continue
                    if t[j] == "/":
                        break
                    j += 1
                blank(i, min(j + 1, n))
                return j + 1
            return i + 1

        while i < n:
            if not stack or stack[-1][2] > 0:
                if stack:
                    if t[i] == "(":
                        stack[-1][2] += 1
                    elif t[i] == ")":
                        stack[-1][2] -= 1
                        if stack[-1][2] == 0:
                            out[i] = " "
                            i += 1
                            continue
                i = code_step(i)
                continue
            close, hashes, _, buf, start = stack[-1]
            if t.startswith(close, i):
                blank(i, i + len(close))
                self.strings.append((start, "".join(buf)))
                stack.pop()
                i += len(close)
                continue
            if t.startswith("\\" + hashes + "(", i):
                blank(i, i + len(hashes) + 2)
                stack[-1][2] = 1
                i += len(hashes) + 2
                continue
            if t.startswith("\\" + hashes, i) and i + len(hashes) + 1 < n:
                k = i + len(hashes) + 1
                buf.append(t[i:k + 1])
                blank(i, k + 1)
                i = k + 1
                continue
            buf.append(t[i])
            if t[i] != "\n":
                out[i] = " "
            i += 1
        return "".join(out)

    @staticmethod
    def _regex_start(t, i):
        # Swift reads a bare `/` as a regex literal only where an operand begins and never before a space; this
        # codebase writes division with spaces around it.
        if i + 1 >= len(t) or t[i + 1] in " \t\n/*=":
            return False
        k = i - 1
        while k >= 0 and t[k] in " \t":
            k -= 1
        return k < 0 or t[k] in "(,:=[{!&|?\n" or t[max(0, k - 5):k + 1].endswith("return")


def block_end(code, open_at):
    pairs = {"{": "}", "[": "]", "(": ")"}
    want, depth = [pairs[code[open_at]]], 1
    i = open_at + 1
    while i < len(code) and want:
        c = code[i]
        if c in pairs:
            want.append(pairs[c])
        elif want and c == want[-1]:
            want.pop()
        i += 1
    return i


def swift_files(*dirs):
    found = []
    for d in dirs:
        for base, subdirs, files in os.walk(os.path.join(ROOT, d)):
            subdirs[:] = sorted(s for s in subdirs if not s.startswith("."))
            for f in sorted(files):
                if f.endswith(".swift"):
                    found.append(os.path.relpath(os.path.join(base, f), ROOT))
    return found


_sources = {}


def load(path):
    if path not in _sources:
        _sources[path] = Source(path)
    return _sources[path]


class Hit:
    def __init__(self, check, path, line, key):
        self.check, self.path, self.line, self.key = check, path, line, " ".join(key.split())

    def entry(self):
        return "\t".join((self.check, self.path, self.key))


CHECKS = []  # (name, what to do instead, function)


def check(name, advice):
    def wrap(fn):
        CHECKS.append((name, advice, fn))
        return fn
    return wrap


# Views ----------------------------------------------------------------------------------------------------------------

VIEW_DECL = re.compile(r"\b(struct|extension)\s+([A-Za-z_][\w.]*)\s*(<[^>{]*>)?\s*(:\s*([^{]*))?\{")


def view_blocks():
    # A view's helpers often sit in an extension in another file, so names are gathered from every file first.
    files = [load(p) for p in swift_files("app/features")]
    names = set()
    for s in files:
        for m in VIEW_DECL.finditer(s.code):
            if m.group(1) == "struct" and m.group(5) and re.search(r"\b(View|ViewModifier)\b", m.group(5)):
                names.add(m.group(2))
    blocks = []
    for s in files:
        for m in VIEW_DECL.finditer(s.code):
            conforms = m.group(5) and re.search(r"\b(View|ViewModifier)\b", m.group(5))
            if m.group(2) in names or (m.group(1) == "extension" and conforms):
                blocks.append((s, m.end() - 1, block_end(s.code, m.end() - 1)))
    return blocks


@check("view-workspace-call",
       "a view reads its model; put the call behind a model property or method (AGENTS.md \"화면: 모델과 뷰\")")
def view_workspace_calls():
    hits = []
    for s, a, b in view_blocks():
        for m in re.finditer(r"\bworkspace\s*\.\s*(\w+)\s*\(", s.code[a:b]):
            hits.append(Hit("view-workspace-call", s.path, s.line_of(a + m.start()), "workspace." + m.group(1) + "("))
    return hits


VIEW_MEMBER = re.compile(r"\b(?:var\s+(\w+)\s*:\s*some\s+View|func\s+(\w+)\b[^{;]*?->\s*some\s+View)\s*\{")
BODY_LOGIC = re.compile(
    r"\.(?P<call>filter|reduce|sorted|count\s*\(\s*where|min\s*\(\s*by|max\s*\(\s*by|partition)\b"
    r"|\b(?P<group>Dictionary\s*\(\s*grouping)\b")


@check("view-body-logic",
       "group, filter, sort and count in the model (or FolioDomain for a data rule) and give the view the result")
def view_body_logic():
    hits = []
    seen = set()
    for s, a, b in view_blocks():
        for m in VIEW_MEMBER.finditer(s.code, a, b):
            start = m.end() - 1
            if (s.path, start) in seen:
                continue
            seen.add((s.path, start))
            end = block_end(s.code, start)
            member = m.group(1) or m.group(2)
            for h in BODY_LOGIC.finditer(s.code, start, end):
                what = "." + h.group("call") if h.group("call") else h.group("group")
                hits.append(Hit("view-body-logic", s.path, s.line_of(h.start()), member + ": " + re.sub(r"\s+", "", what)))
    return hits


# Strings --------------------------------------------------------------------------------------------------------------

HANGUL = re.compile(r"[가-힣ㄱ-ㆎ]")
TEXT_INIT = re.compile(
    r"\b(Text|Button|Label|Toggle|Picker|Section|Menu|TextField|SecureField|LabeledContent|GroupBox|DisclosureGroup|"
    r"Link|NavigationLink|ContentUnavailableView)\s*\(\s*$"
    r"|\.(help|navigationTitle|accessibilityLabel|accessibilityHint|alert|confirmationDialog|badge|searchable)\s*\(\s*$"
    r"|\bString\s*\(\s*localized\s*:\s*$|\bLocalizedStringKey\s*\(\s*$")


def exempt_ranges(s):
    """Offsets a `// strings: data` mark, `#if DEBUG` or `#Preview` takes out of the string check."""
    ranges = []
    for off, text in s.comments:
        if re.match(r"//\s*strings: data\b", text):
            line = s.line_of(off)
            a = s.line_starts[line - 1]
            ranges.append((a, off))
            code_line = s.code[a:off].rstrip()
            if code_line and code_line[-1] in "{[(":
                ranges.append((a, block_end(s.code, a + len(code_line) - 1)))
    return ranges + debug_ranges(s)


DEBUG_FILE = re.compile(r"(^|/)debug-[^/]*\.swift$|-snapshots\.swift$")


def debug_ranges(s):
    """Offsets of `#if DEBUG` blocks and `#Preview`s: code the shipped app never runs."""
    ranges = []
    depth_debug, open_at = [], None
    for m in re.finditer(r"^[ \t]*#(if|elseif|else|endif)\b(.*)$", s.code, re.M):
        kind, rest = m.group(1), m.group(2)
        if kind == "if":
            depth_debug.append(rest.strip() == "DEBUG")
            if depth_debug[-1] and open_at is None:
                open_at = m.start()
        elif kind in ("else", "elseif") and depth_debug:
            if depth_debug[-1] and open_at is not None and depth_debug.count(True) == 1:
                ranges.append((open_at, m.start()))
                open_at = None
            depth_debug[-1] = False
        elif kind == "endif" and depth_debug:
            was = depth_debug.pop()
            if was and open_at is not None and True not in depth_debug:
                ranges.append((open_at, m.end()))
                open_at = None
    for m in re.finditer(r"#Preview\b", s.code):
        j = m.end()
        while j < len(s.code) and s.code[j] in " \t":
            j += 1
        if j < len(s.code) and s.code[j] == "(":
            j = block_end(s.code, j)
        while j < len(s.code) and s.code[j] in " \t\n":
            j += 1
        if j < len(s.code) and s.code[j] == "{":
            ranges.append((m.start(), block_end(s.code, j)))
    return ranges


@check("ui-string",
       "put screen copy in app/resources/Localizable.xcstrings as a key; mark data strings `// strings: data, <why>`")
def ui_strings():
    hits = []
    for path in swift_files("app"):
        if DEBUG_FILE.search(path):
            continue
        s = load(path)
        exempt = exempt_ranges(s)
        for off, text in s.strings:
            if any(a <= off < b for a, b in exempt):
                continue
            before = s.code[max(0, off - 80):off]
            if HANGUL.search(text) or (TEXT_INIT.search(before) and re.search(r"[A-Za-z]{2}", text)):
                hits.append(Hit("ui-string", path, s.line_of(off), '"' + text + '"'))
    return hits


LAYOUT_NAMES = ("Syllabus", "Lectures", "Exercises", "Textbooks", "Inherited", "Assignments", "Exams", "Study", "Notes",
                "Ink", "Recordings", "Archive", ".folio", "_Admin", "_Credited", "course.json", "transcript.json",
                "catalog.json", "settings.json", "moves.jsonl")


@check("layout-name",
       "folder and file names come from FolioDomain's standard-layout.swift (Term, SemesterFolder, CourseFolder)")
def layout_names():
    hits = []
    for path in swift_files("app", "packages/folio-core/sources", "packages/folio-markdown/sources",
                            "packages/folio-ai/sources"):
        if path.endswith("/standard-layout.swift") or "/folio-fixtures/" in path:
            continue
        s = load(path)
        for off, text in s.strings:
            if text in LAYOUT_NAMES:
                hits.append(Hit("layout-name", path, s.line_of(off), '"' + text + '"'))
    return hits


# Layers ---------------------------------------------------------------------------------------------------------------

DISK = re.compile(r"\b(FileManager|NSFileCoordinator|FileHandle|NSFileVersion)\b"
                  r"|\b(Data|String|NSData|NSString)\s*\(\s*contentsOf(File)?\s*:|\batomically\s*:|\.write\s*\(\s*to\s*:")


@check("layer",
       "keep each layer to its job (AGENTS.md \"레이어\"): packages draw no UI, FolioDomain and FolioMarkdown don't touch "
       "the disk, screens reach files through FolioActions or their model's Workspace")
def layers():
    hits = []
    for path in swift_files("packages"):
        if "/sources/" not in path:
            continue
        s = load(path)
        for m in re.finditer(r"^\s*import\s+(SwiftUI)\b", s.code, re.M):
            hits.append(Hit("layer", path, s.line_of(m.start(1)), "import " + m.group(1)))
    for path in swift_files("packages/folio-core/sources/folio-domain", "packages/folio-markdown/sources"):
        s = load(path)
        for m in DISK.finditer(s.code):
            hits.append(Hit("layer", path, s.line_of(m.start()), "disk: " + re.sub(r"\s+", "", m.group(0))))
    # Debug-only code (snapshot walks writing their pictures) is not a screen the shipped app runs.
    for path in swift_files("app/features"):
        if DEBUG_FILE.search(path):
            continue
        s = load(path)
        debug = debug_ranges(s)
        for m in re.finditer(r"\bFileManager\b", s.code):
            if any(a <= m.start() < b for a, b in debug):
                continue
            hits.append(Hit("layer", path, s.line_of(m.start()), "FileManager in a screen"))
    return hits


# Comments -------------------------------------------------------------------------------------------------------------

FILLER = {"a", "an", "the", "of", "for", "to", "in", "on", "is", "are", "this", "that", "its", "it", "and", "or", "with",
          "by", "from", "returns", "return", "gets", "get", "sets", "set", "current", "given", "value", "property",
          "function", "method", "initializer", "init", "creates", "create", "type", "struct", "class", "enum", "view",
          "model", "var", "let", "func"}
DECL = re.compile(r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:(?:public|private|fileprivate|internal|static|final|override|"
                  r"nonisolated|mutating|lazy|weak|unowned|required|convenience|indirect)\s+)*"
                  r"(?:var|let|func|struct|class|enum|case|protocol|typealias|actor|init|subscript)\b\s*([^\n]*)")


def words(text):
    text = re.sub(r"([a-z0-9])([A-Z])", r"\1 \2", text)
    found = set()
    for w in re.findall(r"[A-Za-z]+", text.lower()):
        found.add(w)
        if w.endswith("s") and len(w) > 3:
            found.add(w[:-1])
    return found


@check("restating-comment",
       "a comment says why the code is this way; drop one that only names what the declaration under it already says")
def restating_comments():
    hits = []
    for path in swift_files("app", "packages/folio-core/sources", "packages/folio-markdown/sources",
                            "packages/folio-ai/sources"):
        if "/generated/" in path or "/folio-actions/" in path:
            continue  # an @Action field's `///` is its CLI help
        s = load(path)
        lines = s.lines
        i = 0
        while i < len(lines):
            m = re.match(r"^\s*///?\s?(.*)$", lines[i])
            if not m or s.code_lines[i].strip():
                i += 1
                continue
            start, text = i, [m.group(1)]
            while i + 1 < len(lines) and re.match(r"^\s*///?", lines[i + 1]) and not s.code_lines[i + 1].strip():
                i += 1
                text.append(re.sub(r"^\s*///?\s?", "", lines[i]))
            i += 1
            if i >= len(lines) or len(text) > 1:
                continue
            decl = DECL.match(lines[i])
            comment = " ".join(text).strip()
            said = words(comment) - FILLER
            # A code span or a symbol says something the name can't, such as the syntax a case stands for.
            if not decl or not said or HANGUL.search(comment) or re.search(r"[`\\[\]<>/=+*#@$%^&|~]", comment):
                continue
            if re.match(r"(MARK|TODO|FIXME|swiftlint|design:|strings:)", comment):
                continue
            named = words(decl.group(1)[:120])
            if said <= named:
                hits.append(Hit("restating-comment", path, start + 1, comment))
    return hits


# Baseline -------------------------------------------------------------------------------------------------------------

def read_baseline():
    if not os.path.exists(BASELINE):
        return Counter()
    with open(BASELINE, encoding="utf-8") as f:
        return Counter(l.rstrip("\n") for l in f if l.strip() and not l.startswith("#"))


def write_baseline(hits):
    header = ("# Places that broke a rule of scripts/check-code.py before the check existed. Fix one and delete its "
              "line.\n# check\tfile\twhat\n")
    with open(BASELINE, "w", encoding="utf-8") as f:
        f.write(header)
        for e in sorted(h.entry() for h in hits):
            f.write(e + "\n")


def main():
    update = "--update" in sys.argv[1:]
    hits, advice = [], {}
    for name, why, fn in CHECKS:
        advice[name] = why
        hits.extend(fn())
    if update:
        write_baseline(hits)
        print("wrote %d entries to %s" % (len(hits), os.path.relpath(BASELINE, ROOT)))
        return 0
    known = read_baseline()
    now = Counter(h.entry() for h in hits)
    new = now - known
    gone = known - now
    failed = False
    if new:
        failed = True
        budget = Counter(new)
        by_check = {}
        for h in hits:
            if budget[h.entry()] > 0:
                budget[h.entry()] -= 1
                by_check.setdefault(h.check, []).append(h)
        for name, items in by_check.items():
            print("%s: %s" % (name, advice[name]), file=sys.stderr)
            for h in sorted(items, key=lambda h: (h.path, h.line)):
                print("  %s:%d: %s" % (h.path, h.line, h.key), file=sys.stderr)
    if gone:
        failed = True
        print("Fixed or moved since scripts/check-code-baseline.txt was written; run `scripts/check-code.py --update` "
              "to drop them (and check it adds nothing):", file=sys.stderr)
        for e in sorted(gone.elements()):
            print("  " + e.replace("\t", "  "), file=sys.stderr)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
