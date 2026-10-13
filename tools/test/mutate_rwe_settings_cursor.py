# RWE settings panel cursor fix (RWE-52 check thread): does the bench catch the versions
# that would ship it wrong?
#
#   M1  the manager never ticks the panel      update() is never called, so nothing
#                                              re-asserts the cursor (the reported bug)
#   M2  the per-frame cursor re-assert dropped the game hides the cursor again
#   M3  the per-frame camera hold dropped      mouse-look turns the camera under the panel
#   M4  open saves no camera rotation          the hold has nothing to hold
#   M5  close leaves the cursor shown          the cursor stays after the panel is gone
#   M6  the auto-close on a GUI dropped        the panel fights a menu for the cursor
#   M7  close no longer saves settings         a behaviour the old toggle had is lost
#   M8  the EC-6 market re-read on open dropped (Bob's review of #53)
#   M9  that re-read no longer server-gated     a pure client asks the server-side bridge
#
# Every edit asserts it LANDED by exact occurrence count; restore is proved by sha256.
# "DID NOT APPLY" never counts as a kill.
#
# Run from the repo root:  py tools/test/mutate_rwe_settings_cursor.py [id-prefix ...]
import hashlib, os, re, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
def p(rel): return os.path.join(ROOT, rel)

PANEL = "gui/RWESettingsPanel.lua"
MAIN = "RandomWorldEvents.lua"

MUTATIONS = [
 ("M1-manager-never-ticks-the-panel", MAIN,
  [("    if self.settingsPanel then\n        self.settingsPanel:update()\n    end\n", "", 1)],
  "RandomWorldEvents:update never calls the panel's update, so the cursor is shown only once"),

 ("M2-cursor-reassert-dropped", PANEL,
  [("    if not self.isOpen then return end\n    if g_inputBinding and g_inputBinding.setShowMouseCursor then\n        g_inputBinding:setShowMouseCursor(true, true)\n    end\n",
    "    if not self.isOpen then return end\n", 1)],
  "the per-frame cursor re-assert is gone"),

 ("M3-camera-hold-dropped", PANEL,
  [("            pcall(setRotation, cam, self.savedCamRotX, self.savedCamRotY, self.savedCamRotZ)\n", "", 1)],
  "the camera is not held while the panel is open"),

 ("M4-open-saves-no-rotation", PANEL,
  [("                self.savedCamRotX, self.savedCamRotY, self.savedCamRotZ = rx, ry, rz\n", "", 1)],
  "open never records the rotation, so update() has nothing to hold"),

 ("M5-close-leaves-cursor-shown", PANEL,
  [("        g_inputBinding:setShowMouseCursor(false)\n", "", 1)],
  "closing the panel does not hide the cursor"),

 ("M6-auto-close-dropped", PANEL,
  [("    if g_gui and (g_gui:getIsGuiVisible() or g_gui:getIsDialogVisible()) then\n        self:close()\n    end\n", "", 1)],
  "a menu opening on top leaves the panel open and asserting the cursor"),

 ("M8-market-watch-on-open-dropped", PANEL,
  # Bob's review of #53 (MAJOR 1): the EC-6 re-read on open was dropped by the rewrite
  [("    if g_server ~= nil and RWEMarketBridge ~= nil then\n        RWEMarketBridge.watch(self.rwe)\n    end\n", "", 1)],
  "opening the panel no longer re-reads the market price status (EC-6)"),

 ("M9-market-watch-not-server-gated", PANEL,
  [("    if g_server ~= nil and RWEMarketBridge ~= nil then\n        RWEMarketBridge.watch(self.rwe)",
    "    if RWEMarketBridge ~= nil then\n        RWEMarketBridge.watch(self.rwe)", 1)],
  "a pure client re-reads the market status the server owns"),

 ("M7-close-does-not-save", PANEL,
  [("    if self.rwe and self.rwe.saveSettings then\n        self.rwe:saveSettings()\n    end\n", "", 1)],
  "settings no longer persist when the panel closes"),
]


def sha(b): return hashlib.sha256(b).hexdigest()


def run_bench():
    r = subprocess.run(["node", os.path.join("tools", "test", "rwe-settings-cursor-bench.mjs"), "."], cwd=ROOT,
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    out = r.stdout + r.stderr
    fails = [l.strip() for l in out.splitlines() if "✗" in l]
    return r.returncode, fails


only = sys.argv[1:]
rc, fails = run_bench()
if rc != 0:
    print("BASELINE IS NOT GREEN; fix that before trusting any mutation result.")
    for l in fails[:10]:
        print("   " + l.encode("ascii", "replace").decode("ascii"))
    sys.exit(2)
print("baseline green")

killed, survived, badedit = [], [], []
for mid, rel, edits, why in MUTATIONS:
    if only and not any(mid.startswith(o) for o in only):
        continue
    path = p(rel)
    with open(path, "rb") as f:
        original = f.read()
    crlf = b"\r\n" in original
    enc = lambda s: (s.replace("\n", "\r\n") if crlf else s).encode("utf-8")
    ok, mutated = True, original
    for old, new, want in edits:
        ob, nb = enc(old), enc(new)
        n = mutated.count(ob)
        if n != want:
            badedit.append((mid, "anchor matched %dx, expected %d" % (n, want)))
            print("  !! %s: ANCHOR MISMATCH (%d != %d), mutation NOT applied" % (mid, n, want))
            ok = False
            break
        mutated = mutated.replace(ob, nb, want)
    if not ok:
        continue
    with open(path, "wb") as f:
        f.write(mutated)
    with open(path, "rb") as f:
        landed = f.read()
    if landed == original or landed != mutated:
        with open(path, "wb") as f:
            f.write(original)
        badedit.append((mid, "edit did not land"))
        print("  !! %s: EDIT DID NOT LAND" % mid)
        continue
    try:
        rc, fails = run_bench()
    finally:
        with open(path, "wb") as f:
            f.write(original)
    with open(path, "rb") as f:
        if sha(f.read()) != sha(original):
            print("  !! %s: RESTORE FAILED, stopping" % mid)
            sys.exit(3)
    named = [l for l in fails if re.search(r"[A-F]\d ", l)]
    if rc != 0 and named:
        killed.append(mid); tag = "KILLED  "
    elif rc != 0:
        killed.append(mid); tag = "KILLED* "
    else:
        survived.append((mid, why)); tag = "SURVIVED"
    print("  %s %s" % (tag, mid))
    print("        (%s)" % why)
    for l in fails[:3]:
        print("        " + l[:170].encode("ascii", "replace").decode("ascii"))

print("\n==== MUTATION RESULT ====")
print("killed   %d" % len(killed))
print("survived %d" % len(survived))
print("bad edit %d" % len(badedit))
for mid, why in survived:
    print("--- SURVIVED %s: %s" % (mid, why))
for mid, msg in badedit:
    print("--- BAD EDIT %s: %s" % (mid, msg))
print("all files restored byte-identical (hash-checked per mutation)")
sys.exit(1 if (survived or badedit) else 0)
