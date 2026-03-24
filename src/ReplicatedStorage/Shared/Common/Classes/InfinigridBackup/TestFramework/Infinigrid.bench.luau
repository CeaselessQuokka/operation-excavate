--[[
	Benchmarks for Infinigrid.
	Measures construction, index/position conversions, chunk lookup, neighbor
	queries, and bulk throughput using DiagnosticHelper's per-call sampling.

	Each section has a header describing what is being measured, why it matters,
	and how many iterations it runs.

	Usage (from a Roblox script):
		require(path.to.TestFramework["Infinigrid.bench"])
--]]

--!strict

--- Services ---
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--- Imports ---
local DiagnosticHelper = require(ReplicatedStorage.Shared.Helpers.DiagnosticHelper)
local Grid = require(script.Parent.Parent)

--- Variables ---
local ITERATIONS = 10_000

--- Benchmarks ---
local diag = DiagnosticHelper.new("Infinigrid Benchmark", {
	TimeUnit = "ms",
	DecimalPlaces = 4,
	MaxSamples = ITERATIONS,
})

print("")
print("======================================================================")
print("  INFINIGRID BENCHMARK SUITE")
print("======================================================================")
print(`  Iterations per test : {ITERATIONS}`)
print("======================================================================")

-- ============================================================
-- [1] Grid.new() — Constructor Performance
-- Measures the cost of creating a new grid instance with
-- Grid.new(). Construction includes ceil-aligning the center
-- to the 4-stud terrain grid, aligning chunk size to 8-stud
-- multiples, expanding GridWorldSize to 8-stud multiples,
-- computing GenerationOrigin and GridSize, and creating the
-- OnChunkGenerated signal. This is the hot path for dynamic
-- grid creation and respawning.
-- ============================================================

print("")
print("  [1] Grid.new() — Constructor Performance")
print("  How long does it take to create a grid under different configs?")
print("----------------------------------------------------------------------")

for _ = 1, ITERATIONS do
	diag:StartTimer("Grid.new(center, worldSize) — default 64-stud chunks")
	Grid.new(Vector3.zero, Vector3.new(64, 64, 64))
	diag:StopTimer("Grid.new(center, worldSize) — default 64-stud chunks")
end

for _ = 1, ITERATIONS do
	diag:StartTimer("Grid.new(center, worldSize, 8) — explicit 8-stud chunks")
	Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
	diag:StopTimer("Grid.new(center, worldSize, 8) — explicit 8-stud chunks")
end

for _ = 1, ITERATIONS do
	diag:StartTimer("Grid.new(unaligned center) — triggers ceil alignment")
	Grid.new(Vector3.new(1, 3, 5), Vector3.new(64, 64, 64), 8)
	diag:StopTimer("Grid.new(unaligned center) — triggers ceil alignment")
end

for _ = 1, ITERATIONS do
	diag:StartTimer("Grid.new(chunkSize=10) — triggers chunk size alignment to 16")
	Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 10)
	diag:StopTimer("Grid.new(chunkSize=10) — triggers chunk size alignment to 16")
end

for _ = 1, ITERATIONS do
	diag:StartTimer("Grid.new(center only) — default max world size")
	Grid.new(Vector3.zero)
	diag:StopTimer("Grid.new(center only) — default max world size")
end

for _ = 1, ITERATIONS do
	diag:StartTimer("Grid.new(512³ world, 8-stud chunks) — large grid (64³ cells)")
	Grid.new(Vector3.zero, Vector3.new(512, 512, 512), 8)
	diag:StopTimer("Grid.new(512³ world, 8-stud chunks) — large grid (64³ cells)")
end

-- ============================================================
-- [2] GridPositionToChunkIndex / ChunkIndexToGridPosition /
--     GridPositionToWorldPosition
-- Measures the arithmetic cost of converting between:
--   • Grid positions (Vector3 in grid space) and flat chunk
--     indices (row-major XYZ order: Z fastest, X slowest).
--   • Grid positions and world positions (offset from
--     GenerationOrigin by gridPosition * ChunkSize).
-- These are the most frequently called methods during chunk
-- generation, spatial queries, and neighbor lookups.
-- ============================================================

