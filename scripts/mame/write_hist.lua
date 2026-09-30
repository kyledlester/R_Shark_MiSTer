-- MAME 0.289 Lua: scanline histograms of R-Shark 68000 writes per target region.
local out = io.open(os.getenv("RS_OUT") or "write_hist.txt", "w")
local frames = tonumber(os.getenv("RS_FRAMES") or "1800")
local scr = manager.machine.screens[":screen"]
local sp = manager.machine.devices[":maincpu"].spaces["program"]
local FP, SP, PP = scr.frame_period, scr.scan_period, scr.pixel_period
local function vpos() local e = (FP - scr:time_until_pos(0, 0)) % FP; return math.floor(e / SP + 1e-9) end
local hist = {}
local function add(name) local v = vpos(); hist[name] = hist[name] or {}; hist[name][v] = (hist[name][v] or 0) + 1 end
t1 = sp:install_write_tap(0x04d000, 0x04dfff, "spr", function(o, d, m) add("spriteram") end)
t2 = sp:install_write_tap(0x0c8000, 0x0c8fff, "pal", function(o, d, m) add("palette") end)
t3 = sp:install_read_tap(0x04d000, 0x04dfff, "sprr", function(o, d, m) add("spriteram_read") end)
t4 = sp:install_read_tap(0x0c8000, 0x0c8fff, "palr", function(o, d, m) add("palette_read") end)
t5 = sp:install_read_tap(0x0c0000, 0x0fffff, "unm", function(o, d, m)
  if not (o >= 0x0c0002 and o <= 0x0c0007) and not (o >= 0x0c8000 and o < 0x0c9000) then add(string.format("read_%06x", o)) end end)
t6 = sp:install_write_tap(0x050000, 0x0bffff, "hole", function(o, d, m) add(string.format("write_%06x", o)) end)
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
