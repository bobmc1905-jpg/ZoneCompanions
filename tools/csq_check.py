"""Zone Companions - static sanity checks.

Run before every commit, after every game update, and before every deploy:

    python tools/csq_check.py

There is no GML compiler available outside the game, so this script stands in for
one. Every check below exists because the mistake it catches is otherwise
invisible: GML has no build step here, GMLoader's exit code does not reflect
whether a patch applied, and the failure mode of a bad edit is a silent no-op or
a crash on somebody else's machine.

  1.  brace/paren/bracket balance in every mods/code/*.gml
  2.  "declarations only" - no top-level executable code in a global script
  3.  config keys declared in csq_config_spec() vs actual csq_cfg() read sites
  4.  every csq_* function called is defined exactly once
  5.  every code_patch entry exists in the decompiled vanilla export
  6.  every function invoked from the patch YAML is defined in mods/code/
  7.  no mods/code filename collides with a vanilla script or object event
  8.  struct field names are not GML keywords
  9.  banned vanilla symbols are never touched
  10. every write to `state` goes through csq_ai_state_idle/combat()
  11. bark ids written to global.t_npc_text are written to all 8 sibling arrays
  12. no hub checks inside the raid-only behaviour modules
  13. every csq_* call passes an argument count the declaration accepts
  14. every vanilla instance variable the mod writes is on a reasoned allowlist
  15. every config key is documented, and the docs agree on version and counts

Exit code is 1 if anything failed, so it can gate a build.
"""

import io
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
CODE = os.path.join(ROOT, "mods", "code")
PATCH = os.path.join(ROOT, "mods", "config", "code_patch")

# The decompiled vanilla export is ground truth for patch targets and for the
# filename-collision check. It lives outside this repo (it is huge and not
# redistributable), so allow an override.
EXPORT = os.environ.get(
    "ZS_EXPORT",
    os.path.join(os.path.dirname(ROOT), "_scratch", "gmexport",
                 "vanilla_export", "Exported_Code"))

FAILURES = []
WARNINGS = []

# The five behaviour modules added by the "human companions" pass. They only ever
# run inside a raid -- csq_tick_deferred_spawn refuses to spawn anywhere else -- so
# a hub test inside one of them is dead code by construction (check 12).
RAID_ONLY_MODULES = (
    "gml_GlobalScript_csq_human.gml",
    "gml_GlobalScript_csq_combat.gml",
    "gml_GlobalScript_csq_voice.gml",
    "gml_GlobalScript_csq_care.gml",
    "gml_GlobalScript_csq_idle.gml",
)


def fail(msg):
    FAILURES.append(msg)
    print("  FAIL  " + msg)


def warn(msg):
    WARNINGS.append(msg)
    print("  warn  " + msg)


def read(path):
    return io.open(path, encoding="utf-8", errors="replace").read()


BS = chr(92)


def strip_code(s):
    """Remove string literals and comments so counting is meaningful."""
    out, i, n = [], 0, len(s)
    while i < n:
        c = s[i]
        if c == '"':
            i += 1
            while i < n and s[i] != '"':
                i += 2 if s[i] == BS else 1
            i += 1
            continue
        if s.startswith("//", i):
            j = s.find(chr(10), i)
            i = n if j < 0 else j
            continue
        if s.startswith("/*", i):
            j = s.find("*/", i)
            i = n if j < 0 else j + 2
            continue
        out.append(c)
        i += 1
    return "".join(out)


def strip_comments_only(s):
    """Drop comments AND string-literal contents, preserving line numbering.

    Both are needed. Comments in this codebase discuss the banned symbols at
    length by design, and log lines contain text like "state=" -- neither is code,
    and a checker that cannot tell the difference gets switched off.
    """
    out, i, n = [], 0, len(s)
    while i < n:
        if s[i] == '"':
            j = i + 1
            while j < n and s[j] != '"':
                j += 2 if s[j] == BS else 1
            out.append('""')
            i = j + 1
            continue
        if s.startswith("//", i):
            j = s.find(chr(10), i)
            i = n if j < 0 else j
            continue
        if s.startswith("/*", i):
            j = s.find("*/", i)
            chunk = s[i:n] if j < 0 else s[i:j + 2]
            out.append(chr(10) * chunk.count(chr(10)))
            i = n if j < 0 else j + 2
            continue
        out.append(s[i])
        i += 1
    return "".join(out)