print("")
print("  [2] Index / Position Conversion Methods")
print("  Per-call cost of GridPositionToChunkIndex, ChunkIndexToGridPosition,")
print("  and GridPositionToWorldPosition on small (8³) and large (64³) grids.")
print("----------------------------------------------------------------------")

local smallGrid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8) -- GridSize=8×8×8 → 512 chunks
local largeGrid = Grid.new(Vector3.zero, Vector3.new(512, 512, 512), 8) -- GridSize=64×64×64 → 262,144 chunks

for _ = 1, ITERATIONS do
	diag:StartTimer("GridPositionToChunkIndex — 8³ grid (512 chunks)")
	smallGrid:GridPositionToChunkIndex(Vector3.new(4, 5, 3))
	diag:StopTimer("GridPositionToChunkIndex — 8³ grid (512 chunks)")
end

for _ = 1, ITERATIONS do
	diag:StartTimer("GridPositionToChunkIndex — 64³ grid (262K chunks)")
	largeGrid:GridPositionToChunkIndex(Vector3.new(32, 48, 17))
	diag:StopTimer("GridPositionToChunkIndex — 64³ grid (262K chunks)")
end

for _ = 1, ITERATIONS do
	diag:StartTimer("ChunkIndexToGridPosition — 8³ grid, index 256 (middle)")
	smallGrid:ChunkIndexToGridPosition(256)
	diag:StopTimer("ChunkIndexToGridPosition — 8³ grid, index 256 (middle)")
end

for _ = 1, ITERATIONS do
	diag:StartTimer("ChunkIndexToGridPosition — 64³ grid, index 131072 (middle)")
	largeGrid:ChunkIndexToGridPosition(131072)
	diag:StopTimer("ChunkIndexToGridPosition — 64³ grid, index 131072 (middle)")
end

for _ = 1, ITERATIONS do
	diag:StartTimer("GridPositionToWorldPosition — 8³ grid")
	smallGrid:GridPositionToWorldPosition(Vector3.new(4, 5, 3))
	diag:StopTimer("GridPositionToWorldPosition — 8³ grid")
end

for _ = 1, ITERATIONS do
	diag:StartTimer("GridPositionToWorldPosition — 64³ grid")
	largeGrid:GridPositionToWorldPosition(Vector3.new(32, 48, 17))
	diag:StopTimer("GridPositionToWorldPosition — 64³ grid")
end

for _ = 1, ITERATIONS do
	diag:StartTimer("ChunkIndex→GridPosition→WorldPosition pipeline — 8³ grid")
	local pos = smallGrid:ChunkIndexToGridPosition(256)
	smallGrid:GridPositionToWorldPosition(pos)
	diag:StopTimer("ChunkIndex→GridPosition→WorldPosition pipeline — 8³ grid")
end

-- ============================================================
-- [3] GetNearestChunkAtPosition
-- Measures world-position-to-chunk lookup. Internally this
-- subtracts GenerationOrigin, divides by ChunkSize, clamps to
-- grid bounds, and performs a table lookup in self.Chunks.
--
-- Tested scenarios:
--   • Hit: chunk exists at the queried position
--   • Miss: grid is empty, so lookup returns nil
--   • 1-stud offset: query is 1 stud away from chunk center
--     (tests the floor+0.5 rounding path)
--   • Non-zero center: center is at (500,500,500) to exercise
--     the GenerationOrigin subtraction path
--   • Large grid: 64³ grid (262K chunks) to measure hash
--     table performance at scale
-- ============================================================

print("")
print("  [3] GetNearestChunkAtPosition — World Position Chunk Lookup")
print("  How fast can we find which chunk contains a given world position?")
print("----------------------------------------------------------------------")

