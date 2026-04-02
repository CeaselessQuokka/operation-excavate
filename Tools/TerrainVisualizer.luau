--!strict
--- Services ---

--- Imports ---

--- Types ---

--- Variables ---
local partTemplate = Instance.new("Part")
partTemplate.TopSurface = Enum.SurfaceType.Smooth
partTemplate.BottomSurface = Enum.SurfaceType.Smooth
partTemplate.Material = Enum.Material.SmoothPlastic
partTemplate.Anchored = true
partTemplate.CanCollide = false
partTemplate.CastShadow = false
partTemplate.Transparency = 0.5

--- Functions ---
local function GetExpandedRegion(at: Vector3, size: Vector3): Region3
	local halfSize = size / 2
	local min, max = at - halfSize, at + halfSize
	return Region3.new(min, max):ExpandToGrid(4)
end

local function CreateContainer(name: string?): Folder
	local container = Instance.new("Folder")
	container.Name = name or "TerrainVisualization"
	container.Parent = workspace.Terrain
	return container
end

local function CreateBox(at: Vector3, size: Vector3): Part
	local part = partTemplate:Clone()
	part.Position = at
	part.Size = size
	part.Color = Color3.fromRGB(255, 0, 255)
	part.Parent = workspace.Terrain
	return part
end

local function VisualizeTerrainVoxels(at: Vector3, size: Vector3): Folder
	local visualizationContainer = CreateContainer()

	-- Bounding box of simulated terrain size.
	local boundingBox = CreateBox(at, size)
	boundingBox.Name = "SmallestBoundingBox"
	boundingBox.Parent = visualizationContainer

	-- Create expanded bounding box if size is not correctly aligned to terrain grid.
	local region = GetExpandedRegion(at, size)
	-- if not region.Size:FuzzyEq(size) then
	-- 	local expandedBoundingBox = CreateBox(region.CFrame.Position, region.Size)
	-- 	expandedBoundingBox.Color = Color3.fromRGB(0, 255, 255)
	-- 	expandedBoundingBox.Transparency = 0.625
	-- 	expandedBoundingBox.Parent = visualizationContainer
	-- end

	-- Visualize individual voxels in region.
	local gridSizeVoxel = region.Size / 4
	local regionMin = region.CFrame.Position - (region.Size / 2)
	for x = 1, gridSizeVoxel.X do
		for y = 1, gridSizeVoxel.Y do
			for z = 1, gridSizeVoxel.Z do
				local voxelPosition = regionMin + (Vector3.new(x, y, z) * 4) - Vector3.new(2, 2, 2)
				local voxel = CreateBox(voxelPosition, Vector3.new(4, 4, 4))
				voxel.Name = `{x}{y}{z}`
				voxel.Color = Color3.fromRGB(100, 100, 0)
				voxel.Transparency = 0.75
				voxel.Parent = visualizationContainer
			end
		end
	end

	return visualizationContainer
end

--- Terrain Visualizer ---
VisualizeTerrainVoxels(Vector3.zero, Vector3.one * 4)
