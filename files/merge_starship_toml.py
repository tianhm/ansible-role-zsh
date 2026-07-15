#!/usr/bin/env python3
"""Deep-merge one or more starship TOML files and print the result to stdout.

Usage: merge_starship_toml.py <in1> [<in2> ...]

Later inputs override earlier ones. Tables are merged recursively (key-by-key);
scalars and lists replace. Missing input paths are skipped silently, so callers
can pass optional overrides (user file, inline var) unconditionally.

Self-contained: reads with the stdlib ``tomllib`` (Python 3.11+) when available
and otherwise with the small pure-Python reader below, and serializes with the
matching emitter, so no third-party TOML library is required on the managed host
regardless of its Python version (works on Python 3.7+).
"""

import datetime
import re
import sys

try:
    import tomllib  # Python 3.11+
except ImportError:  # pragma: no cover - depends on host Python
    tomllib = None

_BARE_KEY = re.compile(r"^[A-Za-z0-9_-]+$")


# --------------------------------------------------------------------------- #
# TOML reader
#
# Prefer the stdlib ``tomllib`` (Python 3.11+); fall back to the minimal
# pure-Python parser below on older hosts. The fallback covers the TOML subset
# used by starship configs: comments, dotted/quoted keys, [table] and
# [[array.of.tables]] headers, basic/literal strings (single- and multi-line),
# integers, floats, booleans, datetimes, arrays, and inline tables.
# --------------------------------------------------------------------------- #
class _TomlError(Exception):
    pass


_INT_RE = re.compile(r"^[+-]?[0-9](_?[0-9])*$")
_HEX_RE = re.compile(r"^0x[0-9A-Fa-f](_?[0-9A-Fa-f])*$")
_OCT_RE = re.compile(r"^0o[0-7](_?[0-7])*$")
_BIN_RE = re.compile(r"^0b[01](_?[01])*$")
_FLOAT_RE = re.compile(
    r"^[+-]?([0-9](_?[0-9])*)(\.[0-9](_?[0-9])*)?([eE][+-]?[0-9](_?[0-9])*)?$"
)
_DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
_TIME_RE = re.compile(r"^\d{2}:\d{2}:\d{2}(\.\d+)?$")
_DATETIME_RE = re.compile(
    r"^\d{4}-\d{2}-\d{2}[Tt ]\d{2}:\d{2}:\d{2}(\.\d+)?([Zz]|[+-]\d{2}:\d{2})?$"
)
_WS = " \t"
_ESCAPES = {
    "b": "\b",
    "t": "\t",
    "n": "\n",
    "f": "\f",
    "r": "\r",
    '"': '"',
    "\\": "\\",
}


def _interpret_atom(tok):
    if _DATETIME_RE.match(tok) or _DATE_RE.match(tok) or _TIME_RE.match(tok):
        return _parse_datetime(tok)
    low = tok.lower()
    if low in ("inf", "+inf"):
        return float("inf")
    if low == "-inf":
        return float("-inf")
    if low in ("nan", "+nan", "-nan"):
        return float("nan")
    cleaned = tok.replace("_", "")
    if _HEX_RE.match(tok):
        return int(cleaned, 16)
    if _OCT_RE.match(tok):
        return int(cleaned, 8)
    if _BIN_RE.match(tok):
        return int(cleaned, 2)
    if _INT_RE.match(tok):
        return int(cleaned)
    if _FLOAT_RE.match(tok):
        return float(cleaned)
    raise _TomlError("cannot parse value: %r" % (tok,))


def _parse_datetime(tok):
    try:
        if _TIME_RE.match(tok):
            return datetime.time.fromisoformat(tok)
        if _DATE_RE.match(tok):
            return datetime.date.fromisoformat(tok)
        iso = tok.replace("t", "T").replace("z", "Z").replace("Z", "+00:00")
        iso = iso.replace(" ", "T", 1)
        return datetime.datetime.fromisoformat(iso)
    except ValueError:
        # Unparseable by this Python; keep the raw text rather than fail.
        return tok


