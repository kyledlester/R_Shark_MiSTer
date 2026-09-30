-- MAME 0.289 Lua: first RS_N 68000 data-bus transactions (reads incl. opcode fetches, writes) of
-- R-Shark after reset, one line each: "R|W address data mask" (address = word address * 2).
-- Output: $RS_OUT. Used as the reference for sim/tb/m3_boot_tb.sv.
local out = io.open(os.getenv("RS_OUT") or "bus_trace.txt", "w")
local n, max = 0, tonumber(os.getenv("RS_N") or "20000")
local sp = manager.machine.devices[":maincpu"].spaces["program"]
local function log(kind, off, data, mask)
  if n < max then
    out:write(string.format("%s %06x %04x %04x\n", kind, off & 0xfffffe, data & 0xffff, mask & 0xffff))
    n = n + 1
    if n == max then out:close() end
  end
end
rt = sp:install_read_tap(0x000000, 0x0fffff, "r", function(off, data, mask) log("R", off, data, mask) end)
wt = sp:install_write_tap(0x000000, 0x0fffff, "w", function(off, data, mask) log("W", off, data, mask) end)
emu.register_frame_done(function() if n >= max then manager.machine:exit() end end)
