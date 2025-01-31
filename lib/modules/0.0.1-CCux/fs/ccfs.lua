--[[
### CCFS ###
    ComputerCraft FileSystem

    this is just a kernel driver which retypes default fs of CraftOS and allows and puts it into kernel level
    decently modified so it can support metadata
--]]

local module = {}
local restriced_dictionaries = {"/lib/modules/0.0.1-CCux", "/etc", "/boot"}
local hidden = {"/metadata"}

-- I am crazy
-- uh