--[[
	An infinite grid system that generates axis-aligned chunks.
	The resolution is hardcoded to be 4x4x4 which obeys the Roblox terrain system.

	Note: Need to have deloading capabilities for when memory gets high (on the server but also on the client)
	-- Maybe chunks can go into a "low memory" mode if they havent been visited in a while
	Note: should have a method to serialize and a constructor to do fromSerial. That way it can be easily saved and loaded, and also sent over remotes if needed? I should only be sending patches anyway, but it'd be useful for syncing on join so yeah i guess
	Note: Perhaps this low memory mode is a serialized version in a buffer or something? ANd this is added to a bigger buffer that has asleep chunks? We would need a lookup buffer hmmm, most likely not worth
	Note: have viewer able to actually edit the spawnable data real-time with its edit functionality
--]]

--!strict
--- Services ---

--- Imports ---

--- Types ---
export type BaseChunkState = {
	ChunkIndex: number, -- The index of the chunk in the grid. Calculated as (x + y * gridSizeX + z * gridSizeX * gridSizeY).
	ChunkPosition: Vector3, -- Position in grid, in grid space.
}

--- Variables ---
local DEFAULT_MAX_GRID_SIZE = Vector3.one * ((2 ^ 16) - 1) -- Max grid size in studs.
local DEFAULT_CHUNK_SIZE = 64 -- Size of each chunk in studs. Must be a multiple of 8 to avoid potential ReadVoxels instability.

--- Functions ---
local function ExpandVectorToGrid(vector: Vector3, resolution: number): Vector3
	return Vector3.new(
		math.ceil(vector.X / resolution) * resolution,
		math.ceil(vector.Y / resolution) * resolution,
		math.ceil(vector.Z / resolution) * resolution
	)
end

local function RoundVectorToGrid(vector: Vector3): Vector3
	return Vector3.new(math.round(vector.X / 4) * 4, math.round(vector.Y / 4) * 4, math.round(vector.Z / 4) * 4)
end

--- Grid Class ---
local Grid = {}
Grid.__index = Grid

export type Grid<ChunkState> = typeof(setmetatable(
	{} :: {
		Center: Vector3, -- World-space position of the grid's center.
		GenerationOrigin: Vector3, -- World-space position of the grid's generation origin.
		ChunkSize: number, -- Size of each chunk in studs (cubed).
		GridSize: Vector3, -- Size of the grid in grid space. Calculated as GridWorldSize / ChunkSize.
		GridWorldSize: Vector3, -- Optional maximum size of the grid in studs. If nil, the grid can grow infinitely in all directions.
		Chunks: { BaseChunkState & ChunkState }, -- Table of chunks indexed by their chunk index. Chunks are stored in XYZ order exactly like terrain.
	},
	Grid
))
function Grid.new<ChunkState>(center: Vector3, gridWorldSize: Vector3?, chunkSize: number?): Grid<ChunkState>
	chunkSize = chunkSize or DEFAULT_CHUNK_SIZE
	chunkSize = math.ceil(chunkSize / 8) * 8 -- Align chunk size to terrain resolution (8x8x8) to avoid potential ReadVoxels instability.
	local worldCenter = ExpandVectorToGrid(center, 4)
	local worldSize = ExpandVectorToGrid(gridWorldSize or DEFAULT_MAX_GRID_SIZE, 8)
	local grid: Grid<ChunkState> = setmetatable({
		Center = worldCenter, -- World-space, aligned to terrain resolution (4x4x4).
		GenerationOrigin = worldCenter - (worldSize / 2), -- World-space position of the grid's generation origin. This mimics how terrain writes.
		ChunkSize = chunkSize, -- 8x8x8 seems to do better with ReadVoxels stability.
		GridSize = worldSize / chunkSize,
		GridWorldSize = worldSize, -- Max grid size must be a multiple of chunk size to avoid any sort of read (and potentially write) instability.
		Chunks = {}, -- A flat array (can have holes) of all chunks in the grid. Indexed by chunk index.
	}, Grid)
	if not grid.Center:FuzzyEq(center) then
		warn(
			`Grid center {center} was expanded to {grid.Center} to align with terrain resolution (4x4x4). This may cause unexpected behavior if you were relying on the original center.`
		)
	end
	if grid.ChunkSize ~= chunkSize then
		warn(
			`Chunk size {chunkSize} was expanded to {grid.ChunkSize} to align with terrain resolution (8x8x8). This may cause unexpected behavior if you were relying on the original chunk size.`
		)
	end
	return grid
end

-- TODO: self evaluate all methods to ensure correctness in successes and failures (things that should fail do fail)
-- TODO: test out funcName<<TypeHere>>(...) syntax
function Grid.GetChunkAtPosition<ChunkState>(self: Grid<ChunkState>, position: Vector3): (BaseChunkState & ChunkState)?
	local chunkWorldPosition = RoundVectorToGrid(position) - self.GenerationOrigin
	local chunkGridPosition = chunkWorldPosition / self.ChunkSize
	return self.Chunks[self:GridPositionToChunkIndex(chunkGridPosition)]
end

function Grid.GridPositionToWorldPosition(self: Grid<any>, gridPosition: Vector3): Vector3
	return self.GenerationOrigin + (gridPosition * self.ChunkSize)
end

function Grid.ChunkIndexToGridPosition<any>(self: Grid<any>, chunkIndex: number): Vector3
	local gridSize = self.GridSize
	local sizeYZ, sizeZ = gridSize.Y * gridSize.Z, gridSize.Z
	local remainder = chunkIndex % sizeYZ
	return Vector3.new(chunkIndex // sizeYZ, remainder // sizeZ, remainder % sizeZ)
end

function Grid.GridPositionToChunkIndex<any>(self: Grid<any>, gridPosition: Vector3): number
	local gridSize = self.GridSize
	local sizeYZ, sizeZ = gridSize.Y * gridSize.Z, gridSize.Z
	return (gridPosition.X * sizeYZ) + (gridPosition.Y * sizeZ) + gridPosition.Z
end

return table.freeze(Grid)
