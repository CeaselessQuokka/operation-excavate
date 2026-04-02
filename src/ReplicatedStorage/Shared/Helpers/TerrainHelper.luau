--!strict
--- Imports ---
local DebugHelper = require(workspace.Camera.DebugHelper:Clone())

--- Types ---
export type MaterialsMatrix = { { { Enum.Material } } }
export type OccupanciesMatrix = { { { number } } }
type Vector = Vector3 | vector

--- Terrain Helper ---
local TerrainHelper = {}

function TerrainHelper.GenerateBlockMatrix(
	size: Vector3 | number,
	material: Enum.Material
): (MaterialsMatrix, OccupanciesMatrix, Region3)
	local halfSize = (if typeof(size) == "number" then Vector3.one * size else size) / 2
	local min, max = -halfSize, halfSize
	local region = Region3.new(min, max):ExpandToGrid(4)
	local alignedSize = region.Size
	local voxelAlignedSize = alignedSize / 4
	local vx, vy, vz = voxelAlignedSize.X, voxelAlignedSize.Y, voxelAlignedSize.Z
	local occupancies = table.create(vx) :: OccupanciesMatrix
	local materials = table.create(vx) :: MaterialsMatrix
	min = region.CFrame.Position - (alignedSize / 2)
	for x = 1, vx do
		local yMaterials = table.create(vy) :: { { Enum.Material } }
		local yOccupancies = table.create(vy) :: { { number } }
		materials[x] = yMaterials
		occupancies[x] = yOccupancies
		for y = 1, vy do
			local zMaterials = table.create(vz) :: { Enum.Material }
			local zOccupancies = table.create(vz) :: { number }
			yMaterials[y] = zMaterials
			yOccupancies[y] = zOccupancies
			for z = 1, vz do
				local voxelWorldPosition = min + Vector3.new((x - 0.5) * 4, (y - 0.5) * 4, (z - 0.5) * 4)
				local axisDistance = voxelWorldPosition:Abs() - halfSize
				local signedDistance = axisDistance:Max(Vector3.zero).Magnitude
					+ math.min(math.max(axisDistance.X, axisDistance.Y, axisDistance.Z), 0)
				local occupancy: number
				if signedDistance <= -2 then
					occupancy = 1
				elseif signedDistance >= 2 then
					occupancy = 0
				else
					occupancy = 1 - ((signedDistance + 2) / 4)
				end
				zMaterials[z] = material
				zOccupancies[z] = occupancy
			end
		end
	end
	return materials, occupancies, region
end

function TerrainHelper.GenerateBallMatrix(
	radius: number,
	material: Enum.Material
): (MaterialsMatrix, OccupanciesMatrix, Region3)
	local radiusVector = Vector3.one * radius
	local minBound, maxBound = -radiusVector, radiusVector
	local region = Region3.new(minBound, maxBound):ExpandToGrid(4)
	local alignedSize = region.Size
	local voxelAlignedSize = alignedSize / 4
	local vx, vy, vz = voxelAlignedSize.X, voxelAlignedSize.Y, voxelAlignedSize.Z
	local occupancies = table.create(vx) :: OccupanciesMatrix
	local materials = table.create(vx) :: MaterialsMatrix
	minBound = region.CFrame.Position - (alignedSize / 2)
	for x = 1, vx do
		local yMaterials = table.create(vy) :: { { Enum.Material } }
		local yOccupancies = table.create(vy) :: { { number } }
		materials[x] = yMaterials
		occupancies[x] = yOccupancies
		for y = 1, vy do
			local zMaterials = table.create(vz) :: { Enum.Material }
			local zOccupancies = table.create(vz) :: { number }
			yMaterials[y] = zMaterials
			yOccupancies[y] = zOccupancies
			for z = 1, vz do
				local voxelWorldPosition = minBound + Vector3.new((x - 0.5) * 4, (y - 0.5) * 4, (z - 0.5) * 4)
				local signedDistance = voxelWorldPosition.Magnitude - radius
				local occupancy: number
				if signedDistance <= -2 then
					occupancy = 1
				elseif signedDistance >= 2 then
					occupancy = 0
				else
					occupancy = 1 - ((signedDistance + 2) / 4)
				end
				zMaterials[z] = material
				zOccupancies[z] = occupancy
			end
		end
	end
	return materials, occupancies, region
end

function TerrainHelper.SubtractOccupancies(
	src: OccupanciesMatrix,
	subtract: OccupanciesMatrix,
	srcSize: Vector,
	subtractSize: Vector,
	offset: Vector?
): OccupanciesMatrix
	local s = os.clock()
	offset = (offset or vector.zero) :: vector
	local srcMin, srcMax = vector.one, srcSize :: vector
	local subtractMin, subtractMax = offset + vector.one, (subtractSize :: vector) + offset
	local overlapMin = vector.max(srcMin, subtractMin)
	local overlapMax = vector.min(srcMax, subtractMax)
	if overlapMin.x > overlapMax.x or overlapMin.y > overlapMax.y or overlapMin.z > overlapMax.z then
		return src
	end

	local srcOverlapStart = overlapMin - srcMin
	local subtractOverlapStart = overlapMin - subtractMin
	local overlapSize = overlapMax - overlapMin + vector.one
	for x = 1, overlapSize.x do
		local ySrcMatrix = src[srcOverlapStart.x + x]
		local ySubtractMatrix = subtract[subtractOverlapStart.x + x]
		for y = 1, overlapSize.y do
			local zSrcMatrix = ySrcMatrix[srcOverlapStart.y + y]
			local zSubtractMatrix = ySubtractMatrix[subtractOverlapStart.y + y]
			for z = 1, overlapSize.z do
				local zSrcIndex = srcOverlapStart.z + z
				zSrcMatrix[zSrcIndex] = math.max(0, zSrcMatrix[zSrcIndex] - zSubtractMatrix[subtractOverlapStart.z + z])
			end
		end
	end
	print(os.clock() - s)
	return src
end

local s = os.clock()
local sm, src, sReg = TerrainHelper.GenerateBallMatrix(256, Enum.Material.LeafyGrass)
--DebugHelper.Region3(sReg)
print("Gen src", os.clock() - s)
local s = os.clock()
local sum, subtract, suReg = TerrainHelper.GenerateBallMatrix(128, Enum.Material.Air)
--DebugHelper.Region3(suReg, { Color = Color3.new(0, 1, 0) })
print("Gen sub", os.clock() - s)
workspace.Terrain:WriteVoxels(sReg, 4, sm, src)
task.wait(1)
TerrainHelper.SubtractOccupancies(src, subtract, sReg.Size / 4, suReg.Size / 4, vector.one * 1)
workspace.Terrain:WriteVoxels(sReg, 4, sm, src)
--print(src)

-- local m, o, r = TerrainHelper.GenerateBlockMatrix(Vector3.one * 32, Enum.Material.LeafyGrass)
-- workspace.Terrain:WriteVoxels(r, 4, m, o)

return table.freeze(TerrainHelper)
