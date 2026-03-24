--[[
	
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
--- Services ---

--- Imports ---
local Cleaner = require(ReplicatedStorage.Shared.Helpers.Cleaner)
local Infinigrid = require(script.Parent)

--- Types ---
type Infinigrid = Infinigrid.Grid<any>

--- Variables ---

--- Functions ---

--- Infinigrid(ebugger) Class ---
local Debugger = {}
Debugger.__index = Debugger

export type Debugger = typeof(setmetatable(
	{} :: {
		Enabled: boolean,
		Grid: Infinigrid,
		Cleaner: Cleaner.Cleaner,
	},
	Debugger
))
function Debugger.new(grid: Infinigrid): Debugger
	local self: Debugger = setmetatable({
		Enabled = false,
		Grid = grid,
		Cleaner = Cleaner.new(),
	}, Debugger)
	return self
end

function Debugger.Enable(self: Debugger) end

function Debugger.Disable(self: Debugger)
	self.Cleaner:Clean()
	self.Enabled = false
end

return table.freeze(Debugger)
