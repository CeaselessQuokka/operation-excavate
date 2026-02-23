--[[
	An infinite grid system that generates axis-aligned chunks.
	The resolution is hardcoded to be 4x4x4 which obeys the Roblox terrain system.

	TODO: Need to have deloading capabilities for when memory gets high (on the server but also on the client)
	-- Maybe chunks can go into a "low memory" mode if they havent been visited in a while
	TODO: should have a method to serialize and a constructor to do fromSerial. That way it can be easily saved and loaded, and also sent over remotes if needed? I should only be sending patches anyway, but it'd be useful for syncing on join so yeah i guess
	TODO: Perhaps this low memory mode is a serialized version in a buffer or something? ANd this is added to a bigger buffer that has asleep chunks? We would need a lookup buffer hmmm, most likely not worth
	TODO: have viewer able to actually edit the spawnable data real-time with its edit functionality

	TODO WHEN BACK: VERIFY CORRECTNESS OF CURRENT METHODS AND GENERATION BY FILLING OUT THE DEBUGGER TO VISUALIZE CHUNKS (see if Highlight instance will work with BlockMesh scale)
--]]

--!strict
--- Services ---
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--- Imports ---
local Signal = require(ReplicatedStorage.Packages.Signal)

--- Types ---
export type BaseChunkState<ChunkState> = {
	Grid: Grid<ChunkState>, -- Reference to the parent grid of this chunk.
	ChunkIndex: number, -- The index of the chunk in the grid. Calculated as (x + y * gridSizeX + z * gridSizeX * gridSizeY).

	-- TODO: For ChunkState (future type note: this may different from client to server, so I need to handle that gracefully somehow; probably just using the new type passing with `fn<<TypeHere>>(...)`)
	-- A buffer that only exists if the chunk is in low memory mode.
	-- Serial: buffer?,

	-- A patch serial that is applied to the chunk to put it in parity with loaded chunks.
	-- This patch is what is necessary to transform the current chunk into the chunk at its last save state.
	-- PatchSerial: buffer?,

	-- Whether the chunk is currently rendered or not.
	-- For the client, this means if anything related to spawned items such as ores, dropped items, etc.
	-- For the server, this means the physical terrain is being rendered or not. This can happen if this chunk has been unvisited for a while, or if it's just not visible because it's underneath another chunk.
	-- IsRendered: boolean,

	-- NOTE/TODO: terrain chunks (and in general chunks) will be efficiently rendered, for example, if it's not "exposed to air" then there is no use in ever rendering it since it cannot be seen
	--- I also need an efficient way to determine how much a player can see so i can decide how many chunks to render so everything is actually in view, like it would be in real life (again, i need an efficient way to use items from a different part in chunks to pop into view your view. Technically, chunks do not need their items unless they are in view, so maybe an InView field?)
	-- InView: boolean, -- Maybe add this; refer to above "---" line

	-- TODO: implement system that will instantly and efficiently recycle existing exposed items as you rotate your camera, so if something goes out of view but can be used just in a different part of the view, then use that item (make sure to benchmark this and everything)
}

--- Variables ---
local DEFAULT_MAX_GRID_SIZE = Vector3.one * (2 ^ 14) -- Number arbitrarily picked based off how stable looking Roblox rendering was at that position.
local DEFAULT_CHUNK_SIZE = 64 -- Size of each chunk in studs. Must be a multiple of 8 to avoid potential ReadVoxels instability.

