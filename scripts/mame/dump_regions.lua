-- MAME 0.289 Lua: dump R-Shark ROM regions as MAME sees them. 16-bit regions via read_u16
-- (logical big-endian word value), written as hi,lo bytes. Output dir: $RS_OUT.
local dir = os.getenv("RS_OUT")
local words = {maincpu=true, sprite=true, bg0=true, bg1=true, fg0=true, fg1=true}
for _, name in ipairs({"maincpu","audiocpu","sprite","bg0","bg1","fg0","fg1","tmap_hi","oki"}) do
  local r = manager.machine.memory.regions[":" .. name]
  local f = io.open(dir .. "/" .. name .. ".bin", "wb")
  local t = {}
  if words[name] then
    for i = 0, r.size - 2, 2 do local w = r:read_u16(i); t[#t+1] = string.char(w >> 8, w & 0xff)
      if #t >= 4096 then f:write(table.concat(t)); t = {} end end
  else
    for i = 0, r.size - 1 do t[#t+1] = string.char(r:read_u8(i))
      if #t >= 8192 then f:write(table.concat(t)); t = {} end end
  end
  f:write(table.concat(t)); f:close()
end
manager.machine:exit()
