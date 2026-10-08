"""Run with python3 -m unittest discover -s tests -v (requires liblua 5.4)."""
import ctypes
import ctypes.util
from pathlib import Path
import os
import unittest
import subprocess
import tempfile
import tomllib
import zipfile
import sqlite3
import json
import re

ROOT = Path(__file__).resolve().parent.parent

class Lua:
    def __init__(self):
        self.lib = ctypes.CDLL(ctypes.util.find_library('lua5.4'))
        for name, args, result in [
            ('luaL_newstate', [], ctypes.c_void_p),
            ('luaL_openlibs', [ctypes.c_void_p], None),
            ('luaL_loadstring', [ctypes.c_void_p, ctypes.c_char_p], ctypes.c_int),
            ('lua_pcallk', [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_longlong, ctypes.c_void_p], ctypes.c_int),
            ('lua_tolstring', [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p], ctypes.c_char_p),
            ('lua_close', [ctypes.c_void_p], None),
        ]:
            fn = getattr(self.lib, name); fn.argtypes = args; fn.restype = result
        self.state = self.lib.luaL_newstate()
        self.lib.luaL_openlibs(self.state)

    def database(self):
        lib = self.lib
        state = self.state
        self.connection = sqlite3.connect(':memory:')
        self.connection.row_factory = sqlite3.Row
        for name, args, result in [
            ('lua_gettop', [ctypes.c_void_p], ctypes.c_int),
            ('lua_type', [ctypes.c_void_p, ctypes.c_int], ctypes.c_int),
            ('lua_tonumberx', [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p], ctypes.c_double),
            ('lua_rawgeti', [ctypes.c_void_p, ctypes.c_int, ctypes.c_longlong], ctypes.c_int),
            ('lua_settop', [ctypes.c_void_p, ctypes.c_int], None),
            ('lua_pushstring', [ctypes.c_void_p, ctypes.c_char_p], ctypes.c_void_p),
            ('lua_pushcclosure', [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_int], None),
            ('lua_setglobal', [ctypes.c_void_p, ctypes.c_char_p], None),
        ]:
            fn = getattr(lib, name); fn.argtypes = args; fn.restype = result
        def sql_callback(state):
            try:
                query = lib.lua_tolstring(state, 1, None).decode()
                params = []
                if lib.lua_gettop(state) >= 2 and lib.lua_type(state, 2) == 5:
                    for i in range(1, 100):
                        kind = lib.lua_rawgeti(state, 2, i)
                        if kind == 0:
                            lib.lua_settop(state, -2)
                            break
                        value = lib.lua_tolstring(state, -1, None)
                        params.append(lib.lua_tonumberx(state, -1, None) if kind == 3 else value.decode() if value else None)
                        lib.lua_settop(state, -2)
                cursor = self.connection.execute(query, params)
                rows = [dict(row) for row in cursor.fetchall()] if cursor.description else []
                def lua_value(v):
                    if v is None: return 'nil'
                    if isinstance(v, str): return json.dumps(v, ensure_ascii=False)
                    return str(v)
                result = '{' + ','.join('{' + ','.join('['+lua_value(k)+']='+lua_value(v) for k,v in row.items()) + '}' for row in rows) + '}'
                lib.luaL_loadstring(state, ('return ' + result).encode())
                status = lib.lua_pcallk(state, 0, 1, 0, 0, None)
                if status: raise RuntimeError(lib.lua_tolstring(state, -1, None).decode())
                return 1
            except Exception as error:
                lib.lua_pushstring(state, str(error).encode())
                return 1
        self.callback = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.c_void_p)(sql_callback)
        lib.lua_pushcclosure(state, self.callback, 0)
        lib.lua_setglobal(state, b'_sql')

    def run(self, code):
        try:
            status = self.lib.luaL_loadstring(self.state, code.encode())
            if not status:
                status = self.lib.lua_pcallk(self.state, 0, 0, 0, 0, None)
            if status:
                raise AssertionError(self.lib.lua_tolstring(self.state, -1, None).decode())
        finally:
            self.lib.lua_close(self.state)


