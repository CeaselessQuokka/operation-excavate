--!strict
--- Types ---
export type ChunkIndex = number

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

export type Grid = setmetatable<
	{

		Center: Vector3, -- World-space position of the grid's center.
		GenerationOrigin: Vector3, -- World-space position of the grid's generation origin.
		ChunkSize: number, -- Size of each chunk in studs (cubed).
		GridSize: Vector3, -- Size of the grid in grid space. Calculated as GridWorldSize / ChunkSize.
		GridWorldSize: Vector3, -- Optional maximum size of the grid in studs. If nil, the grid can grow to DEFAULT_MAX_GRID_SIZE.
		_zeroBasedGridSize: Vector3, -- Equal to GridSize - Vector3.one. Used for bounds checking when clamping chunk indices.
		_theoreticalMaxChunkIndex: number, -- Used for bounds checking when clamping chunk indices.
	},
	typeof(Grid)
>
function Grid.new(center: Vector3, gridWorldSize: Vector3, chunkSize: number): Grid
	local alignedChunkSize = math.ceil(chunkSize / 8) * 8 -- Align chunk size to terrain resolution (8x8x8) to avoid potential ReadVoxels instability.
	local worldSpaceCenter = ExpandVectorToGrid(center, 4)
	local worldSpaceSize = ExpandVectorToGrid(gridWorldSize, 8)
	local gridSpaceSize = (worldSpaceSize / alignedChunkSize):Ceil()
	local grid: Grid = setmetatable({
		Center = worldSpaceCenter,
		GenerationOrigin = worldSpaceCenter - (worldSpaceSize / 2) + (Vector3.one * (alignedChunkSize / 2)),
		ChunkSize = alignedChunkSize,
		GridSize = gridSpaceSize,
		GridWorldSize = worldSpaceSize,
		_zeroBasedGridSize = gridSpaceSize - Vector3.one,
		_theoreticalMaxChunkIndex = (gridSpaceSize.X * gridSpaceSize.Y * gridSpaceSize.Z) - 1,
	}, Grid)
	if not grid.Center:FuzzyEq(center) then
		warn(
			`Grid center {center} was expanded to {grid.Center} to align with terrain resolution (4x4x4). This may cause unexpected behavior if you were relying on the original center.`
		)
	end
	if not grid.GridWorldSize:FuzzyEq(gridWorldSize) then
		warn(
			`Grid world size {gridWorldSize} was expanded to {grid.GridWorldSize} to align with terrain resolution (8x8x8). This may cause unexpected behavior if you were relying on the original world size.`
		)
	end
	if grid.ChunkSize ~= chunkSize then
		warn(
			`Chunk size {chunkSize} was expanded to {grid.ChunkSize} to align with terrain resolution (8x8x8). This may cause unexpected behavior if you were relying on the original chunk size.`
		)
	end
	return grid
end

function Grid.GetNearestChunkIndexAtPosition(self: Grid, position: Vector3): number
	local chunkGridPosition = (position - self.GenerationOrigin) / self.ChunkSize
	local zeroBasedGridSize = self._zeroBasedGridSize
	local sizeZ = self.GridSize.Z
	local x = math.clamp(math.round(chunkGridPosition.X), 0, zeroBasedGridSize.X)
	local y = math.clamp(math.round(chunkGridPosition.Y), 0, zeroBasedGridSize.Y)
	local z = math.clamp(math.round(chunkGridPosition.Z), 0, zeroBasedGridSize.Z)
	return (x * self.GridSize.Y * sizeZ) + (y * sizeZ) + z
end

function Grid.GetNeighborIndices(self: Grid, chunkIndex: ChunkIndex): { ChunkIndex }
	local neighborIndex = 1
	local neighboringChunks: { ChunkIndex } = {}
	local gridSize = self.GridSize
	local sizeY, sizeZ = gridSize.Y, gridSize.Z
	local sizeYZ = sizeY * sizeZ
	local chunkYCoordinate, chunkZCoordinate = (chunkIndex % sizeYZ) // sizeZ, chunkIndex % sizeZ
	if chunkIndex >= sizeYZ then -- Left chunk.
		neighboringChunks[neighborIndex] = chunkIndex - sizeYZ
		neighborIndex += 1
	end
	if chunkIndex + sizeYZ <= self._theoreticalMaxChunkIndex then -- Right chunk.
		neighboringChunks[neighborIndex] = chunkIndex + sizeYZ
		neighborIndex += 1
	end
	if chunkZCoordinate > 0 then -- Back chunk.
		neighboringChunks[neighborIndex] = chunkIndex - 1
		neighborIndex += 1
	end
	if chunkZCoordinate < sizeZ - 1 then -- Front chunk.
		neighboringChunks[neighborIndex] = chunkIndex + 1
		neighborIndex += 1
	end
	if chunkYCoordinate > 0 then -- Bottom chunk.
		neighboringChunks[neighborIndex] = chunkIndex - sizeZ
		neighborIndex += 1
	end
	if chunkYCoordinate < sizeY - 1 then -- Top chunk.
		neighboringChunks[neighborIndex] = chunkIndex + sizeZ
	end
	return neighboringChunks
end

function Grid.ChunkIndexToGridPosition(self: Grid, chunkIndex: number): Vector3
	local gridSize = self.GridSize
	local sizeYZ, sizeZ = gridSize.Y * gridSize.Z, gridSize.Z
	local remainder = chunkIndex % sizeYZ
	return Vector3.new(chunkIndex // sizeYZ, remainder // sizeZ, remainder % sizeZ)
end

function Grid.GridPositionToWorldPosition(self: Grid, gridPosition: Vector3): Vector3
	return self.GenerationOrigin + (gridPosition * self.ChunkSize)
end

function Grid.ChunkIndexToWorldPosition(self: Grid, chunkIndex: number): Vector3
	return self.GenerationOrigin + (self.ChunkIndexToGridPosition(self, chunkIndex) * self.ChunkSize)
end

function Grid.GridPositionToChunkIndex(self: Grid, gridPosition: Vector3): number
	local gridSize = self.GridSize
	local sizeYZ, sizeZ = gridSize.Y * gridSize.Z, gridSize.Z
	return (gridPosition.X * sizeYZ) + (gridPosition.Y * sizeZ) + gridPosition.Z
end

return table.freeze(Grid)
