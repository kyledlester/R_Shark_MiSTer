-- MAME 0.289 Lua: capture R-Shark video state + rendered pixels at selected frames.
--   RS_OUT     output directory (one subdirectory fNNNNN per frame)
--   RS_FRAMES  comma-separated frame numbers (screen frame_number at frame_done)
--   RS_INPUTS  optional script "frame:port:field:value;..." e.g. "600:SYSTEM:Coin 1:1;610:SYSTEM:Coin 1:0"
-- Per frame: pixels.bin (384x240 ARGB32 LE, MAME's rendered visible area), palette.bin (2048 BE words),
-- sprbuf.bin (the sprite buffer MAME used = :spriteram contents at the previous frame_done, which is
-- the vblank-begin instant of the copy), regs.txt (last byte written to every tilemap control
-- register and the main control byte), ram.bin (0x040000-0x04FFFF BE words).
-- Timing basis (src/emu/screen.cpp vblank_begin): frame_update() renders, THEN the vblank callbacks
-- run buffered_spriteram16_device::vblank_copy_rising. frame_done fires inside frame_update.
-- screen:pixels() returns the previously completed bitmap (MAME double-buffers screen bitmaps), so
-- the pixels of the frame rendered at frame_done(N) are read at frame_done(N+1) (RS_PIXDELAY=1,
-- established empirically: state N vs pixels N+1 is pixel-exact, see docs/MAME_REFERENCE.md).
local dir = os.getenv("RS_OUT")
local want = {}
local last = 0
local pixdelay = tonumber(os.getenv("RS_PIXDELAY") or "1")
for n in string.gmatch(os.getenv("RS_FRAMES") or "", "%d+") do want[tonumber(n)] = true; last = math.max(last, tonumber(n)) end
local inputs = {}
for f, port, field, v in string.gmatch(os.getenv("RS_INPUTS") or "", "(%d+):([^:]+):([^:]+):(%d+)") do
  inputs[#inputs + 1] = {frame = tonumber(f), port = port, field = field, value = tonumber(v)}
end
local m = manager.machine
local scr = m.screens[":screen"]
local sp = m.devices[":maincpu"].spaces["program"]
local regs = {}
for i = 0, 0x3f do regs[i] = 0 end
local ctrl = 0
-- tilemap ctrl_w is mapped with umask16(0x00ff): register = (addr & 0xf) >> 1, data = low byte
local function reg_tap(base, slot)
  return sp:install_write_tap(base, base + 0xf, "tm" .. slot, function(off, data, mask)
    if (mask & 0x00ff) ~= 0 then regs[slot * 8 + ((off - base) >> 1)] = data & 0xff end
  end)
end
taps = { reg_tap(0x0c4000, 0), reg_tap(0x0c4010, 1), reg_tap(0x0cc000, 2), reg_tap(0x0cc010, 3),
  sp:install_write_tap(0x0c0014, 0x0c0015, "ctrl", function(off, data, mask)
    if (mask & 0x00ff) ~= 0 then ctrl = data & 0xff end end) }
local function share_bytes(name)
  local s = m.memory.shares[name]
  local t = {}
  for i = 0, s.size - 2, 2 do local w = s:read_u16(i); t[#t + 1] = string.char(w >> 8, w & 0xff) end
  return table.concat(t)
end
local prev_spr = share_bytes(":spriteram")
local function wfile(path, data) local f = io.open(path, "wb"); f:write(data); f:close() end
emu.register_frame_done(function()
  local fn = scr:frame_number()
  for _, e in ipairs(inputs) do
    if e.frame == fn then m.ioport.ports[":" .. e.port].fields[e.field]:set_value(e.value) end
  end
  if want[fn - pixdelay] then
    wfile(string.format("%s/f%05d/pixels.bin", dir, fn - pixdelay), scr:pixels())
  end
  if want[fn] then
    local d = string.format("%s/f%05d", dir, fn)
    os.execute('mkdir "' .. d:gsub("/", "\\") .. '" 2>nul')
    wfile(d .. "/palette.bin", share_bytes(":palette"))
    wfile(d .. "/sprbuf.bin", prev_spr)
    wfile(d .. "/spr_live.bin", share_bytes(":spriteram"))   -- what the vblank copy takes now
    local t = {}
    for i = 0x040000, 0x04fffe, 2 do local w = sp:read_u16(i); t[#t + 1] = string.char(w >> 8, w & 0xff) end
    wfile(d .. "/ram.bin", table.concat(t))
    local f = io.open(d .. "/regs.txt", "w")
    local names = {"bg0", "bg1", "fg0", "fg1"}
    for s = 0, 3 do
      local r = {}
      for i = 0, 7 do r[#r + 1] = string.format("%02x", regs[s * 8 + i]) end
      f:write(names[s + 1] .. " " .. table.concat(r, " ") .. "\n")
    end
    f:write(string.format("ctrl %02x\n", ctrl))
    f:close()
  end
  prev_spr = share_bytes(":spriteram")
  if fn >= last + pixdelay then m:exit() end
end)
