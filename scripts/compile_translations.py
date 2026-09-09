#!/usr/bin/env python3
"""Validate PO catalogs and compile the package-local Plasma translation domain."""

import argparse
from collections import Counter
import gettext
import json
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent
PLACEHOLDERS = re.compile(r"%[1-9][0-9]*")


def validate_placeholders(compiled, catalog, source_name):
    # GNUTranslations validates this freshly generated MO, but its lookup table
    # discards msgid_plural. Read the original pairs from the MO string tables.
    data = compiled.read_bytes()
    endian = "<" if data[:4] == b"\xde\x12\x04\x95" else ">"
    count, originals, translations = struct.unpack_from(endian + "III", data, 8)
    for index in range(count):
        source_size, source_offset = struct.unpack_from(endian + "II", data, originals + index * 8)
        translated_size, translated_offset = struct.unpack_from(endian + "II", data, translations + index * 8)
        if source_size == 0:
            continue
        source_forms = data[source_offset:source_offset + source_size].decode(catalog.charset()).split("\0")
        source_forms[0] = source_forms[0].rsplit("\x04", 1)[-1]
        required = Counter(PLACEHOLDERS.findall(source_forms[0]))
        allowed = required.copy()
        for original in source_forms[1:]:
            placeholders = Counter(PLACEHOLDERS.findall(original))
            required &= placeholders
            allowed |= placeholders
        translated_forms = data[translated_offset:translated_offset + translated_size].decode(catalog.charset()).split("\0")
        for translated in translated_forms:
            actual = Counter(PLACEHOLDERS.findall(translated))
            # Gettext permits a count argument to be omitted in finite singular
            # forms. Arguments shared by both English forms must still survive.
            if required - actual or actual - allowed:
                raise ValueError(f"{source_name}: changed placeholders in {source_forms[0]!r}")


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
            # msgcat gives each complete entry its own block, preserving
            # contexts and multiline strings. Mark every active entry because
            # JavaScript extraction leaves some KDE arguments unflagged.
            normalized = subprocess.run(["msgcat", "--no-wrap", "--to-code=UTF-8", str(source)],
                                        check=True, capture_output=True, text=True, encoding="utf-8").stdout
            checked_source = Path(temporary) / source.name
            checked_source.write_text("\n\n".join(
                re.sub(r"(?m)^(msgctxt |msgid )", r"#, kde-format\n\1", entry, count=1)
                for entry in normalized.split("\n\n")), encoding="utf-8")
            # Gettext retains both English forms and interprets Plural-Forms;
            # msgstr[0] is not necessarily a translation of the English singular.
            subprocess.run(["msgfmt", "--check", "--check-format", "-o", str(compiled), str(checked_source)],
                           check=True, capture_output=True, text=True)
            with compiled.open("rb") as catalog_file:
                catalog = gettext.GNUTranslations(catalog_file)
            if catalog.info().get("language") != language:
                raise ValueError(f"{source.name}: Language header must match its filename")
            validate_placeholders(compiled, catalog, source.name)
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
