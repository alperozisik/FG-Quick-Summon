"""Check the real catalogue path and selected-element rule with mock module records."""
from pathlib import Path
from lua_runtime import run

root = Path(__file__).resolve().parents[1]
source = b""
for name, path in [("QuickSummonRules", "scripts/rules.lua"),
                   ("QuickSummon", "scripts/manager.lua")]:
    source += (f"{name}={{}}\nsetfenv(assert(loadstring([====[".encode()
               + (root / path).read_bytes()
               + f"]====])),setmetatable({name},{{__index=_G}}))()\n".encode())
run(source + (root / "tests/element_filter.lua").read_bytes(), "element_filter_regression")
print("PASS: selected element, CR/upcast, family aliases, mixed mephits and catalogue integration")
