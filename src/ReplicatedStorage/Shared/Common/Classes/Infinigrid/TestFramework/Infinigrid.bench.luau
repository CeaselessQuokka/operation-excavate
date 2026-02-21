--[[
	Benchmark for Infinigrid construction and index/position conversions.
	Uses DiagnosticHelper for detailed per-call statistics.

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

--- Benchmark ---
local diag = DiagnosticHelper.new("Infinigrid Benchmark", {
	TimeUnit = "ms",
	DecimalPlaces = 4,
	MaxSamples = ITERATIONS,
})

-- Construction --
for _ = 1, ITERATIONS do
	diag:StartTimer("new (aligned, default chunk)")
	Grid.new(Vector3.zero, Vector3.new(64, 64, 64))
	diag:StopTimer("new (aligned, default chunk)")
end

for _ = 1, ITERATIONS do
	diag:StartTimer("new (aligned, custom chunk)")
	Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
	diag:StopTimer("new (aligned, custom chunk)")
end

for _ = 1, ITERATIONS do
	diag:StartTimer("new (unaligned center)")
	Grid.new(Vector3.new(1, 3, 5), Vector3.new(64, 64, 64), 8)
	diag:StopTimer("new (unaligned center)")
end

for _ = 1, ITERATIONS do
	diag:StartTimer("new (unaligned chunk)")
	Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 10)
	diag:StopTimer("new (unaligned chunk)")
end

for _ = 1, ITERATIONS do
	diag:StartTimer("new (default world)")
	Grid.new(Vector3.zero)
	diag:StopTimer("new (default world)")
end

for _ = 1, ITERATIONS do
	diag:StartTimer("new (large world)")
	Grid.new(Vector3.zero, Vector3.new(512, 512, 512), 8)
	diag:StopTimer("new (large world)")
end

-- Index / Position Conversion --
local smallGrid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8) -- 8×8×8
local largeGrid = Grid.new(Vector3.zero, Vector3.new(512, 512, 512), 8) -- 64×64×64

for _ = 1, ITERATIONS do
	diag:StartTimer("PosToIndex (8³)")
	smallGrid:GridPositionToChunkIndex(Vector3.new(4, 5, 3))
	diag:StopTimer("PosToIndex (8³)")
end

for _ = 1, ITERATIONS do
	diag:StartTimer("PosToIndex (64³)")
	largeGrid:GridPositionToChunkIndex(Vector3.new(32, 48, 17))
	diag:StopTimer("PosToIndex (64³)")
end

for _ = 1, ITERATIONS do
	diag:StartTimer("IndexToPos (8³)")
	smallGrid:ChunkIndexToGridPosition(256)
	diag:StopTimer("IndexToPos (8³)")
end

for _ = 1, ITERATIONS do
	diag:StartTimer("IndexToPos (64³)")
	largeGrid:ChunkIndexToGridPosition(131072)
	diag:StopTimer("IndexToPos (64³)")
end

for _ = 1, ITERATIONS do
	diag:StartTimer("PosToWorld (8³)")
	smallGrid:GridPositionToWorldPosition(Vector3.new(4, 5, 3))
	diag:StopTimer("PosToWorld (8³)")
end

for _ = 1, ITERATIONS do
	diag:StartTimer("PosToWorld (64³)")
	largeGrid:GridPositionToWorldPosition(Vector3.new(32, 48, 17))
	diag:StopTimer("PosToWorld (64³)")
end

for _ = 1, ITERATIONS do
	diag:StartTimer("FullPipeline (8³)")
	local pos = smallGrid:ChunkIndexToGridPosition(256)
	smallGrid:GridPositionToWorldPosition(pos)
	diag:StopTimer("FullPipeline (8³)")
end

-- GetChunkAtPosition --
do
	-- Populate some chunks for lookup testing.
	local lookupGrid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
	for i = 0, 511 do
		local pos = lookupGrid:ChunkIndexToGridPosition(i)
		lookupGrid.Chunks[i] = { ChunkIndex = i, ChunkPosition = pos } :: any
	end
	local queryWorldPos = lookupGrid:GridPositionToWorldPosition(Vector3.new(4, 5, 3))

	for _ = 1, ITERATIONS do
		diag:StartTimer("GetChunkAtPos (8³, hit)")
		lookupGrid:GetChunkAtPosition(queryWorldPos)
		diag:StopTimer("GetChunkAtPos (8³, hit)")
	end

	local emptyGrid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
	for _ = 1, ITERATIONS do
		diag:StartTimer("GetChunkAtPos (8³, miss)")
		emptyGrid:GetChunkAtPosition(queryWorldPos)
		diag:StopTimer("GetChunkAtPos (8³, miss)")
	end

	-- Offset query (small displacement within chunk bounds).
	local offsetPos = queryWorldPos + Vector3.new(1, 1, 1)
	for _ = 1, ITERATIONS do
		diag:StartTimer("GetChunkAtPos (8³, offset)")
		lookupGrid:GetChunkAtPosition(offsetPos)
		diag:StopTimer("GetChunkAtPos (8³, offset)")
	end
