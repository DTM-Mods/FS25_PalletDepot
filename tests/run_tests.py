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


def run_file(path):
    lua = lupa.LuaRuntime()
    load = lua.eval("function(src, name) local f, err = load(src, '@' .. name) if not f then error(err) end return f() end")
    load(read(os.path.join(HERE, "stubs.lua")), "stubs.lua")
    for script in SCRIPTS:
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
