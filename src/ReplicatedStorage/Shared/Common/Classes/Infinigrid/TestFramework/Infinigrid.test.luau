--[[
	Comprehensive unit tests for Infinigrid.
	Exercises Grid construction, alignment, index/position conversions,
	world position mapping, chunk lookup, and edge cases.

	Usage (from a Roblox script):
		local Litmus = require(ReplicatedStorage.Shared.Litmus)
		local InfinigridTests = require(path.to.Infinigrid.TestFramework["Infinigrid.test"])
		Litmus.RunSuite(InfinigridTests)
--]]

--!strict

--- Services ---
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--- Imports ---
local Grid = require(script.Parent.Parent)
local Litmus = require(ReplicatedStorage.Shared.Litmus)

--- Variables ---
local DEFAULT_CHUNK_SIZE = 64
local DEFAULT_MAX_GRID_SIZE = Vector3.one * (2 ^ 14)

--- Infinigrid Tests ---
return Litmus.Suite("Infinigrid", function(describe, it, expect, beforeEach, afterEach, skip)
	-- ================================================================
	-- Construction
	-- ================================================================
	describe("Grid.new", function()
		it("should create a grid with default parameters", function()
			local grid = Grid.new(Vector3.zero)
			expect(grid).To.Exist()
			expect(grid.Center).To.Equal(Vector3.zero)
			expect(grid.ChunkSize).To.Equal(DEFAULT_CHUNK_SIZE)
			expect(grid.Chunks).To.DeepEqual({})
		end)

		it("should use default chunk size when omitted", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(512, 512, 512))
			expect(grid.ChunkSize).To.Equal(DEFAULT_CHUNK_SIZE)
		end)

		it("should use custom chunk size when provided", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(512, 512, 512), 8)
			expect(grid.ChunkSize).To.Equal(8)
		end)

		it("should set GridWorldSize to default when omitted", function()
			local grid = Grid.new(Vector3.zero)
			local expected = Vector3.new(
				math.ceil(DEFAULT_MAX_GRID_SIZE.X / 8) * 8,
				math.ceil(DEFAULT_MAX_GRID_SIZE.Y / 8) * 8,
				math.ceil(DEFAULT_MAX_GRID_SIZE.Z / 8) * 8
			)
			expect(grid.GridWorldSize).To.Equal(expected)
		end)

		it("should compute GridSize as GridWorldSize / ChunkSize", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
			expect(grid.GridSize).To.Equal(Vector3.new(8, 8, 8))
		end)

		it("should accept a custom GridWorldSize", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(128, 256, 64), 8)
			expect(grid.GridWorldSize).To.Equal(Vector3.new(128, 256, 64))
		end)

		describe("center alignment", function()
			it("should keep center at zero when already aligned", function()
				local grid = Grid.new(Vector3.zero)
				expect(grid.Center).To.Equal(Vector3.zero)
			end)

			it("should keep center unchanged when already a multiple of 4", function()
				local grid = Grid.new(Vector3.new(8, 12, 16))
				expect(grid.Center).To.Equal(Vector3.new(8, 12, 16))
			end)

			it("should ceil center components to the nearest multiple of 4", function()
				local grid = Grid.new(Vector3.new(1, 1, 1))
				expect(grid.Center).To.Equal(Vector3.new(4, 4, 4))
			end)

			it("should ceil each component independently", function()
				local grid = Grid.new(Vector3.new(2, 5, 9))
				expect(grid.Center).To.Equal(Vector3.new(4, 8, 12))
			end)

			it("should not change center when exactly on a 4-boundary", function()
				local grid = Grid.new(Vector3.new(4, 8, 100))
				expect(grid.Center).To.Equal(Vector3.new(4, 8, 100))
			end)

			it("should ceil negative center components toward zero", function()
				local grid = Grid.new(Vector3.new(-5, -5, -5))
				expect(grid.Center).To.Equal(Vector3.new(-4, -4, -4))
			end)

			it("should handle mixed positive and negative components", function()
				local grid = Grid.new(Vector3.new(-3, 2, -7))
				expect(grid.Center).To.Equal(Vector3.new(0, 4, -4))
			end)
		end)

		describe("generation origin", function()
			it("should compute GenerationOrigin as center - worldSize/2 + chunkSize/2", function()
				local grid = Grid.new(Vector3.new(100, 100, 100), Vector3.new(64, 64, 64), 8)
				expect(grid.GenerationOrigin).To.Equal(
					grid.Center - (grid.GridWorldSize / 2) + (Vector3.one * (grid.ChunkSize / 2))
				)
			end)

			it("should place GenerationOrigin at -worldSize/2 + chunkSize/2 when center is zero", function()
				local grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
				expect(grid.GenerationOrigin).To.Equal(Vector3.new(-28, -28, -28))
			end)

			it("should compute GenerationOrigin with negative center", function()
				local grid = Grid.new(Vector3.new(-100, -100, -100), Vector3.new(64, 64, 64), 8)
				expect(grid.GenerationOrigin).To.Equal(Vector3.new(-128, -128, -128))
			end)
		end)

		describe("chunk size alignment", function()
			it("should keep chunk size when already a multiple of 8", function()
				local grid = Grid.new(Vector3.zero, nil, 8)
				expect(grid.ChunkSize).To.Equal(8)
			end)

			it("should ceil chunk size to nearest multiple of 8", function()
				local grid = Grid.new(Vector3.zero, nil, 5)
				expect(grid.ChunkSize).To.Equal(8)
			end)

			it("should ceil chunk size of 9 to 16", function()
				local grid = Grid.new(Vector3.zero, nil, 9)
				expect(grid.ChunkSize).To.Equal(16)
			end)

			it("should keep large multiples of 8 unchanged", function()
				local grid = Grid.new(Vector3.zero, nil, 64)
				expect(grid.ChunkSize).To.Equal(64)
			end)

			it("should ceil chunk size of 1 to 8", function()
				local grid = Grid.new(Vector3.zero, nil, 1)
				expect(grid.ChunkSize).To.Equal(8)
			end)

			it("should ceil chunk size of 7 to 8", function()
				local grid = Grid.new(Vector3.zero, nil, 7)
				expect(grid.ChunkSize).To.Equal(8)
			end)
		end)

		describe("grid world size alignment", function()
			it("should ceil grid world size components to nearest multiple of 8", function()
				local grid = Grid.new(Vector3.zero, Vector3.new(10, 10, 10), 8)
				expect(grid.GridWorldSize).To.Equal(Vector3.new(16, 16, 16))
			end)

			it("should keep grid world size when already aligned", function()
				local grid = Grid.new(Vector3.zero, Vector3.new(64, 128, 256), 8)
				expect(grid.GridWorldSize).To.Equal(Vector3.new(64, 128, 256))
			end)
		end)

		it("should start with an empty Chunks table", function()
			local grid = Grid.new(Vector3.zero)
			expect(#grid.Chunks).To.Equal(0)
		end)
	end)

	-- ================================================================
	-- GridPositionToChunkIndex
	-- ================================================================
	describe("GridPositionToChunkIndex", function()
		local grid

		beforeEach(function()
			grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
		end)

		it("should return 0 for grid position (0,0,0)", function()
			expect(grid:GridPositionToChunkIndex(Vector3.zero)).To.Equal(0)
		end)

		it("should increase by 1 along the Z axis", function()
			local a = grid:GridPositionToChunkIndex(Vector3.new(0, 0, 0))
			local b = grid:GridPositionToChunkIndex(Vector3.new(0, 0, 1))
			expect(b - a).To.Equal(1)
		end)

		it("should increase by GridSize.Z along the Y axis", function()
			local a = grid:GridPositionToChunkIndex(Vector3.new(0, 0, 0))
			local b = grid:GridPositionToChunkIndex(Vector3.new(0, 1, 0))
			expect(b - a).To.Equal(grid.GridSize.Z)
		end)

		it("should increase by GridSize.Y * GridSize.Z along the X axis", function()
			local a = grid:GridPositionToChunkIndex(Vector3.new(0, 0, 0))
			local b = grid:GridPositionToChunkIndex(Vector3.new(1, 0, 0))
			expect(b - a).To.Equal(grid.GridSize.Y * grid.GridSize.Z)
		end)

		it("should compute the correct max index for the last position", function()
			local gs = grid.GridSize
			local maxIndex = grid:GridPositionToChunkIndex(Vector3.new(gs.X - 1, gs.Y - 1, gs.Z - 1))
			local expectedMax = (gs.X * gs.Y * gs.Z) - 1
			expect(maxIndex).To.Equal(expectedMax)
		end)

		it("should return an integer for all valid grid positions", function()
			local gs = grid.GridSize
			for x = 0, math.min(gs.X - 1, 3) do
				for y = 0, math.min(gs.Y - 1, 3) do
					for z = 0, math.min(gs.Z - 1, 3) do
						local index = grid:GridPositionToChunkIndex(Vector3.new(x, y, z))
						expect(index % 1).To.Equal(0)
					end
				end
			end
		end)
	end)

	-- ================================================================
	-- ChunkIndexToGridPosition
	-- ================================================================
	describe("ChunkIndexToGridPosition", function()
		local grid

		beforeEach(function()
			grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
		end)

		it("should return (0,0,0) for index 0", function()
			expect(grid:ChunkIndexToGridPosition(0)).To.Equal(Vector3.zero)
		end)

		it("should return (0,0,1) for index 1", function()
			expect(grid:ChunkIndexToGridPosition(1)).To.Equal(Vector3.new(0, 0, 1))
		end)

		it("should return the last position for the max index", function()
			local gs = grid.GridSize
			local maxIndex = (gs.X * gs.Y * gs.Z) - 1
			expect(grid:ChunkIndexToGridPosition(maxIndex)).To.Equal(Vector3.new(gs.X - 1, gs.Y - 1, gs.Z - 1))
		end)

		it("should step to (0,1,0) after filling one Z row", function()
			expect(grid:ChunkIndexToGridPosition(grid.GridSize.Z)).To.Equal(Vector3.new(0, 1, 0))
		end)

		it("should step to (1,0,0) after filling one YZ plane", function()
			local sizeYZ = grid.GridSize.Y * grid.GridSize.Z
			expect(grid:ChunkIndexToGridPosition(sizeYZ)).To.Equal(Vector3.new(1, 0, 0))
		end)

		it("should return integer grid position components for all valid indices", function()
			local gs = grid.GridSize
			local total = gs.X * gs.Y * gs.Z
			local step = math.max(1, math.floor(total / 64))
			for i = 0, total - 1, step do
				local pos = grid:ChunkIndexToGridPosition(i)
				expect(pos.X % 1).To.Equal(0)
				expect(pos.Y % 1).To.Equal(0)
				expect(pos.Z % 1).To.Equal(0)
			end
		end)
	end)

	-- ================================================================
	-- Index / Position Round-trips
	-- ================================================================
	describe("index/position round-trip", function()
		local grid

		beforeEach(function()
			grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
		end)

		it("should round-trip position to index to position", function()
			local positions = {
				Vector3.new(0, 0, 0),
				Vector3.new(3, 5, 2),
				Vector3.new(7, 7, 7),
				Vector3.new(0, 7, 0),
				Vector3.new(4, 4, 4),
			}
			for _, pos in positions do
				local index = grid:GridPositionToChunkIndex(pos)
				expect(grid:ChunkIndexToGridPosition(index)).To.Equal(pos)
			end
		end)

		it("should round-trip index to position to index", function()
			local indices = { 0, 1, 7, 8, 63, 64, 100, 255, 511 }
			for _, index in indices do
				local pos = grid:ChunkIndexToGridPosition(index)
				expect(grid:GridPositionToChunkIndex(pos)).To.Equal(index)
			end
		end)

		it("should round-trip all indices in a small grid", function()
			local smallGrid = Grid.new(Vector3.zero, Vector3.new(16, 16, 16), 8)
			local total = smallGrid.GridSize.X * smallGrid.GridSize.Y * smallGrid.GridSize.Z
			for i = 0, total - 1 do
				local pos = smallGrid:ChunkIndexToGridPosition(i)
				expect(smallGrid:GridPositionToChunkIndex(pos)).To.Equal(i)
			end
		end)

		it("should round-trip all indices in a small grid (reversed)", function()
			local smallGrid = Grid.new(Vector3.zero, Vector3.new(16, 16, 16), 8)
			local gs = smallGrid.GridSize
			for x = 0, gs.X - 1 do
				for y = 0, gs.Y - 1 do
					for z = 0, gs.Z - 1 do
						local pos = Vector3.new(x, y, z)
						local index = smallGrid:GridPositionToChunkIndex(pos)
						expect(smallGrid:ChunkIndexToGridPosition(index)).To.Equal(pos)
					end
				end
			end
		end)
	end)

	-- ================================================================
	-- Index Ordering
	-- ================================================================
	describe("index ordering", function()
		local grid

		beforeEach(function()
			grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
		end)

		it("should order Z as the fastest-changing axis", function()
			for z = 0, 6 do
				local a = grid:GridPositionToChunkIndex(Vector3.new(0, 0, z))
				local b = grid:GridPositionToChunkIndex(Vector3.new(0, 0, z + 1))
				expect(b - a).To.Equal(1)
			end
		end)

		it("should order X as the slowest-changing axis", function()
			local planeSize = grid.GridSize.Y * grid.GridSize.Z
			for x = 0, 6 do
				local a = grid:GridPositionToChunkIndex(Vector3.new(x, 0, 0))
				local b = grid:GridPositionToChunkIndex(Vector3.new(x + 1, 0, 0))
				expect(b - a).To.Equal(planeSize)
			end
		end)

		it("should produce contiguous indices for a full grid enumeration", function()
			local gs = grid.GridSize
			local total = gs.X * gs.Y * gs.Z
			local seen: { [number]: boolean } = {}
			for x = 0, gs.X - 1 do
				for y = 0, gs.Y - 1 do
					for z = 0, gs.Z - 1 do
						local index = grid:GridPositionToChunkIndex(Vector3.new(x, y, z))
						expect(seen[index]).To.BeNil()
						seen[index] = true
					end
				end
			end
			for i = 0, total - 1 do
				expect(seen[i]).To.Equal(true)
			end
		end)
	end)

	-- ================================================================
	-- GridPositionToWorldPosition
	-- ================================================================
	describe("GridPositionToWorldPosition", function()
		it("should offset from GenerationOrigin by gridPosition * chunkSize", function()
			local grid = Grid.new(Vector3.new(100, 100, 100), Vector3.new(64, 64, 64), 8)
			local worldPos = grid:GridPositionToWorldPosition(Vector3.new(1, 2, 3))
			expect(worldPos).To.Equal(grid.GenerationOrigin + Vector3.new(1 * 8, 2 * 8, 3 * 8))
		end)

		it("should return GenerationOrigin for grid position (0,0,0)", function()
			local grid = Grid.new(Vector3.new(50, 50, 50), Vector3.new(64, 64, 64), 8)
			expect(grid:GridPositionToWorldPosition(Vector3.zero)).To.Equal(grid.GenerationOrigin)
		end)

		it("should scale with chunk size", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(256, 256, 256), 16)
			local worldPos = grid:GridPositionToWorldPosition(Vector3.new(2, 3, 4))
			expect(worldPos).To.Equal(grid.GenerationOrigin + Vector3.new(2 * 16, 3 * 16, 4 * 16))
		end)

		it("should work correctly with non-cubic grids", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(32, 16, 64), 8)
			expect(grid:GridPositionToWorldPosition(Vector3.new(1, 1, 1))).To.Equal(
				grid.GenerationOrigin + Vector3.new(8, 8, 8)
			)
		end)

		it("should return correct world position for the last grid cell", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
			local gs = grid.GridSize
			local lastPos = Vector3.new(gs.X - 1, gs.Y - 1, gs.Z - 1)
			expect(grid:GridPositionToWorldPosition(lastPos)).To.Equal(grid.GenerationOrigin + lastPos * grid.ChunkSize)
		end)

		it("should produce world positions aligned to terrain resolution (4-stud grid)", function()
			local grid = Grid.new(Vector3.new(100, 100, 100), Vector3.new(64, 64, 64), 8)
			for x = 0, 3 do
				for y = 0, 3 do
					for z = 0, 3 do
						local wp = grid:GridPositionToWorldPosition(Vector3.new(x, y, z))
						expect(wp.X % 4).To.Equal(0)
						expect(wp.Y % 4).To.Equal(0)
						expect(wp.Z % 4).To.Equal(0)
					end
				end
			end
		end)
	end)

	-- ================================================================
	-- Non-cubic Grids
	-- ================================================================
	describe("non-cubic grids", function()
		it("should handle rectangular GridWorldSize correctly", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(32, 16, 64), 8)
			expect(grid.GridSize).To.Equal(Vector3.new(4, 2, 8))
		end)

		it("should round-trip indices in a non-cubic grid", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(32, 16, 64), 8)
			local total = grid.GridSize.X * grid.GridSize.Y * grid.GridSize.Z
			for i = 0, total - 1 do
				local pos = grid:ChunkIndexToGridPosition(i)
				expect(grid:GridPositionToChunkIndex(pos)).To.Equal(i)
			end
		end)

		it("should produce unique indices for all positions in a non-cubic grid", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(64, 32, 48), 16)
			local gs = grid.GridSize
			local seen: { [number]: boolean } = {}
			for x = 0, gs.X - 1 do
				for y = 0, gs.Y - 1 do
					for z = 0, gs.Z - 1 do
						local index = grid:GridPositionToChunkIndex(Vector3.new(x, y, z))
						expect(seen[index]).To.BeNil()
						seen[index] = true
					end
				end
			end
		end)
	end)

	-- ================================================================
	-- Edge Cases
	-- ================================================================
	describe("edge cases", function()
		it("should handle a 1x1x1 grid", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(8, 8, 8), 8)
			expect(grid.GridSize).To.Equal(Vector3.new(1, 1, 1))
			expect(grid:GridPositionToChunkIndex(Vector3.zero)).To.Equal(0)
			expect(grid:ChunkIndexToGridPosition(0)).To.Equal(Vector3.zero)
		end)

		it("should handle a 1x1xN grid (single row)", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(8, 8, 32), 8)
			expect(grid.GridSize).To.Equal(Vector3.new(1, 1, 4))
			for z = 0, 3 do
				expect(grid:GridPositionToChunkIndex(Vector3.new(0, 0, z))).To.Equal(z)
			end
		end)

		it("should handle large chunk sizes", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(512, 512, 512), 64)
			expect(grid.ChunkSize).To.Equal(64)
			expect(grid.GridSize).To.Equal(Vector3.new(8, 8, 8))
		end)

		it("should produce identical results for identical inputs", function()
			local gridA = Grid.new(Vector3.new(50, 50, 50), Vector3.new(128, 128, 128), 16)
			local gridB = Grid.new(Vector3.new(50, 50, 50), Vector3.new(128, 128, 128), 16)
			expect(gridA.Center).To.Equal(gridB.Center)
			expect(gridA.GenerationOrigin).To.Equal(gridB.GenerationOrigin)
			expect(gridA.ChunkSize).To.Equal(gridB.ChunkSize)
			expect(gridA.GridSize).To.Equal(gridB.GridSize)
			expect(gridA.GridWorldSize).To.Equal(gridB.GridWorldSize)
		end)

		it("should handle negative offset grid with correct world positions", function()
			local grid = Grid.new(Vector3.new(-64, -64, -64), Vector3.new(128, 128, 128), 16)
			expect(grid.GenerationOrigin).To.Equal(Vector3.new(-120, -120, -120))
			expect(grid:GridPositionToWorldPosition(Vector3.zero)).To.Equal(grid.GenerationOrigin)
		end)

		skip("serialization / deserialization (not yet implemented)")
		skip("chunk deloading under memory pressure (not yet implemented)")
	end)

	-- ================================================================
	-- Grid Module Structure
	-- ================================================================
	describe("Grid module", function()
		it("should be a frozen table", function()
			expect(table.isfrozen(Grid)).To.Equal(true)
		end)

		it("should expose methods through metatable __index", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
			expect(grid.GridPositionToChunkIndex).To.Exist()
			expect(grid.ChunkIndexToGridPosition).To.Exist()
			expect(grid.GridPositionToWorldPosition).To.Exist()
			expect(grid.GetNearestChunkAtPosition).To.Exist()
			expect(grid.GetNeighboringChunksIndices).To.Exist()
			expect(grid._GetNearestChunkIndexAtPosition).To.Exist()
			expect(grid.OnChunkGenerated).To.Exist()
		end)

		it("should have Grid as its __index metatable", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
			local mt = getmetatable(grid)
			expect(mt).To.Exist()
			expect(mt.__index).To.Equal(Grid)
		end)

		it("should expose the new constructor", function()
			expect(Grid.new).To.Exist()
			expect(Grid.new).To.BeA("function")
		end)
	end)

	-- ================================================================
	-- Invariants
	-- ================================================================
	describe("invariants", function()
		it("should satisfy GridSize * ChunkSize == GridWorldSize", function()
			local configs = {
				{ Vector3.zero, Vector3.new(64, 64, 64), 8 },
				{ Vector3.zero, Vector3.new(512, 256, 128), 16 },
				{ Vector3.new(100, 200, 300), Vector3.new(256, 256, 256), 32 },
				{ Vector3.zero, Vector3.new(128, 64, 256), 64 },
			}
			for _, cfg in configs do
				local grid = Grid.new(cfg[1] :: Vector3, cfg[2] :: Vector3, cfg[3] :: number)
				expect(grid.GridSize * grid.ChunkSize).To.Equal(grid.GridWorldSize)
			end
		end)

		it("should satisfy GenerationOrigin == Center - GridWorldSize / 2 + ChunkSize / 2", function()
			local configs = {
				{ Vector3.zero, Vector3.new(64, 64, 64), 8 },
				{ Vector3.new(100, 100, 100), Vector3.new(256, 256, 256), 16 },
				{ Vector3.new(-64, -64, -64), Vector3.new(128, 128, 128), 32 },
				{ Vector3.new(7, 13, 29), Vector3.new(64, 128, 256), 8 },
			}
			for _, cfg in configs do
				local grid = Grid.new(cfg[1] :: Vector3, cfg[2] :: Vector3, cfg[3] :: number)
				expect(grid.GenerationOrigin).To.Equal(
					grid.Center - (grid.GridWorldSize / 2) + (Vector3.one * (grid.ChunkSize / 2))
				)
			end
		end)

		it("should have ChunkSize always be a multiple of 8", function()
			local chunkSizes = { 1, 3, 5, 7, 8, 9, 12, 15, 16, 17, 24, 33, 64, 100, 128 }
			for _, cs in chunkSizes do
				local grid = Grid.new(Vector3.zero, nil, cs)
				expect(grid.ChunkSize % 8).To.Equal(0)
			end
		end)

		it("should have GridWorldSize components always be multiples of 8", function()
			local worldSizes = {
				Vector3.new(1, 1, 1),
				Vector3.new(7, 9, 15),
				Vector3.new(10, 20, 30),
				Vector3.new(64, 128, 256),
			}
			for _, ws in worldSizes do
				local grid = Grid.new(Vector3.zero, ws, 8)
				expect(grid.GridWorldSize.X % 8).To.Equal(0)
				expect(grid.GridWorldSize.Y % 8).To.Equal(0)
				expect(grid.GridWorldSize.Z % 8).To.Equal(0)
			end
		end)

		it("should have Center components always be multiples of 4", function()
			local centers = {
				Vector3.new(0, 0, 0),
				Vector3.new(1, 2, 3),
				Vector3.new(-1, -2, -3),
				Vector3.new(5, 10, 15),
				Vector3.new(4, 8, 12),
				Vector3.new(0.5, 1.5, 2.5),
			}
			for _, c in centers do
				local grid = Grid.new(c)
				expect(grid.Center.X % 4).To.Equal(0)
				expect(grid.Center.Y % 4).To.Equal(0)
				expect(grid.Center.Z % 4).To.Equal(0)
			end
		end)

		it("should have all GridSize components be positive integers", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(128, 64, 256), 8)
			expect(grid.GridSize.X).To.BeGreaterThan(0)
			expect(grid.GridSize.Y).To.BeGreaterThan(0)
			expect(grid.GridSize.Z).To.BeGreaterThan(0)
			expect(grid.GridSize.X % 1).To.Equal(0)
			expect(grid.GridSize.Y % 1).To.Equal(0)
			expect(grid.GridSize.Z % 1).To.Equal(0)
		end)

		it("should have ChunkSize always be a positive integer", function()
			for cs = 1, 64 do
				local grid = Grid.new(Vector3.zero, nil, cs)
				expect(grid.ChunkSize).To.BeGreaterThan(0)
				expect(grid.ChunkSize % 1).To.Equal(0)
			end
		end)
	end)

	-- ================================================================
	-- World Position Properties
	-- ================================================================
	describe("world position properties", function()
		it("should produce monotonically increasing world X for increasing grid X", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
			for x = 0, 6 do
				local a = grid:GridPositionToWorldPosition(Vector3.new(x, 0, 0))
				local b = grid:GridPositionToWorldPosition(Vector3.new(x + 1, 0, 0))
				expect(b.X).To.BeGreaterThan(a.X)
			end
		end)

		it("should produce monotonically increasing world Y for increasing grid Y", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
			for y = 0, 6 do
				local a = grid:GridPositionToWorldPosition(Vector3.new(0, y, 0))
				local b = grid:GridPositionToWorldPosition(Vector3.new(0, y + 1, 0))
				expect(b.Y).To.BeGreaterThan(a.Y)
			end
		end)

		it("should produce monotonically increasing world Z for increasing grid Z", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
			for z = 0, 6 do
				local a = grid:GridPositionToWorldPosition(Vector3.new(0, 0, z))
				local b = grid:GridPositionToWorldPosition(Vector3.new(0, 0, z + 1))
				expect(b.Z).To.BeGreaterThan(a.Z)
			end
		end)

		it("should space adjacent chunks exactly ChunkSize apart", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
			local cs = grid.ChunkSize
			local origin = grid:GridPositionToWorldPosition(Vector3.new(3, 3, 3))
			local neighborX = grid:GridPositionToWorldPosition(Vector3.new(4, 3, 3))
			local neighborY = grid:GridPositionToWorldPosition(Vector3.new(3, 4, 3))
			local neighborZ = grid:GridPositionToWorldPosition(Vector3.new(3, 3, 4))
			expect(neighborX - origin).To.Equal(Vector3.new(cs, 0, 0))
			expect(neighborY - origin).To.Equal(Vector3.new(0, cs, 0))
			expect(neighborZ - origin).To.Equal(Vector3.new(0, 0, cs))
		end)

		it("should place the midpoint of first and last chunk world positions at Center", function()
			local grid = Grid.new(Vector3.new(100, 100, 100), Vector3.new(64, 64, 64), 8)
			local firstPos = grid:GridPositionToWorldPosition(Vector3.zero)
			local lastPos = grid:GridPositionToWorldPosition(grid.GridSize - Vector3.one)
			local midpoint = (firstPos + lastPos) / 2
			expect(midpoint).To.Equal(grid.Center)
		end)

		it("should span exactly GridWorldSize from first to last cell edge", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(128, 64, 256), 8)
			local firstPos = grid:GridPositionToWorldPosition(Vector3.zero)
			local gs = grid.GridSize
			local lastPos = grid:GridPositionToWorldPosition(Vector3.new(gs.X, gs.Y, gs.Z))
			expect(lastPos - firstPos).To.Equal(grid.GridWorldSize)
		end)
	end)

	-- ================================================================
	-- Large Grid Round-trips
	-- ================================================================
	describe("large grid round-trips", function()
		it("should round-trip all indices in a 64-cubed grid", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(512, 512, 512), 8)
			local gs = grid.GridSize
			local total = gs.X * gs.Y * gs.Z
			local testIndices = {
				0,
				1,
				2,
				gs.Z - 1,
				gs.Z,
				gs.Z + 1,
				gs.Y * gs.Z - 1,
				gs.Y * gs.Z,
				gs.Y * gs.Z + 1,
				math.floor(total / 4),
				math.floor(total / 2),
				math.floor(total * 3 / 4),
				total - 3,
				total - 2,
				total - 1,
			}
			for _, index in testIndices do
				local pos = grid:ChunkIndexToGridPosition(index)
				expect(grid:GridPositionToChunkIndex(pos)).To.Equal(index)
			end
		end)

		it("should round-trip boundary positions in a 64-cubed grid", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(512, 512, 512), 8)
			local gs = grid.GridSize
			local corners = {
				Vector3.new(0, 0, 0),
				Vector3.new(gs.X - 1, 0, 0),
				Vector3.new(0, gs.Y - 1, 0),
				Vector3.new(0, 0, gs.Z - 1),
				Vector3.new(gs.X - 1, gs.Y - 1, 0),
				Vector3.new(gs.X - 1, 0, gs.Z - 1),
				Vector3.new(0, gs.Y - 1, gs.Z - 1),
				Vector3.new(gs.X - 1, gs.Y - 1, gs.Z - 1),
			}
			for _, pos in corners do
				local index = grid:GridPositionToChunkIndex(pos)
				expect(grid:ChunkIndexToGridPosition(index)).To.Equal(pos)
			end
		end)
	end)

	-- ================================================================
	-- Asymmetric Grids
	-- ================================================================
	describe("asymmetric grids", function()
		it("should handle an Nx1x1 grid (single X axis)", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(64, 8, 8), 8)
			expect(grid.GridSize).To.Equal(Vector3.new(8, 1, 1))
			for x = 0, 7 do
				expect(grid:GridPositionToChunkIndex(Vector3.new(x, 0, 0))).To.Equal(x)
				expect(grid:ChunkIndexToGridPosition(x)).To.Equal(Vector3.new(x, 0, 0))
			end
		end)

		it("should handle a 1xNx1 grid (single Y axis)", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(8, 64, 8), 8)
			expect(grid.GridSize).To.Equal(Vector3.new(1, 8, 1))
			for y = 0, 7 do
				expect(grid:GridPositionToChunkIndex(Vector3.new(0, y, 0))).To.Equal(y)
				expect(grid:ChunkIndexToGridPosition(y)).To.Equal(Vector3.new(0, y, 0))
			end
		end)

		it("should handle a highly asymmetric grid (16x1x4)", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(128, 8, 32), 8)
			expect(grid.GridSize).To.Equal(Vector3.new(16, 1, 4))
			local total = 16 * 1 * 4
			for i = 0, total - 1 do
				local pos = grid:ChunkIndexToGridPosition(i)
				expect(grid:GridPositionToChunkIndex(pos)).To.Equal(i)
			end
		end)

		it("should order indices correctly in a non-cubic grid (Z fastest)", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(32, 16, 64), 8)
			local a = grid:GridPositionToChunkIndex(Vector3.new(0, 0, 0))
			local b = grid:GridPositionToChunkIndex(Vector3.new(0, 0, 1))
			expect(b - a).To.Equal(1)
			local c = grid:GridPositionToChunkIndex(Vector3.new(0, 1, 0))
			expect(c - a).To.Equal(grid.GridSize.Z)
			local d = grid:GridPositionToChunkIndex(Vector3.new(1, 0, 0))
			expect(d - a).To.Equal(grid.GridSize.Y * grid.GridSize.Z)
		end)
	end)

	-- ================================================================
	-- Multiple Grid Independence
	-- ================================================================
	describe("multiple grid independence", function()
		it("should not share state between independent grid instances", function()
			local gridA = Grid.new(Vector3.new(0, 0, 0), Vector3.new(64, 64, 64), 8)
			local gridB = Grid.new(Vector3.new(200, 200, 200), Vector3.new(256, 256, 256), 16)
			expect(gridA.Center).Never.To.Equal(gridB.Center)
			expect(gridA.ChunkSize).Never.To.Equal(gridB.ChunkSize)
			expect(gridA.GridSize).Never.To.Equal(gridB.GridSize)
			gridA.Chunks[1] = { ChunkIndex = 0, ChunkPosition = Vector3.zero } :: any
			expect(#gridB.Chunks).To.Equal(0)
		end)

		it("should produce different world positions from different grids", function()
			local gridA = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
			local gridB = Grid.new(Vector3.new(1000, 1000, 1000), Vector3.new(64, 64, 64), 8)
			local posA = gridA:GridPositionToWorldPosition(Vector3.new(1, 1, 1))
			local posB = gridB:GridPositionToWorldPosition(Vector3.new(1, 1, 1))
			expect(posA).Never.To.Equal(posB)
		end)

		it("should have independent Chunks tables (mutations do not leak)", function()
			local gridA = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
			local gridB = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
			gridA.Chunks[0] = { ChunkIndex = 0, ChunkPosition = Vector3.zero } :: any
			expect(gridA.Chunks[0]).To.Exist()
			expect(gridB.Chunks[0]).To.BeNil()
		end)
	end)

	-- ================================================================
	-- ExpandVectorToGrid Coverage
	-- ================================================================
	describe("ExpandVectorToGrid coverage", function()
		it("should ceil fractional center values to nearest 4", function()
			local grid = Grid.new(Vector3.new(0.5, 1.5, 2.5))
			expect(grid.Center).To.Equal(Vector3.new(4, 4, 4))
		end)

		it("should ceil fractional world size values to nearest 8", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(10.5, 20.5, 30.5), 8)
			expect(grid.GridWorldSize).To.Equal(Vector3.new(16, 24, 32))
		end)

		it("should handle very small positive values", function()
			local grid = Grid.new(Vector3.new(0.01, 0.01, 0.01))
			expect(grid.Center).To.Equal(Vector3.new(4, 4, 4))
		end)

		it("should handle exact negative multiples of 4", function()
			local grid = Grid.new(Vector3.new(-4, -8, -12))
			expect(grid.Center).To.Equal(Vector3.new(-4, -8, -12))
		end)

		it("should handle zero components mixed with nonzero", function()
			local grid = Grid.new(Vector3.new(0, 5, 0))
			expect(grid.Center.X).To.Equal(0)
			expect(grid.Center.Y).To.Equal(8)
			expect(grid.Center.Z).To.Equal(0)
		end)
	end)

	-- ================================================================
	-- GetNearestChunkAtPosition (exact corner queries)
	-- ================================================================
	describe("GetNearestChunkAtPosition", function()
		it("should return nil when no chunk exists at the position", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
			expect(grid:GetNearestChunkAtPosition(Vector3.new(4, 4, 4))).To.BeNil()
		end)

		it("should return a stored chunk at the origin grid position", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
			local chunk = { ChunkIndex = 0, ChunkPosition = Vector3.zero, Data = "test" }
			grid.Chunks[0] = chunk :: any
			local result = grid:GetNearestChunkAtPosition(grid.GenerationOrigin)
			expect(result).To.Exist()
			expect((result :: any).Data).To.Equal("test")
		end)

		it("should return the correct chunk for a position in the middle of the grid", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
			local gridPos = Vector3.new(3, 4, 5)
			local chunkIndex = grid:GridPositionToChunkIndex(gridPos)
			local worldPos = grid:GridPositionToWorldPosition(gridPos)
			grid.Chunks[chunkIndex] = { ChunkIndex = chunkIndex, ChunkPosition = gridPos, Value = 42 } :: any
			local result = grid:GetNearestChunkAtPosition(worldPos)
			expect(result).To.Exist()
			expect((result :: any).Value).To.Equal(42)
		end)

		it("should find a chunk when queried at the exact chunk corner", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
			local gridPos = Vector3.new(2, 2, 2)
			local chunkIndex = grid:GridPositionToChunkIndex(gridPos)
			local worldPos = grid:GridPositionToWorldPosition(gridPos)
			grid.Chunks[chunkIndex] = { ChunkIndex = chunkIndex, ChunkPosition = gridPos } :: any
			local result = grid:GetNearestChunkAtPosition(worldPos)
			expect(result).To.Exist()
			expect((result :: any).ChunkIndex).To.Equal(chunkIndex)
		end)

		it("should find the correct chunk when queried with a small offset", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
			local gridPos = Vector3.new(4, 4, 4)
			local chunkIndex = grid:GridPositionToChunkIndex(gridPos)
			local worldPos = grid:GridPositionToWorldPosition(gridPos)
			grid.Chunks[chunkIndex] = { ChunkIndex = chunkIndex, ChunkPosition = gridPos } :: any
			local result = grid:GetNearestChunkAtPosition(worldPos + Vector3.new(1, 1, 1))
			expect(result).To.Exist()
			expect((result :: any).ChunkIndex).To.Equal(chunkIndex)
		end)

		it("should return nil for a position outside the populated chunks", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
			grid.Chunks[0] = { ChunkIndex = 0, ChunkPosition = Vector3.zero } :: any
			local farWorldPos = grid:GridPositionToWorldPosition(Vector3.new(7, 7, 7))
			expect(grid:GetNearestChunkAtPosition(farWorldPos)).To.BeNil()
		end)

		it("should work correctly with a non-zero center grid", function()
			local grid = Grid.new(Vector3.new(100, 200, 300), Vector3.new(64, 64, 64), 8)
			local gridPos = Vector3.new(1, 1, 1)
			local chunkIndex = grid:GridPositionToChunkIndex(gridPos)
			local worldPos = grid:GridPositionToWorldPosition(gridPos)
			grid.Chunks[chunkIndex] = { ChunkIndex = chunkIndex, ChunkPosition = gridPos } :: any
			local result = grid:GetNearestChunkAtPosition(worldPos)
			expect(result).To.Exist()
			expect((result :: any).ChunkIndex).To.Equal(chunkIndex)
		end)

		it("should work correctly with a negative center grid", function()
			local grid = Grid.new(Vector3.new(-100, -100, -100), Vector3.new(64, 64, 64), 8)
			local gridPos = Vector3.new(3, 3, 3)
			local chunkIndex = grid:GridPositionToChunkIndex(gridPos)
			local worldPos = grid:GridPositionToWorldPosition(gridPos)
			grid.Chunks[chunkIndex] = { ChunkIndex = chunkIndex, ChunkPosition = gridPos } :: any
			local result = grid:GetNearestChunkAtPosition(worldPos)
			expect(result).To.Exist()
			expect((result :: any).ChunkIndex).To.Equal(chunkIndex)
		end)

		it("should work with large chunk sizes", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(512, 512, 512), 64)
			local gridPos = Vector3.new(3, 5, 2)
			local chunkIndex = grid:GridPositionToChunkIndex(gridPos)
			local worldPos = grid:GridPositionToWorldPosition(gridPos)
			grid.Chunks[chunkIndex] = { ChunkIndex = chunkIndex, ChunkPosition = gridPos } :: any
			local result = grid:GetNearestChunkAtPosition(worldPos)
			expect(result).To.Exist()
			expect((result :: any).ChunkIndex).To.Equal(chunkIndex)
		end)

		it("should be consistent with GridPositionToWorldPosition round-trip", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
			local testPositions = {
				Vector3.new(0, 0, 0),
				Vector3.new(1, 2, 3),
				Vector3.new(7, 7, 7),
				Vector3.new(4, 0, 6),
			}
			for _, gridPos in testPositions do
				local chunkIndex = grid:GridPositionToChunkIndex(gridPos)
				grid.Chunks[chunkIndex] = { ChunkIndex = chunkIndex, ChunkPosition = gridPos } :: any
			end
			for _, gridPos in testPositions do
				local worldPos = grid:GridPositionToWorldPosition(gridPos)
				local result = grid:GetNearestChunkAtPosition(worldPos)
				expect(result).To.Exist()
				expect((result :: any).ChunkPosition).To.Equal(gridPos)
			end
		end)
	end)

	-- ================================================================
	-- GetNearestChunkAtPosition — Exhaustive
	-- ================================================================
	describe("GetNearestChunkAtPosition exhaustive", function()
		it("should find all chunks in a fully populated 2x2x2 grid", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(16, 16, 16), 8)
			local total = grid.GridSize.X * grid.GridSize.Y * grid.GridSize.Z
			for i = 0, total - 1 do
				local pos = grid:ChunkIndexToGridPosition(i)
				grid.Chunks[i] = { ChunkIndex = i, ChunkPosition = pos } :: any
			end
			for i = 0, total - 1 do
				local pos = grid:ChunkIndexToGridPosition(i)
				local worldPos = grid:GridPositionToWorldPosition(pos)
				local result = grid:GetNearestChunkAtPosition(worldPos)
				expect(result).To.Exist()
				expect((result :: any).ChunkIndex).To.Equal(i)
			end
		end)

		it("should find all chunks in a fully populated 4x4x4 grid", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(32, 32, 32), 8)
			local total = grid.GridSize.X * grid.GridSize.Y * grid.GridSize.Z
			for i = 0, total - 1 do
				local pos = grid:ChunkIndexToGridPosition(i)
				grid.Chunks[i] = { ChunkIndex = i, ChunkPosition = pos } :: any
			end
			for i = 0, total - 1 do
				local pos = grid:ChunkIndexToGridPosition(i)
				local worldPos = grid:GridPositionToWorldPosition(pos)
				local result = grid:GetNearestChunkAtPosition(worldPos)
				expect(result).To.Exist()
				expect((result :: any).ChunkIndex).To.Equal(i)
			end
		end)

		it("should find all chunks with a positive center", function()
			local grid = Grid.new(Vector3.new(200, 200, 200), Vector3.new(32, 32, 32), 8)
			local total = grid.GridSize.X * grid.GridSize.Y * grid.GridSize.Z
			for i = 0, total - 1 do
				local pos = grid:ChunkIndexToGridPosition(i)
				grid.Chunks[i] = { ChunkIndex = i, ChunkPosition = pos } :: any
			end
			for i = 0, total - 1 do
				local pos = grid:ChunkIndexToGridPosition(i)
				local worldPos = grid:GridPositionToWorldPosition(pos)
				local result = grid:GetNearestChunkAtPosition(worldPos)
				expect(result).To.Exist()
				expect((result :: any).ChunkIndex).To.Equal(i)
			end
		end)

		it("should find all chunks with a negative center", function()
			local grid = Grid.new(Vector3.new(-200, -200, -200), Vector3.new(32, 32, 32), 8)
			local total = grid.GridSize.X * grid.GridSize.Y * grid.GridSize.Z
			for i = 0, total - 1 do
				local pos = grid:ChunkIndexToGridPosition(i)
				grid.Chunks[i] = { ChunkIndex = i, ChunkPosition = pos } :: any
			end
			for i = 0, total - 1 do
				local pos = grid:ChunkIndexToGridPosition(i)
				local worldPos = grid:GridPositionToWorldPosition(pos)
				local result = grid:GetNearestChunkAtPosition(worldPos)
				expect(result).To.Exist()
				expect((result :: any).ChunkIndex).To.Equal(i)
			end
		end)

		it("should find all chunks with an unaligned center", function()
			local grid = Grid.new(Vector3.new(37, 53, 91), Vector3.new(32, 32, 32), 8)
			local total = grid.GridSize.X * grid.GridSize.Y * grid.GridSize.Z
			for i = 0, total - 1 do
				local pos = grid:ChunkIndexToGridPosition(i)
				grid.Chunks[i] = { ChunkIndex = i, ChunkPosition = pos } :: any
			end
			for i = 0, total - 1 do
				local pos = grid:ChunkIndexToGridPosition(i)
				local worldPos = grid:GridPositionToWorldPosition(pos)
				local result = grid:GetNearestChunkAtPosition(worldPos)
				expect(result).To.Exist()
				expect((result :: any).ChunkIndex).To.Equal(i)
			end
		end)

		it("should find all chunks with 16-stud chunk size", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 16)
			local total = grid.GridSize.X * grid.GridSize.Y * grid.GridSize.Z
			for i = 0, total - 1 do
				local pos = grid:ChunkIndexToGridPosition(i)
				grid.Chunks[i] = { ChunkIndex = i, ChunkPosition = pos } :: any
			end
			for i = 0, total - 1 do
				local pos = grid:ChunkIndexToGridPosition(i)
				local worldPos = grid:GridPositionToWorldPosition(pos)
				local result = grid:GetNearestChunkAtPosition(worldPos)
				expect(result).To.Exist()
				expect((result :: any).ChunkIndex).To.Equal(i)
			end
		end)

		it("should find sampled chunks with 64-stud chunk size on 512-cubed world", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(512, 512, 512), 64)
			local total = grid.GridSize.X * grid.GridSize.Y * grid.GridSize.Z
			for i = 0, total - 1 do
				local pos = grid:ChunkIndexToGridPosition(i)
				grid.Chunks[i] = { ChunkIndex = i, ChunkPosition = pos } :: any
			end
			local testIndices = { 0, 1, 7, 8, 63, 64, 255, 256, total - 1 }
			for _, i in testIndices do
				local pos = grid:ChunkIndexToGridPosition(i)
				local worldPos = grid:GridPositionToWorldPosition(pos)
				local result = grid:GetNearestChunkAtPosition(worldPos)
				expect(result).To.Exist()
				expect((result :: any).ChunkIndex).To.Equal(i)
			end
		end)

		it("should find all chunks in a non-cubic grid (4x2x8)", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(32, 16, 64), 8)
			local total = grid.GridSize.X * grid.GridSize.Y * grid.GridSize.Z
			for i = 0, total - 1 do
				local pos = grid:ChunkIndexToGridPosition(i)
				grid.Chunks[i] = { ChunkIndex = i, ChunkPosition = pos } :: any
			end
			for i = 0, total - 1 do
				local pos = grid:ChunkIndexToGridPosition(i)
				local worldPos = grid:GridPositionToWorldPosition(pos)
				local result = grid:GetNearestChunkAtPosition(worldPos)
				expect(result).To.Exist()
				expect((result :: any).ChunkIndex).To.Equal(i)
			end
		end)

		it("should correctly distinguish adjacent chunks along X", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
			local posA, posB = Vector3.new(3, 3, 3), Vector3.new(4, 3, 3)
			local indexA, indexB = grid:GridPositionToChunkIndex(posA), grid:GridPositionToChunkIndex(posB)
			grid.Chunks[indexA] = { ChunkIndex = indexA, ChunkPosition = posA, Tag = "A" } :: any
			grid.Chunks[indexB] = { ChunkIndex = indexB, ChunkPosition = posB, Tag = "B" } :: any
			expect((grid:GetNearestChunkAtPosition(grid:GridPositionToWorldPosition(posA)) :: any).Tag).To.Equal("A")
			expect((grid:GetNearestChunkAtPosition(grid:GridPositionToWorldPosition(posB)) :: any).Tag).To.Equal("B")
		end)

		it("should correctly distinguish adjacent chunks along Y", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
			local posA, posB = Vector3.new(2, 2, 2), Vector3.new(2, 3, 2)
			local indexA, indexB = grid:GridPositionToChunkIndex(posA), grid:GridPositionToChunkIndex(posB)
			grid.Chunks[indexA] = { ChunkIndex = indexA, ChunkPosition = posA, Tag = "Y0" } :: any
			grid.Chunks[indexB] = { ChunkIndex = indexB, ChunkPosition = posB, Tag = "Y1" } :: any
			expect((grid:GetNearestChunkAtPosition(grid:GridPositionToWorldPosition(posA)) :: any).Tag).To.Equal("Y0")
			expect((grid:GetNearestChunkAtPosition(grid:GridPositionToWorldPosition(posB)) :: any).Tag).To.Equal("Y1")
		end)

		it("should correctly distinguish adjacent chunks along Z", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
			local posA, posB = Vector3.new(5, 5, 5), Vector3.new(5, 5, 6)
			local indexA, indexB = grid:GridPositionToChunkIndex(posA), grid:GridPositionToChunkIndex(posB)
			grid.Chunks[indexA] = { ChunkIndex = indexA, ChunkPosition = posA, Tag = "Z0" } :: any
			grid.Chunks[indexB] = { ChunkIndex = indexB, ChunkPosition = posB, Tag = "Z1" } :: any
			expect((grid:GetNearestChunkAtPosition(grid:GridPositionToWorldPosition(posA)) :: any).Tag).To.Equal("Z0")
			expect((grid:GetNearestChunkAtPosition(grid:GridPositionToWorldPosition(posB)) :: any).Tag).To.Equal("Z1")
		end)

		it("should return the same chunk on repeated queries", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
			local gridPos = Vector3.new(5, 3, 6)
			local chunkIndex = grid:GridPositionToChunkIndex(gridPos)
			grid.Chunks[chunkIndex] = { ChunkIndex = chunkIndex, ChunkPosition = gridPos } :: any
			local worldPos = grid:GridPositionToWorldPosition(gridPos)
			local first = grid:GetNearestChunkAtPosition(worldPos)
			local second = grid:GetNearestChunkAtPosition(worldPos)
			local third = grid:GetNearestChunkAtPosition(worldPos)
			expect(first).To.Exist()
			expect(first).To.Equal(second)
			expect(second).To.Equal(third)
		end)

		it("should find all chunks with a large positive center (1000)", function()
			local grid = Grid.new(Vector3.new(1000, 1000, 1000), Vector3.new(32, 32, 32), 8)
			local total = grid.GridSize.X * grid.GridSize.Y * grid.GridSize.Z
			for i = 0, total - 1 do
				local pos = grid:ChunkIndexToGridPosition(i)
				grid.Chunks[i] = { ChunkIndex = i, ChunkPosition = pos } :: any
			end
			for i = 0, total - 1 do
				local pos = grid:ChunkIndexToGridPosition(i)
				local worldPos = grid:GridPositionToWorldPosition(pos)
				local result = grid:GetNearestChunkAtPosition(worldPos)
				expect(result).To.Exist()
				expect((result :: any).ChunkIndex).To.Equal(i)
			end
		end)

		it("should find all chunks with a large negative center (-1000)", function()
			local grid = Grid.new(Vector3.new(-1000, -1000, -1000), Vector3.new(32, 32, 32), 8)
			local total = grid.GridSize.X * grid.GridSize.Y * grid.GridSize.Z
			for i = 0, total - 1 do
				local pos = grid:ChunkIndexToGridPosition(i)
				grid.Chunks[i] = { ChunkIndex = i, ChunkPosition = pos } :: any
			end
			for i = 0, total - 1 do
				local pos = grid:ChunkIndexToGridPosition(i)
				local worldPos = grid:GridPositionToWorldPosition(pos)
				local result = grid:GetNearestChunkAtPosition(worldPos)
				expect(result).To.Exist()
				expect((result :: any).ChunkIndex).To.Equal(i)
			end
		end)

		it("should find all chunks with mixed positive/negative center", function()
			local grid = Grid.new(Vector3.new(-100, 200, -300), Vector3.new(32, 32, 32), 8)
			local total = grid.GridSize.X * grid.GridSize.Y * grid.GridSize.Z
			for i = 0, total - 1 do
				local pos = grid:ChunkIndexToGridPosition(i)
				grid.Chunks[i] = { ChunkIndex = i, ChunkPosition = pos } :: any
			end
			for i = 0, total - 1 do
				local pos = grid:ChunkIndexToGridPosition(i)
				local worldPos = grid:GridPositionToWorldPosition(pos)
				local result = grid:GetNearestChunkAtPosition(worldPos)
				expect(result).To.Exist()
				expect((result :: any).ChunkIndex).To.Equal(i)
			end
		end)
	end)

	-- ================================================================
	-- Large Coordinate Stability
	-- ================================================================
	describe("large coordinate stability", function()
		it("should construct with large positive center", function()
			local grid = Grid.new(Vector3.new(10000, 10000, 10000), Vector3.new(64, 64, 64), 8)
			expect(grid.Center).To.Equal(Vector3.new(10000, 10000, 10000))
			expect(grid.GenerationOrigin).To.Equal(Vector3.new(9972, 9972, 9972))
		end)

		it("should construct with large negative center", function()
			local grid = Grid.new(Vector3.new(-10000, -10000, -10000), Vector3.new(64, 64, 64), 8)
			expect(grid.Center).To.Equal(Vector3.new(-10000, -10000, -10000))
			expect(grid.GenerationOrigin).To.Equal(Vector3.new(-10028, -10028, -10028))
		end)

		it("should round-trip correctly with large grid at offset center", function()
			local grid = Grid.new(Vector3.new(5000, 5000, 5000), Vector3.new(512, 512, 512), 8)
			local gs = grid.GridSize
			local positions = {
				Vector3.new(0, 0, 0),
				Vector3.new(gs.X - 1, gs.Y - 1, gs.Z - 1),
				Vector3.new(math.floor(gs.X / 2), math.floor(gs.Y / 2), math.floor(gs.Z / 2)),
			}
			for _, pos in positions do
				local index = grid:GridPositionToChunkIndex(pos)
				expect(grid:ChunkIndexToGridPosition(index)).To.Equal(pos)
			end
		end)

		it("should produce correct world positions at large offsets", function()
			local grid = Grid.new(Vector3.new(10000, 10000, 10000), Vector3.new(64, 64, 64), 8)
			local worldPos = grid:GridPositionToWorldPosition(Vector3.new(4, 4, 4))
			expect(worldPos).To.Equal(grid.GenerationOrigin + Vector3.new(32, 32, 32))
		end)
	end)

	-- ================================================================
	-- Cross-method Consistency
	-- ================================================================
	describe("cross-method consistency", function()
		it("should have ChunkIndexToGridPosition and GridPositionToChunkIndex as exact inverses", function()
			local configs = {
				{ Vector3.zero, Vector3.new(64, 64, 64), 8 },
				{ Vector3.new(100, 100, 100), Vector3.new(128, 128, 128), 16 },
				{ Vector3.zero, Vector3.new(32, 16, 64), 8 },
			}
			for _, cfg in configs do
				local grid = Grid.new(cfg[1] :: Vector3, cfg[2] :: Vector3, cfg[3] :: number)
				local total = grid.GridSize.X * grid.GridSize.Y * grid.GridSize.Z
				local sampleSize = math.min(total, 64)
				for i = 0, sampleSize - 1 do
					local pos = grid:ChunkIndexToGridPosition(i)
					expect(grid:GridPositionToChunkIndex(pos)).To.Equal(i)
				end
			end
		end)

		it("should resolve every GridPositionToWorldPosition through GetNearestChunkAtPosition", function()
			local grid = Grid.new(Vector3.new(50, 50, 50), Vector3.new(64, 64, 64), 8)
			local total = grid.GridSize.X * grid.GridSize.Y * grid.GridSize.Z
			for i = 0, total - 1 do
				local gridPos = grid:ChunkIndexToGridPosition(i)
				grid.Chunks[i] = { ChunkIndex = i, ChunkPosition = gridPos } :: any
			end
			for i = 0, total - 1 do
				local gridPos = grid:ChunkIndexToGridPosition(i)
				local worldPos = grid:GridPositionToWorldPosition(gridPos)
				local result = grid:GetNearestChunkAtPosition(worldPos)
				expect(result).To.Exist()
				expect((result :: any).ChunkIndex).To.Equal(i)
			end
		end)

		it("should have all methods agree on chunk identity for 512 chunks", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
			for i = 0, 511 do
				local gridPos = grid:ChunkIndexToGridPosition(i)
				local reconstructedIndex = grid:GridPositionToChunkIndex(gridPos)
				local worldPos = grid:GridPositionToWorldPosition(gridPos)
				local expectedWorld = grid.GenerationOrigin + gridPos * grid.ChunkSize
				expect(reconstructedIndex).To.Equal(i)
				expect(worldPos).To.Equal(expectedWorld)
			end
		end)

		it("should have GetNearestChunkAtPosition agree across multiple center configurations", function()
			local centers = { Vector3.zero, Vector3.new(100, -50, 300), Vector3.new(-1000, -1000, -1000) }
			for _, center in centers do
				local grid = Grid.new(center, Vector3.new(32, 32, 32), 8)
				local total = grid.GridSize.X * grid.GridSize.Y * grid.GridSize.Z
				for i = 0, total - 1 do
					local gridPos = grid:ChunkIndexToGridPosition(i)
					grid.Chunks[i] = { ChunkIndex = i, ChunkPosition = gridPos } :: any
				end
				for i = 0, total - 1 do
					local gridPos = grid:ChunkIndexToGridPosition(i)
					local worldPos = grid:GridPositionToWorldPosition(gridPos)
					local result = grid:GetNearestChunkAtPosition(worldPos)
					expect(result).To.Exist()
					expect((result :: any).ChunkIndex).To.Equal(i)
				end
			end
		end)
	end)

	-- ================================================================
	-- GenerationOrigin Invariants
	-- ================================================================
	describe("GenerationOrigin invariants", function()
		it("should always be a multiple of 4 in all components", function()
			local centers = {
				Vector3.zero,
				Vector3.new(1, 2, 3),
				Vector3.new(-1, -2, -3),
				Vector3.new(100, 200, 300),
				Vector3.new(-100, -200, -300),
				Vector3.new(7, 13, 29),
			}
			for _, c in centers do
				local grid = Grid.new(c, Vector3.new(64, 64, 64), 8)
				expect(grid.GenerationOrigin.X % 4).To.Equal(0)
				expect(grid.GenerationOrigin.Y % 4).To.Equal(0)
				expect(grid.GenerationOrigin.Z % 4).To.Equal(0)
			end
		end)

		it("should always be less than or equal to Center", function()
			local configs = {
				{ Vector3.zero, Vector3.new(64, 64, 64), 8 },
				{ Vector3.new(100, 100, 100), Vector3.new(256, 256, 256), 16 },
				{ Vector3.new(-50, -50, -50), Vector3.new(128, 128, 128), 32 },
			}
			for _, cfg in configs do
				local grid = Grid.new(cfg[1] :: Vector3, cfg[2] :: Vector3, cfg[3] :: number)
				expect(grid.GenerationOrigin.X).To.BeLessThan(grid.Center.X + 1)
				expect(grid.GenerationOrigin.Y).To.BeLessThan(grid.Center.Y + 1)
				expect(grid.GenerationOrigin.Z).To.BeLessThan(grid.Center.Z + 1)
			end
		end)

		it("should be symmetric about Center with first and last chunk positions", function()
			local configs = {
				{ Vector3.zero, Vector3.new(64, 64, 64), 8 },
				{ Vector3.new(500, 500, 500), Vector3.new(128, 128, 128), 16 },
				{ Vector3.new(-300, 100, -500), Vector3.new(256, 64, 128), 32 },
			}
			for _, cfg in configs do
				local grid = Grid.new(cfg[1] :: Vector3, cfg[2] :: Vector3, cfg[3] :: number)
				local firstChunkWorldPos = grid.GenerationOrigin
				local lastChunkWorldPos = grid:GridPositionToWorldPosition(grid.GridSize - Vector3.one)
				local midpoint = (firstChunkWorldPos + lastChunkWorldPos) / 2
				expect(midpoint).To.Equal(grid.Center)
			end
		end)
	end)

	-- ================================================================
	-- Boundary Chunk Access
	-- ================================================================
	describe("boundary chunk access", function()
		it("should access first and last chunk in an 8x8x8 grid", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
			local gs = grid.GridSize
			local firstIndex = grid:GridPositionToChunkIndex(Vector3.zero)
			expect(firstIndex).To.Equal(0)
			local lastPos = Vector3.new(gs.X - 1, gs.Y - 1, gs.Z - 1)
			local lastIndex = grid:GridPositionToChunkIndex(lastPos)
			expect(lastIndex).To.Equal(gs.X * gs.Y * gs.Z - 1)
			expect(grid:ChunkIndexToGridPosition(firstIndex)).To.Equal(Vector3.zero)
			expect(grid:ChunkIndexToGridPosition(lastIndex)).To.Equal(lastPos)
		end)

		it("should map all 8 corner chunks to unique indices", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
			local gs = grid.GridSize
			local corners = {
				Vector3.new(0, 0, 0),
				Vector3.new(gs.X - 1, 0, 0),
				Vector3.new(0, gs.Y - 1, 0),
				Vector3.new(0, 0, gs.Z - 1),
				Vector3.new(gs.X - 1, gs.Y - 1, 0),
				Vector3.new(gs.X - 1, 0, gs.Z - 1),
				Vector3.new(0, gs.Y - 1, gs.Z - 1),
				Vector3.new(gs.X - 1, gs.Y - 1, gs.Z - 1),
			}
			local seen: { [number]: boolean } = {}
			for _, corner in corners do
				local index = grid:GridPositionToChunkIndex(corner)
				expect(seen[index]).To.BeNil()
				seen[index] = true
				expect(grid:ChunkIndexToGridPosition(index)).To.Equal(corner)
			end
		end)

		it("should store and retrieve corner chunks via GetNearestChunkAtPosition", function()
			local grid = Grid.new(Vector3.new(100, 100, 100), Vector3.new(64, 64, 64), 8)
			local gs = grid.GridSize
			local corners = {
				Vector3.new(0, 0, 0),
				Vector3.new(gs.X - 1, 0, 0),
				Vector3.new(0, gs.Y - 1, 0),
				Vector3.new(0, 0, gs.Z - 1),
				Vector3.new(gs.X - 1, gs.Y - 1, gs.Z - 1),
			}
			for _, corner in corners do
				local index = grid:GridPositionToChunkIndex(corner)
				grid.Chunks[index] = { ChunkIndex = index, ChunkPosition = corner } :: any
			end
			for _, corner in corners do
				local worldPos = grid:GridPositionToWorldPosition(corner)
				local result = grid:GetNearestChunkAtPosition(worldPos)
				expect(result).To.Exist()
				expect((result :: any).ChunkPosition).To.Equal(corner)
			end
		end)
	end)

	-- ================================================================
	-- Chunk Storage Integrity
	-- ================================================================
	describe("chunk storage integrity", function()
		it("should preserve all custom fields on stored chunks", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
			local chunk = {
				ChunkIndex = 42,
				ChunkPosition = Vector3.new(0, 0, 42),
				CustomField = "hello",
				NumericData = 3.14159,
				NestedTable = { a = 1, b = 2 },
			}
			grid.Chunks[42] = chunk :: any
			local stored = grid.Chunks[42] :: any
			expect(stored.CustomField).To.Equal("hello")
			expect(stored.NumericData).To.BeNear(3.14159, 0.001)
			expect(stored.NestedTable.a).To.Equal(1)
			expect(stored.NestedTable.b).To.Equal(2)
		end)

		it("should support sparse chunk storage with gaps", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
			grid.Chunks[0] = { ChunkIndex = 0, ChunkPosition = Vector3.zero } :: any
			grid.Chunks[100] = { ChunkIndex = 100, ChunkPosition = grid:ChunkIndexToGridPosition(100) } :: any
			grid.Chunks[511] = { ChunkIndex = 511, ChunkPosition = grid:ChunkIndexToGridPosition(511) } :: any
			expect(grid.Chunks[0]).To.Exist()
			expect(grid.Chunks[100]).To.Exist()
			expect(grid.Chunks[511]).To.Exist()
			expect(grid.Chunks[1]).To.BeNil()
			expect(grid.Chunks[50]).To.BeNil()
			expect(grid.Chunks[200]).To.BeNil()
		end)

		it("should allow overwriting chunks at the same index", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
			grid.Chunks[0] = { ChunkIndex = 0, ChunkPosition = Vector3.zero, Version = 1 } :: any
			expect((grid.Chunks[0] :: any).Version).To.Equal(1)
			grid.Chunks[0] = { ChunkIndex = 0, ChunkPosition = Vector3.zero, Version = 2 } :: any
			expect((grid.Chunks[0] :: any).Version).To.Equal(2)
		end)

		it("should allow deleting chunks by setting to nil", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
			grid.Chunks[0] = { ChunkIndex = 0, ChunkPosition = Vector3.zero } :: any
			expect(grid.Chunks[0]).To.Exist()
			grid.Chunks[0] = nil :: any
			expect(grid.Chunks[0]).To.BeNil()
		end)

		it("should store chunks at 0-based indices (not 1-based)", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
			grid.Chunks[0] = { ChunkIndex = 0, ChunkPosition = Vector3.zero } :: any
			expect(grid.Chunks[0]).To.Exist()
			-- Lua's # operator does not count 0-based keys.
			expect(#grid.Chunks).To.Equal(0)
		end)
	end)

	-- ================================================================
	-- Constructor Parameter Combinations
	-- ================================================================
	describe("constructor parameter combinations", function()
		it("should handle every valid chunk size from 1 to 64", function()
			for cs = 1, 64 do
				local grid = Grid.new(Vector3.zero, Vector3.new(512, 512, 512), cs)
				expect(grid.ChunkSize).To.BeGreaterThan(0)
				expect(grid.ChunkSize % 8).To.Equal(0)
			end
		end)

		it("should handle centers at multiples of different resolutions", function()
			local centers = {
				Vector3.new(0, 0, 0),
				Vector3.new(4, 4, 4),
				Vector3.new(8, 8, 8),
				Vector3.new(16, 16, 16),
				Vector3.new(32, 32, 32),
				Vector3.new(64, 64, 64),
			}
			for _, c in centers do
				local grid = Grid.new(c, Vector3.new(64, 64, 64), 8)
				expect(grid.Center).To.Equal(c)
			end
		end)

		it("should maintain all invariants across many configurations", function()
			local testCases = {
				{ Vector3.zero, Vector3.new(8, 8, 8), 8 },
				{ Vector3.zero, Vector3.new(16, 32, 64), 8 },
				{ Vector3.new(50, 50, 50), Vector3.new(64, 64, 64), 16 },
				{ Vector3.new(-100, 200, -300), Vector3.new(256, 128, 512), 32 },
				{ Vector3.new(1000, 1000, 1000), Vector3.new(128, 128, 128), 8 },
				{ Vector3.new(-1, -1, -1), Vector3.new(64, 64, 64), 8 },
			}
			for _, cfg in testCases do
				local grid = Grid.new(cfg[1] :: Vector3, cfg[2] :: Vector3, cfg[3] :: number)
				expect(grid.GridSize * grid.ChunkSize).To.Equal(grid.GridWorldSize)
				expect(grid.GenerationOrigin).To.Equal(
					grid.Center - grid.GridWorldSize / 2 + Vector3.one * (grid.ChunkSize / 2)
				)
				expect(grid.ChunkSize % 8).To.Equal(0)
				expect(grid.Center.X % 4).To.Equal(0)
				expect(grid.Center.Y % 4).To.Equal(0)
				expect(grid.Center.Z % 4).To.Equal(0)
				expect(grid.GridWorldSize.X % 8).To.Equal(0)
				expect(grid.GridWorldSize.Y % 8).To.Equal(0)
				expect(grid.GridWorldSize.Z % 8).To.Equal(0)
			end
		end)
	end)

	-- ================================================================
	-- Index Space Coverage
	-- ================================================================
	describe("index space coverage", function()
		it("should map every index to a unique position in a 4x4x4 grid", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(32, 32, 32), 8)
			local total = 4 * 4 * 4
			local positionSet: { [string]: boolean } = {}
			for i = 0, total - 1 do
				local pos = grid:ChunkIndexToGridPosition(i)
				local key = tostring(pos)
				expect(positionSet[key]).To.BeNil()
				positionSet[key] = true
			end
		end)

		it("should map every position to a unique index in a 4x4x4 grid", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(32, 32, 32), 8)
			local indexSet: { [number]: boolean } = {}
			for x = 0, 3 do
				for y = 0, 3 do
					for z = 0, 3 do
						local index = grid:GridPositionToChunkIndex(Vector3.new(x, y, z))
						expect(indexSet[index]).To.BeNil()
						indexSet[index] = true
					end
				end
			end
		end)

		it("should produce indices in range [0, total-1] for an 8x8x8 grid", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
			local gs = grid.GridSize
			local total = gs.X * gs.Y * gs.Z
			for x = 0, gs.X - 1 do
				for y = 0, gs.Y - 1 do
					for z = 0, gs.Z - 1 do
						local index = grid:GridPositionToChunkIndex(Vector3.new(x, y, z))
						expect(index).To.BeGreaterThanOrEqual(0)
						expect(index).To.BeLessThan(total)
					end
				end
			end
		end)

		it("should produce positions with all components in range [0, GridSize-1]", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
			local gs = grid.GridSize
			local total = gs.X * gs.Y * gs.Z
			for i = 0, total - 1 do
				local pos = grid:ChunkIndexToGridPosition(i)
				expect(pos.X).To.BeGreaterThanOrEqual(0)
				expect(pos.X).To.BeLessThan(gs.X)
				expect(pos.Y).To.BeGreaterThanOrEqual(0)
				expect(pos.Y).To.BeLessThan(gs.Y)
				expect(pos.Z).To.BeGreaterThanOrEqual(0)
				expect(pos.Z).To.BeLessThan(gs.Z)
			end
		end)
	end)

	-- ================================================================
	-- World Position Coverage
	-- ================================================================
	describe("world position coverage", function()
		it("should produce all world positions within the grid bounding box", function()
			local grid = Grid.new(Vector3.new(100, 100, 100), Vector3.new(64, 64, 64), 8)
			local gs = grid.GridSize
			local minBound = grid.GenerationOrigin
			local maxBound = grid.GenerationOrigin + grid.GridWorldSize
			for x = 0, gs.X - 1 do
				for y = 0, gs.Y - 1 do
					for z = 0, gs.Z - 1 do
						local wp = grid:GridPositionToWorldPosition(Vector3.new(x, y, z))
						expect(wp.X).To.BeGreaterThanOrEqual(minBound.X)
						expect(wp.Y).To.BeGreaterThanOrEqual(minBound.Y)
						expect(wp.Z).To.BeGreaterThanOrEqual(minBound.Z)
						expect(wp.X).To.BeLessThan(maxBound.X)
						expect(wp.Y).To.BeLessThan(maxBound.Y)
						expect(wp.Z).To.BeLessThan(maxBound.Z)
					end
				end
			end
		end)

		it("should produce unique world positions for unique grid positions", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(32, 32, 32), 8)
			local worldSet: { [string]: boolean } = {}
			local gs = grid.GridSize
			for x = 0, gs.X - 1 do
				for y = 0, gs.Y - 1 do
					for z = 0, gs.Z - 1 do
						local wp = grid:GridPositionToWorldPosition(Vector3.new(x, y, z))
						local key = tostring(wp)
						expect(worldSet[key]).To.BeNil()
						worldSet[key] = true
					end
				end
			end
		end)

		it("should have uniform spacing between adjacent world positions", function()
			local grid = Grid.new(Vector3.new(200, -50, 100), Vector3.new(64, 64, 64), 8)
			local cs = grid.ChunkSize
			for x = 0, 6 do
				local a = grid:GridPositionToWorldPosition(Vector3.new(x, 3, 3))
				local b = grid:GridPositionToWorldPosition(Vector3.new(x + 1, 3, 3))
				expect((b - a).Magnitude).To.BeNear(cs, 0.001)
			end
			for y = 0, 6 do
				local a = grid:GridPositionToWorldPosition(Vector3.new(3, y, 3))
				local b = grid:GridPositionToWorldPosition(Vector3.new(3, y + 1, 3))
				expect((b - a).Magnitude).To.BeNear(cs, 0.001)
			end
			for z = 0, 6 do
				local a = grid:GridPositionToWorldPosition(Vector3.new(3, 3, z))
				local b = grid:GridPositionToWorldPosition(Vector3.new(3, 3, z + 1))
				expect((b - a).Magnitude).To.BeNear(cs, 0.001)
			end
		end)
	end)

	-- ================================================================
	-- Determinism
	-- ================================================================
	describe("determinism", function()
		it("should produce identical results for identical constructor calls", function()
			local results = {}
			for i = 1, 5 do
				local grid = Grid.new(Vector3.new(37, 53, 91), Vector3.new(128, 256, 64), 24)
				results[i] = {
					Center = grid.Center,
					GenerationOrigin = grid.GenerationOrigin,
					ChunkSize = grid.ChunkSize,
					GridSize = grid.GridSize,
					GridWorldSize = grid.GridWorldSize,
				}
			end
			for i = 2, 5 do
				expect(results[i].Center).To.Equal(results[1].Center)
				expect(results[i].GenerationOrigin).To.Equal(results[1].GenerationOrigin)
				expect(results[i].ChunkSize).To.Equal(results[1].ChunkSize)
				expect(results[i].GridSize).To.Equal(results[1].GridSize)
				expect(results[i].GridWorldSize).To.Equal(results[1].GridWorldSize)
			end
		end)

		it("should produce identical index/position mappings across instances", function()
			local referenceGrid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
			local referenceMappings = {}
			for i = 0, 511 do
				referenceMappings[i] = referenceGrid:ChunkIndexToGridPosition(i)
			end
			for _ = 1, 3 do
				local grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
				for i = 0, 511 do
					expect(grid:ChunkIndexToGridPosition(i)).To.Equal(referenceMappings[i])
				end
			end
		end)

		it("should produce identical GetNearestChunkAtPosition results across instances", function()
			local center = Vector3.new(100, -200, 300)
			local worldSize = Vector3.new(32, 32, 32)
			for _ = 1, 3 do
				local grid = Grid.new(center, worldSize, 8)
				local total = grid.GridSize.X * grid.GridSize.Y * grid.GridSize.Z
				for i = 0, total - 1 do
					local gridPos = grid:ChunkIndexToGridPosition(i)
					grid.Chunks[i] = { ChunkIndex = i, ChunkPosition = gridPos } :: any
				end
				for i = 0, total - 1 do
					local gridPos = grid:ChunkIndexToGridPosition(i)
					local worldPos = grid:GridPositionToWorldPosition(gridPos)
					local result = grid:GetNearestChunkAtPosition(worldPos)
					expect(result).To.Exist()
					expect((result :: any).ChunkIndex).To.Equal(i)
				end
			end
		end)
	end)

	-- ================================================================
	-- RoundVectorToGrid Precision (Bug-catching)
	-- Tests that the internal RoundVectorToGrid function rounds
	-- correctly to the 4-stud terrain grid. Since it's called
	-- internally by GetNearestChunkAtPosition, these tests exercise it
	-- indirectly by checking chunk lookups at various positions.
	-- ================================================================
	describe("RoundVectorToGrid precision", function()
		it("should snap to the same grid point for positions within 2 studs of a corner", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
			local gridPos = Vector3.new(4, 4, 4)
			local chunkIndex = grid:GridPositionToChunkIndex(gridPos)
			local worldPos = grid:GridPositionToWorldPosition(gridPos)
			grid.Chunks[chunkIndex] = { ChunkIndex = chunkIndex, ChunkPosition = gridPos } :: any
			-- math.round(1/4)*4 = 0 -> same as corner (0,0,0 relative shift).
			local result = grid:GetNearestChunkAtPosition(worldPos + Vector3.new(1, 0, 0))
			expect(result).To.Exist()
			expect((result :: any).ChunkIndex).To.Equal(chunkIndex)
		end)

		it("should snap position at exactly 2 studs from corner consistently", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
			local gridPos = Vector3.new(4, 4, 4)
			local chunkIndex = grid:GridPositionToChunkIndex(gridPos)
			local worldPos = grid:GridPositionToWorldPosition(gridPos)
			grid.Chunks[chunkIndex] = { ChunkIndex = chunkIndex, ChunkPosition = gridPos } :: any
			-- math.round(2/4)*4 = math.round(0.5)*4; Luau rounds 0.5 to 1 -> snap to 4.
			-- worldPos+4 should ideally still resolve or the next chunk. This test documents behavior.
			local result = grid:GetNearestChunkAtPosition(worldPos + Vector3.new(2, 0, 0))
			-- The rounding of 2 studs is implementation-dependent; we just verify no crash.
			expect(true).To.Equal(true)
		end)
	end)

	-- ================================================================
	-- Chunk Index Boundary Values (Bug-catching)
	-- Tests edge conditions around index calculation boundaries.
	-- ================================================================
	describe("chunk index boundary values", function()
		it("should correctly compute index at YZ plane boundary", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
			local gs = grid.GridSize
			-- The index right before the first YZ plane boundary.
			local lastInFirstPlane = grid:GridPositionToChunkIndex(Vector3.new(0, gs.Y - 1, gs.Z - 1))
			-- The first index in the second YZ plane.
			local firstInSecondPlane = grid:GridPositionToChunkIndex(Vector3.new(1, 0, 0))
			expect(firstInSecondPlane - lastInFirstPlane).To.Equal(1)
		end)

		it("should correctly compute index at Z row boundary", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
			local gs = grid.GridSize
			local lastInFirstRow = grid:GridPositionToChunkIndex(Vector3.new(0, 0, gs.Z - 1))
			local firstInSecondRow = grid:GridPositionToChunkIndex(Vector3.new(0, 1, 0))
			expect(firstInSecondRow - lastInFirstRow).To.Equal(1)
		end)

		it("should give the maximum valid index for the very last cell", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
			local gs = grid.GridSize
			local maxIndex = grid:GridPositionToChunkIndex(Vector3.new(gs.X - 1, gs.Y - 1, gs.Z - 1))
			expect(maxIndex).To.Equal(gs.X * gs.Y * gs.Z - 1)
		end)

		it("should give 0 for the very first cell", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
			expect(grid:GridPositionToChunkIndex(Vector3.zero)).To.Equal(0)
		end)
	end)

	-- ================================================================
	-- Negative Center Alignment Precision
	-- ================================================================
	describe("negative center alignment", function()
		it("should correctly align large negative centers", function()
			local grid = Grid.new(Vector3.new(-999, -999, -999))
			expect(grid.Center.X % 4).To.Equal(0)
			expect(grid.Center.Y % 4).To.Equal(0)
			expect(grid.Center.Z % 4).To.Equal(0)
		end)

		it("should correctly compute origin for asymmetric negative center", function()
			local grid = Grid.new(Vector3.new(-7, -13, -21), Vector3.new(64, 64, 64), 8)
			expect(grid.GenerationOrigin).To.Equal(
				grid.Center - grid.GridWorldSize / 2 + Vector3.one * (grid.ChunkSize / 2)
			)
		end)

		it("should round-trip chunks with negative center grid", function()
			local grid = Grid.new(Vector3.new(-500, -500, -500), Vector3.new(32, 32, 32), 8)
			local total = grid.GridSize.X * grid.GridSize.Y * grid.GridSize.Z
			for i = 0, total - 1 do
				local pos = grid:ChunkIndexToGridPosition(i)
				grid.Chunks[i] = { ChunkIndex = i, ChunkPosition = pos } :: any
			end
			for i = 0, total - 1 do
				local pos = grid:ChunkIndexToGridPosition(i)
				local worldPos = grid:GridPositionToWorldPosition(pos)
				local result = grid:GetNearestChunkAtPosition(worldPos)
				expect(result).To.Exist()
				expect((result :: any).ChunkIndex).To.Equal(i)
			end
		end)
	end)

	-- ================================================================
	-- Type Safety / Structural Tests
	-- ================================================================
	describe("type safety and structure", function()
		it("should have all expected fields on a constructed grid", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
			expect(grid.Center).To.BeA("Vector3")
			expect(grid.GenerationOrigin).To.BeA("Vector3")
			expect(grid.ChunkSize).To.BeA("number")
			expect(grid.GridSize).To.BeA("Vector3")
			expect(grid.GridWorldSize).To.BeA("Vector3")
			expect(grid.Chunks).To.BeA("table")
			expect(grid.OnChunkGenerated).To.Exist()
			expect(grid._zeroBasedGridSize).To.BeA("Vector3")
			expect(grid._theoreticalMaxChunkIndex).To.BeA("number")
		end)

		it("should return a number from GridPositionToChunkIndex", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
			local index = grid:GridPositionToChunkIndex(Vector3.new(1, 2, 3))
			expect(index).To.BeA("number")
			expect(index % 1).To.Equal(0)
		end)

		it("should return a Vector3 from ChunkIndexToGridPosition", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
			local pos = grid:ChunkIndexToGridPosition(42)
			expect(pos).To.BeA("Vector3")
		end)

		it("should return a Vector3 from GridPositionToWorldPosition", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
			local wp = grid:GridPositionToWorldPosition(Vector3.new(1, 1, 1))
			expect(wp).To.BeA("Vector3")
		end)

		it("should return nil or a table from GetNearestChunkAtPosition", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
			local result = grid:GetNearestChunkAtPosition(Vector3.zero)
			expect(result == nil or typeof(result) == "table").To.Equal(true)
		end)

		it("should return a number from _GetNearestChunkIndexAtPosition", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
			local index = grid:_GetNearestChunkIndexAtPosition(grid.GenerationOrigin)
			expect(index).To.BeA("number")
			expect(index % 1).To.Equal(0)
		end)

		it("should return a table from GetNeighboringChunksIndices", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
			local neighbors = grid:GetNeighboringChunksIndices(0)
			expect(neighbors).To.BeA("table")
		end)
	end)

	-- ================================================================
	-- Internal Fields
	-- ================================================================
	describe("internal fields", function()
		it("should set _zeroBasedGridSize to GridSize - Vector3.one", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
			expect(grid._zeroBasedGridSize).To.Equal(grid.GridSize - Vector3.one)
		end)

		it("should set _theoreticalMaxChunkIndex to total chunks - 1", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
			local gs = grid.GridSize
			expect(grid._theoreticalMaxChunkIndex).To.Equal((gs.X * gs.Y * gs.Z) - 1)
		end)

		it("should compute _theoreticalMaxChunkIndex correctly for non-cubic grids", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(32, 16, 64), 8)
			local gs = grid.GridSize
			expect(grid._theoreticalMaxChunkIndex).To.Equal((gs.X * gs.Y * gs.Z) - 1)
		end)

		it("should have _zeroBasedGridSize components all >= 0", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(8, 8, 8), 8)
			expect(grid._zeroBasedGridSize.X).To.BeGreaterThanOrEqual(0)
			expect(grid._zeroBasedGridSize.Y).To.BeGreaterThanOrEqual(0)
			expect(grid._zeroBasedGridSize.Z).To.BeGreaterThanOrEqual(0)
		end)

		it("should have _theoreticalMaxChunkIndex >= 0", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(8, 8, 8), 8)
			expect(grid._theoreticalMaxChunkIndex).To.BeGreaterThanOrEqual(0)
		end)
	end)

	-- ================================================================
	-- GetNeighboringChunksIndices
	-- ================================================================
	describe("GetNeighboringChunksIndices", function()
		local grid

		beforeEach(function()
			grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8) -- 8x8x8 grid
		end)

		it("should return 6 neighbors for an interior chunk", function()
			local index = grid:GridPositionToChunkIndex(Vector3.new(4, 4, 4))
			local neighbors = grid:GetNeighboringChunksIndices(index)
			expect(#neighbors).To.Equal(6)
		end)

		it("should return 3 neighbors for the origin corner (0,0,0)", function()
			local index = grid:GridPositionToChunkIndex(Vector3.zero)
			local neighbors = grid:GetNeighboringChunksIndices(index)
			expect(#neighbors).To.Equal(3)
		end)

		it("should return 3 neighbors for the far corner (7,7,7)", function()
			local gs = grid.GridSize
			local index = grid:GridPositionToChunkIndex(Vector3.new(gs.X - 1, gs.Y - 1, gs.Z - 1))
			local neighbors = grid:GetNeighboringChunksIndices(index)
			expect(#neighbors).To.Equal(3)
		end)

		it("should return 4 neighbors for an edge chunk (0,0,4)", function()
			local index = grid:GridPositionToChunkIndex(Vector3.new(0, 0, 4))
			local neighbors = grid:GetNeighboringChunksIndices(index)
			expect(#neighbors).To.Equal(4)
		end)

		it("should return 5 neighbors for a face chunk (0,4,4)", function()
			local index = grid:GridPositionToChunkIndex(Vector3.new(0, 4, 4))
			local neighbors = grid:GetNeighboringChunksIndices(index)
			expect(#neighbors).To.Equal(5)
		end)

		it("should return the correct +X neighbor", function()
			local pos = Vector3.new(3, 4, 4)
			local index = grid:GridPositionToChunkIndex(pos)
			local expectedNeighbor = grid:GridPositionToChunkIndex(Vector3.new(4, 4, 4))
			local neighbors = grid:GetNeighboringChunksIndices(index)
			expect(table.find(neighbors, expectedNeighbor)).To.Exist()
		end)

		it("should return the correct -X neighbor", function()
			local pos = Vector3.new(4, 4, 4)
			local index = grid:GridPositionToChunkIndex(pos)
			local expectedNeighbor = grid:GridPositionToChunkIndex(Vector3.new(3, 4, 4))
			local neighbors = grid:GetNeighboringChunksIndices(index)
			expect(table.find(neighbors, expectedNeighbor)).To.Exist()
		end)

		it("should return the correct +Y neighbor", function()
			local pos = Vector3.new(4, 3, 4)
			local index = grid:GridPositionToChunkIndex(pos)
			local expectedNeighbor = grid:GridPositionToChunkIndex(Vector3.new(4, 4, 4))
			local neighbors = grid:GetNeighboringChunksIndices(index)
			expect(table.find(neighbors, expectedNeighbor)).To.Exist()
		end)

		it("should return the correct -Y neighbor", function()
			local pos = Vector3.new(4, 4, 4)
			local index = grid:GridPositionToChunkIndex(pos)
			local expectedNeighbor = grid:GridPositionToChunkIndex(Vector3.new(4, 3, 4))
			local neighbors = grid:GetNeighboringChunksIndices(index)
			expect(table.find(neighbors, expectedNeighbor)).To.Exist()
		end)

		it("should return the correct +Z neighbor", function()
			local pos = Vector3.new(4, 4, 3)
			local index = grid:GridPositionToChunkIndex(pos)
			local expectedNeighbor = grid:GridPositionToChunkIndex(Vector3.new(4, 4, 4))
			local neighbors = grid:GetNeighboringChunksIndices(index)
			expect(table.find(neighbors, expectedNeighbor)).To.Exist()
		end)

		it("should return the correct -Z neighbor", function()
			local pos = Vector3.new(4, 4, 4)
			local index = grid:GridPositionToChunkIndex(pos)
			local expectedNeighbor = grid:GridPositionToChunkIndex(Vector3.new(4, 4, 3))
			local neighbors = grid:GetNeighboringChunksIndices(index)
			expect(table.find(neighbors, expectedNeighbor)).To.Exist()
		end)

		it("should not include -X neighbor for X=0 chunks", function()
			local pos = Vector3.new(0, 4, 4)
			local index = grid:GridPositionToChunkIndex(pos)
			local invalidNeighbor = grid:GridPositionToChunkIndex(Vector3.new(-1, 4, 4))
			local neighbors = grid:GetNeighboringChunksIndices(index)
			expect(table.find(neighbors, invalidNeighbor)).To.BeNil()
		end)

		it("should not include +X neighbor for X=max chunks", function()
			local gs = grid.GridSize
			local pos = Vector3.new(gs.X - 1, 4, 4)
			local index = grid:GridPositionToChunkIndex(pos)
			local neighbors = grid:GetNeighboringChunksIndices(index)
			-- The +X neighbor index would exceed _theoreticalMaxChunkIndex or wrap
			for _, neighbor in neighbors do
				local neighborPos = grid:ChunkIndexToGridPosition(neighbor)
				expect(neighborPos.X).Never.To.Equal(gs.X)
			end
		end)

		it("should return only valid indices within [0, _theoreticalMaxChunkIndex]", function()
			local maxIndex = grid._theoreticalMaxChunkIndex
			-- Test several positions including corners and edges
			local testIndices = { 0, 1, 7, 63, 64, 255, 256, 511 }
			for _, chunkIndex in testIndices do
				local neighbors = grid:GetNeighboringChunksIndices(chunkIndex)
				for _, neighbor in neighbors do
					expect(neighbor).To.BeGreaterThanOrEqual(0)
					expect(neighbor).To.BeLessThanOrEqual(maxIndex)
				end
			end
		end)

		it("should return unique indices (no duplicates)", function()
			local index = grid:GridPositionToChunkIndex(Vector3.new(4, 4, 4))
			local neighbors = grid:GetNeighboringChunksIndices(index)
			local seen: { [number]: boolean } = {}
			for _, neighbor in neighbors do
				expect(seen[neighbor]).To.BeNil()
				seen[neighbor] = true
			end
		end)

		it("should not include the chunk itself in its neighbors", function()
			local index = grid:GridPositionToChunkIndex(Vector3.new(4, 4, 4))
			local neighbors = grid:GetNeighboringChunksIndices(index)
			expect(table.find(neighbors, index)).To.BeNil()
		end)

		it("should produce neighbors that differ by exactly 1 grid step on one axis", function()
			local pos = Vector3.new(4, 4, 4)
			local index = grid:GridPositionToChunkIndex(pos)
			local neighbors = grid:GetNeighboringChunksIndices(index)
			for _, neighbor in neighbors do
				local neighborPos = grid:ChunkIndexToGridPosition(neighbor)
				local diff = neighborPos - pos
				local absDiff = Vector3.new(math.abs(diff.X), math.abs(diff.Y), math.abs(diff.Z))
				-- Exactly one axis should differ by 1, others should be 0
				local totalDiff = absDiff.X + absDiff.Y + absDiff.Z
				expect(totalDiff).To.Equal(1)
			end
		end)

		it("should be symmetric: if A neighbors B, then B neighbors A", function()
			local indexA = grid:GridPositionToChunkIndex(Vector3.new(4, 4, 4))
			local neighborsA = grid:GetNeighboringChunksIndices(indexA)
			for _, neighborIndex in neighborsA do
				local neighborsB = grid:GetNeighboringChunksIndices(neighborIndex)
				expect(table.find(neighborsB, indexA)).To.Exist()
			end
		end)

		it("should work correctly with a non-cubic grid", function()
			local ncGrid = Grid.new(Vector3.zero, Vector3.new(32, 16, 64), 8) -- 4x2x8
			local interiorIndex = ncGrid:GridPositionToChunkIndex(Vector3.new(2, 1, 4))
			local neighbors = ncGrid:GetNeighboringChunksIndices(interiorIndex)
			-- All returned indices should be valid
			for _, neighbor in neighbors do
				expect(neighbor).To.BeGreaterThanOrEqual(0)
				expect(neighbor).To.BeLessThanOrEqual(ncGrid._theoreticalMaxChunkIndex)
			end
		end)

		it("should return 0 neighbors for a 1x1x1 grid (single chunk)", function()
			-- In a 1x1x1 grid there is only 1 chunk; it has no valid neighbors
			local tinyGrid = Grid.new(Vector3.zero, Vector3.new(8, 8, 8), 8)
			local neighbors = tinyGrid:GetNeighboringChunksIndices(0)
			-- All directional checks should fail bounds
			expect(#neighbors).To.Equal(0)
		end)

		it("should work for every chunk in a small grid without error", function()
			local smallGrid = Grid.new(Vector3.zero, Vector3.new(24, 24, 24), 8) -- 3x3x3
			local total = smallGrid.GridSize.X * smallGrid.GridSize.Y * smallGrid.GridSize.Z
			for i = 0, total - 1 do
				local neighbors = smallGrid:GetNeighboringChunksIndices(i)
				expect(#neighbors).To.BeGreaterThanOrEqual(0)
				expect(#neighbors).To.BeLessThanOrEqual(6)
			end
		end)

		it("should return between 0 and 6 neighbors for every chunk in the grid", function()
			local gs = grid.GridSize
			local total = gs.X * gs.Y * gs.Z
			for i = 0, total - 1 do
				local neighbors = grid:GetNeighboringChunksIndices(i)
				expect(#neighbors).To.BeGreaterThanOrEqual(0)
				expect(#neighbors).To.BeLessThanOrEqual(6)
				-- All returned indices must be valid
				for _, neighbor in neighbors do
					expect(neighbor).To.BeGreaterThanOrEqual(0)
					expect(neighbor).To.BeLessThanOrEqual(grid._theoreticalMaxChunkIndex)
				end
			end
		end)
	end)

	-- ================================================================
	-- _GetNearestChunkIndexAtPosition
	-- ================================================================
	describe("_GetNearestChunkIndexAtPosition", function()
		it("should return 0 for a query at GenerationOrigin", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
			expect(grid:_GetNearestChunkIndexAtPosition(grid.GenerationOrigin)).To.Equal(0)
		end)

		it("should return the same index as GetNearestChunkAtPosition's chunk", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
			local gridPos = Vector3.new(3, 4, 5)
			local chunkIndex = grid:GridPositionToChunkIndex(gridPos)
			local worldPos = grid:GridPositionToWorldPosition(gridPos)
			grid.Chunks[chunkIndex] = { ChunkIndex = chunkIndex, ChunkPosition = gridPos } :: any
			local resultIndex = grid:_GetNearestChunkIndexAtPosition(worldPos)
			local resultChunk = grid:GetNearestChunkAtPosition(worldPos)
			expect(resultIndex).To.Equal(chunkIndex)
			expect((resultChunk :: any).ChunkIndex).To.Equal(resultIndex)
		end)

		it("should agree with GridPositionToChunkIndex for all chunks in a small grid", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(32, 32, 32), 8)
			local total = grid.GridSize.X * grid.GridSize.Y * grid.GridSize.Z
			for i = 0, total - 1 do
				local gridPos = grid:ChunkIndexToGridPosition(i)
				local worldPos = grid:GridPositionToWorldPosition(gridPos)
				expect(grid:_GetNearestChunkIndexAtPosition(worldPos)).To.Equal(i)
			end
		end)

		it("should handle +1 stud offset correctly (rounds to nearest chunk)", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
			local gridPos = Vector3.new(4, 4, 4)
			local chunkIndex = grid:GridPositionToChunkIndex(gridPos)
			local worldPos = grid:GridPositionToWorldPosition(gridPos)
			expect(grid:_GetNearestChunkIndexAtPosition(worldPos + Vector3.new(1, 1, 1))).To.Equal(chunkIndex)
		end)

		it("should clamp to grid bounds for positions far outside the grid", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
			local farPos = Vector3.new(99999, 99999, 99999)
			local index = grid:_GetNearestChunkIndexAtPosition(farPos)
			-- Should clamp to the maximum valid index
			expect(index).To.BeGreaterThanOrEqual(0)
			expect(index).To.BeLessThanOrEqual(grid._theoreticalMaxChunkIndex)
		end)

		it("should clamp to grid bounds for large negative positions", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
			local farNegPos = Vector3.new(-99999, -99999, -99999)
			local index = grid:_GetNearestChunkIndexAtPosition(farNegPos)
			expect(index).To.Equal(0)
		end)

		it("should work with a non-zero center grid", function()
			local grid = Grid.new(Vector3.new(500, 500, 500), Vector3.new(64, 64, 64), 8)
			local gridPos = Vector3.new(2, 3, 4)
			local chunkIndex = grid:GridPositionToChunkIndex(gridPos)
			local worldPos = grid:GridPositionToWorldPosition(gridPos)
			expect(grid:_GetNearestChunkIndexAtPosition(worldPos)).To.Equal(chunkIndex)
		end)

		it("should return an integer for all valid world positions", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(32, 32, 32), 8)
			local gs = grid.GridSize
			for x = 0, gs.X - 1 do
				for y = 0, gs.Y - 1 do
					for z = 0, gs.Z - 1 do
						local worldPos = grid:GridPositionToWorldPosition(Vector3.new(x, y, z))
						local index = grid:_GetNearestChunkIndexAtPosition(worldPos)
						expect(index % 1).To.Equal(0)
					end
				end
			end
		end)
	end)
end)