def gml_files():
    if not os.path.isdir(CODE):
        fail("no mods/code directory at " + CODE)
        return []
    names = sorted(f for f in os.listdir(CODE) if f.endswith(".gml"))
    return [os.path.join(CODE, f) for f in names]


FILES = gml_files()
BASENAMES = [os.path.basename(f) for f in FILES]
ALL = "\n".join(read(f) for f in FILES)
ALL_CODE = "\n".join(strip_comments_only(read(f)) for f in FILES)

# Loaded up front so check 4 can tell "never called" from "called from the patch
# YAML" -- the five lifecycle entry points have no caller inside mods/code by design.
PATCH_YAML = ""
if not os.path.isdir(PATCH):
    fail("no code_patch directory at " + PATCH)
else:
    for _name in sorted(os.listdir(PATCH)):
        if _name.endswith((".yaml", ".yml")):
            PATCH_YAML += read(os.path.join(PATCH, _name)) + "\n"
PATCH_CALLS = set(re.findall(r"\b(csq_\w+)\s*\(", PATCH_YAML))

print("-- 1. balance --")
print("   files: %d" % len(FILES))
_unbalanced = 0
for path in FILES:
    t = strip_code(read(path))
    b = t.count("{") - t.count("}")
    p = t.count("(") - t.count(")")
    k = t.count("[") - t.count("]")
    if b or p or k:
        _unbalanced += 1
        fail("%s braces%+d parens%+d brackets%+d" % (os.path.basename(path), b, p, k))
print("   balanced: %d/%d" % (len(FILES) - _unbalanced, len(FILES)))

print("")
print("-- 2. declarations only (global scripts) --")
# A newly created global script is not guaranteed to run at game start, so anything
# at column 0 that is not a declaration is a bug: it would either never run or run
# at an unpredictable time. Object event files are the opposite -- they ARE
# top-level code -- so only gml_GlobalScript_* is checked.
ALLOWED = re.compile(r"^(function\s+\w+|enum\s+\w+|#macro\s|[{}]|//|/\*|\*)")
_scripts = [p for p in FILES if os.path.basename(p).startswith("gml_GlobalScript_")]
for path in _scripts:
    for n, line in enumerate(read(path).splitlines(), 1):
        if not line.strip() or line[0] in " \t":
            continue
        if not ALLOWED.match(line.strip()):
            fail("%s:%d top-level statement: %s"
                 % (os.path.basename(path), n, line.strip()[:60]))
print("   checked %d global script(s), skipped %d object event(s)"
      % (len(_scripts), len(FILES) - len(_scripts)))

print("")
print("-- 3. config keys: spec vs read sites --")
spec_keys = re.findall(r'key\s*:\s*"([a-z0-9_]+)"', ALL)
read_keys = set(re.findall(r'csq_cfg\(\s*"([a-z0-9_]+)"\s*\)', ALL))

# Typed wrappers around csq_cfg. Their string argument is a read site too; without
# these every key_* and recruit_key_* would look unread.
for _w in ("csq_input_key", "csq_input_pressed", "csq_recruit_key_label"):
    read_keys |= set(re.findall(_w + r'\(\s*"([a-z0-9_]+)"\s*\)', ALL))

# Keys built at runtime, e.g. csq_cfg("recruit_tier" + _n + "_price"). Anything in
# the spec matching prefix...suffix counts as read.
for _pre, _suf in re.findall(r'csq_cfg\(\s*"([a-z0-9_]+)"\s*\+[^)]*?\+\s*"([a-z0-9_]+)"\s*\)', ALL):
    _dyn = re.compile(r"^" + _pre + r".*" + _suf + r"$")
    read_keys |= set(k for k in spec_keys if _dyn.match(k))

