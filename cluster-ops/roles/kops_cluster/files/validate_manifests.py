#!/usr/bin/env python3
"""Validate rendered kOps manifests before handing them to kops.

kops reports structural problems with unhelpful messages - an empty YAML
document surfaces only as "Object 'Kind' is missing in 'null'", which gives no
clue that a stray '---' after a comment block is the cause. Catching it here
turns a confusing kops failure into a precise one.

Usage: validate_manifests.py FILE [FILE ...]
"""

import sys

import yaml

REQUIRED_KEYS = ("apiVersion", "kind", "metadata")


def check(path: str) -> list[str]:
    problems: list[str] = []

    try:
        with open(path, encoding="utf-8") as handle:
            documents = list(yaml.safe_load_all(handle))
    except yaml.YAMLError as exc:
        return [f"{path}: not valid YAML: {exc}"]
    except OSError as exc:
        return [f"{path}: cannot read: {exc}"]

    if not documents:
        return [f"{path}: contains no YAML documents"]

    for index, document in enumerate(documents):
        where = f"{path}[doc {index}]"

        if document is None:
            problems.append(
                f"{where}: empty document - usually a stray '---' after a "
                f"comment block; kops rejects this as \"Object 'Kind' is "
                f"missing in 'null'\""
            )
            continue

        if not isinstance(document, dict):
            problems.append(f"{where}: expected a mapping, got {type(document).__name__}")
            continue

        missing = [key for key in REQUIRED_KEYS if key not in document]
        if missing:
            problems.append(f"{where}: missing required key(s): {', '.join(missing)}")

    if not problems:
        kinds = [f"{d['kind']}/{d['metadata'].get('name', '?')}" for d in documents]
        print(f"{path}: {len(documents)} valid document(s): {', '.join(kinds)}")

    return problems


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2

    all_problems: list[str] = []
    for path in sys.argv[1:]:
        all_problems.extend(check(path))

    for problem in all_problems:
        print(f"ERROR: {problem}", file=sys.stderr)

    return 1 if all_problems else 0


if __name__ == "__main__":
    sys.exit(main())