end

do
	-- GetChunkAtPosition with non-zero center.
	local offsetGrid = Grid.new(Vector3.new(500, 500, 500), Vector3.new(64, 64, 64), 8)
	for i = 0, 511 do
		local pos = offsetGrid:ChunkIndexToGridPosition(i)
		offsetGrid.Chunks[i] = { ChunkIndex = i, ChunkPosition = pos } :: any
	end
	local offsetQueryPos = offsetGrid:GridPositionToWorldPosition(Vector3.new(4, 5, 3))

	for _ = 1, ITERATIONS do
		diag:StartTimer("GetChunkAtPos (8³, center offset)")
		offsetGrid:GetChunkAtPosition(offsetQueryPos)
		diag:StopTimer("GetChunkAtPos (8³, center offset)")
	end
end

do
	-- GetChunkAtPosition on 64³ grid.
	local bigLookupGrid = Grid.new(Vector3.zero, Vector3.new(512, 512, 512), 8)
	for i = 0, 262143 do -- 64³ = 262144 chunks
		local pos = bigLookupGrid:ChunkIndexToGridPosition(i)
		bigLookupGrid.Chunks[i] = { ChunkIndex = i, ChunkPosition = pos } :: any
	end
	local bigQueryPos = bigLookupGrid:GridPositionToWorldPosition(Vector3.new(32, 48, 17))

	for _ = 1, ITERATIONS do
		diag:StartTimer("GetChunkAtPos (64³, hit)")
		bigLookupGrid:GetChunkAtPosition(bigQueryPos)
		diag:StopTimer("GetChunkAtPos (64³, hit)")
	end
end

-- Bulk Operations --
for _ = 1, BULK_ITERATIONS do
	diag:StartTimer("RoundTrip 512 (8³)")
	for i = 0, 511 do
		local pos = smallGrid:ChunkIndexToGridPosition(i)
		smallGrid:GridPositionToChunkIndex(pos)
	end
	diag:StopTimer("RoundTrip 512 (8³)")
end

for _ = 1, BULK_ITERATIONS do
	diag:StartTimer("RoundTrip 512 (64³)")
	for i = 0, 511 do
		local pos = largeGrid:ChunkIndexToGridPosition(i)
		largeGrid:GridPositionToChunkIndex(pos)
	end
	diag:StopTimer("RoundTrip 512 (64³)")
end

for _ = 1, BULK_ITERATIONS do
	diag:StartTimer("Enumerate 512 (8³)")
	local gs = smallGrid.GridSize
	for x = 0, gs.X - 1 do
		for y = 0, gs.Y - 1 do
			for z = 0, gs.Z - 1 do
				smallGrid:GridPositionToChunkIndex(Vector3.new(x, y, z))
			end
		end
	end
	diag:StopTimer("Enumerate 512 (8³)")
end

for _ = 1, BULK_ITERATIONS do
	diag:StartTimer("FullPipeline 512 (8³)")
	for i = 0, 511 do
		local pos = smallGrid:ChunkIndexToGridPosition(i)
		smallGrid:GridPositionToWorldPosition(pos)
	end
	diag:StopTimer("FullPipeline 512 (8³)")
end

do
	-- Bulk GetChunkAtPosition.
	local bulkLookupGrid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
	for i = 0, 511 do
		local pos = bulkLookupGrid:ChunkIndexToGridPosition(i)
		bulkLookupGrid.Chunks[i] = { ChunkIndex = i, ChunkPosition = pos } :: any
	end

	for _ = 1, BULK_ITERATIONS do
		diag:StartTimer("GetChunkAtPos 512 (8³)")
		for i = 0, 511 do
			local pos = bulkLookupGrid:ChunkIndexToGridPosition(i)
			local worldPos = bulkLookupGrid:GridPositionToWorldPosition(pos)
			bulkLookupGrid:GetChunkAtPosition(worldPos)
		end
		diag:StopTimer("GetChunkAtPos 512 (8³)")
	end
end

-- Print detailed breakdown --
diag:PrintBreakdown(true)
diag:Destroy()

return true
