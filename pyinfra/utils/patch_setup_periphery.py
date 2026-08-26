#!/usr/bin/env python3
"""Patches setup-periphery.py's eager, unauthenticated GitHub API call out
of its --version argparse default (see moghtech/komodo issue #148): argparse
evaluates default= expressions eagerly, so that call fires even though
--version is always passed explicitly below, and it intermittently hits
GitHub's unauthenticated rate limit."""

import sys

path = sys.argv[1]
content = open(path).read()

old = 'json.load(urllib.request.urlopen("https://api.github.com/repos/moghtech/komodo/releases/latest"))["tag_name"]'
new = '"unused"'  # never actually used -- --version always overrides it

if old not in content:
    sys.exit(f"Expected string not found in {path} -- setup-periphery.py may have changed upstream, patch needs updating")

open(path, "w").write(content.replace(old, new))
