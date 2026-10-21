"""Writes src/manifest.json listing every synced script for build/Sync.luau.

Layout (Rojo-like):  src/<Service>/<Folder...>/<Name>[.server|.client].luau
  .server.luau -> Script, .client.luau -> LocalScript, .luau -> ModuleScript
  src/StarterPlayerScripts maps to StarterPlayer.StarterPlayerScripts. src/build is not synced.
"""
import json
import os

SRC = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "src")
ROOTS = ("ReplicatedStorage", "ServerScriptService", "StarterPlayerScripts")


def main():
    entries = []
    for root in ROOTS:
        base = os.path.join(SRC, root)
        for dirpath, _, files in os.walk(base):
            for f in sorted(files):
                if not f.endswith(".luau"):
                    continue
                rel = os.path.relpath(os.path.join(dirpath, f), SRC).replace("\\", "/")
                parts = rel.split("/")
                name = parts[-1][:-5]
                cls = "ModuleScript"
                if name.endswith(".server"):
                    name, cls = name[:-7], "Script"
                elif name.endswith(".client"):
                    name, cls = name[:-7], "LocalScript"
                entries.append({"url": rel, "parents": parts[:-1], "name": name, "class": cls})
    with open(os.path.join(SRC, "manifest.json"), "w", encoding="utf-8") as fh:
        json.dump(entries, fh, indent=1)
    print(f"manifest: {len(entries)} scripts")


if __name__ == "__main__":
    main()
