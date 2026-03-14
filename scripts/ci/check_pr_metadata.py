#!/usr/bin/env python3
"""Fail CI when required PR governance fields are missing."""

from __future__ import annotations

import os
import re
import sys


def main() -> int:
    body = os.environ.get("PR_BODY", "")

    required_sections = [
        "## Problem",
        "## ADRs Referenced",
        "## Architecture Impact",
        "## Risks / Follow-ups",
    ]

    missing = [section for section in required_sections if section.lower() not in body.lower()]
    if missing:
        print("Missing required PR sections:")
        for section in missing:
            print(f"- {section}")
        return 1

    # Require ADR classification language in the ADR section.
    if not re.search(r"ADR-\d{4}|none", body, flags=re.IGNORECASE):
        print("Missing ADR reference format. Include ADR IDs like ADR-0003, or state 'None'.")
        return 1

    print("PR metadata gate passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