do
	local lookupGrid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
	for i = 0, 511 do
		local pos = lookupGrid:ChunkIndexToGridPosition(i)
		lookupGrid.Chunks[i] = { ChunkIndex = i, ChunkPosition = pos } :: any
	end
	local queryWorldPos = lookupGrid:GridPositionToWorldPosition(Vector3.new(4, 5, 3))

	for _ = 1, ITERATIONS do
		diag:StartTimer("GetNearestChunkAtPosition — 8³ grid, populated (chunk found)")
		lookupGrid:GetNearestChunkAtPosition(queryWorldPos)
		diag:StopTimer("GetNearestChunkAtPosition — 8³ grid, populated (chunk found)")
	end

	local emptyGrid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
	for _ = 1, ITERATIONS do
		diag:StartTimer("GetNearestChunkAtPosition — 8³ grid, empty (returns nil)")
		emptyGrid:GetNearestChunkAtPosition(queryWorldPos)
		diag:StopTimer("GetNearestChunkAtPosition — 8³ grid, empty (returns nil)")
	end

	local offsetPos = queryWorldPos + Vector3.new(1, 1, 1)
	for _ = 1, ITERATIONS do
		diag:StartTimer("GetNearestChunkAtPosition — 8³ grid, +1 stud offset (rounding)")
		lookupGrid:GetNearestChunkAtPosition(offsetPos)
		diag:StopTimer("GetNearestChunkAtPosition — 8³ grid, +1 stud offset (rounding)")
	end
end

do
	local offsetGrid = Grid.new(Vector3.new(500, 500, 500), Vector3.new(64, 64, 64), 8)
	for i = 0, 511 do
		local pos = offsetGrid:ChunkIndexToGridPosition(i)
		offsetGrid.Chunks[i] = { ChunkIndex = i, ChunkPosition = pos } :: any
	end
	local offsetQueryPos = offsetGrid:GridPositionToWorldPosition(Vector3.new(4, 5, 3))

	for _ = 1, ITERATIONS do
		diag:StartTimer("GetNearestChunkAtPosition — 8³ grid, center=(500,500,500)")
		offsetGrid:GetNearestChunkAtPosition(offsetQueryPos)
		diag:StopTimer("GetNearestChunkAtPosition — 8³ grid, center=(500,500,500)")
	end
end

do
	local bigLookupGrid = Grid.new(Vector3.zero, Vector3.new(512, 512, 512), 8)
	for i = 0, 262143 do
		local pos = bigLookupGrid:ChunkIndexToGridPosition(i)
		bigLookupGrid.Chunks[i] = { ChunkIndex = i, ChunkPosition = pos } :: any
	end
	local bigQueryPos = bigLookupGrid:GridPositionToWorldPosition(Vector3.new(32, 48, 17))

	for _ = 1, ITERATIONS do
		diag:StartTimer("GetNearestChunkAtPosition — 64³ grid (262K chunks), populated")
		bigLookupGrid:GetNearestChunkAtPosition(bigQueryPos)
		diag:StopTimer("GetNearestChunkAtPosition — 64³ grid (262K chunks), populated")
	end
end

-- ============================================================
-- [4] _GetNearestChunkIndexAtPosition (internal)
-- Same algorithm as GetNearestChunkAtPosition but returns the
-- raw chunk index (number) instead of doing the Chunks table
-- lookup. Used internally when only the index is needed.
-- Compared against GetNearestChunkAtPosition to measure the
-- cost of the table lookup itself.
-- ============================================================

print("")
print("  [4] _GetNearestChunkIndexAtPosition — Index-Only Lookup (internal)")
print("  Same math as GetNearestChunkAtPosition but skips the Chunks table read.")
print("----------------------------------------------------------------------")

do
	local indexGrid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
	local queryWorldPos = indexGrid:GridPositionToWorldPosition(Vector3.new(4, 5, 3))

	for _ = 1, ITERATIONS do
		diag:StartTimer("_GetNearestChunkIndexAtPosition — 8³ grid")
		indexGrid:_GetNearestChunkIndexAtPosition(queryWorldPos)
		diag:StopTimer("_GetNearestChunkIndexAtPosition — 8³ grid")
	end

	local bigIndexGrid = Grid.new(Vector3.zero, Vector3.new(512, 512, 512), 8)
	local bigQueryPos = bigIndexGrid:GridPositionToWorldPosition(Vector3.new(32, 48, 17))

	for _ = 1, ITERATIONS do
		diag:StartTimer("_GetNearestChunkIndexAtPosition — 64³ grid")
		bigIndexGrid:_GetNearestChunkIndexAtPosition(bigQueryPos)
		diag:StopTimer("_GetNearestChunkIndexAtPosition — 64³ grid")
	end

	local offsetQueryPos = queryWorldPos + Vector3.new(1, 1, 1)
	for _ = 1, ITERATIONS do
		diag:StartTimer("_GetNearestChunkIndexAtPosition — 8³ grid, +1 stud offset")
		indexGrid:_GetNearestChunkIndexAtPosition(offsetQueryPos)
		diag:StopTimer("_GetNearestChunkIndexAtPosition — 8³ grid, +1 stud offset")
	end