class _Reader:
    def __init__(self, text):
        self.s = text
        self.i = 0
        self.n = len(text)

    # -- low-level scanning -------------------------------------------------- #
    def _skip_inline_ws(self):
        while self.i < self.n and self.s[self.i] in _WS:
            self.i += 1

    def _skip_comment(self):
        if self.i < self.n and self.s[self.i] == "#":
            while self.i < self.n and self.s[self.i] not in "\r\n":
                self.i += 1

    def _skip_ws_comments_newlines(self):
        while self.i < self.n:
            c = self.s[self.i]
            if c in _WS or c in "\r\n":
                self.i += 1
            elif c == "#":
                self._skip_comment()
            else:
                break

    def _cur(self):
        if self.i >= self.n:
            raise _TomlError("unexpected end of input")
        return self.s[self.i]

    # -- entry point --------------------------------------------------------- #
    def parse(self):
        root = {}
        current = root
        while True:
            self._skip_ws_comments_newlines()
            if self.i >= self.n:
                break
            if self.s[self.i] == "[":
                if self.s[self.i : self.i + 2] == "[[":
                    current = self._array_table(root)
                else:
                    current = self._table(root)
            else:
                self._keyval(current)
            self._skip_inline_ws()
            self._skip_comment()
            if self.i < self.n and self.s[self.i] not in "\r\n":
                raise _TomlError("expected newline at position %d" % self.i)
        return root

    # -- keys ---------------------------------------------------------------- #
    def _parse_key(self):
        parts = []
        while True:
            self._skip_inline_ws()
            c = self._cur()
            if c == '"':
                parts.append(self._basic_string())
            elif c == "'":
                parts.append(self._literal_string())
            else:
                parts.append(self._bare_key())
            self._skip_inline_ws()
            if self.i < self.n and self.s[self.i] == ".":
                self.i += 1
                continue
            break
        return parts

    def _bare_key(self):
        start = self.i
        while self.i < self.n and (
            self.s[self.i].isalnum() or self.s[self.i] in "_-"
        ):
            self.i += 1
        if self.i == start:
            raise _TomlError("empty key at position %d" % self.i)
        return self.s[start : self.i]

    # -- table headers ------------------------------------------------------- #
    def _table(self, root):
        self.i += 1  # '['
        key = self._parse_key()
        self._skip_inline_ws()
        if self._cur() != "]":
            raise _TomlError("expected ']' at position %d" % self.i)
        self.i += 1
        return self._descend(root, key, array=False)

    def _array_table(self, root):
        self.i += 2  # '[['
        key = self._parse_key()
        self._skip_inline_ws()
        if self.s[self.i : self.i + 2] != "]]":
            raise _TomlError("expected ']]' at position %d" % self.i)
        self.i += 2
        return self._descend(root, key, array=True)

    def _descend(self, root, parts, array):
        d = root
        for part in parts[:-1]:
            nxt = d.get(part)
            if nxt is None:
                nxt = {}
                d[part] = nxt
            elif isinstance(nxt, list):
                nxt = nxt[-1]
            d = nxt
        last = parts[-1]
        if array:
            lst = d.get(last)
            if lst is None:
                lst = []
                d[last] = lst
            tbl = {}
            lst.append(tbl)
            return tbl
        tbl = d.get(last)
        if tbl is None:
            tbl = {}
            d[last] = tbl
        return tbl

    # -- key/value ----------------------------------------------------------- #
    def _keyval(self, table):
        parts = self._parse_key()
        self._skip_inline_ws()
        if self._cur() != "=":
            raise _TomlError("expected '=' at position %d" % self.i)
        self.i += 1
        self._skip_inline_ws()
        value = self._value()
        d = table
        for part in parts[:-1]:
            nxt = d.get(part)
            if nxt is None:
                nxt = {}
                d[part] = nxt
            d = nxt
        d[parts[-1]] = value

    def _value(self):
        c = self._cur()
        if c == '"':
            if self.s[self.i : self.i + 3] == '"""':
                return self._ml_basic_string()
            return self._basic_string()
        if c == "'":
            if self.s[self.i : self.i + 3] == "'''":
                return self._ml_literal_string()
            return self._literal_string()
        if c == "[":
            return self._array()
        if c == "{":
            return self._inline_table()
        if self.s.startswith("true", self.i):
            self.i += 4
            return True
        if self.s.startswith("false", self.i):
            self.i += 5
            return False
        return self._atom()

    def _atom(self):
        start = self.i
        while self.i < self.n and self.s[self.i] not in " \t\r\n,]}#":
            self.i += 1
        tok = self.s[start : self.i]
        # Space-separated datetime (RFC 3339 with a space instead of 'T').
        if _DATE_RE.match(tok) and self.i < self.n and self.s[self.i] == " ":
            j = self.i + 1
            k = j
            while k < self.n and self.s[k] not in " \t\r\n,]}#":
                k += 1
            rest = self.s[j:k]
            if _TIME_RE.match(rest) or re.match(r"^\d{2}:\d{2}:\d{2}", rest):
                tok = tok + "T" + rest
                self.i = k
        return _interpret_atom(tok)

    # -- strings ------------------------------------------------------------- #
    def _escape(self):
        c = self.s[self.i]
        self.i += 1
        if c in _ESCAPES:
            return _ESCAPES[c]
        if c == "u":
            code = self.s[self.i : self.i + 4]
            self.i += 4
            return chr(int(code, 16))
        if c == "U":
            code = self.s[self.i : self.i + 8]
            self.i += 8
            return chr(int(code, 16))
        raise _TomlError("invalid escape '\\%s'" % c)

    def _basic_string(self):
        self.i += 1  # opening '"'
        out = []
        while self.i < self.n:
            c = self.s[self.i]
            if c == '"':
                self.i += 1
                return "".join(out)
            if c == "\\":
                self.i += 1
                out.append(self._escape())
            elif c in "\r\n":
                raise _TomlError("newline in basic string")
            else:
                out.append(c)
                self.i += 1
        raise _TomlError("unterminated string")

    def _literal_string(self):
        self.i += 1  # opening "'"
        start = self.i
        while self.i < self.n and self.s[self.i] != "'":
            if self.s[self.i] in "\r\n":
                raise _TomlError("newline in literal string")
            self.i += 1
        val = self.s[start : self.i]
        self.i += 1  # closing "'"
        return val

    def _ml_basic_string(self):
        self.i += 3
        if self.s[self.i : self.i + 2] == "\r\n":
            self.i += 2
        elif self.i < self.n and self.s[self.i] == "\n":
            self.i += 1
        out = []
        while self.i < self.n:
            if self.s[self.i : self.i + 3] == '"""':
                self.i += 3
                return "".join(out)
            c = self.s[self.i]
            if c == "\\":
                nxt = self.i + 1
                k = nxt
                while k < self.n and self.s[k] in " \t":
                    k += 1
                if k < self.n and self.s[k] in "\r\n":
                    self.i = k
                    while self.i < self.n and self.s[self.i] in " \t\r\n":
                        self.i += 1
                    continue
                self.i += 1
                out.append(self._escape())
            else:
                out.append(c)
                self.i += 1
        raise _TomlError("unterminated multi-line string")

    def _ml_literal_string(self):
        self.i += 3
        if self.s[self.i : self.i + 2] == "\r\n":
            self.i += 2
        elif self.i < self.n and self.s[self.i] == "\n":
            self.i += 1
        start = self.i
        while self.i < self.n:
            if self.s[self.i : self.i + 3] == "'''":
                val = self.s[start : self.i]
                self.i += 3
                return val
            self.i += 1
        raise _TomlError("unterminated multi-line literal string")

    # -- collections --------------------------------------------------------- #
    def _array(self):
        self.i += 1  # '['
        items = []
        while True:
            self._skip_ws_comments_newlines()
            if self._cur() == "]":
                self.i += 1
                return items
            items.append(self._value())
            self._skip_ws_comments_newlines()
            if self.i < self.n and self.s[self.i] == ",":
                self.i += 1
                continue
            if self._cur() == "]":
                self.i += 1
                return items
            raise _TomlError("expected ',' or ']' at position %d" % self.i)

    def _inline_table(self):
        self.i += 1  # '{'
        d = {}
        self._skip_inline_ws()
        if self._cur() == "}":
            self.i += 1
            return d
        while True:
            self._skip_inline_ws()
            self._keyval(d)
            self._skip_inline_ws()
            c = self._cur()
            if c == ",":
                self.i += 1
                continue
            if c == "}":
                self.i += 1
                return d
            raise _TomlError("expected ',' or '}' at position %d" % self.i)


