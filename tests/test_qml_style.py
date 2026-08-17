#!/usr/bin/env python3
"""Guards the house style of the QML. Run: python3 tests/test_qml_style.py

These are the mistakes that do not throw, do not warn, and do not show up in
any log — they only show up when you put a screenshot of this plugin next to
a screenshot of a built-in one. Adapted from hass/tests/test_qml_style.py.
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

QML_FILES = []
for dirpath, dirnames, filenames in os.walk(ROOT):
    dirnames[:] = [d for d in dirnames if d not in (".git", "tests", "docs")]
    for name in sorted(filenames):
        if name.endswith(".qml"):
            QML_FILES.append(os.path.join(dirpath, name))

failures = []
checks = 0


def rel(path):
    return os.path.relpath(path, ROOT)


def blocks(source, opener):
    """Yield (line_number, block_text) for each `opener` block, brace-matched."""
    for match in re.finditer(r"(?m)^[ \t]*" + re.escape(opener) + r"\s*\{", source):
        start = match.end() - 1
        depth = 0
        for index in range(start, len(source)):
            if source[index] == "{":
                depth += 1
            elif source[index] == "}":
                depth -= 1
                if depth == 0:
                    yield source.count("\n", 0, match.start()) + 1, source[start:index]
                    break


def check(condition, message):
    global checks
    checks += 1
    if not condition:
        failures.append(message)


print("every Text sets a font family")
for path in QML_FILES:
    source = open(path, encoding="utf-8").read()
    for line, block in blocks(source, "Text"):
        check("font.family" in block,
              "%s:%d Text without font.family" % (rel(path), line))

print("every Text pins textFormat to plain")
for path in QML_FILES:
    source = open(path, encoding="utf-8").read()
    for line, block in blocks(source, "Text"):
        check("textFormat: Text.PlainText" in block,
              "%s:%d Text without textFormat: Text.PlainText" % (rel(path), line))

print("no hardcoded palette entries where the bar's colours belong")
for path in QML_FILES:
    source = open(path, encoding="utf-8").read()
    # Unlike hass, Quickdex has no settings-only surface to exempt — every
    # file here sits on the bar/popup, so this has no exemption list.
    for number, text in enumerate(source.splitlines(), start=1):
        check("Color.muted" not in text,
              "%s:%d uses Color.muted; dim the bar foreground instead"
              % (rel(path), number))

print("a padded BorderSurface actually applies its insets")
for path in QML_FILES:
    source = open(path, encoding="utf-8").read()
    for line, block in blocks(source, "BorderSurface"):
        if not re.search(r"\bpadding\s*:", block):
            continue
        check(re.search(r"content(Top|Left|Right|Bottom)Inset", source) is not None,
              "%s:%d BorderSurface sets padding but nothing reads content*Inset"
              % (rel(path), line))

print("PanelActionButton instances pass a font family")
for path in QML_FILES:
    source = open(path, encoding="utf-8").read()
    for line, block in blocks(source, "PanelActionButton"):
        check("fontFamily" in block,
              "%s:%d PanelActionButton without fontFamily" % (rel(path), line))

print()
if failures:
    for failure in failures:
        print("  FAIL %s" % failure)
    print("\nFAILED: %d of %d checks" % (len(failures), checks))
    sys.exit(1)
print("all %d checks passed across %d files" % (checks, len(QML_FILES)))