if not spec_keys:
    fail("csq_config_spec() declares no keys")

for key in sorted(set(spec_keys)):
    declared = spec_keys.count(key)
    if declared != 1:
        fail('config key "%s" declared %d times' % (key, declared))
    if key not in read_keys:
        # Not fatal: the milestone plan lands a key's spec entry in the same commit
        # as its section, sometimes before the code that reads it.
        warn('config key "%s" is declared but never read' % key)

for key in sorted(read_keys - set(spec_keys)):
    fail('csq_cfg("%s") reads a key that csq_config_spec() never declares' % key)

_sections = []
for m in re.finditer(r'section\s*:\s*"([a-z_]+)"', ALL):
    if m.group(1) not in _sections:
        _sections.append(m.group(1))
print("   keys: %d declared, %d read, %d unread"
      % (len(set(spec_keys)), len(read_keys), len(set(spec_keys) - read_keys)))
print("   sections: " + ", ".join(_sections))

print("")
print("-- 4. functions: defined once, and every call resolves --")
defs = re.findall(r"^function\s+(csq_\w+)\s*\(", ALL, re.M)
calls = set(re.findall(r"(?<!function )\b(csq_\w+)\s*\(", ALL_CODE))

for name in sorted(set(defs)):
    n = defs.count(name)
    if n != 1:
        fail("function %s defined %d times" % (name, n))

for name in sorted(calls - set(defs)):
    fail("call to %s() but no definition in mods/code/" % name)

for name in sorted(set(defs) - calls):
    if name in PATCH_CALLS:
        continue
    warn("function %s() is defined but never called" % name)

print("   defined: %d   called: %d   (%d from the patch YAML)"
      % (len(set(defs)), len(calls), len(PATCH_CALLS)))

print("")
print("-- 5. patch targets exist in the vanilla export --")
yaml_text = PATCH_YAML

have_export = os.path.isdir(EXPORT)
if not have_export:
    print("   SKIP: export not found at %s (set ZS_EXPORT)" % EXPORT)

# Each patch is "<entry>:\n  - type: <type>", optionally with a find string.
patches = re.findall(
    r"^(gml_\w+)\s*:\s*\n\s*-\s*type\s*:\s*(\w+)(?:\s*\n\s*find\s*:\s*\|-\s*\n\s+(.+))?",
    yaml_text, re.M)

if not patches:
    fail("no patches parsed out of mods/config/code_patch/")

for entry, ptype, find in patches:
    if have_export and not os.path.isfile(os.path.join(EXPORT, entry + ".gml")):
        fail("%s: no such entry in the vanilla export" % entry)
        continue
    if not find:
        print("   %-46s %-16s ok (no find string, cannot drift)" % (entry, ptype))
        continue
    src = read(os.path.join(EXPORT, entry + ".gml")) if have_export else ""
    hits = sum(1 for ln in src.splitlines() if ln.strip() == find.strip())
    if have_export and hits != 1:
        fail("%s: find string matches %d lines (want exactly 1)" % (entry, hits))
    else:
        print("   %-46s %-16s find hits=%d" % (entry, ptype, hits))

print("")
print("-- 6. functions called from the patch YAML are defined --")
patch_calls = PATCH_CALLS
if not patch_calls:
    fail("the patch YAML calls no csq_* function at all")
for name in sorted(patch_calls):
    if name in set(defs):
        print("   %-32s defined" % name)
    else:
        fail("patch calls %s() which is not defined in mods/code/" % name)

print("")
print("-- 7. no filename collides with the vanilla export --")
# GMLoader imports mods/code with QueueReplace. A file whose name matches a vanilla
# script or object event therefore REPLACES that vanilla code wholesale, silently.
# Every file this mod ships is meant to be additive, so any collision is a bug.
if not have_export:
    print("   SKIP: export not found (set ZS_EXPORT)")
