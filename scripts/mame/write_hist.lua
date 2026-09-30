-- MAME 0.289 Lua: scanline histograms of R-Shark 68000 writes per target region.
local out = io.open(os.getenv("RS_OUT") or "write_hist.txt", "w")
local frames = tonumber(os.getenv("RS_FRAMES") or "1800")
local scr = manager.machine.screens[":screen"]
local sp = manager.machine.devices[":maincpu"].spaces["program"]
local FP, SP, PP = scr.frame_period, scr.scan_period, scr.pixel_period
local function vpos() local e = (FP - scr:time_until_pos(0, 0)) % FP; return math.floor(e / SP + 1e-9) end
local hist = {}
local superx = manager.machine.system.name:sub(1, 6) == "superx"
local iob = superx and 0x080000 or 0x0c0000
local ram = superx and 0x0d0000 or 0x040000
local function add(name) local v = vpos(); hist[name] = hist[name] or {}; hist[name][v] = (hist[name][v] or 0) + 1 end
t1 = sp:install_write_tap(ram + 0xd000, ram + 0xdfff, "spr", function(o, d, m) add("spriteram") end)
t2 = sp:install_write_tap(iob + 0x8000, iob + 0x8fff, "pal", function(o, d, m) add("palette") end)
t3 = sp:install_read_tap(ram + 0xd000, ram + 0xdfff, "sprr", function(o, d, m) add("spriteram_read") end)
t4 = sp:install_read_tap(iob + 0x8000, iob + 0x8fff, "palr", function(o, d, m) add("palette_read") end)
t5 = sp:install_read_tap(iob, iob + 0xffff, "unm", function(o, d, m)
  if not (o >= iob + 2 and o <= iob + 7) and not (o >= iob + 0x8000 and o < iob + 0x9000) then add(string.format("read_%06x", o)) end end)
t7 = sp:install_write_tap(iob + 0x4000, iob + 0xcfff, "tm", function(o, d, m)
  if (o < iob + 0x8000 or o >= iob + 0x9000) then add("tilemap_regs") end end)
emu.register_frame_done(function()
  if scr:frame_number() >= frames then
    for name, h in pairs(hist) do
      local keys = {} for k in pairs(h) do keys[#keys + 1] = k end table.sort(keys)
      local s, tot = {}, 0
      for _, k in ipairs(keys) do s[#s + 1] = k .. ":" .. h[k]; tot = tot + h[k] end
      out:write(name .. " total=" .. tot .. " " .. table.concat(s, " ") .. "\n")
    end
    out:close(); manager.machine:exit()
  end
end)
