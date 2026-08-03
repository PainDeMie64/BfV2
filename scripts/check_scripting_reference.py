#!/usr/bin/env python3

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
PARSER = (ROOT / "Scripting.as").read_text(encoding="utf-8")
REFERENCE = (ROOT / "ScriptingReference.as").read_text(encoding="utf-8")

aliases = set(re.findall(r'lower == "([^"]+)"', PARSER))
function_prefixes = set(
    value.removesuffix("(")
    for value in re.findall(r'StartsWith\(lower, "([^"]+)"\)', PARSER)
)

missing = sorted(
    value for value in aliases | function_prefixes
    if value not in REFERENCE
)
if missing:
    raise SystemExit(
        "ScriptingReference.as is missing parser names: "
        + ", ".join(missing)
    )

print(
    "Scripting reference covers "
    f"{len(aliases)} variables and {len(function_prefixes)} functions."
)
