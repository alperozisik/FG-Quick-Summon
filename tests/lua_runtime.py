"""Run isolated regression scripts with the installed FG Lua runtime."""
import ctypes
from pathlib import Path
import sys


DLL = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(
    r"C:\Program Files\SmiteWorks\Fantasy Grounds\FantasyGrounds_Data\Plugins\x86_64\lua5.1.dll"
)
lua = ctypes.CDLL(str(DLL))
lua.luaL_newstate.restype = ctypes.c_void_p
lua.luaL_openlibs.argtypes = [ctypes.c_void_p]
lua.luaL_loadbuffer.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_size_t, ctypes.c_char_p]
lua.lua_pcall.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int]
lua.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.POINTER(ctypes.c_size_t)]
lua.lua_tolstring.restype = ctypes.c_char_p
lua.lua_close.argtypes = [ctypes.c_void_p]

def run(source, name="regression"):
    state = lua.luaL_newstate()
    try:
        lua.luaL_openlibs(state)
        status = lua.luaL_loadbuffer(state, source, len(source), name.encode())
        if not status:
            status = lua.lua_pcall(state, 0, 0, 0)
        if status:
            raise RuntimeError(lua.lua_tolstring(state, -1, None).decode())
    finally:
        lua.lua_close(state)
