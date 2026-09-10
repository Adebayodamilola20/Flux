#!/usr/bin/env python3
"""Writes the Sparkle appcast for one release.

Kept out of `package_dmg.sh` deliberately: it is the one part of packaging with
real structure to get wrong, and a heredoc inside a shell script is a poor place
to keep anything that has to be read again.

Sparkle decides what is newer by comparing `sparkle:version` to the installed
bundle's `CFBundleVersion`, so that field carries the build stamp — the same
twelve digits the DMG is stamped with, which only ever rise.

Usage:
    make_appcast.py VERSION BUILD URL NOTES SIGNATURE OUT
"""

from __future__ import annotations

import email.utils
import html
import sys


def main(argv: list[str]) -> int:
    try:
        version, build, url, notes, signature, out = argv[1:7]
    except ValueError:
        print(__doc__, file=sys.stderr)
        return 2

    # `sign_update` prints the enclosure's two attributes ready to paste —
    # `sparkle:edSignature="…" length="…"`. Taken verbatim rather than parsed
    # and rebuilt, so a change to what it emits cannot be silently dropped.
    attributes = signature.strip()
    if "edSignature" not in attributes:
        print(f"refusing to write an unsigned appcast: {attributes!r}", file=sys.stderr)
        return 1

    # No release note is not an error — it is a build nobody wrote one for —
    # but the item still needs something to show.
    description = notes.strip() or f"DevNotch {version}."

    feed = f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>DevNotch</title>
    <description>Updates to DevNotch.</description>
    <language>en</language>
    <item>
      <title>{html.escape(version)}</title>
      <pubDate>{email.utils.formatdate(localtime=True)}</pubDate>
      <sparkle:version>{html.escape(build)}</sparkle:version>
      <sparkle:shortVersionString>{html.escape(version)}</sparkle:shortVersionString>
      <!-- The bundle's own floor. Sparkle will not offer this to a Mac that
           cannot run it, which matters here: the app moved from macOS 13 to 15,
           so some installed copies are on a version this build would refuse to
           launch on. Better that they are never offered it than that they take
           it and lose the app. -->
      <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
      <description><![CDATA[{description}]]></description>
      <enclosure url="{html.escape(url)}" type="application/octet-stream" {attributes} />
    </item>
  </channel>
</rss>
"""

    with open(out, "w", encoding="utf-8") as handle:
        handle.write(feed)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
