-- MAME 0.289 Lua: R-Shark sound traffic with timestamps (microseconds since start).
--   M <t> <value>          68000 sound-latch write (0x0C0013)
--   Z <t> R|W <addr> <v>   Z80 access to F800-F80F (latch read, YM2151, OKI)
-- Output $RS_OUT, duration $RS_SECONDS (default 4).
local m = manager.machine
local out = io.open(os.getenv("RS_OUT") or "sound_trace.txt", "w")
local stop = tonumber(os.getenv("RS_SECONDS") or "4")
local function t() return m.time:as_double() * 1e6 end
local msp = m.devices[":maincpu"].spaces["program"]
local zsp = m.devices[":audiocpu"].spaces["program"]
t1 = msp:install_write_tap(0x0c0012, 0x0c0013, "lat", function(o, d, mk)
  if (mk & 0xff) ~= 0 then out:write(string.format("M %.3f %02x\n", t(), d & 0xff)) end end)
t2 = zsp:install_read_tap(0xf800, 0xf80f, "zr", function(o, d, mk)
  out:write(string.format("Z %.3f R %04x %02x\n", t(), o, d & 0xff)) end)
t3 = zsp:install_write_tap(0xf800, 0xf80f, "zw", function(o, d, mk)
  out:write(string.format("Z %.3f W %04x %02x\n", t(), o, d & 0xff)) end)
emu.register_frame_done(function() if m.time:as_double() >= stop then out:close(); m:exit() end end)
