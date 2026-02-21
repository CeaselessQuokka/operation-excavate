--!strict
--- Services ---
local Workspace = game:GetService("Workspace")

--- Types ---
type ViewerPart = BasePart

--- Variables ---
local Cleaner = setmetatable({ _items = {} }, {
	__call = function(self, item: any)
		if item ~= nil then
			table.insert(self._items, item)
		else
			for _, item in self._items :: any do
				if not pcall(function()
					item:Destroy()
				end) then
					if not pcall(function()
						item:Disconnect()
					end) then
						warn("Failed to clean up item:", item)
					end
				end
			end
			table.clear(self._items)
		end
		return item
	end,
})

local region: Region3

--- Functions ---
local function ExpandVectorToResolutionCube(vector: Vector3, resolution: number): Vector3
	local size = math.ceil(math.max(vector.X, vector.Y, vector.Z) / resolution) * resolution
	return Vector3.new(size, size, size)
end

local function RoundVectorToResolution(vector: Vector3, resolution: number): Vector3
	return Vector3.new(
		math.ceil(vector.X / resolution) * resolution,
		math.ceil(vector.Y / resolution) * resolution,
		math.ceil(vector.Z / resolution) * resolution
	)
end

local function PrettyPrintVoxels(materials: { { { Enum.Material } } }, occupancy: { { { number } } })
	local sizeX = #materials
	local sizeY = if sizeX > 0 then #materials[1] else 0
	local sizeZ = if sizeY > 0 then #materials[1][1] else 0

	print(string.format("Voxel Grid: %dx%dx%d", sizeX, sizeY, sizeZ))
	print(string.rep("=", 60))

	for y = sizeY, 1, -1 do
		print(string.format("--- Layer Y=%d ---", y))
		local header = string.format("%-4s", "")
		for x = 1, sizeX do
			header ..= string.format("| %-20s ", string.format("X=%d", x))
		end
		print(header)
		print(string.rep("-", 4 + sizeX * 23))

		for z = 1, sizeZ do
			local row = string.format("Z=%-2d", z)
			for x = 1, sizeX do
				local mat = materials[x][y][z]
				local occ = occupancy[x][y][z]
				local matName = if mat == Enum.Material.Air then "Air" else mat.Name
				row ..= string.format("| %-12s %5.1f%% ", matName, occ * 100)
			end
			print(row)
		end
		print("")
	end
end

local function EnsureViewerPart(): ViewerPart
	local viewerPart: ViewerPart = Workspace:QueryDescendants("BasePart#ViewerPart")[1] :: any
	if not viewerPart then
		local vp = Instance.new("Part")
		vp.Name = "ViewerPart"
		vp.Anchored = true
		vp.CanCollide = false
		vp.CastShadow = false
		vp.BrickColor = BrickColor.new("Bright red")
		vp.TopSurface = Enum.SurfaceType.Smooth
		vp.BottomSurface = Enum.SurfaceType.Smooth
		vp.Transparency = 0.5
		vp.Size = Vector3.new(8, 8, 8)
		vp.Position = Workspace.CurrentCamera.CFrame * Vector3.new(0, 0, -12)
		vp.Parent = Workspace
		viewerPart = vp
	end
	return viewerPart
end

local function EnsureViewerPartSize(viewerPart: ViewerPart): RBXScriptConnection
	viewerPart.Size = ExpandVectorToResolutionCube(viewerPart.Size, 4):Max(Vector3.one * 8)
	return viewerPart:GetPropertyChangedSignal("Size"):Connect(function()
		viewerPart.Size = ExpandVectorToResolutionCube(viewerPart.Size, 4):Max(Vector3.one * 8)
	end)
end

local function EnsureViewerPartPosition(viewerPart: ViewerPart): RBXScriptConnection
	local lastPosition: Vector3
	local function UpdatePosition()
		viewerPart.CFrame = CFrame.new(RoundVectorToResolution(viewerPart.Position, 4))
		if lastPosition and (viewerPart.Position - lastPosition).Magnitude > 0 then
			local min = viewerPart.Position - viewerPart.Size / 2
			local max = viewerPart.Position + viewerPart.Size / 2
			region = Region3.new(min, max)
		end
		lastPosition = viewerPart.Position
	end
	task.defer(UpdatePosition)
	return viewerPart:GetPropertyChangedSignal("CFrame"):Connect(UpdatePosition)
