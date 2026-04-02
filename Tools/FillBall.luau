--!strict
export type MaterialsMatrix = { { { Enum.Material } } }
export type OccupanciesMatrix = { { { number } } }
local function FillBall(center: Vector3, radius: number, material: Enum.Material): (MaterialsMatrix, OccupanciesMatrix)
	local radiusVector = Vector3.one * radius
	local minBound, maxBound = center - radiusVector, center + radiusVector
	local region = Region3.new(minBound, maxBound):ExpandToGrid(4)
	local alignedSize = region.Size
	local voxelAlignedSize = alignedSize / 4
	local vx, vy, vz = voxelAlignedSize.X, voxelAlignedSize.Y, voxelAlignedSize.Z
	local occupancies = table.create(vx) :: OccupanciesMatrix
	local materials = table.create(vx) :: MaterialsMatrix
	minBound = region.CFrame.Position - (region.Size / 2)
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
	workspace.Terrain:WriteVoxels(region, 4, materials, occupancies)
	return materials, occupancies
end

FillBall(Vector3.zero, 16, Enum.Material.LeafyGrass)