def _toml_loads(text):
    if tomllib is not None:
        return tomllib.loads(text)
    return _Reader(text).parse()


def deep_merge(base, over):
    """Recursively merge ``over`` onto ``base`` and return a new dict."""
    result = dict(base)
    for key, value in over.items():
        if (
            key in result
            and isinstance(result[key], dict)
            and isinstance(value, dict)
        ):
            result[key] = deep_merge(result[key], value)
        else:
            result[key] = value
    return result


def _esc(text):
    out = []
    for ch in text:
        if ch == "\\":
            out.append("\\\\")
        elif ch == '"':
            out.append('\\"')
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\t":
            out.append("\\t")
        elif ch == "\r":
            out.append("\\r")
        elif ord(ch) < 0x20:
            out.append("\\u%04x" % ord(ch))
        else:
            out.append(ch)
    return '"' + "".join(out) + '"'


def _key(name):
    return name if _BARE_KEY.match(name) else _esc(name)


def _fmt_value(value):
    # bool must precede int: bool is a subclass of int.
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return repr(value) if isinstance(value, float) else str(value)
    if isinstance(value, str):
        return _esc(value)
    if isinstance(value, (datetime.datetime, datetime.date, datetime.time)):
        return value.isoformat()
    if isinstance(value, list):
        return "[" + ", ".join(_fmt_value(item) for item in value) + "]"
    raise TypeError("unsupported TOML value type: %r" % (type(value),))


def _emit(table, path, lines):
    scalars = [(k, v) for k, v in table.items() if not isinstance(v, dict)]
    subtables = [(k, v) for k, v in table.items() if isinstance(v, dict)]
    if path:
        if lines and lines[-1] != "":
            lines.append("")
        lines.append("[" + ".".join(_key(part) for part in path) + "]")
    for key, value in scalars:
        lines.append(_key(key) + " = " + _fmt_value(value))
    for key, value in subtables:
        _emit(value, path + [key], lines)


def main(argv):
    merged = {}
    for path in argv:
        try:
            with open(path, "rb") as handle:
                text = handle.read().decode("utf-8")
        except FileNotFoundError:
            continue
        merged = deep_merge(merged, _toml_loads(text))
    lines = []
    _emit(merged, [], lines)
    sys.stdout.write("\n".join(lines) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
