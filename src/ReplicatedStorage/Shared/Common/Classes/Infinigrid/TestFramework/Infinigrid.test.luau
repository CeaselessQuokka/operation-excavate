--[[
	Unit tests for Infinigrid.
	Exercises Grid construction, alignment, index/position conversions, and world position mapping.

	Usage (from a Roblox script):
		local TestFramework = require(path.to.TestFramework)
		local InfinigridTests = require(path.to.Infinigrid.TestFramework.Infinigrid.test)
		TestFramework.RunSuite(InfinigridTests)
--]]

--!strict

--- Imports ---
local Grid = require(script.Parent.Parent)
local TestFramework = require(script.Parent)

--- Variables ---
local DEFAULT_CHUNK_SIZE = 64
local DEFAULT_MAX_GRID_SIZE = Vector3.one * ((2 ^ 16) - 1) -- Mirrors the module constant.

--- Infinigrid Tests ---
return TestFramework.Suite("Infinigrid", function(describe, it, expect, beforeEach, afterEach, skip)
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
			-- DEFAULT_MAX_GRID_SIZE ceiled to nearest 8.
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
				-- math.ceil(2/4)*4 = 4, math.ceil(5/4)*4 = 8, math.ceil(9/4)*4 = 12
				expect(grid.Center).To.Equal(Vector3.new(4, 8, 12))
			end)

			it("should not change center when exactly on a 4-boundary", function()
				local grid = Grid.new(Vector3.new(4, 8, 100))
				expect(grid.Center).To.Equal(Vector3.new(4, 8, 100))
			end)

			it("should ceil negative center components toward zero", function()
				-- math.ceil(-5/4)*4 = -1*4 = -4
				local grid = Grid.new(Vector3.new(-5, -5, -5))
				expect(grid.Center).To.Equal(Vector3.new(-4, -4, -4))
			end)

			it("should handle mixed positive and negative components", function()
				-- math.ceil(-3/4)*4 = 0, math.ceil(2/4)*4 = 4, math.ceil(-7/4)*4 = -4
				local grid = Grid.new(Vector3.new(-3, 2, -7))
				expect(grid.Center).To.Equal(Vector3.new(0, 4, -4))
			end)
		end)

		describe("generation origin", function()
			it("should compute GenerationOrigin as center - worldSize/2", function()
				local center = Vector3.new(100, 100, 100)
				local worldSize = Vector3.new(64, 64, 64)
				local grid = Grid.new(center, worldSize, 8)
				-- Center gets ceiled to 100 (already aligned), worldSize stays 64.
				expect(grid.GenerationOrigin).To.Equal(grid.Center - (grid.GridWorldSize / 2))
			end)

			it("should place GenerationOrigin at -worldSize/2 when center is zero", function()
				local grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
				expect(grid.GenerationOrigin).To.Equal(Vector3.new(-32, -32, -32))
			end)

			it("should compute GenerationOrigin with negative center", function()
				-- center=-100 (already aligned to 4), worldSize=64.
				-- GenerationOrigin = -100 - 64/2 = -132.
				local grid = Grid.new(Vector3.new(-100, -100, -100), Vector3.new(64, 64, 64), 8)
				expect(grid.GenerationOrigin).To.Equal(Vector3.new(-132, -132, -132))
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
		end)

		describe("grid world size alignment", function()
			it("should ceil grid world size components to nearest multiple of 8", function()
				local grid = Grid.new(Vector3.zero, Vector3.new(10, 10, 10), 8)
				-- math.ceil(10/8)*8 = 16
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

	describe("GridPositionToChunkIndex (0-based)", function()
		local grid

		beforeEach(function()
			-- 64x64x64 world, 8-stud chunks → GridSize = 8,8,8
			grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
		end)

		it("should return 0 for grid position (0,0,0)", function()
			local index = grid:GridPositionToChunkIndex(Vector3.zero)
			expect(index).To.Equal(0)
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
			-- Last 0-based position is (gs.X-1, gs.Y-1, gs.Z-1).
			local maxIndex = grid:GridPositionToChunkIndex(Vector3.new(gs.X - 1, gs.Y - 1, gs.Z - 1))
			local expectedMax = (gs.X * gs.Y * gs.Z) - 1
			expect(maxIndex).To.Equal(expectedMax)
		end)
	end)

	describe("ChunkIndexToGridPosition (0-based)", function()
		local grid

		beforeEach(function()
			grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
		end)

		it("should return (0,0,0) for index 0", function()
			local pos = grid:ChunkIndexToGridPosition(0)
			expect(pos).To.Equal(Vector3.zero)
		end)

		it("should return (0,0,1) for index 1", function()
			local pos = grid:ChunkIndexToGridPosition(1)
			expect(pos).To.Equal(Vector3.new(0, 0, 1))
		end)

		it("should return the last position for the max index", function()
			local gs = grid.GridSize
			local maxIndex = (gs.X * gs.Y * gs.Z) - 1
			local pos = grid:ChunkIndexToGridPosition(maxIndex)
			expect(pos).To.Equal(Vector3.new(gs.X - 1, gs.Y - 1, gs.Z - 1))
		end)

		it("should step to (0,1,0) after filling one Z row", function()
			local sizeZ = grid.GridSize.Z
			local pos = grid:ChunkIndexToGridPosition(sizeZ)
			expect(pos).To.Equal(Vector3.new(0, 1, 0))
		end)

		it("should step to (1,0,0) after filling one YZ plane", function()
			local sizeYZ = grid.GridSize.Y * grid.GridSize.Z
			local pos = grid:ChunkIndexToGridPosition(sizeYZ)
			expect(pos).To.Equal(Vector3.new(1, 0, 0))
		end)
	end)

	describe("index/position round-trip (0-based)", function()
		local grid

		beforeEach(function()
			grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
		end)

		it("should round-trip position → index → position", function()
			local positions = {
				Vector3.new(0, 0, 0),
				Vector3.new(3, 5, 2),
				Vector3.new(7, 7, 7),
				Vector3.new(0, 7, 0),
				Vector3.new(4, 4, 4),
			}
			for _, pos in positions do
				local index = grid:GridPositionToChunkIndex(pos)
				local result = grid:ChunkIndexToGridPosition(index)
				expect(result).To.Equal(pos)
			end
		end)

		it("should round-trip index → position → index", function()
			local indices = { 0, 1, 7, 8, 63, 64, 100, 255, 511 }
			for _, index in indices do
				local pos = grid:ChunkIndexToGridPosition(index)
				local result = grid:GridPositionToChunkIndex(pos)
				expect(result).To.Equal(index)
			end
		end)

		it("should round-trip all indices in a small grid", function()
			local smallGrid = Grid.new(Vector3.zero, Vector3.new(16, 16, 16), 8)
			-- GridSize = 2,2,2 → 8 chunks total (indices 0..7)
			local total = smallGrid.GridSize.X * smallGrid.GridSize.Y * smallGrid.GridSize.Z
			for i = 0, total - 1 do
				local pos = smallGrid:ChunkIndexToGridPosition(i)
				local result = smallGrid:GridPositionToChunkIndex(pos)
				expect(result).To.Equal(i)
			end
		end)
	end)

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

	describe("GridPositionToWorldPosition", function()
		it("should offset from GenerationOrigin by gridPosition * chunkSize", function()
			local grid = Grid.new(Vector3.new(100, 100, 100), Vector3.new(64, 64, 64), 8)
			local worldPos = grid:GridPositionToWorldPosition(Vector3.new(1, 2, 3))
			expect(worldPos).To.Equal(grid.GenerationOrigin + Vector3.new(1 * 8, 2 * 8, 3 * 8))
		end)

		it("should return GenerationOrigin for grid position (0,0,0)", function()
			local grid = Grid.new(Vector3.new(50, 50, 50), Vector3.new(64, 64, 64), 8)
			local worldPos = grid:GridPositionToWorldPosition(Vector3.zero)
			expect(worldPos).To.Equal(grid.GenerationOrigin)
		end)

		it("should scale with chunk size", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(256, 256, 256), 16)
			-- GenerationOrigin = 0 - 256/2 = -128
			local worldPos = grid:GridPositionToWorldPosition(Vector3.new(2, 3, 4))
			expect(worldPos).To.Equal(grid.GenerationOrigin + Vector3.new(2 * 16, 3 * 16, 4 * 16))
		end)

		it("should work correctly with non-cubic grids", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(32, 16, 64), 8)
			local worldPos = grid:GridPositionToWorldPosition(Vector3.new(1, 1, 1))
			expect(worldPos).To.Equal(grid.GenerationOrigin + Vector3.new(8, 8, 8))
		end)

		it("should return correct world position for the last grid cell", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
			local gs = grid.GridSize
			local lastPos = Vector3.new(gs.X - 1, gs.Y - 1, gs.Z - 1)
			local worldPos = grid:GridPositionToWorldPosition(lastPos)
			expect(worldPos).To.Equal(grid.GenerationOrigin + lastPos * grid.ChunkSize)
		end)
	end)

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
				local result = grid:GridPositionToChunkIndex(pos)
				expect(result).To.Equal(i)
			end
		end)

		it("should produce unique indices for all positions in a non-cubic grid", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(64, 32, 48), 16)
			-- GridSize = 4,2,3
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

	describe("edge cases", function()
		it("should handle a 1x1x1 grid", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(8, 8, 8), 8)
			expect(grid.GridSize).To.Equal(Vector3.new(1, 1, 1))
			local index = grid:GridPositionToChunkIndex(Vector3.zero)
			expect(index).To.Equal(0)
			local pos = grid:ChunkIndexToGridPosition(0)
			expect(pos).To.Equal(Vector3.zero)
		end)

		it("should handle a 1x1xN grid (single row)", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(8, 8, 32), 8)
			-- GridSize = 1,1,4
			expect(grid.GridSize).To.Equal(Vector3.new(1, 1, 4))
			for z = 0, 3 do
				local index = grid:GridPositionToChunkIndex(Vector3.new(0, 0, z))
				expect(index).To.Equal(z)
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
			-- Center: -64 (already aligned). GenerationOrigin: -64 - 64 = -128.
			expect(grid.GenerationOrigin).To.Equal(Vector3.new(-128, -128, -128))
			local worldPos = grid:GridPositionToWorldPosition(Vector3.zero)
			expect(worldPos).To.Equal(grid.GenerationOrigin)
		end)

		skip("serialization / deserialization (not yet implemented)")
		skip("chunk deloading under memory pressure (not yet implemented)")
	end)

	describe("Grid module", function()
		it("should be a frozen table", function()
			expect(table.isfrozen(Grid)).To.Equal(true)
		end)

		it("should expose methods through metatable __index", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
			expect(grid.GridPositionToChunkIndex).To.Exist()
			expect(grid.ChunkIndexToGridPosition).To.Exist()
			expect(grid.GridPositionToWorldPosition).To.Exist()
			expect(grid.GetChunkAtPosition).To.Exist()
		end)
	end)

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

		it("should satisfy GenerationOrigin == Center - GridWorldSize / 2", function()
			local configs = {
				{ Vector3.zero, Vector3.new(64, 64, 64), 8 },
				{ Vector3.new(100, 100, 100), Vector3.new(256, 256, 256), 16 },
				{ Vector3.new(-64, -64, -64), Vector3.new(128, 128, 128), 32 },
				{ Vector3.new(7, 13, 29), Vector3.new(64, 128, 256), 8 },
			}
			for _, cfg in configs do
				local grid = Grid.new(cfg[1] :: Vector3, cfg[2] :: Vector3, cfg[3] :: number)
				expect(grid.GenerationOrigin).To.Equal(grid.Center - (grid.GridWorldSize / 2))
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
	end)

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

		it("should map the center grid position near the constructor center", function()
			local grid = Grid.new(Vector3.new(100, 100, 100), Vector3.new(64, 64, 64), 8)
			local gs = grid.GridSize
			-- The midpoint of the grid in grid-space.
			local midGridPos = Vector3.new(gs.X / 2, gs.Y / 2, gs.Z / 2)
			local midWorldPos = grid:GridPositionToWorldPosition(midGridPos)
			-- Should equal Center exactly: GenerationOrigin + (GridSize/2) * ChunkSize
			-- = (Center - WorldSize/2) + WorldSize/2 = Center
			expect(midWorldPos).To.Equal(grid.Center)
		end)

		it("should span exactly GridWorldSize from first to last cell edge", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(128, 64, 256), 8)
			local firstPos = grid:GridPositionToWorldPosition(Vector3.zero)
			local gs = grid.GridSize
			local lastPos = grid:GridPositionToWorldPosition(Vector3.new(gs.X, gs.Y, gs.Z))
			-- Distance from (0,0,0) to (GridSize) should be GridWorldSize.
			expect(lastPos - firstPos).To.Equal(grid.GridWorldSize)
		end)
	end)

	describe("large grid round-trips", function()
		it("should round-trip all indices in a 64³ grid", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(512, 512, 512), 8) -- 64×64×64
			local gs = grid.GridSize
			local total = gs.X * gs.Y * gs.Z
			-- Sample boundary and middle indices to avoid O(n) explosion.
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
				local result = grid:GridPositionToChunkIndex(pos)
				expect(result).To.Equal(index)
			end
		end)

		it("should round-trip boundary positions in a 64³ grid", function()
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
				local result = grid:ChunkIndexToGridPosition(index)
				expect(result).To.Equal(pos)
			end
		end)
	end)

	describe("asymmetric grids", function()
		it("should handle an Nx1x1 grid (single X axis)", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(64, 8, 8), 8)
			expect(grid.GridSize).To.Equal(Vector3.new(8, 1, 1))
			for x = 0, 7 do
				local index = grid:GridPositionToChunkIndex(Vector3.new(x, 0, 0))
				expect(index).To.Equal(x)
				local pos = grid:ChunkIndexToGridPosition(x)
				expect(pos).To.Equal(Vector3.new(x, 0, 0))
			end
		end)

		it("should handle a 1xNx1 grid (single Y axis)", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(8, 64, 8), 8)
			expect(grid.GridSize).To.Equal(Vector3.new(1, 8, 1))
			for y = 0, 7 do
				local index = grid:GridPositionToChunkIndex(Vector3.new(0, y, 0))
				expect(index).To.Equal(y)
				local pos = grid:ChunkIndexToGridPosition(y)
				expect(pos).To.Equal(Vector3.new(0, y, 0))
			end
		end)

		it("should handle a highly asymmetric grid (16x1x4)", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(128, 8, 32), 8)
			expect(grid.GridSize).To.Equal(Vector3.new(16, 1, 4))
			local total = 16 * 1 * 4
			for i = 0, total - 1 do
				local pos = grid:ChunkIndexToGridPosition(i)
				local result = grid:GridPositionToChunkIndex(pos)
				expect(result).To.Equal(i)
			end
		end)

		it("should order indices correctly in a non-cubic grid (Z fastest)", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(32, 16, 64), 8) -- 4x2x8
			-- Z should still stride by 1.
			local a = grid:GridPositionToChunkIndex(Vector3.new(0, 0, 0))
			local b = grid:GridPositionToChunkIndex(Vector3.new(0, 0, 1))
			expect(b - a).To.Equal(1)
			-- Y should stride by GridSize.Z = 8.
			local c = grid:GridPositionToChunkIndex(Vector3.new(0, 1, 0))
			expect(c - a).To.Equal(grid.GridSize.Z)
			-- X should stride by GridSize.Y * GridSize.Z = 16.
			local d = grid:GridPositionToChunkIndex(Vector3.new(1, 0, 0))
			expect(d - a).To.Equal(grid.GridSize.Y * grid.GridSize.Z)
		end)
	end)

	describe("multiple grid independence", function()
		it("should not share state between independent grid instances", function()
			local gridA = Grid.new(Vector3.new(0, 0, 0), Vector3.new(64, 64, 64), 8)
			local gridB = Grid.new(Vector3.new(200, 200, 200), Vector3.new(256, 256, 256), 16)
			-- Different centers.
			expect(gridA.Center).Never.To.Equal(gridB.Center)
			-- Different chunk sizes.
			expect(gridA.ChunkSize).Never.To.Equal(gridB.ChunkSize)
			-- Different grid sizes. (8,8,8 vs 16,16,16)
			expect(gridA.GridSize).Never.To.Equal(gridB.GridSize)
			-- Chunks tables are separate references.
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
	end)

	describe("ExpandVectorToGrid coverage", function()
		it("should ceil fractional center values to nearest 4", function()
			local grid = Grid.new(Vector3.new(0.5, 1.5, 2.5))
			-- math.ceil(0.5/4)*4 = 4, math.ceil(1.5/4)*4 = 4, math.ceil(2.5/4)*4 = 4
			expect(grid.Center).To.Equal(Vector3.new(4, 4, 4))
		end)

		it("should ceil fractional world size values to nearest 8", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(10.5, 20.5, 30.5), 8)
			-- math.ceil(10.5/8)*8 = 16, math.ceil(20.5/8)*8 = 24, math.ceil(30.5/8)*8 = 32
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
	end)

	describe("GetChunkAtPosition", function()
		it("should return nil when no chunk exists at the position", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
			local result = grid:GetChunkAtPosition(Vector3.new(4, 4, 4))
			expect(result).To.BeNil()
		end)

		it("should return a stored chunk at the origin grid position", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
			-- GenerationOrigin = -32,-32,-32. Grid position (0,0,0) → index 0.
			local chunk = { ChunkIndex = 0, ChunkPosition = Vector3.zero, Data = "test" }
			grid.Chunks[0] = chunk :: any
			local result = grid:GetChunkAtPosition(grid.GenerationOrigin)
			expect(result).To.Exist()
			expect((result :: any).Data).To.Equal("test")
		end)

		it("should return the correct chunk for a position in the middle of the grid", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
			-- Grid position (3, 4, 5) → world = GenerationOrigin + (3,4,5)*8
			local gridPos = Vector3.new(3, 4, 5)
			local chunkIndex = grid:GridPositionToChunkIndex(gridPos)
			local worldPos = grid:GridPositionToWorldPosition(gridPos)
			local chunk = { ChunkIndex = chunkIndex, ChunkPosition = gridPos, Value = 42 }
			grid.Chunks[chunkIndex] = chunk :: any
			local result = grid:GetChunkAtPosition(worldPos)
			expect(result).To.Exist()
			expect((result :: any).Value).To.Equal(42)
		end)

		it("should find a chunk when queried near the center of that chunk", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
			local gridPos = Vector3.new(2, 2, 2)
			local chunkIndex = grid:GridPositionToChunkIndex(gridPos)
			local worldPos = grid:GridPositionToWorldPosition(gridPos)
			local chunk = { ChunkIndex = chunkIndex, ChunkPosition = gridPos }
			grid.Chunks[chunkIndex] = chunk :: any
			-- Query at the exact world position (chunk corner).
			local result = grid:GetChunkAtPosition(worldPos)
			expect(result).To.Exist()
			expect((result :: any).ChunkIndex).To.Equal(chunkIndex)
		end)

		it("should find the correct chunk when queried with a small offset", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
			local gridPos = Vector3.new(4, 4, 4)
			local chunkIndex = grid:GridPositionToChunkIndex(gridPos)
			local worldPos = grid:GridPositionToWorldPosition(gridPos)
			local chunk = { ChunkIndex = chunkIndex, ChunkPosition = gridPos }
			grid.Chunks[chunkIndex] = chunk :: any
			-- Query with a small offset within rounding tolerance.
			local result = grid:GetChunkAtPosition(worldPos + Vector3.new(1, 1, 1))
			expect(result).To.Exist()
			expect((result :: any).ChunkIndex).To.Equal(chunkIndex)
		end)

		it("should return nil for a position outside the populated chunks", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
			-- Only populate chunk at (0,0,0).
			grid.Chunks[0] = { ChunkIndex = 0, ChunkPosition = Vector3.zero } :: any
			-- Query at grid position (7,7,7) which has no chunk stored.
			local farWorldPos = grid:GridPositionToWorldPosition(Vector3.new(7, 7, 7))
			local result = grid:GetChunkAtPosition(farWorldPos)
			expect(result).To.BeNil()
		end)

		it("should work correctly with a non-zero center grid", function()
			local grid = Grid.new(Vector3.new(100, 200, 300), Vector3.new(64, 64, 64), 8)
			local gridPos = Vector3.new(1, 1, 1)
			local chunkIndex = grid:GridPositionToChunkIndex(gridPos)
			local worldPos = grid:GridPositionToWorldPosition(gridPos)
			local chunk = { ChunkIndex = chunkIndex, ChunkPosition = gridPos }
			grid.Chunks[chunkIndex] = chunk :: any
			local result = grid:GetChunkAtPosition(worldPos)
			expect(result).To.Exist()
			expect((result :: any).ChunkIndex).To.Equal(chunkIndex)
		end)

		it("should work correctly with a negative center grid", function()
			local grid = Grid.new(Vector3.new(-100, -100, -100), Vector3.new(64, 64, 64), 8)
			local gridPos = Vector3.new(3, 3, 3)
			local chunkIndex = grid:GridPositionToChunkIndex(gridPos)
			local worldPos = grid:GridPositionToWorldPosition(gridPos)
			local chunk = { ChunkIndex = chunkIndex, ChunkPosition = gridPos }
			grid.Chunks[chunkIndex] = chunk :: any
			local result = grid:GetChunkAtPosition(worldPos)
			expect(result).To.Exist()
			expect((result :: any).ChunkIndex).To.Equal(chunkIndex)
		end)

		it("should work with large chunk sizes", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(512, 512, 512), 64)
			local gridPos = Vector3.new(3, 5, 2)
			local chunkIndex = grid:GridPositionToChunkIndex(gridPos)
			local worldPos = grid:GridPositionToWorldPosition(gridPos)
			local chunk = { ChunkIndex = chunkIndex, ChunkPosition = gridPos }
			grid.Chunks[chunkIndex] = chunk :: any
			local result = grid:GetChunkAtPosition(worldPos)
			expect(result).To.Exist()
			expect((result :: any).ChunkIndex).To.Equal(chunkIndex)
		end)

		it("should be consistent with GridPositionToWorldPosition round-trip", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
			-- Populate several chunks and verify each can be found via world position.
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
				local result = grid:GetChunkAtPosition(worldPos)
				expect(result).To.Exist()
				expect((result :: any).ChunkPosition).To.Equal(gridPos)
			end
		end)
	end)

	describe("large coordinate stability", function()
		it("should construct with large positive center", function()
			local grid = Grid.new(Vector3.new(10000, 10000, 10000), Vector3.new(64, 64, 64), 8)
			expect(grid.Center).To.Equal(Vector3.new(10000, 10000, 10000))
			expect(grid.GenerationOrigin).To.Equal(Vector3.new(10000 - 32, 10000 - 32, 10000 - 32))
		end)

		it("should construct with large negative center", function()
			local grid = Grid.new(Vector3.new(-10000, -10000, -10000), Vector3.new(64, 64, 64), 8)
			expect(grid.Center).To.Equal(Vector3.new(-10000, -10000, -10000))
			expect(grid.GenerationOrigin).To.Equal(Vector3.new(-10032, -10032, -10032))
		end)

		it("should round-trip correctly with large grid at offset center", function()
			local grid = Grid.new(Vector3.new(5000, 5000, 5000), Vector3.new(512, 512, 512), 8) -- 64³
			local gs = grid.GridSize
			-- Test corners and a few interior points.
			local positions = {
				Vector3.new(0, 0, 0),
				Vector3.new(gs.X - 1, gs.Y - 1, gs.Z - 1),
				Vector3.new(math.floor(gs.X / 2), math.floor(gs.Y / 2), math.floor(gs.Z / 2)),
			}
			for _, pos in positions do
				local index = grid:GridPositionToChunkIndex(pos)
				local result = grid:ChunkIndexToGridPosition(index)
				expect(result).To.Equal(pos)
			end
		end)

		it("should produce correct world positions at large offsets", function()
			local grid = Grid.new(Vector3.new(10000, 10000, 10000), Vector3.new(64, 64, 64), 8)
			local worldPos = grid:GridPositionToWorldPosition(Vector3.new(4, 4, 4))
			local expected = grid.GenerationOrigin + Vector3.new(32, 32, 32)
			expect(worldPos).To.Equal(expected)
		end)
	end)

	describe("GetChunkAtPosition exhaustive", function()
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
				local result = grid:GetChunkAtPosition(worldPos)
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
				local result = grid:GetChunkAtPosition(worldPos)
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
				local result = grid:GetChunkAtPosition(worldPos)
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
				local result = grid:GetChunkAtPosition(worldPos)
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
				local result = grid:GetChunkAtPosition(worldPos)
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
				local result = grid:GetChunkAtPosition(worldPos)
				expect(result).To.Exist()
				expect((result :: any).ChunkIndex).To.Equal(i)
			end
		end)

		it("should find sampled chunks with 64-stud chunk size on 512³ world", function()
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
				local result = grid:GetChunkAtPosition(worldPos)
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
				local result = grid:GetChunkAtPosition(worldPos)
				expect(result).To.Exist()
				expect((result :: any).ChunkIndex).To.Equal(i)
			end
		end)

		it("should correctly distinguish adjacent chunks along X", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
			local posA = Vector3.new(3, 3, 3)
			local posB = Vector3.new(4, 3, 3)
			local indexA = grid:GridPositionToChunkIndex(posA)
			local indexB = grid:GridPositionToChunkIndex(posB)
			grid.Chunks[indexA] = { ChunkIndex = indexA, ChunkPosition = posA, Tag = "A" } :: any
			grid.Chunks[indexB] = { ChunkIndex = indexB, ChunkPosition = posB, Tag = "B" } :: any
			local resultA = grid:GetChunkAtPosition(grid:GridPositionToWorldPosition(posA))
			local resultB = grid:GetChunkAtPosition(grid:GridPositionToWorldPosition(posB))
			expect((resultA :: any).Tag).To.Equal("A")
			expect((resultB :: any).Tag).To.Equal("B")
		end)

		it("should correctly distinguish adjacent chunks along Y", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
			local posA = Vector3.new(2, 2, 2)
			local posB = Vector3.new(2, 3, 2)
			local indexA = grid:GridPositionToChunkIndex(posA)
			local indexB = grid:GridPositionToChunkIndex(posB)
			grid.Chunks[indexA] = { ChunkIndex = indexA, ChunkPosition = posA, Tag = "Y0" } :: any
			grid.Chunks[indexB] = { ChunkIndex = indexB, ChunkPosition = posB, Tag = "Y1" } :: any
			local resultA = grid:GetChunkAtPosition(grid:GridPositionToWorldPosition(posA))
			local resultB = grid:GetChunkAtPosition(grid:GridPositionToWorldPosition(posB))
			expect((resultA :: any).Tag).To.Equal("Y0")
			expect((resultB :: any).Tag).To.Equal("Y1")
		end)

		it("should correctly distinguish adjacent chunks along Z", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
			local posA = Vector3.new(5, 5, 5)
			local posB = Vector3.new(5, 5, 6)
			local indexA = grid:GridPositionToChunkIndex(posA)
			local indexB = grid:GridPositionToChunkIndex(posB)
			grid.Chunks[indexA] = { ChunkIndex = indexA, ChunkPosition = posA, Tag = "Z0" } :: any
			grid.Chunks[indexB] = { ChunkIndex = indexB, ChunkPosition = posB, Tag = "Z1" } :: any
			local resultA = grid:GetChunkAtPosition(grid:GridPositionToWorldPosition(posA))
			local resultB = grid:GetChunkAtPosition(grid:GridPositionToWorldPosition(posB))
			expect((resultA :: any).Tag).To.Equal("Z0")
			expect((resultB :: any).Tag).To.Equal("Z1")
		end)

		it("should return the same chunk on repeated queries", function()
			local grid = Grid.new(Vector3.zero, Vector3.new(64, 64, 64), 8)
			local gridPos = Vector3.new(5, 3, 6)
			local chunkIndex = grid:GridPositionToChunkIndex(gridPos)
			grid.Chunks[chunkIndex] = { ChunkIndex = chunkIndex, ChunkPosition = gridPos } :: any
			local worldPos = grid:GridPositionToWorldPosition(gridPos)
			local first = grid:GetChunkAtPosition(worldPos)
			local second = grid:GetChunkAtPosition(worldPos)
			local third = grid:GetChunkAtPosition(worldPos)
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
				local result = grid:GetChunkAtPosition(worldPos)
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
				local result = grid:GetChunkAtPosition(worldPos)
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
				local result = grid:GetChunkAtPosition(worldPos)
				expect(result).To.Exist()
				expect((result :: any).ChunkIndex).To.Equal(i)
			end
		end)
	end)

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
					local roundTripped = grid:GridPositionToChunkIndex(pos)
					expect(roundTripped).To.Equal(i)
				end
			end
		end)

		it("should resolve every GridPositionToWorldPosition through GetChunkAtPosition", function()
			local grid = Grid.new(Vector3.new(50, 50, 50), Vector3.new(64, 64, 64), 8)
			local total = grid.GridSize.X * grid.GridSize.Y * grid.GridSize.Z
			for i = 0, total - 1 do
				local gridPos = grid:ChunkIndexToGridPosition(i)
				grid.Chunks[i] = { ChunkIndex = i, ChunkPosition = gridPos } :: any
			end
			for i = 0, total - 1 do
				local gridPos = grid:ChunkIndexToGridPosition(i)
				local worldPos = grid:GridPositionToWorldPosition(gridPos)
				local result = grid:GetChunkAtPosition(worldPos)
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

		it("should have GetChunkAtPosition agree across multiple center configurations", function()
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
					local result = grid:GetChunkAtPosition(worldPos)
					expect(result).To.Exist()
					expect((result :: any).ChunkIndex).To.Equal(i)
				end
			end
		end)
	end)

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
				-- GenerationOrigin = Center - WorldSize/2, so always <= Center (worldSize > 0).
				expect(grid.GenerationOrigin.X).To.BeLessThan(grid.Center.X + 1)
				expect(grid.GenerationOrigin.Y).To.BeLessThan(grid.Center.Y + 1)
				expect(grid.GenerationOrigin.Z).To.BeLessThan(grid.Center.Z + 1)
			end
		end)

		it("should be symmetric about Center with GridWorldSize", function()
			local configs = {
				{ Vector3.zero, Vector3.new(64, 64, 64), 8 },
				{ Vector3.new(500, 500, 500), Vector3.new(128, 128, 128), 16 },
				{ Vector3.new(-300, 100, -500), Vector3.new(256, 64, 128), 32 },
			}
			for _, cfg in configs do
				local grid = Grid.new(cfg[1] :: Vector3, cfg[2] :: Vector3, cfg[3] :: number)
				local endCorner = grid.GenerationOrigin + grid.GridWorldSize
				local midpoint = (grid.GenerationOrigin + endCorner) / 2
				expect(midpoint).To.Equal(grid.Center)
			end
		end)
	end)

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
				local roundTripped = grid:ChunkIndexToGridPosition(index)
				expect(roundTripped).To.Equal(corner)
			end
		end)

		it("should store and retrieve corner chunks via GetChunkAtPosition", function()
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
				local result = grid:GetChunkAtPosition(worldPos)
				expect(result).To.Exist()
				expect((result :: any).ChunkPosition).To.Equal(corner)
			end
		end)
	end)

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
	end)

	describe("constructor parameter combinations", function()
		it("should handle every valid chunk size from 1 to 64", function()
			for cs = 1, 64 do
				local grid = Grid.new(Vector3.zero, Vector3.new(512, 512, 512), cs)
				expect(grid.ChunkSize).To.BeGreaterThan(0)
				expect(grid.ChunkSize % 8).To.Equal(0)
				expect(grid.GridSize * grid.ChunkSize).To.Equal(grid.GridWorldSize)
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
				expect(grid.GenerationOrigin).To.Equal(grid.Center - grid.GridWorldSize / 2)
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
						expect(index).To.BeGreaterThan(-1)
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
				expect(pos.X).To.BeGreaterThan(-1)
				expect(pos.X).To.BeLessThan(gs.X)
				expect(pos.Y).To.BeGreaterThan(-1)
				expect(pos.Y).To.BeLessThan(gs.Y)
				expect(pos.Z).To.BeGreaterThan(-1)
				expect(pos.Z).To.BeLessThan(gs.Z)
			end
		end)
	end)

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
						expect(wp.X).To.BeGreaterThan(minBound.X - 1)
						expect(wp.Y).To.BeGreaterThan(minBound.Y - 1)
						expect(wp.Z).To.BeGreaterThan(minBound.Z - 1)
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
					local pos = grid:ChunkIndexToGridPosition(i)
					expect(pos).To.Equal(referenceMappings[i])
				end
			end
		end)

		it("should produce identical GetChunkAtPosition results across instances", function()
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
					local result = grid:GetChunkAtPosition(worldPos)
					expect(result).To.Exist()
					expect((result :: any).ChunkIndex).To.Equal(i)
				end
			end
		end)
	end)
end)
