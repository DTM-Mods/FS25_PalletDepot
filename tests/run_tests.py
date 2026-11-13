"""Runs the mod's Lua tests offline: tests/*_test.lua against the real scripts, with the engine stubbed.

Each test file gets a fresh Lua runtime: tests/stubs.lua, then the scripts in SCRIPTS (in modDesc.xml's order),
then the test file, which returns a table of test functions. Needs the lupa package (pip install lupa); GitHub
Actions runs this after the build (test-command in .github/workflows/build.yml).

    python tests/run_tests.py
"""
import glob
import os
import sys

import lupa

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SCRIPTS = ["PalletDepot.lua", "PalletDepotPallets.lua", "PalletDepotStoring.lua", "PalletDepotSpawn.lua"]


def read(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


# The game's own Lua (GIANTS' debugger source, on the modder's PC; not in the repository). A test file that needs real
# game functions names them in its header; without the zip (GitHub Actions) that file is skipped, never faked.
GAME_SOURCE = os.path.join(os.path.expanduser("~"), "OneDrive", "Documents", "My Games", "FarmingSimulator2025",
                           "debugger", "gameSource.zip")
if not os.path.isfile(GAME_SOURCE):
    # The sandbox account has a different home; the project may be under the user's profile.
    from pathlib import Path
    for parent in Path(ROOT).parents:
        candidate = parent / "debugger" / "gameSource.zip"
        if candidate.is_file():
            GAME_SOURCE = str(candidate)
            break


def game_function(zf, filename, name):
    """The source of one top-level function (function A:b( / function A.b( ... end) from a game file."""
    src = zf.read(filename).decode("utf-8", "ignore").replace("\r", "")
    start = src.find("function %s(" % name)
    if start < 0 or (start > 0 and src[start - 1] != "\n"):
        raise SystemExit("game function %s not found in %s" % (name, filename))
    end = src.find("\nend\n", start)
    return src[start:end + 5]


def header(path):
    """-- game: <file> <Func> ...   -- before: <tests file>   -- scripts: <script> ... (top of a test file)"""
    games, before, scripts = [], [], []
    for line in read(path).splitlines():
        if not line.startswith("--"):
            break
        parts = line[2:].strip().split()
        if parts[:1] == ["game:"]:
            games.append((parts[1], parts[2:]))
        elif parts[:1] == ["before:"]:
            before += parts[1:]
        elif parts[:1] == ["scripts:"]:
            scripts += parts[1:]
    return games, before, scripts


def run_file(path):
    games, before, extra = header(path)
    if games and not os.path.isfile(GAME_SOURCE):
        print("  skip (needs the game's Lua: %s)" % GAME_SOURCE)
        return 0, 0
    lua = lupa.LuaRuntime()
    load = lua.eval("function(src, name) local f, err = load(src, '@' .. name) if not f then error(err) end return f() end")
    load(read(os.path.join(HERE, "stubs.lua")), "stubs.lua")
    # XML-derived engine fixtures: tests cannot silently drift away from the built pallet models.
    import xml.etree.ElementTree as ET
    models = {}
    for size in (1000, 2500, 5000):
        model = ET.parse(os.path.join(ROOT, "vehicles", "depotPallet%d.xml" % size)).getroot()
        unit = model.find("fillUnit/fillUnitConfigurations/fillUnitConfiguration/fillUnits/fillUnit")
        part = model.find("animations/animation/part")
        if part is not None:
            models[size] = {"capacity": int(unit.get("capacity")),
                            "layers": len(model.findall("pallet/content/object")),
                            "height": float(model.find("base/size").get("height")),
                            "minScale": float(part.get("startScale").split()[1])}
    lua.globals().PALLET_MODELS = lua.table_from(models, recursive=True)
    for name in before:
        load(read(os.path.join(ROOT, name)), name)
    if games:
        import zipfile
        with zipfile.ZipFile(GAME_SOURCE) as zf:
            for filename, functions in games:
                for function in functions:
                    load(game_function(zf, filename, function), "game:" + filename + ":" + function)
    for script in SCRIPTS + extra:
        load(read(os.path.join(ROOT, "scripts", script)), "scripts/" + script)
    tests = load(read(path), os.path.relpath(path, ROOT))
    run = lua.eval("function(f) local ok, err = pcall(f) return ok, tostring(err) end")
    failed = 0
    for name in sorted(tests.keys()):
        ok, err = run(tests[name])
        print("  %s %s%s" % ("ok  " if ok else "FAIL", name, "" if ok else ": " + err))
        failed += 0 if ok else 1
    return len(list(tests.keys())), failed


def main():
    total = failed = 0
    for path in sorted(glob.glob(os.path.join(HERE, "*_test.lua"))):
        print(os.path.relpath(path, ROOT))
        count, bad = run_file(path)
        total, failed = total + count, failed + bad
    print("%d tests, %d failed" % (total, failed))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