end

local voxels = {} -- Try to keep the code contained around here so there are logical segments to this tool for easy navigation

local VOXEL_RESOLUTION = 4
local VOXEL_DISPLAY_SIZE = 3.8 -- slightly smaller than 4 so gaps are visible between cells

local MATERIAL_COLORS: { [Enum.Material]: Color3 } = {
	[Enum.Material.Air] = Color3.fromRGB(180, 180, 200),
	[Enum.Material.Grass] = Color3.fromRGB(76, 153, 0),
	[Enum.Material.LeafyGrass] = Color3.fromRGB(60, 140, 20),
	[Enum.Material.Sand] = Color3.fromRGB(224, 200, 130),
	[Enum.Material.Rock] = Color3.fromRGB(128, 128, 128),
	[Enum.Material.Water] = Color3.fromRGB(0, 120, 215),
	[Enum.Material.Ground] = Color3.fromRGB(140, 100, 50),
	[Enum.Material.Mud] = Color3.fromRGB(100, 70, 40),
	[Enum.Material.Sandstone] = Color3.fromRGB(190, 160, 100),
	[Enum.Material.Limestone] = Color3.fromRGB(200, 190, 170),
	[Enum.Material.Slate] = Color3.fromRGB(90, 95, 100),
	[Enum.Material.Basalt] = Color3.fromRGB(50, 50, 55),
	[Enum.Material.Concrete] = Color3.fromRGB(160, 160, 160),
	[Enum.Material.Pavement] = Color3.fromRGB(150, 150, 150),
	[Enum.Material.Cobblestone] = Color3.fromRGB(140, 130, 120),
	[Enum.Material.Asphalt] = Color3.fromRGB(60, 60, 65),
	[Enum.Material.Snow] = Color3.fromRGB(235, 240, 245),
	[Enum.Material.Ice] = Color3.fromRGB(170, 210, 230),
	[Enum.Material.Glacier] = Color3.fromRGB(170, 210, 235),
	[Enum.Material.Salt] = Color3.fromRGB(230, 230, 220),
	[Enum.Material.CrackedLava] = Color3.fromRGB(220, 50, 0),
}

local function GetMaterialColor(material: Enum.Material): Color3
	return MATERIAL_COLORS[material] or Color3.fromRGB(180, 100, 180)
end

local function CreateVoxelLabel(
	text: string,
	textColor: Color3,
	layoutOrder: number,
	font: Enum.Font,
	sizeY: number
): TextLabel
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, sizeY, 0)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = textColor
	label.TextScaled = true
	label.Font = font
	label.TextStrokeTransparency = 0.3
	label.LayoutOrder = layoutOrder
	return label
end

