-- MAME 0.289 Lua: trace R-Shark 68000 accesses to 0x0C0000-0x0CFFFF (I/O, video regs, palette)
-- with frame/scanline stamps.  Output: $RS_OUT (default io_trace.txt).  Frames: $RS_FRAMES.
local out = io.open(os.getenv("RS_OUT") or "io_trace.txt", "w")
local frames = tonumber(os.getenv("RS_FRAMES") or "600")
local scr = manager.machine.screens[":screen"]
local cpu = manager.machine.devices[":maincpu"]
local sp = cpu.spaces["program"]
local FP, SP, PP = scr.frame_period, scr.scan_period, scr.pixel_period
local function beam()
  local e = (FP - scr:time_until_pos(0, 0)) % FP
  local v = math.floor(e / SP + 1e-9)
  return v, math.floor((e - v * SP) / PP + 1e-9)
end
local function stamp() local v, h = beam(); return string.format("%5d %3d %3d", scr:frame_number(), v, h) end
local palcount = 0
wt = sp:install_write_tap(0x0c0000, 0x0cffff, "iow", function(off, data, mask)
  if off >= 0x0c8000 and off < 0x0c9000 then palcount = palcount + 1
    if palcount <= 64 then out:write(string.format("%s W %06x %04x %04x PAL\n", stamp(), off, data, mask)) end
    return end
  out:write(string.format("%s W %06x %04x %04x\n", stamp(), off, data, mask))
end)
rt = sp:install_read_tap(0x0c0000, 0x0cffff, "ior", function(off, data, mask)
  out:write(string.format("%s R %06x %04x %04x\n", stamp(), off, data, mask))
end)
emu.register_frame_done(function()
  if scr:frame_number() >= frames then
    out:write(string.format("palette writes total %d\n", palcount))
    out:close(); manager.machine:exit()
  end
end)
