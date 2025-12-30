-- super-excavate: wireless-enabled quarry turtle
-- Arguments: excavate <length> <width> [depth]
-- Places mined items into a chest directly above the turtle at the start position.

local core = dofile("excavate_core.lua")

core.run(_G, { ... })