--- Functions ---
local function ExpandVectorToGrid(vector: Vector3, resolution: number): Vector3
	return Vector3.new(
		math.ceil(vector.X / resolution) * resolution,
		math.ceil(vector.Y / resolution) * resolution,
		math.ceil(vector.Z / resolution) * resolution
	)
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
		GridWorldSize: Vector3, -- Optional maximum size of the grid in studs. If nil, the grid can grow to DEFAULT_MAX_GRID_SIZE.
		Chunks: { [number]: BaseChunkState<ChunkState> }, -- Table of chunks (can have holes) indexed by their chunk index. Chunks are stored in XYZ order exactly like terrain.
		_zeroBasedGridSize: Vector3, -- Equal to GridSize - Vector3.one. Used for bounds checking when clamping chunk indices.

		OnChunkGenerated: Signal.Signal<BaseChunkState<ChunkState>>,
	},
	Grid
))
function Grid.new<ChunkState>(center: Vector3, gridWorldSize: Vector3?, chunkSize: number?): Grid<ChunkState>
	chunkSize = chunkSize or DEFAULT_CHUNK_SIZE
	local alignedChunkSize = math.ceil(chunkSize / 8) * 8 -- Align chunk size to terrain resolution (8x8x8) to avoid potential ReadVoxels instability.
	local worldSpaceCenter = ExpandVectorToGrid(center, 4)
	local worldSpaceSize = ExpandVectorToGrid(gridWorldSize or DEFAULT_MAX_GRID_SIZE, 8)
	local gridSpaceSize = (worldSpaceSize / alignedChunkSize):Ceil()
	local grid: Grid<ChunkState> = setmetatable({
		Center = worldSpaceCenter,
		GenerationOrigin = worldSpaceCenter - (worldSpaceSize / 2) + (Vector3.one * (alignedChunkSize / 2)),
		ChunkSize = alignedChunkSize,
		GridSize = gridSpaceSize,
		GridWorldSize = worldSpaceSize,
		Chunks = {},
		_zeroBasedGridSize = gridSpaceSize - Vector3.one,

		OnChunkGenerated = Signal.new(),
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

function Grid.GetNearestChunkAtPosition<ChunkState>(self: Grid<ChunkState>, position: Vector3): BaseChunkState<ChunkState>?
	local chunkWorldPosition = position - self.GenerationOrigin
	local chunkGridPosition = chunkWorldPosition / self.ChunkSize
	local zeroBasedGridSize = self._zeroBasedGridSize
	local clampedChunkGridPosition = Vector3.new(
		math.clamp(math.floor(chunkGridPosition.X + 0.5), 0, zeroBasedGridSize.X),
		math.clamp(math.floor(chunkGridPosition.Y + 0.5), 0, zeroBasedGridSize.Y),
		math.clamp(math.floor(chunkGridPosition.Z + 0.5), 0, zeroBasedGridSize.Z)
	)
	return self.Chunks[self:GridPositionToChunkIndex(clampedChunkGridPosition)]
end

function Grid._GetNearestChunkIndexAtPosition<ChunkState>(self: Grid<ChunkState>, position: Vector3): number
	local chunkWorldPosition = position - self.GenerationOrigin
	local chunkGridPosition = chunkWorldPosition / self.ChunkSize
	local zeroBasedGridSize = self._zeroBasedGridSize
	local clampedChunkGridPosition = Vector3.new(
		math.clamp(math.floor(chunkGridPosition.X + 0.5), 0, zeroBasedGridSize.X),
		math.clamp(math.floor(chunkGridPosition.Y + 0.5), 0, zeroBasedGridSize.Y),
		math.clamp(math.floor(chunkGridPosition.Z + 0.5), 0, zeroBasedGridSize.Z)
	)
	return self:GridPositionToChunkIndex(clampedChunkGridPosition)
end

function Grid.GridPositionToWorldPosition(self: Grid<any>, gridPosition: Vector3): Vector3
	return self.GenerationOrigin + (gridPosition * self.ChunkSize)
end

function Grid.ChunkIndexToGridPosition(self: Grid<any>, chunkIndex: number): Vector3
	local gridSize = self.GridSize
	local sizeYZ, sizeZ = gridSize.Y * gridSize.Z, gridSize.Z
	local remainder = chunkIndex % sizeYZ
	return Vector3.new(chunkIndex // sizeYZ, remainder // sizeZ, remainder % sizeZ)
end

function Grid.GridPositionToChunkIndex(self: Grid<any>, gridPosition: Vector3): number
	local gridSize = self.GridSize
	local sizeYZ, sizeZ = gridSize.Y * gridSize.Z, gridSize.Z
	return (gridPosition.X * sizeYZ) + (gridPosition.Y * sizeZ) + gridPosition.Z
end

return table.freeze(Grid)
