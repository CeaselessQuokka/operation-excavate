--[[
	
--]]

--!strict
--- Services ---

--- Imports ---
local Infinigrid = require(script.Parent)

--- Types ---
type Infinigrid = Infinigrid.Grid<any>

--- Variables ---

--- Functions ---

--- Infinigrid(ebugger) Class ---
local Debugger = {}
Debugger.__index = Debugger

export type Debugger = typeof(setmetatable({} :: { Grid: Infinigrid }, Debugger))
function Debugger.new(grid: Infinigrid): Debugger
	local self: Debugger = setmetatable({ Grid = grid }, Debugger)
	return self
end

function Debugger.Enable(self: Debugger) end

function Debugger.Disable(self: Debugger) end

return table.freeze(Debugger)
