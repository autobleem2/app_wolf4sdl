#!/usr/bin/env python3
"""Write the AutoBleem Store's descriptor for one platform's package of one of the two Apps (autobleem-repo
CLAUDE.md, "The AutoBleem Store's catalog"), next to the package and its picture, ready for
`repo_publish.sh store <platform> ...`:

    tools/store_item.py dist/sodemo-psc-20260504-1.zip   -> dist/store/psc/sodemo.item.json
                                                             + sodemo.png + the zip

The id is the same on every platform (app/wolf4sdl - the RetroBoot App's, so it is updated in place - and
app/sodemo). Only the standard library is needed.
"""
import json
import os
import re
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

WOLF4SDL = "Wolf4SDL by Moritz Kroll and contributors"
ITEMS = {
    "wolf4sdl": {
        "title": "Wolfenstein 3D (Shareware)",
        "author": WOLF4SDL + "; Wolfenstein 3D by id Software",
        "licence": "GPL-2.0 (the v1.4 shareware data: id Software / Apogee shareware, freely distributable)",
        "description": "Escape from Wolfenstein, the first episode of the 1992 classic - ten levels - through "
                       "Wolf4SDL, a faithful source port.",
    },
    "sodemo": {
        "title": "Spear of Destiny (Demo)",
        "author": WOLF4SDL + "; Spear of Destiny by id Software",
        "licence": "GPL-2.0 (the v1.0 demo data: id Software / FormGen, freely distributable demo)",
        "description": "The playable demo of Spear of Destiny, the 1992 follow-up to Wolfenstein 3D - two "
                       "levels - through Wolf4SDL.",
    },
}


def main(argv):
    if len(argv) != 2:
        print(__doc__)
        return 2
    package = argv[1]
    m = re.match(r"^(?P<app>wolf4sdl|sodemo)-(?P<key>[a-z0-9]+)-(?P<version>.+)\.zip$", os.path.basename(package))
    if not m:
        print("not a <wolf4sdl|sodemo>-<key>-<version>.zip: %s" % package)
        return 1
    app, key, version = m.group("app"), m.group("key"), m.group("version")
    out = os.path.join(os.path.dirname(package), "store", key)
    os.makedirs(out, exist_ok=True)
    shutil.copy(package, out)
    shutil.copy(os.path.join(ROOT, "resources", app, "icon.png"), os.path.join(out, app + ".png"))
    info = ITEMS[app]
    item = {
        "id": "app/" + app,
        "kind": "app",
        "title": info["title"],
        "version": version,
        "author": info["author"],
        "licence": info["licence"],
        "description": info["description"],
        "image": app + ".png",
        "files": [{"name": os.path.basename(package)}],
    }
    with open(os.path.join(out, app + ".item.json"), "w", encoding="utf-8") as f:
        json.dump(item, f, indent=2)
        f.write("\n")
    print(out)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
