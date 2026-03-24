--!strict
--[[
	Compares Grid (native vector) vs InfinigridBackup (Vector3)
	across all shared functions.

	Copy this into Studio as a Script under any container and run.
	Requires Benchmark.luau to be a sibling ModuleScript.
--]]

--- Imports ---
local Benchmark = require(script.Parent.Benchmark)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Classes = ReplicatedStorage.Shared.Common.Classes
local Grid = require(Classes.Grid)
local Infinigrid = require(Classes.InfinigridBackup)

--- Setup ---
-- Shared parameters: same center, world size, and chunk size for both grids.
local CENTER_VEC = vector.create(512, 256, 512)
local CENTER_V3 = Vector3.new(512, 256, 512)
local WORLD_SIZE_VEC = vector.create(2048, 1024, 2048)
local WORLD_SIZE_V3 = Vector3.new(2048, 1024, 2048)
local CHUNK_SIZE = 64

-- Pre-create the grids (construction cost is benchmarked separately).
local grid = Grid.new(CENTER_VEC, WORLD_SIZE_VEC, CHUNK_SIZE)
local infgrid = Infinigrid.new(CENTER_V3, WORLD_SIZE_V3, CHUNK_SIZE)

-- Pre-compute some test inputs so allocations don't pollute iteration timings.
-- Pick a variety of chunk indices spread across the grid.
local gridSizeX = grid.GridSize.x
local gridSizeY = grid.GridSize.y
local gridSizeZ = grid.GridSize.z
local maxIndex = (gridSizeX * gridSizeY * gridSizeZ) - 1

