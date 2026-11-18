"""Verify summon lifetime hooks using mocked FG services and the real Lua engine."""
from pathlib import Path
from lua_runtime import run

root = Path(__file__).resolve().parents[1]
manager = (root / "scripts/manager.lua").read_bytes()
lifetime = (root / "scripts/lifetime.lua").read_bytes()
harness = (root / "tests/lifetime.lua").read_bytes()
# Keep manager and lifetime globals isolated as FG script packages do.
source = b'QuickSummon={}\nsetfenv(assert(loadstring([====['+manager+b']====])),setmetatable(QuickSummon,{__index=_G}))()\n'
source += b'QuickSummonLifetime={}\nsetfenv(assert(loadstring([====['+lifetime+b']====])),setmetatable(QuickSummonLifetime,{__index=_G}))()\n'
run(source + harness, "lifetime_regression")
print("PASS: timed effects, rests, cleanup, hostility, migration, locks and Spiritual Weapon")
