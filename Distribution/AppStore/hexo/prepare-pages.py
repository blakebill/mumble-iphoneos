#!/usr/bin/env python3
"""Render the English privacy page using only Python's standard library."""

import argparse
import datetime
import difflib
import json
import re
from pathlib import Path
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parent
PAGES = {
    "privacy.en.md": "mumble/privacy/index.md",
}


def https_url(value):
    parsed = urlsplit(value)
    if (parsed.scheme != "https" or not parsed.netloc or parsed.username
            or parsed.password or parsed.query or parsed.fragment
            or re.search(r'[\s<>"{}]', value)):
        raise ValueError(f"Expected a public HTTPS URL: {value!r}")
    return value.rstrip("/")


def render(config):
    required = {"site_url", "app_name", "publisher_name", "contact_email",
                "source_url", "issues_url", "policy_date"}
    if set(config) != required or not all(isinstance(v, str) and v.strip() for v in config.values()):
        raise ValueError("site.json must contain exactly the documented non-empty string fields")
    for field in ("app_name", "publisher_name"):
        if re.search(r'[\r\n<>\[\]{}\\]', config[field]):
            raise ValueError(f"Use a plain-text {field}")
    if not re.fullmatch(r"[A-Za-z0-9._+%-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}", config["contact_email"]):
        raise ValueError("Use a plain public contact email address")
    datetime.date.fromisoformat(config["policy_date"])
    base = https_url(config["site_url"])
    tokens = {key.upper(): value for key, value in config.items()}
    tokens.update({
        "SITE_URL": base,
        "SOURCE_URL": https_url(config["source_url"]),
        "ISSUES_URL": https_url(config["issues_url"]),
        "PRIVACY_URL": base + "/mumble/privacy/",
    })
    rendered = {}
    for template, destination in PAGES.items():
        source = (ROOT / "templates" / template).read_text(encoding="utf-8")
        text = re.sub(r"\{\{([A-Z_]+)\}\}", lambda match: tokens[match[1]], source)
        if "{{" in text or "}}" in text:
            raise ValueError(f"Unresolved template field in {template}")
        rendered[destination] = text
    return rendered, tokens


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=ROOT / "site.json")
    parser.add_argument("--output", type=Path, default=ROOT / "source",
                        help="Hexo source directory to generate (default: this folder's source)")
    parser.add_argument("--check", action="store_true", help="Check that generated pages are up to date without writing")
    args = parser.parse_args()
    pages, tokens = render(json.loads(args.config.read_text(encoding="utf-8")))
    stale = []
    for relative, content in pages.items():
        path = args.output / relative
        if args.check:
            actual = path.read_text(encoding="utf-8") if path.exists() else ""
            if actual != content:
                stale.append(str(path))
                print("".join(difflib.unified_diff(actual.splitlines(True), content.splitlines(True),
                                                fromfile=str(path), tofile="expected")))
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding="utf-8")
    if stale:
        raise SystemExit("Generated pages are missing or stale; run prepare-pages.py")
    print(("Checked" if args.check else "Generated") + " English privacy page")
    for key in ("PRIVACY_URL",):
        print(f"{key}: {tokens[key]}")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, OSError) as error:
        raise SystemExit(str(error)) from error