else:
    _collisions = 0
    for name in BASENAMES:
        if os.path.isfile(os.path.join(EXPORT, name)):
            _collisions += 1
            fail("%s exists in the vanilla export -- it would replace vanilla code"
                 % name)
    print("   checked %d file(s), %d collision(s)" % (len(BASENAMES), _collisions))

print("")
print("-- 8. struct field names are not GML keywords --")
# Added after a real deploy failure in a sibling mod. `mod: {...}` compiled fine by
# every check above and then died inside GMLoader with
#   Invalid keyword used for struct field name, must surround with quotes
# because `mod` is the modulo operator. GMLoader still exited 0-ish, recompiled
# data.win without the module, and the mod would have been silently absent in game.
# Operators are the dangerous ones: they read like ordinary words.
GML_KEYWORDS = (
    "mod div and or not xor if then else begin end while do until repeat for switch "
    "case default break continue exit return with var globalvar static function new "
    "delete try catch finally throw enum constructor self other all noone global "
    "true false undefined"
).split()

FIELD = re.compile(r"(?:^|[{,])\s*(" + "|".join(GML_KEYWORDS) + r")\s*:(?!:)")
keyword_fields = 0
for path in FILES:
    body = strip_code(read(path))
    # A switch case ends in a colon too, so drop those lines before looking.
    for n, line in enumerate(body.splitlines(), 1):
        stripped = line.strip()
        if stripped.startswith("case ") or stripped.startswith("default:"):
            continue
        hit = FIELD.search(line)
        if hit:
            keyword_fields += 1
            fail('%s:%d struct field "%s" is a GML keyword -- quote it: "%s":'
                 % (os.path.basename(path), n, hit.group(1), hit.group(1)))
print("   keyword field names: %d" % keyword_fields)

print("")
print("-- 9. banned vanilla symbols --")
# These are shared with every NPC in the game, or they are the vanilla brain's own
# bookkeeping. Writing one either breaks unrelated NPCs or fights the state machine
# the mod deliberately leaves in charge of the trigger.
#
#   sub_ai_peso / sub_ai_stop            global weight and stop tables, read by
#                                        every NPC's selector
#   npc_force_moving_towards_player      sets target = the player and
#                                        target_relation = 2: the companion turns
#                                        on you
BANNED_ANY = ("sub_ai_peso", "sub_ai_stop", "npc_force_moving_towards_player")

# Assignment targets. Reads are fine and common (csq_ai reads target.x).
BANNED_WRITE = ("target", "state_finito", "shoot_time", "riflessi", "riflessi_max",
                "must_take_cover", "force_moving_towards_player",
                "shooted_first_time", "have_to_reload")

# Two documented exceptions, both in the baseline, both narrow.
#
#   have_to_reload   Create_0 clears the single forced reload vanilla schedules for
#                    every freshly spawned NPC, immediately after npc_setup_weapon
#                    has filled the magazine. Mid-fight reloads still work --
#                    scr_enemy_shoot sets the flag again when the magazine runs dry.
#   target           csq_ai_scan_for_targets is the mod's own acquisition path. It
#                    is safe only because the value comes from vanilla's own
#                    scr_find_target_for_human() (or -4 for "none"), which is also
#                    exactly why npc_force_moving_towards_player is banned outright:
#                    that one writes target = the player AND target_relation = 2.
WRITE_EXEMPT = {
    "have_to_reload": ("gml_Object_obj_csq_companion_Create_0.gml",),
    "target": ("gml_GlobalScript_csq_ai.gml",),
}
TARGET_RHS_OK = ("scr_find_target_for_human()", "-4")

