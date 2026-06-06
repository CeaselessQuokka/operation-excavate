--!strict
--- Types ---
export type MaterialsMatrix = { { { Enum.Material } } }
export type OccupanciesMatrix = { { { number } } }
type Vector = Vector3 | vector

--- Terrain Helper ---
local TerrainHelper = {}

function TerrainHelper.GenerateBlockMatrix(
	center: Vector3,
	size: Vector3 | number,
	material: Enum.Material
): (MaterialsMatrix, OccupanciesMatrix, Region3)
	local halfSize = (if typeof(size) == "number" then Vector3.one * size else size) / 2
	local min, max = center - halfSize, center + halfSize
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
				local distanceFromCenter = voxelWorldPosition - center
				local axisDistance = distanceFromCenter:Abs() - halfSize
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
	center: Vector3,
	radius: number,
	material: Enum.Material
): (MaterialsMatrix, OccupanciesMatrix, Region3)
	local radiusVector = Vector3.one * radius
	local minBound, maxBound = center - radiusVector, center + radiusVector
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
				local distanceFromCenter = (voxelWorldPosition - center).Magnitude
				local signedDistance = distanceFromCenter - radius
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
): (OccupanciesMatrix, boolean)
	offset = (offset or vector.zero) :: vector
	local srcMin, srcMax = vector.one, srcSize :: vector
	local subtractMin, subtractMax = offset + vector.one, (subtractSize :: vector) + offset
	local overlapMin = vector.max(srcMin, subtractMin)
	local overlapMax = vector.min(srcMax, subtractMax)
	if overlapMin.x > overlapMax.x or overlapMin.y > overlapMax.y or overlapMin.z > overlapMax.z then
		return src, false
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
	return src, true
end

function TerrainHelper.ApplyTransformation(
	to: OccupanciesMatrix,
	toMaterials: MaterialsMatrix,
	toRegion: Region3,
	with: OccupanciesMatrix,
	withPoint: Vector3,
	withSize: Vector3,
	writeTerrain: boolean?
)
	local chunkMin = toRegion.CFrame.Position - (toRegion.Size / 2)
	local alignedPoint =
		Vector3.new(math.round(withPoint.X / 4) * 4, math.round(withPoint.Y / 4) * 4, math.round(withPoint.Z / 4) * 4)
	local pointMin = alignedPoint - (withSize / 2)
	local offset = (pointMin - chunkMin) / 4
	local modifiedOccupancies, inBounds =
		TerrainHelper.SubtractOccupancies(to, with, toRegion.Size / 4, withSize / 4, offset)
	if writeTerrain and inBounds then
		workspace.Terrain:WriteVoxels(toRegion, 4, toMaterials, modifiedOccupancies)
	end
end

-- do -- TerrainHelper debugger (TODO: remove).
-- 	local chunkMaterials, chunkOccupancies, chunkRegion =
-- 		TerrainHelper.GenerateBlockMatrix(Vector3.zero, 64, Enum.Material.LeafyGrass)
-- 	local ballRadius = 4
-- 	local _, ballOccupancies, ballRegion = TerrainHelper.GenerateBallMatrix(Vector3.zero, ballRadius, Enum.Material.Air)
-- 	local pointPart: BasePart = (workspace :: any).Point
-- 	local point = pointPart.Position
-- 	local chunkMin = chunkRegion.CFrame.Position - (chunkRegion.Size / 2)
-- 	local moveConnection: RBXScriptConnection
-- 	moveConnection = game:GetService("RunService").Heartbeat:Connect(function()
-- 		if workspace:GetAttribute("Stop") then
-- 			moveConnection:Disconnect()
-- 			workspace:SetAttribute("Stop", nil)
-- 			return
-- 		end

-- 		if pointPart.Position ~= point then
-- 			-- Inline SubtractOccupancies.
-- 			--local s = os.clock()
-- 			--point = pointPart.Position
-- 			--local alignedPoint =
-- 			--	Vector3.new(math.round(point.X / 4) * 4, math.round(point.Y / 4) * 4, math.round(point.Z / 4) * 4)
-- 			--local pointMin = alignedPoint - (ballRegion.Size / 2)
-- 			--local offset = (pointMin - chunkMin) / 4
-- 			--local modifiedOccupancies = TerrainHelper.SubtractOccupancies(
-- 			--	chunkOccupancies,
-- 			--	ballOccupancies,
-- 			--	chunkRegion.Size / 4,
-- 			--	ballRegion.Size / 4,
-- 			--	offset
-- 			--)
-- 			--workspace.Terrain:WriteVoxels(chunkRegion, 4, chunkMaterials, modifiedOccupancies)
-- 			--print((1 / 60) / (os.clock() - s))

-- 			-- ApplyTransformation (equivalent to inlined SubtractOccupancies).
-- 			local s = os.clock()
-- 			point = pointPart.Position
-- 			TerrainHelper.ApplyTransformation(
-- 				chunkOccupancies,
-- 				chunkMaterials,
-- 				chunkRegion,
-- 				ballOccupancies,
-- 				point,
-- 				ballRegion.Size,
-- 				true
-- 			)
-- 			print((1 / 60) / (os.clock() - s))
-- 		end
-- 	end)
-- 	workspace.Terrain:WriteVoxels(chunkRegion, 4, chunkMaterials, chunkOccupancies)
-- end

return table.freeze(TerrainHelper)