end

-- ============================================================
-- [5] GetNeighborIndices
-- Measures the cost of computing the 6-directional (±X, ±Y,
-- ±Z) neighbor indices for a given chunk. Internally this
-- performs modular arithmetic and bounds checking against
-- _theoreticalMaxChunkIndex and GridSize to determine valid
-- neighbors. Tested at:
--   • Interior chunk (has all 6 neighbors)
--   • Corner chunk at (0,0,0) (has only 3 neighbors)
--   • Edge chunk (has 4-5 neighbors)
--   • Large grid to measure scaling
-- ============================================================

print("")
print("  [5] GetNeighborIndices — 6-Directional Neighbor Lookup")
print("  How fast can we compute the ±X, ±Y, ±Z neighbor indices for a chunk?")
print("----------------------------------------------------------------------")

do
	-- Interior chunk: all 6 neighbors valid
	local interiorIndex = smallGrid:GridPositionToChunkIndex(Vector3.new(4, 4, 4))
	for _ = 1, ITERATIONS do
		diag:StartTimer("GetNeighborIndices — 8³ grid, interior (6 neighbors)")
		smallGrid:GetNeighborIndices(interiorIndex)
		diag:StopTimer("GetNeighborIndices — 8³ grid, interior (6 neighbors)")
	end

	-- Corner chunk at origin: only +X, +Y, +Z valid (3 neighbors)
	local cornerIndex = smallGrid:GridPositionToChunkIndex(Vector3.zero)
	for _ = 1, ITERATIONS do
		diag:StartTimer("GetNeighborIndices — 8³ grid, corner at (0,0,0) (3 neighbors)")
		smallGrid:GetNeighborIndices(cornerIndex)
		diag:StopTimer("GetNeighborIndices — 8³ grid, corner at (0,0,0) (3 neighbors)")
	end

	-- Edge chunk: some neighbors valid, some not
	local edgeIndex = smallGrid:GridPositionToChunkIndex(Vector3.new(0, 4, 4))
	for _ = 1, ITERATIONS do
		diag:StartTimer("GetNeighborIndices — 8³ grid, edge chunk (5 neighbors)")
		smallGrid:GetNeighborIndices(edgeIndex)
		diag:StopTimer("GetNeighborIndices — 8³ grid, edge chunk (5 neighbors)")
	end

	-- Far corner chunk: (7,7,7) — only -X, -Y, -Z valid (3 neighbors)
	local farCornerIndex = smallGrid:GridPositionToChunkIndex(Vector3.new(7, 7, 7))
	for _ = 1, ITERATIONS do
		diag:StartTimer("GetNeighborIndices — 8³ grid, far corner (7,7,7) (3 neighbors)")
		smallGrid:GetNeighborIndices(farCornerIndex)
		diag:StopTimer("GetNeighborIndices — 8³ grid, far corner (7,7,7) (3 neighbors)")
	end

	-- Large grid interior
	local largeInteriorIndex = largeGrid:GridPositionToChunkIndex(Vector3.new(32, 32, 32))
	for _ = 1, ITERATIONS do
		diag:StartTimer("GetNeighborIndices — 64³ grid, interior (6 neighbors)")
		largeGrid:GetNeighborIndices(largeInteriorIndex)
		diag:StopTimer("GetNeighborIndices — 64³ grid, interior (6 neighbors)")
	end
end

-- ============================================================
-- Results
-- ============================================================

print("")
print("======================================================================")
print("  RESULTS")
print("======================================================================")

diag:PrintBreakdown(true)
diag:Destroy()

print("")
print("======================================================================")
print("  BENCHMARK COMPLETE")
print("======================================================================")

return true