_banned = 0
for path in FILES:
    base = os.path.basename(path)
    body = strip_comments_only(read(path))
    for n, line in enumerate(body.splitlines(), 1):
        for sym in BANNED_ANY:
            if sym in line:
                _banned += 1
                fail("%s:%d touches %s" % (base, n, sym))
        for sym in BANNED_WRITE:
            hit = re.search(r"(?<![\w])" + sym + r"\s*=(?!=)\s*([^;]*)", line)
            if not hit:
                continue
            if base in WRITE_EXEMPT.get(sym, ()):
                # Exempt file, but the right-hand side still has to be sanctioned.
                rhs = re.sub(r"\s+", "", hit.group(1))
                if sym == "target" and rhs not in TARGET_RHS_OK:
                    _banned += 1
                    fail("%s:%d target = %s -- only %s are sanctioned"
                         % (base, n, hit.group(1)[:40], " or ".join(TARGET_RHS_OK)))
                continue
            _banned += 1
            fail("%s:%d assigns to %s (vanilla brain state)" % (base, n, sym))
print("   banned symbol uses: %d" % _banned)

print("")
print("-- 10. every write to `state` goes through an accessor --")
# obj_npc_parent_Step_0's switch(state) has
#     default: trace_error(...)  ->  show_error(..., true)
# which is a hard, uncatchable crash. So `state` may only ever receive a string the
# vanilla machine knows. The two accessors in csq_ai are the only sanctioned source;
# a literal is banned even when it happens to be correct today, because it is the
# next edit that gets it wrong.
STATE_WRITE = re.compile(r"(?<![\w])state\s*=(?!=)\s*([^;]*)")

# obj_csq_recruiter is a fixture, not a companion: it is created once in the hub,
# never fights, and never runs csq_ai. It pins "human_no_move" directly and says so,
# so it does not depend on a csq_ai accessor being loaded.
STATE_LITERAL_OK = ("gml_Object_obj_csq_recruiter_Create_0.gml",)
VANILLA_STATES = ('""',)   # string literals are blanked by strip_comments_only

_state_writes = 0
for path in FILES:
    base = os.path.basename(path)
    for n, line in enumerate(strip_comments_only(read(path)).splitlines(), 1):
        hit = STATE_WRITE.search(line)
        if not hit:
            continue
        rhs = hit.group(1).strip()
        _state_writes += 1
        if rhs.startswith("csq_ai_state_idle(") or rhs.startswith("csq_ai_state_combat("):
            continue
        if base in STATE_LITERAL_OK and rhs in VANILLA_STATES:
            continue
        fail("%s:%d state = %s -- use csq_ai_state_idle()/csq_ai_state_combat()"
             % (base, n, rhs[:40]))
print("   sanctioned state writes: %d" % _state_writes)

print("")
print("-- 11. bark array parity --")
# scr_draw_npc_text has no bounds check, and obj_npc_draw_text's alarms read the
# sibling arrays for the same id. In particular global.t_npc_text_next[n] must be
# literally `false`: the alarm tests `!= false`, and `undefined != false` is true, so
# a missing entry sends the drawer chasing a follow-up line that does not exist.
BARK_ARRAYS = ("t_npc_text", "t_npc_text_next", "t_npc_text_next_id", "t_npc_id",
               "t_npc_needs_sight", "t_npc_text_speed", "t_npc_text_timer",
               "t_npc_suppress_prompts", "t_npc_draw_offset_y")

_idx = {}
for name in BARK_ARRAYS:
    pat = re.compile(r"global\." + name + r"\[\s*@?\s*([^\]]+)\]\s*(?:\[[^\]]*\]\s*)?=(?!=)")
    _idx[name] = set(re.sub(r"\s+", "", m) for m in pat.findall(ALL_CODE))

if not _idx["t_npc_text"]:
    print("   no bark registration in mods/code yet -- nothing to check")
else:
    for expr in sorted(_idx["t_npc_text"]):
        missing = [n for n in BARK_ARRAYS[1:] if expr not in _idx[n]]
        if missing:
            fail("bark index %s is written to t_npc_text but not to: %s"
                 % (expr, ", ".join(missing)))
        else:
            print("   %-28s written to all %d arrays" % (expr, len(BARK_ARRAYS)))

