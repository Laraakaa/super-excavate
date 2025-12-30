-- Auto-start hook for super-excavate.
-- Invokes `sexcavate auto` on boot so turtles resume saved digs.

if fs and fs.exists and fs.exists("sexcavate.lua") then
  if shell and shell.run then
    shell.run("sexcavate", "auto")
  elseif os and os.run then
    os.run(_ENV, "sexcavate", "auto")
  end
end
