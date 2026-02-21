--[[
	Benchmarks for Infinigrid.
	Measures construction, index/position conversions, chunk lookup, and bulk
	throughput using DiagnosticHelper's per-call sampling.

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
local BULK_ITERATIONS = 500

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
print(`  Bulk iterations     : {BULK_ITERATIONS}`)
print("======================================================================")

-- ============================================================
-- [1] Grid Construction
-- Measures the cost of Grid.new() under various parameter
-- combinations. Construction includes ceil-alignment of the
-- center, chunk size, and world size, plus computing the
-- GenerationOrigin and GridSize. Hot path for dynamic grid
-- creation / respawning.
-- ============================================================

print("")
print("  [1] Grid Construction")
print("  Measures Grid.new() throughput with different parameter types.")
print("----------------------------------------------------------------------")

for _ = 1, ITERATIONS do
	diag:StartTimer("Construct — Default chunk size")
	Grid.new(Vector3.zero, Vector3.new(64, 64, 64))
	diag:StopTimer("Construct — Default chunk size")
end

for _ = 1, ITERATIONS do
	diag:StartTimer("Construct — Custom chunk size (8)")
	Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
	diag:StopTimer("Construct — Custom chunk size (8)")
end

for _ = 1, ITERATIONS do
	diag:StartTimer("Construct — Unaligned center")
	Grid.new(Vector3.new(1, 3, 5), Vector3.new(64, 64, 64), 8)
	diag:StopTimer("Construct — Unaligned center")
end

for _ = 1, ITERATIONS do
	diag:StartTimer("Construct — Unaligned chunk size (10)")
	Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 10)
	diag:StopTimer("Construct — Unaligned chunk size (10)")
end

for _ = 1, ITERATIONS do
	diag:StartTimer("Construct — Default world (max)")
	Grid.new(Vector3.zero)
	diag:StopTimer("Construct — Default world (max)")
end

for _ = 1, ITERATIONS do
	diag:StartTimer("Construct — Large world (512³)")
	Grid.new(Vector3.zero, Vector3.new(512, 512, 512), 8)
	diag:StopTimer("Construct — Large world (512³)")
end

-- ============================================================
-- [2] Index / Position Conversion
-- Measures the arithmetic cost of converting between grid
-- positions and flat chunk indices, and from grid positions to
-- world positions. These are the most frequently called methods
-- during chunk generation and spatial queries.
-- ============================================================

print("")
print("  [2] Index / Position Conversion")
print("  Measures per-call cost of the core mapping functions.")
print("----------------------------------------------------------------------")

local smallGrid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8) -- 8x8x8 = 512 chunks
local largeGrid = Grid.new(Vector3.zero, Vector3.new(512, 512, 512), 8) -- 64x64x64 = 262,144 chunks

for _ = 1, ITERATIONS do
	diag:StartTimer("GridPos→Index — 8³ grid")
	smallGrid:GridPositionToChunkIndex(Vector3.new(4, 5, 3))
	diag:StopTimer("GridPos→Index — 8³ grid")
end

for _ = 1, ITERATIONS do
	diag:StartTimer("GridPos→Index — 64³ grid")
	largeGrid:GridPositionToChunkIndex(Vector3.new(32, 48, 17))
	diag:StopTimer("GridPos→Index — 64³ grid")
end

for _ = 1, ITERATIONS do
	diag:StartTimer("Index→GridPos — 8³ grid")
	smallGrid:ChunkIndexToGridPosition(256)
	diag:StopTimer("Index→GridPos — 8³ grid")
end

for _ = 1, ITERATIONS do
	diag:StartTimer("Index→GridPos — 64³ grid")
	largeGrid:ChunkIndexToGridPosition(131072)
	diag:StopTimer("Index→GridPos — 64³ grid")
end

for _ = 1, ITERATIONS do
	diag:StartTimer("GridPos→WorldPos — 8³ grid")
	smallGrid:GridPositionToWorldPosition(Vector3.new(4, 5, 3))
	diag:StopTimer("GridPos→WorldPos — 8³ grid")
end

for _ = 1, ITERATIONS do
	diag:StartTimer("GridPos→WorldPos — 64³ grid")
	largeGrid:GridPositionToWorldPosition(Vector3.new(32, 48, 17))
	diag:StopTimer("GridPos→WorldPos — 64³ grid")
end

for _ = 1, ITERATIONS do
	diag:StartTimer("Full pipeline — Index→GridPos→WorldPos (8³)")
	local pos = smallGrid:ChunkIndexToGridPosition(256)
	smallGrid:GridPositionToWorldPosition(pos)
	diag:StopTimer("Full pipeline — Index→GridPos→WorldPos (8³)")
end

-- ============================================================
-- [3] GetChunkAtPosition
-- Measures world-position-to-chunk lookup, which internally
-- rounds the position to the terrain grid and performs a hash
-- table lookup. Tested under hit (chunk exists), miss (empty
-- grid), offset (query inside chunk but not at corner), and
-- with a non-zero center to exercise the GenerationOrigin
-- subtraction path.
-- ============================================================

