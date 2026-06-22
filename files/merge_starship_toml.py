#!/usr/bin/env python3
"""Deep-merge one or more starship TOML files and print the result to stdout.

Usage: merge_starship_toml.py <in1> [<in2> ...]

Later inputs override earlier ones. Tables are merged recursively (key-by-key);
scalars and lists replace. Missing input paths are skipped silently, so callers
can pass optional overrides (user file, inline var) unconditionally.

Self-contained: reads with the stdlib ``tomllib`` (Python 3.11+) and serializes
with the small emitter below, so no third-party TOML library is required on the
managed host.
"""

import datetime
import re
import sys

try:
    import tomllib
except ImportError:  # pragma: no cover - depends on host Python
    sys.stderr.write(
        "merge_starship_toml.py requires Python 3.11+ (stdlib tomllib).\n"
    )
    sys.exit(1)

_BARE_KEY = re.compile(r"^[A-Za-z0-9_-]+$")


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
                data = tomllib.load(handle)
        except FileNotFoundError:
            continue
        merged = deep_merge(merged, data)
    lines = []
    _emit(merged, [], lines)
    sys.stdout.write("\n".join(lines) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