print("")
print("-- 12. no hub tests in the raid-only behaviour modules --")
HUB = re.compile(r"\b(is_in_hub|csq_in_hub)\s*\(")
_hub = 0
_present = 0
for path in FILES:
    base = os.path.basename(path)
    if base not in RAID_ONLY_MODULES:
        continue
    _present += 1
    for n, line in enumerate(strip_comments_only(read(path)).splitlines(), 1):
        hit = HUB.search(line)
        if hit:
            _hub += 1
            fail("%s:%d calls %s() -- these modules only ever run in a raid"
                 % (base, n, hit.group(1)))
print("   modules present: %d/%d   hub tests: %d"
      % (_present, len(RAID_ONLY_MODULES), _hub))

print("")
print("-- 13. call arity matches the declaration --")
# GML raises "wrong number of arguments" at runtime, not at load, so a call with one
# argument too few sails through every other check here and then throws the first
# time that code path is taken -- which for a rarely-hit branch can be weeks later.


def split_args(_text, _open):
    """Return the argument list of a call whose '(' is at index _open, or None."""
    depth, i, n = 0, _open, len(_text)
    start, args = _open + 1, []
    while i < n:
        c = _text[i]
        if c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
            if depth == 0:
                args.append(_text[start:i])
                return [a for a in args if a.strip() != ""] if len(args) == 1 else args
        elif c == "," and depth == 1:
            args.append(_text[start:i])
            start = i + 1
        i += 1
    return None


ARITY = {}
for m in re.finditer(r"function\s+(csq_\w+)\s*\(", ALL_CODE):
    params = split_args(ALL_CODE, m.end() - 1)
    if params is None:
        fail("could not parse the parameter list of %s()" % m.group(1))
        continue
    # A parameter is optional two ways: a default in the signature, or -- the idiom
    # this codebase actually uses -- an `if (is_undefined(_p)) _p = ...` guard at the
    # top of the body. Both are honoured, because treating the second as mandatory
    # produces false failures on documented-optional arguments.
    body_end = ALL_CODE.find("\nfunction ", m.end())
    body = ALL_CODE[m.end():body_end if body_end > 0 else len(ALL_CODE)]
    lo = len(params)
    for p in reversed(params):
        name = p.split("=")[0].strip()
        optional = ("=" in p) or (name and ("is_undefined(" + name + ")") in body)
        if not optional:
            break
        lo -= 1
    ARITY[m.group(1)] = (lo, len(params))

_arity_bad = 0
for path in FILES:
    base = os.path.basename(path)
    body = strip_comments_only(read(path))
    for m in re.finditer(r"(?<![\w.])(csq_\w+)\s*\(", body):
        name = m.group(1)
        if name not in ARITY:
            continue
        if body[:m.start()].rstrip().endswith("function"):
            continue
        args = split_args(body, m.end() - 1)
        if args is None:
            continue
        lo, hi = ARITY[name]
        if not (lo <= len(args) <= hi):
            _arity_bad += 1
            line = body[:m.start()].count(chr(10)) + 1
            fail("%s:%d %s() called with %d arg(s), declared %d..%d"
                 % (base, line, name, len(args), lo, hi))
print("   functions with a known signature: %d   bad call sites: %d"
      % (len(ARITY), _arity_bad))