local TEST_CHUNK_INDICES: { number } = {}
do
	local step = math.max(1, maxIndex // 63) -- ~64 samples
	local idx = 1
	for i = 0, maxIndex, step do
		TEST_CHUNK_INDICES[idx] = i
		idx += 1
	end
end

-- Positions scattered around the grid's world-space volume.
local TEST_POSITIONS_VEC: { vector } = {}
local TEST_POSITIONS_V3: { Vector3 } = {}
do
	local origin = grid.GenerationOrigin
	local originInf = infgrid.GenerationOrigin
	for i, ci in TEST_CHUNK_INDICES do
		-- Convert to world position via the grid itself for accuracy.
		local gp = grid:ChunkIndexToGridPosition(ci)
		local wp = grid:GridPositionToWorldPosition(gp)
		TEST_POSITIONS_VEC[i] = wp
		-- Mirror for Infinigrid (Vector3).
		local gpInf = infgrid:ChunkIndexToGridPosition(ci)
		local wpInf = infgrid:GridPositionToWorldPosition(gpInf)
		TEST_POSITIONS_V3[i] = wpInf
	end
end

-- Pre-compute grid positions for GridPositionToWorldPosition / GridPositionToChunkIndex.
local TEST_GRID_POSITIONS_VEC: { vector } = {}
local TEST_GRID_POSITIONS_V3: { Vector3 } = {}
for i, ci in TEST_CHUNK_INDICES do
	local gp = grid:ChunkIndexToGridPosition(ci)
	TEST_GRID_POSITIONS_VEC[i] = gp
	local gpInf = infgrid:ChunkIndexToGridPosition(ci)
	TEST_GRID_POSITIONS_V3[i] = gpInf
end

local NUM_SAMPLES = #TEST_CHUNK_INDICES

--- Benchmark Config ---
local ITERATIONS = 5_000
local RUNS = 5
local OPTS: Benchmark.BenchOptions = { Silent = true, Warmup = 500 }

print("\n\n========  GRID vs INFINIGRID BENCHMARK  ========\n")

--------------------------------------------------
-- 1. Constructor: new()
--------------------------------------------------
print(">>> 1/6  Constructor")
Benchmark.CompareMany({
	{
		Name = "Grid.new",
		Fn = function()
			Grid.new(CENTER_VEC, WORLD_SIZE_VEC, CHUNK_SIZE)
		end,
	},
	{
		Name = "Infinigrid.new",
		Fn = function()
			Infinigrid.new(CENTER_V3, WORLD_SIZE_V3, CHUNK_SIZE)
		end,
	},
}, ITERATIONS, RUNS, OPTS)

--------------------------------------------------
-- 2. GetNearestChunkIndexAtPosition
--------------------------------------------------
print(">>> 2/6  GetNearestChunkIndexAtPosition")

local posIdx = 0
Benchmark.CompareMany({
	{
		Name = "Grid",
		Fn = function()
			posIdx = posIdx % NUM_SAMPLES + 1
			grid:GetNearestChunkIndexAtPosition(TEST_POSITIONS_VEC[posIdx])
		end,
	},
	{
		Name = "Infinigrid",
		Fn = function()
			posIdx = posIdx % NUM_SAMPLES + 1
			infgrid:_GetNearestChunkIndexAtPosition(TEST_POSITIONS_V3[posIdx])
		end,
	},
}, ITERATIONS, RUNS, OPTS)

--------------------------------------------------
-- 3. GetNeighborIndices
--------------------------------------------------
print(">>> 3/6  GetNeighborIndices")

local nbIdx = 0
Benchmark.CompareMany({
	{
		Name = "Grid",
		Fn = function()
			nbIdx = nbIdx % NUM_SAMPLES + 1
			grid:GetNeighborIndices(TEST_CHUNK_INDICES[nbIdx])
		end,
	},
	{
		Name = "Infinigrid",
		Fn = function()
			nbIdx = nbIdx % NUM_SAMPLES + 1
			infgrid:GetNeighborIndices(TEST_CHUNK_INDICES[nbIdx])
		end,
	},
}, ITERATIONS, RUNS, OPTS)

--------------------------------------------------
-- 4. ChunkIndexToGridPosition
--------------------------------------------------
print(">>> 4/6  ChunkIndexToGridPosition")

local ciIdx = 0
Benchmark.CompareMany({
	{
		Name = "Grid",
		Fn = function()
			ciIdx = ciIdx % NUM_SAMPLES + 1
			grid:ChunkIndexToGridPosition(TEST_CHUNK_INDICES[ciIdx])
		end,
	},
	{
		Name = "Infinigrid",
		Fn = function()
			ciIdx = ciIdx % NUM_SAMPLES + 1
			infgrid:ChunkIndexToGridPosition(TEST_CHUNK_INDICES[ciIdx])
		end,
	},
}, ITERATIONS, RUNS, OPTS)

--------------------------------------------------
-- 5. GridPositionToWorldPosition
--------------------------------------------------
print(">>> 5/6  GridPositionToWorldPosition")

local gpIdx = 0
Benchmark.CompareMany({
	{
		Name = "Grid",
		Fn = function()
			gpIdx = gpIdx % NUM_SAMPLES + 1
			grid:GridPositionToWorldPosition(TEST_GRID_POSITIONS_VEC[gpIdx])
		end,
	},
	{
		Name = "Infinigrid",
		Fn = function()
			gpIdx = gpIdx % NUM_SAMPLES + 1
			infgrid:GridPositionToWorldPosition(TEST_GRID_POSITIONS_V3[gpIdx])
		end,
	},
}, ITERATIONS, RUNS, OPTS)

--------------------------------------------------
-- 6. GridPositionToChunkIndex
--------------------------------------------------
print(">>> 6/6  GridPositionToChunkIndex")

local gpiIdx = 0
Benchmark.CompareMany({
	{
		Name = "Grid",
		Fn = function()
			gpiIdx = gpiIdx % NUM_SAMPLES + 1
			grid:GridPositionToChunkIndex(TEST_GRID_POSITIONS_VEC[gpiIdx])
		end,
	},
	{
		Name = "Infinigrid",
		Fn = function()
			gpiIdx = gpiIdx % NUM_SAMPLES + 1
			infgrid:GridPositionToChunkIndex(TEST_GRID_POSITIONS_V3[gpiIdx])
		end,
	},
}, ITERATIONS, RUNS, OPTS)

print("\n========  BENCHMARK COMPLETE  ========\n")
