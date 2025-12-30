-- super-excavate: wireless-enabled quarry turtle
-- Arguments: excavate <length> <width> [depth]
-- Places mined items into a chest directly above the turtle at the start position.

local args = { ... }
if not (shell and shell.run) then
  error("This launcher requires the ComputerCraft shell. Run `sexcavate` directly.")
end

shell.run("sexcavate", table.unpack(args))