print("")
print("-- 14. writes to vanilla instance variables are on the allowlist --")
# The design document names the vanilla variables the mod is allowed to write, and
# the reason for the list is that most of the interesting ones have side effects
# somewhere else in a 4000-line Step event. `target` also sets who shoots whom;
# `state_finito` releases the action ratchet; `have_to_reload` gates the trigger.
#
# Check 9 bans the handful that must never be touched. This check is the other half:
# anything the mod assigns that ALSO appears as an assignment target somewhere in the
# vanilla export has to be listed here, with a reason. A new milestone that reaches
# for a vanilla variable nobody has thought about fails until someone thinks about it.
#
# Names are matched only at the start of a statement, so `_e.inst.hp = ...` and
# `with (_o) alpha = ...` style writes are out of scope; those are struct/instance
# member writes and read as such.
VANILLA_WRITE_OK = {
    # --- movement: the whole point of the mod ---
    "move_point_x":       "the A* goal every vanilla NPC pathfinds to",
    "move_point_y":       "the A* goal every vanilla NPC pathfinds to",
    "path_timer":         "vanilla's own 'repath now' idiom (Step_0:637, :2871, :3054, :3120)",
    "x":                  "teleport recovery and spawn placement only",
    "y":                  "teleport recovery and spawn placement only",
    # --- the two vanilla states the mod parks companions in ---
    "state":              "checked far more strictly by check 10",
    # --- identity and setup, written once in Create ---
    "npc_name":           "the name shown in speech bubbles",
    "npc_speaker_id":     "which voice set a companion talks with",
    "have_to_reload":     "cleared once at spawn so a companion does not start dry",
    "human_tick_max_ref": "de-sync: the NPC's own decision interval, adjusted once",
    # --- the vanilla aggro leash, which is how engagement is scoped ---
    "leash_to_spawn":     "enables vanilla's own leash in scr_find_target_for_human",
    "leash_radius":       "how far that leash reaches",
    "original_x":         "the leash anchor, repointed at the player every frame",
    "original_y":         "the leash anchor, repointed at the player every frame",
    "target":             "checked far more strictly by check 9",
    "alert_player":       "zeroed out of combat so the player cannot win the target slot",
    # --- survivability and props ---
    "hp":                 "healing, clamped to csq_hp_max",
    "draw_weapon":        "cosmetic only -- obj_npc_weapon_Draw_0:5 is the sole reader",
    "human_state_now":    "the obj_arms_* props' only handshake; unread while state is human_no_move",
    "grenade_amount_max": "ff_no_grenades takes the grenades away",
    # --- the recruiter fixture, which is a hub prop and never fights ---
    "depth":              "obj_csq_recruiter draw order",
    "image_alpha":        "obj_csq_recruiter fade",
    "visible":            "obj_csq_recruiter show/hide",
}

# A handful of the allowlisted names are only defensible in one file, because the
# argument for them is an argument about that file's host state. human_state_now is
# unread by vanilla only while `state` is "human_no_move", and csq_idle is the one
# module that guarantees it -- writing it from anywhere else would be handing the
# human_general selector a fabricated action.
VANILLA_WRITE_ONE_FILE = {
    "human_state_now": "gml_GlobalScript_csq_idle.gml",
}

ASSIGN = re.compile(r"(?m)^[ \t]*(\w+)\s*(?:=|\+=|-=|\*=|/=|\+\+|--)(?!=)")

_vanilla_names = set()
for _f in os.listdir(EXPORT) if os.path.isdir(EXPORT) else []:
    if not _f.endswith(".gml"):
        continue
    for _m in ASSIGN.finditer(strip_code(read(os.path.join(EXPORT, _f)))):
        _vanilla_names.add(_m.group(1))

if not _vanilla_names:
    warn("check 14 skipped: no vanilla export at %s" % EXPORT)
else:
    _vw = 0
    _vw_bad = 0
    _seen = {}
    for path in FILES:
        base = os.path.basename(path)
        body = strip_code(read(path))
        # `var _x` locals, so a local that happens to share a vanilla name is not
        # reported. The mod's convention is a leading underscore, which is also
        # skipped, but conventions are not guarantees.
        locs = set(re.findall(r"\bvar\s+(\w+)", body))
        for m in ASSIGN.finditer(body):
            name = m.group(1)
            if name.startswith("_") or name.startswith("csq_"):
                continue
            if name in locs or name in GML_KEYWORDS or name not in _vanilla_names:
                continue
            _vw += 1
            _seen.setdefault(name, set()).add(base)
            if name not in VANILLA_WRITE_OK:
                _vw_bad += 1
                fail("%s:%d writes vanilla variable `%s` -- not on the allowlist in "
                     "check 14. Work out what else in obj_npc_parent reads it, then "
                     "either add it with a reason or find another way."
                     % (base, body[:m.start()].count(chr(10)) + 1, name))
            elif name in VANILLA_WRITE_ONE_FILE and base != VANILLA_WRITE_ONE_FILE[name]:
                _vw_bad += 1
                fail("%s:%d writes vanilla variable `%s`, which is only sanctioned in "
                     "%s -- see VANILLA_WRITE_ONE_FILE."
                     % (base, body[:m.start()].count(chr(10)) + 1, name,
                        VANILLA_WRITE_ONE_FILE[name]))
    for name in sorted(_seen):
        if name in VANILLA_WRITE_OK:
            print("   %-19s %s" % (name, VANILLA_WRITE_OK[name]))
    print("   vanilla writes: %d   off the allowlist: %d" % (_vw, _vw_bad))

