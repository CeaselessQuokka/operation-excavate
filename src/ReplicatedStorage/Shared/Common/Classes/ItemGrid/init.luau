--[[
	Uses Infinigrid internally to generate items in terrain
--]]

--!strict
--- Services ---
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--- Imports ---
local Infinigrid = require(ReplicatedStorage.Shared.Common.Classes.Infinigrid)

--- Types ---
export type ItemChunkState = {
	NSpawnbles: number,
}

--- Variables ---

--- Functions ---

--- Item Grid Class ---
local ItemGrid = {}
ItemGrid.__index = ItemGrid

export type ItemGrid = setmetatable<{
	Grid: Infinigrid.Grid<ItemChunkState>,
}, typeof(ItemGrid)>
function ItemGrid.new(center: Vector3, gridWorldSize: Vector3?, chunkSize: number?): ItemGrid
	local self: ItemGrid = setmetatable({
		Grid = Infinigrid.new(center, gridWorldSize, chunkSize) :: any,
	}, ItemGrid)
	return self
end

function ItemGrid.Method(self: ItemGrid, ...: any) end

return table.freeze(ItemGrid)
