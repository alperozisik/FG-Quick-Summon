"""Check reaction cast timing against the installed CoreRPG expiry predicate."""
from pathlib import Path
from zipfile import ZipFile
from lua_runtime import run

root = Path(__file__).resolve().parents[1]
data = Path.home() / "OneDrive/FRP/FG Data"
with ZipFile(data / "rulesets/CoreRPG.pak") as archive:
    effects = archive.read("scripts/manager_effect.lua").decode()
start = effects.index("function processEffectExpire(")
end = effects.index("\nfunction ", start + 1)
predicate = effects[start:end].encode()
source = b""
for name, path in [("QuickSummonRules", "scripts/rules.lua"),
                   ("QuickSummon", "scripts/manager.lua"),
                   ("QuickSummonLifetime", "scripts/lifetime.lua")]:
    source += (f"{name}={{}}\nsetfenv(assert(loadstring([====[".encode()
               + (root / path).read_bytes()
               + f"]====])),setmetatable({name},{{__index=_G}}))()\n".encode())
source += b"NativeTiming={}\nsetfenv(assert(loadstring([====[" + predicate
source += b"]====])),setmetatable(NativeTiming,{__index=_G}))()\n"
run(source + (root / "tests/timing.lua").read_bytes(), "timing_regression")
print("PASS: reaction snapshot, initiative 13/12.9 expiry and SW slot 2-9 scaling")
