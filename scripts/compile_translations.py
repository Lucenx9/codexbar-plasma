#!/usr/bin/env python3
"""Validate PO catalogs and compile the package-local Plasma translation domain."""

import argparse
from collections import Counter
import gettext
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent
PLACEHOLDERS = re.compile(r"%[1-9][0-9]*")


def compile_catalogs(output, root=ROOT, applet_id=None):
    """Replace generated catalogs only after every source catalog passes validation."""
    if applet_id is None:
        applet_id = json.loads((root / "metadata.json").read_text())["KPlugin"]["Id"]
    if not re.fullmatch(r"[A-Za-z0-9_.-]+", applet_id):
        raise ValueError("Invalid applet translation domain")
    catalogs = sorted((root / "po").glob("*.po"))
    if not catalogs:
        raise ValueError("No translation catalogs found in po/")
    if output.is_symlink():
        raise ValueError("Refusing to replace a symlink with generated catalogs")
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".locale-", dir=output.parent) as temporary:
        staged = Path(temporary) / "locale"
        for source in catalogs:
            language = source.stem
            if not re.fullmatch(r"[a-z]{2,3}(?:_[A-Za-z0-9]+)*(?:@[a-z]+)?", language):
                raise ValueError(f"Invalid catalog language: {language}")
            subprocess.run(["msgcmp", "--no-fuzzy-matching", str(source),
                            str(root / "po/codexbar-plasma.pot")], check=True, capture_output=True, text=True)
            compiled = staged / language / "LC_MESSAGES" / f"plasma_applet_{applet_id}.mo"
            compiled.parent.mkdir(parents=True)
            subprocess.run(["msgfmt", "--check", "--check-format", "-o", str(compiled), str(source)],
                           check=True, capture_output=True, text=True)
            with compiled.open("rb") as catalog_file:
                catalog = gettext.GNUTranslations(catalog_file)
            if catalog.info().get("language") != language:
                raise ValueError(f"{source.name}: Language header must match its filename")
            # JavaScript extraction does not mark every KDE %1 argument as a
            # format string. Check all compiled entries, including plural forms.
            for key, translated in catalog._catalog.items():
                original = key[0] if isinstance(key, tuple) else key
                if not original:
                    continue
                original = original.rsplit("\x04", 1)[-1]
                if Counter(PLACEHOLDERS.findall(original)) != Counter(PLACEHOLDERS.findall(translated)):
                    raise ValueError(f"{source.name}: changed placeholders in {original!r}")
        if output.exists():
            shutil.rmtree(output)
        staged.rename(output)
    return [source.stem for source in catalogs]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "contents/locale",
                        help="Generated catalog directory (replaced after successful validation)")
    args = parser.parse_args()
    try:
        languages = compile_catalogs(args.output)
    except subprocess.CalledProcessError as error:
        print(error.stderr.strip(), file=sys.stderr)
        return 1
    except (OSError, ValueError) as error:
        print(error, file=sys.stderr)
        return 1
    print("Compiled translations: " + ", ".join(languages))
    return 0


if __name__ == "__main__":
    sys.exit(main())