print("")
print("-- 15. every config key is documented, and the docs agree on the version --")

# WHY THIS IS A CHECK AND NOT A CONVENTION
# csq_config.ini is regenerated from the spec on every launch, so it can never drift.
# CONFIGURATION.md is hand-written, so it always can -- and a key that exists but is
# documented nowhere is a key no player will ever find. The three number-of-settings
# claims (two in csq_config.gml's prose, one in CONFIGURATION.md) are the other half
# of the same problem: they were correct when written and are wrong the moment a key
# is added, which is exactly the kind of staleness nobody notices in review.
_doc_path = os.path.join(ROOT, "CONFIGURATION.md")
_chg_path = os.path.join(ROOT, "CHANGELOG.md")

if not os.path.isfile(_doc_path):
    fail("CONFIGURATION.md is missing")
else:
    _doc = read(_doc_path)
    _undoc = [k for k in sorted(set(spec_keys)) if ("`%s`" % k) not in _doc]
    for k in _undoc:
        fail('config key "%s" is not documented in CONFIGURATION.md' % k)

    # Section headers carry their own count, e.g. "## `[combat]` -- 22 settings".
    _hdr_bad = 0
    _spec_counts = {}
    for m in re.finditer(r'section\s*:\s*"([a-z_]+)"', ALL):
        _spec_counts[m.group(1)] = _spec_counts.get(m.group(1), 0) + 1
    for _sec, _n in sorted(_spec_counts.items()):
        _m = re.search(r"^## `\[" + _sec + r"\]`\s*\S+\s*(\d+) settings",
                       _doc, re.M)
        if _m is None:
            _hdr_bad += 1
            fail("CONFIGURATION.md has no `[%s]` section header with a count" % _sec)
        elif int(_m.group(1)) != _n:
            _hdr_bad += 1
            fail("CONFIGURATION.md says `[%s]` has %s settings; the spec declares %d"
                 % (_sec, _m.group(1), _n))

    _total = len(set(spec_keys))
    if str(_total) not in _doc:
        fail("CONFIGURATION.md never states the current total of %d settings" % _total)

    print("   keys documented: %d/%d   section headers wrong: %d"
          % (_total - len(_undoc), _total, _hdr_bad))

# The version has to be the same string in three places, or a bug report names a
# release that never existed.
_ver = re.search(r'function\s+csq_mod_version\(\)\s*\{\s*return\s*"([^"]+)"', ALL)
if _ver is None:
    fail("csq_mod_version() not found")
else:
    _v = _ver.group(1)
    _cfg_gml = os.path.join(CODE, "gml_GlobalScript_csq_config.gml")
    if os.path.isfile(_cfg_gml) and str(len(set(spec_keys))) not in read(_cfg_gml):
        warn("csq_config.gml's prose does not mention the current key count of %d"
             % len(set(spec_keys)))
    if not os.path.isfile(_chg_path):
        fail("CHANGELOG.md is missing")
    else:
        _chg = read(_chg_path)
        if ("## [%s]" % _v) not in _chg:
            fail("CHANGELOG.md has no entry for version %s" % _v)
        if ("[%s]: https" % _v) not in _chg:
            fail("CHANGELOG.md has no release link for version %s" % _v)
    print("   version: %s" % _v)

print("")
if WARNINGS:
    print("%d warning(s) (not fatal)" % len(WARNINGS))
if FAILURES:
    print("FAILED: %d problem(s)" % len(FAILURES))
    sys.exit(1)

print("OK: all checks passed")