import sys
SCENARIO = '\nlocal native_loadfile = loadfile\nrequire = function(name) return assert(native_loadfile("src/" .. name .. ".lua"))() end\n-- Match v0.27.0 sandbox.rs, including its deliberately uncached require.\nfor _, key in ipairs({"execute", "exit", "remove", "rename", "tmpname", "setenv", "setlocale"}) do os[key] = nil end\nio = nil; debug = nil; coroutine = nil; dofile = nil; loadfile = nil\npackage = {loaded = {}}\nlocal now = 1800000000\nos.time = function() return now end\nlocal function advance(seconds) now = now + seconds end\nlocal saved, writes, commands, events, gmcp_handlers, triggers, panels, timers, sends = {}, {}, {}, {}, {}, {}, {}, {}, {}, {}\nstorage = {get=function(key) return saved[key] end, set=function(key, value) saved[key]=value; writes[key]=(writes[key] or 0)+1 end}\nsettings = {get=function(key) if key == "arrow_set" then return "default" end; return true end}\nlocal function handle() return {enable=function(self) self.enabled=true end, disable=function(self) self.enabled=false end, remove=function(self) self.removed=true end} end\nmud = {\n world={character="Being"}, command_prefix=function() return "/" end,\n note=function() end, span=function(text) return text end,\n send=function(text) sends[#sends+1]=text end,\n command=function(name, callback) assert(not commands[name]); commands[name]=callback end,\n trigger=function(pattern, callback, opts) local h=handle(); h.callback=callback; h.pattern=pattern; h.enabled=true; triggers[opts.name]=h; return h end,\n on_send=function(pattern, callback, opts) return handle() end,\n every=function(ms, callback) local h=handle(); h.callback=callback; timers[#timers+1]=h; return h end,\n delay=function(ms, callback) local h=handle(); h.callback=callback; timers[#timers+1]=h; return h end,\n panel=function(id)\n  local p={messages={}, posts={}}\n  function p:on_message(name, callback) self.messages[name]=callback end\n  function p:post(name, data) self.posts[name]=data end\n  panels[id]=p; return p\n end,\n}\nworld={on=function(name, callback) events[name]=callback end}\ngmcp={on=function(name, callback) gmcp_handlers[name]=callback end}\nlog={info=function() end, warn=function() end}\ndb={exec=function(query, params) local result=_sql(query, params); assert(type(result)=="table", result) end,\n query=function(query, params) local result=_sql(query, params); assert(type(result)=="table", result); return result end,\n transaction=function(callback) _sql("SAVEPOINT test"); local ok, err=pcall(callback); if not ok then _sql("ROLLBACK TO test") end; _sql("RELEASE test"); assert(ok, err) end}\nassert(native_loadfile("src/main.lua"))()\n\nlocal engine=require("route_engine"); local tracker=require("npc_tracker"); local database=require("database")\ngmcp_handlers["Room.Info"]("Room.Info", {identifier="A", name="Start"})\nengine.set_pending_direction("n")\ngmcp_handlers["Room.Info"]("Room.Info", {identifier="B", name="Noble street"})\nassert(engine.bfs("A", "B")[1]=="n")\nassert(engine.bfs("B", "A")[1]=="s")\ntracker.record_kill("a nobleman", "B", "Noble street")\ntracker.record_kill("a nobleman", "B", "Noble street")\nassert(tracker.get_total_kills()==2)\nassert(tracker.record_kill("a cat", "B")==nil)\nlocal high=tracker.get_high_value_rooms(2); assert(#high==1 and high[1].id=="B")\nlocal route=engine.calculate_route(high,"A"); assert(route[1].path[1]=="n" and route[2].is_return)\nengine.save(); engine.reload(); assert(engine.bfs("A","B")[1]=="n")\nlocal data=database.export(); assert(data.total_kills==2)\nengine.reset(); assert(tracker.get_total_kills()==0 and engine.bfs("A","B")==nil)\n'

class PluginTests(unittest.TestCase):
    def test_lua_syntax(self):
        for path in (ROOT / 'src').glob('*.lua'):
            with self.subTest(path=path):
                Lua().run(f'assert(loadfile({str(path)!r}))')

    def test_clean_reproducible_package(self):
        manifest = tomllib.loads((ROOT / 'plugin.toml').read_text())
        self.assertEqual(manifest['mallard_api_version'], '1.0')
        self.assertEqual(manifest['minimum_app_version'], '0.27.0')
        with tempfile.TemporaryDirectory() as directory:
            a, b = [Path(directory) / n for n in ('a.mallardx', 'b.mallardx')]
            for output in (a, b):
                subprocess.run([sys.executable, str(ROOT / 'scripts/build.py'), str(output)], check=True, capture_output=True)
            self.assertEqual(a.read_bytes(), b.read_bytes())
            with zipfile.ZipFile(a) as archive:
                names = archive.namelist()
                self.assertEqual(len(names), len(set(names)))
                self.assertIn('plugin.toml', names)
                self.assertIn('README.md', names)
                for name in names:
                    self.assertTrue(name in ('plugin.toml', 'LICENSE', 'README.md') or name.startswith(('src/', 'ui/', 'assets/')), name)
                    self.assertNotIn('..', Path(name).parts)
                    self.assertEqual(archive.read(name), (ROOT / name).read_bytes())
                self.assertIn(manifest['entry'], names)
                for panel in manifest.get('panels', {}).values(): self.assertIn(panel['entry'], names)

    def test_permissions(self):
        manifest = tomllib.loads((ROOT / 'plugin.toml').read_text())
        permissions = manifest['permissions']
        source = '\n'.join(path.read_text() for path in (ROOT / 'src').glob('*.lua'))
        if re.search(r'mud\.send(?:_raw)?\s*\(', source): self.assertTrue(permissions['sends'])
        if re.search(r'db\.(?:query|exec|transaction)\s*\(', source): self.assertTrue(permissions.get('database'))
        for package in re.findall(r'gmcp\.on\("([^"\n]+)"', source):
            self.assertIn(package, permissions.get('gmcp_access', []))
        self.assertFalse(permissions.get('network'))

    def test_runtime_behavior(self):
        previous = Path.cwd()
        try:
            os.chdir(ROOT)
            lua = Lua()
            lua.database()
            lua.run(SCENARIO)
        finally:
            os.chdir(previous)

if __name__ == '__main__':
    unittest.main()