print("")
print("  [3] GetChunkAtPosition")
print("  Measures chunk lookup from world coordinates.")
print("----------------------------------------------------------------------")

do
	local lookupGrid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
	for i = 0, 511 do
		local pos = lookupGrid:ChunkIndexToGridPosition(i)
		lookupGrid.Chunks[i] = { ChunkIndex = i, ChunkPosition = pos } :: any
	end
	local queryWorldPos = lookupGrid:GridPositionToWorldPosition(Vector3.new(4, 5, 3))

	for _ = 1, ITERATIONS do
		diag:StartTimer("ChunkLookup — 8³, cache hit")
		lookupGrid:GetChunkAtPosition(queryWorldPos)
		diag:StopTimer("ChunkLookup — 8³, cache hit")
	end

	local emptyGrid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
	for _ = 1, ITERATIONS do
		diag:StartTimer("ChunkLookup — 8³, cache miss")
		emptyGrid:GetChunkAtPosition(queryWorldPos)
		diag:StopTimer("ChunkLookup — 8³, cache miss")
	end

	local offsetPos = queryWorldPos + Vector3.new(1, 1, 1)
	for _ = 1, ITERATIONS do
		diag:StartTimer("ChunkLookup — 8³, 1-stud offset")
		lookupGrid:GetChunkAtPosition(offsetPos)
		diag:StopTimer("ChunkLookup — 8³, 1-stud offset")
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
		diag:StartTimer("ChunkLookup — 8³, non-zero center")
		offsetGrid:GetChunkAtPosition(offsetQueryPos)
		diag:StopTimer("ChunkLookup — 8³, non-zero center")
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
		diag:StartTimer("ChunkLookup — 64³, cache hit")
		bigLookupGrid:GetChunkAtPosition(bigQueryPos)
		diag:StopTimer("ChunkLookup — 64³, cache hit")
	end
end

-- ============================================================
-- [4] Bulk Operations
-- Measures throughput of processing all 512 chunks in a single
-- pass. This simulates real workloads like full-grid iteration,
-- chunk generation sweeps, and spatial query across all chunks.
-- Each timer captures one complete pass over 512 chunks.
-- ============================================================

print("")
print("  [4] Bulk Operations (512 chunks per pass)")
print("  Measures full-sweep throughput for batch processing.")
print("----------------------------------------------------------------------")

for _ = 1, BULK_ITERATIONS do
	diag:StartTimer("Bulk — Index↔GridPos round-trip ×512 (8³)")
	for i = 0, 511 do
		local pos = smallGrid:ChunkIndexToGridPosition(i)
		smallGrid:GridPositionToChunkIndex(pos)
	end
	diag:StopTimer("Bulk — Index↔GridPos round-trip ×512 (8³)")
end

for _ = 1, BULK_ITERATIONS do
	diag:StartTimer("Bulk — Index↔GridPos round-trip ×512 (64³)")
	for i = 0, 511 do
		local pos = largeGrid:ChunkIndexToGridPosition(i)
		largeGrid:GridPositionToChunkIndex(pos)
	end
	diag:StopTimer("Bulk — Index↔GridPos round-trip ×512 (64³)")
end

for _ = 1, BULK_ITERATIONS do
	diag:StartTimer("Bulk — Enumerate all 512 via nested XYZ (8³)")
	local gs = smallGrid.GridSize
	for x = 0, gs.X - 1 do
		for y = 0, gs.Y - 1 do
			for z = 0, gs.Z - 1 do
				smallGrid:GridPositionToChunkIndex(Vector3.new(x, y, z))
			end
		end
	end
	diag:StopTimer("Bulk — Enumerate all 512 via nested XYZ (8³)")
end

for _ = 1, BULK_ITERATIONS do
	diag:StartTimer("Bulk — Full pipeline ×512 (Index→Pos→World)")
	for i = 0, 511 do
		local pos = smallGrid:ChunkIndexToGridPosition(i)
		smallGrid:GridPositionToWorldPosition(pos)
	end
	diag:StopTimer("Bulk — Full pipeline ×512 (Index→Pos→World)")
end

do
	local bulkLookupGrid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
	for i = 0, 511 do
		local pos = bulkLookupGrid:ChunkIndexToGridPosition(i)
		bulkLookupGrid.Chunks[i] = { ChunkIndex = i, ChunkPosition = pos } :: any
	end

	for _ = 1, BULK_ITERATIONS do
		diag:StartTimer("Bulk — GetChunkAtPosition ×512 (8³)")
		for i = 0, 511 do
			local pos = bulkLookupGrid:ChunkIndexToGridPosition(i)
			local worldPos = bulkLookupGrid:GridPositionToWorldPosition(pos)
			bulkLookupGrid:GetChunkAtPosition(worldPos)
		end
		diag:StopTimer("Bulk — GetChunkAtPosition ×512 (8³)")
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