local function CreateVoxelDisplay(
	worldPos: Vector3,
	material: Enum.Material,
	occupancy: number,
	gridPos: Vector3
): BasePart
	local isAir = material == Enum.Material.Air
	local matName = if isAir then "Air" else material.Name
	local color = GetMaterialColor(material)

	local part = Instance.new("Part")
	part.Name = string.format("Voxel_%d_%d_%d", gridPos.X, gridPos.Y, gridPos.Z)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Size = Vector3.one * VOXEL_DISPLAY_SIZE
	part.Position = worldPos
	part.Color = color
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Transparency = if isAir then 0.95 else math.clamp(0.5 + (1 - occupancy) * 0.4, 0.3, 0.95)

	local selectionBox = Instance.new("SelectionBox")
	selectionBox.Adornee = part
	selectionBox.Color3 = color
	selectionBox.LineThickness = 0.02
	selectionBox.Transparency = if isAir then 0.7 else 0.2
	selectionBox.Parent = part

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(4.5, 0, 3, 0)
	billboard.AlwaysOnTop = false
	billboard.LightInfluence = 0
	billboard.Parent = part

	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(0.9, 0, 0.9, 0)
	frame.Position = UDim2.new(0.05, 0, 0.05, 0)
	frame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	frame.BackgroundTransparency = 0.35
	frame.BorderSizePixel = 0
	frame.Parent = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.08, 0)
	corner.Parent = frame

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0.05, 0)
	padding.PaddingRight = UDim.new(0.05, 0)
	padding.PaddingTop = UDim.new(0.05, 0)
	padding.PaddingBottom = UDim.new(0.05, 0)
	padding.Parent = frame

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = frame

	CreateVoxelLabel(matName, color, 1, Enum.Font.GothamBold, 0.35).Parent = frame
	CreateVoxelLabel(
		string.format("%.0f%%", occupancy * 100),
		Color3.fromRGB(255, 255, 255),
		2,
		Enum.Font.GothamMedium,
		0.3
	).Parent =
		frame
	CreateVoxelLabel(
		string.format("[%d, %d, %d]", gridPos.X, gridPos.Y, gridPos.Z),
		Color3.fromRGB(170, 170, 170),
		3,
		Enum.Font.Gotham,
		0.25
	).Parent =
		frame

	return part
end

function ShowVoxelsInViewerPart(viewerPart: ViewerPart)
	local folder = Cleaner(Instance.new("Folder")) :: Folder
	folder.Name = "VoxelDisplays"
	folder.Parent = Workspace

	local refreshQueued = false

	local function RefreshVoxelDisplay()
		folder:ClearAllChildren()
		table.clear(voxels)

		local halfSize = viewerPart.Size / 2
		local currentRegion = Region3.new(viewerPart.Position - halfSize, viewerPart.Position + halfSize)
		local materials, occupancy = Workspace.Terrain:ReadVoxels(currentRegion, VOXEL_RESOLUTION)

		local sizeX = #materials
		local sizeY = if sizeX > 0 then #materials[1] else 0
		local sizeZ = if sizeY > 0 then #materials[1][1] else 0
		if sizeX == 0 or sizeY == 0 or sizeZ == 0 then
			return
		end

		local regionMin = currentRegion.CFrame.Position - currentRegion.Size / 2

		for x = 1, sizeX do
			for y = 1, sizeY do
				for z = 1, sizeZ do
					local mat = materials[x][y][z]
					local occ = occupancy[x][y][z]
					local worldPos = regionMin
						+ Vector3.new(
							(x - 0.5) * VOXEL_RESOLUTION,
							(y - 0.5) * VOXEL_RESOLUTION,
							(z - 0.5) * VOXEL_RESOLUTION
						)
					local gridPos = Vector3.new(
						math.floor(worldPos.X / VOXEL_RESOLUTION),
						math.floor(worldPos.Y / VOXEL_RESOLUTION),
						math.floor(worldPos.Z / VOXEL_RESOLUTION)
					)

					local display = CreateVoxelDisplay(worldPos, mat, occ, gridPos)
					display.Parent = folder
					table.insert(voxels, display)
				end
			end
		end
	end

	local function QueueRefresh()
		if refreshQueued then
			return
		end
		refreshQueued = true
		task.defer(function()
			refreshQueued = false
			RefreshVoxelDisplay()
		end)
	end

	Cleaner(viewerPart:GetPropertyChangedSignal("CFrame"):Connect(QueueRefresh))
	Cleaner(viewerPart:GetPropertyChangedSignal("Size"):Connect(QueueRefresh))
	task.defer(RefreshVoxelDisplay)
end

--- Chunk Viewer Tool ---
local viewerPart = EnsureViewerPart()
Cleaner(EnsureViewerPartSize(viewerPart))
Cleaner(EnsureViewerPartPosition(viewerPart))
ShowVoxelsInViewerPart(viewerPart)
Cleaner(viewerPart.AncestryChanged:Connect(function(_, parent)
	if not parent then
		Cleaner()
	end
end))
