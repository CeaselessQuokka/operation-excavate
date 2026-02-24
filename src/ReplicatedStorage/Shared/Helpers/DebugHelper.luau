--[[
	A versatile debug library for drawing and rendering debug information in 3D and 2D space.
	Supports reusable visuals via the Options.Reuse pattern and auto-cleanup via Duration.
--]]

--!strict
--- Services ---
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

--- Imports ---
local TableHelper = require(ReplicatedStorage.Shared.Helpers.TableHelper)

--- Types ---
export type function Partial(t)
	if not t:is("table") then
		error("Can only call Partial on tables")
	end

	local newTable = types.newtable()
	for key, value in t:properties() do
		newTable:setproperty(key, types.optional(value.read))
	end
	return types.optional(newTable)
end

export type Size = number | Vector3

export type Options = { Reuse: Instance? }

export type PointOptions = {
	Color: Color3 | BrickColor,
	Size: number,
	Transparency: number,
	Duration: number,
	Name: string,
}

export type BoxOptions = {
	Color: Color3 | BrickColor,
	Transparency: number,
	Duration: number,
	Name: string,
	Wireframe: boolean,
	WireframeThickness: number,
}

export type LineOptions = {
	Color: Color3 | BrickColor,
	Thickness: number,
	Transparency: number,
	Duration: number,
	Name: string,
	ShowDirection: boolean,
	ArrowSize: number,
}

export type VectorOptions = {
	Color: Color3 | BrickColor,
	Thickness: number,
	Transparency: number,
	ArrowSize: number,
	Scale: number,
	Duration: number,
	Name: string,
}

export type CFrameOptions = {
	Size: number,
	Thickness: number,
	Duration: number,
	Name: string,
	ShowLookVector: boolean,
}

export type SphereOptions = {
	Color: Color3 | BrickColor,
	Transparency: number,
	Duration: number,
	Name: string,
}

export type CylinderOptions = {
	Color: Color3 | BrickColor,
	Transparency: number,
	Duration: number,
	Name: string,
}

export type CapsuleOptions = {
	Color: Color3 | BrickColor,
	Transparency: number,
	Duration: number,
	Name: string,
}

export type TriangleOptions = {
	Color: Color3 | BrickColor,
	Transparency: number,
	Duration: number,
	Name: string,
	ShowNormal: boolean,
	EdgeThickness: number,
}

export type PlaneOptions = {
	Color: Color3 | BrickColor,
	Transparency: number,
	Duration: number,
	Name: string,
	PlaneSize: number,
	ShowNormal: boolean,
}

export type CircleOptions = {
	Color: Color3 | BrickColor,
	Transparency: number,
	Thickness: number,
	Duration: number,
	Name: string,
	Segments: number,
}

export type GridOptions = {
	Color: Color3 | BrickColor,
	Transparency: number,
	Thickness: number,
	Duration: number,
	Name: string,
	CellSize: number,
	CellCountX: number,
	CellCountZ: number,
}

export type ConeOptions = {
	Color: Color3 | BrickColor,
	Transparency: number,
	Duration: number,
	Name: string,
	AngleDegrees: number,
	Length: number,
	Segments: number,
}

export type FrustumOptions = {
	Color: Color3 | BrickColor,
	Transparency: number,
	Duration: number,
	Name: string,
	Near: number,
	Far: number,
	FieldOfView: number,
	AspectRatio: number,
	Thickness: number,
}

export type TextOptions = {
	Color: Color3,
	Duration: number,
	Name: string,
	TextSize: number,
	AlwaysOnTop: boolean,
	MaxDistance: number,
	TextStrokeColor: Color3,
	TextStrokeTransparency: number,
}

export type PathOptions = {
	Color: Color3 | BrickColor,
	Thickness: number,
	Transparency: number,
	Duration: number,
	Name: string,
	ShowPoints: boolean,
	PointSize: number,
	ShowDirection: boolean,
	StartColor: Color3,
	EndColor: Color3,
}

export type AxesOptions = {
	Size: number,
	Thickness: number,
	Duration: number,
	Name: string,
	ShowLabels: boolean,
}

export type HighlightOptions = {
	FillColor: Color3,
	OutlineColor: Color3,
	FillTransparency: number,
	OutlineTransparency: number,
	Duration: number,
	Name: string,
}

export type RaycastVisualOptions = {
	HitColor: Color3,
	MissColor: Color3,
	NormalColor: Color3,
	Thickness: number,
	Duration: number,
	Name: string,
	ShowNormal: boolean,
}

export type SpatialQueryOptions = {
	Color: Color3 | BrickColor,
	HitColor: Color3,
	Transparency: number,
	Duration: number,
	Name: string,
	ShowLabels: boolean,
}

export type BlinkOptions = {
	Colors: { Color3 },
	Interval: number,
	Cycles: number,
	Duration: number,
	RestoreOriginal: boolean,
}

export type TerrainRegionOptions = {
	Color: Color3,
	OccupiedColor: Color3,
	SkippedColor: Color3,
	BoundsColor: Color3,
	ReadBoundsColor: Color3,
	Transparency: number,
	OccupiedTransparency: number,
	Duration: number,
	Name: string,
	VisualScale: number,
	SkipMinX: number,
	SkipMaxX: number,
	SkipMinY: number,
	SkipMaxY: number,
	SkipMinZ: number,
	SkipMaxZ: number,
	ShowOccupied: boolean,
	ShowEmpty: boolean,
	ShowSkipped: boolean,
	ShowBounds: boolean,
	ShowLabel: boolean,
	ShowMaterials: boolean,
	MaxVoxels: number,
	OccupancyAsOpacity: boolean,
	FilterMaterial: Enum.Material?,
}

export type TerrainRegionResult = {
	Folder: Folder,
	GridSize: Vector3,
	ReadSize: Vector3,
	TotalVoxels: number,
	OccupiedCount: number,
	EmptyCount: number,
	SkippedCount: number,
	WasTruncated: boolean,
}

export type SoundRadiusOptions = {
	Color: Color3 | BrickColor,
	Transparency: number,
	Duration: number,
	Name: string,
	InnerColor: Color3,
}

export type LightRadiusOptions = {
	Color: Color3 | BrickColor,
	Transparency: number,
	Duration: number,
	Name: string,
}

export type ScreenTextOptions = {
	Position: UDim2,
	Size: UDim2,
	AnchorPoint: Vector2,
	TextColor: Color3,
	TextSize: number,
	BackgroundTransparency: number,
	BackgroundColor: Color3,
	Duration: number,
	Name: string,
}

export type ScreenLineOptions = {
	Color: Color3,
	Transparency: number,
	Thickness: number,
	Duration: number,
	Name: string,
}

export type ScreenRectOptions = {
	FillColor: Color3,
	FillTransparency: number,
	Duration: number,
	Name: string,
}

export type ScreenCircleOptions = {
	FillColor: Color3,
	FillTransparency: number,
	Duration: number,
	Name: string,
}

export type ProjectileArcOptions = {
	Color: Color3 | BrickColor,
	Transparency: number,
	Thickness: number,
	Duration: number,
	Name: string,
	TimeStep: number,
	MaxTime: number,
	Gravity: Vector3,
}

--- Variables ---
local DEBUG_FOLDER_NAME = "DebugVisuals"
local SCREEN_GUI_NAME = "DebugScreenGui"
local DEFAULT_COLOR: Color3 = Color3.fromRGB(255, 0, 255)
local EPSILON = 0.001
local HALF_PI = math.pi / 2

local BOX_EDGE_INDICES = table.freeze({ 1, 2, 1, 3, 1, 5, 2, 4, 2, 6, 3, 4, 3, 7, 4, 8, 5, 6, 5, 7, 6, 8, 7, 8 })

local AXIS_RED = Color3.fromRGB(255, 0, 0)
local AXIS_GREEN = Color3.fromRGB(0, 255, 0)
local AXIS_BLUE = Color3.fromRGB(0, 0, 255)
local AXIS_CYAN = Color3.fromRGB(0, 255, 255)

local DEFAULT_POINT: PointOptions = table.freeze({
	Color = DEFAULT_COLOR,
	Size = 1,
	Transparency = 0,
	Duration = 0,
	Name = "DebugPoint",
})

local DEFAULT_BOX: BoxOptions = table.freeze({
	Color = DEFAULT_COLOR,
	Transparency = 0.5,
	Duration = 0,
	Name = "DebugBox",
	Wireframe = false,
	WireframeThickness = 0.1,
})

local DEFAULT_LINE: LineOptions = table.freeze({
	Color = DEFAULT_COLOR,
	Thickness = 0.1,
	Transparency = 0,
	Duration = 0,
	Name = "DebugLine",
	ShowDirection = true,
	ArrowSize = 0.5,
})

local DEFAULT_VECTOR: VectorOptions = table.freeze({
	Color = DEFAULT_COLOR,
	Thickness = 0.1,
	Transparency = 0,
	ArrowSize = 0.5,
	Scale = 1,
	Duration = 0,
	Name = "DebugVector",
})

local DEFAULT_CFRAME: CFrameOptions = table.freeze({
	Size = 2,
	Thickness = 0.1,
	Duration = 0,
	Name = "DebugCFrame",
	ShowLookVector = true,
})

local DEFAULT_SPHERE: SphereOptions = table.freeze({
	Color = DEFAULT_COLOR,
	Transparency = 0.5,
	Duration = 0,
	Name = "DebugSphere",
})

local DEFAULT_CYLINDER: CylinderOptions = table.freeze({
	Color = DEFAULT_COLOR,
	Transparency = 0.5,
	Duration = 0,
	Name = "DebugCylinder",
})

local DEFAULT_CAPSULE: CapsuleOptions = table.freeze({
	Color = DEFAULT_COLOR,
	Transparency = 0.5,
	Duration = 0,
	Name = "DebugCapsule",
})

local DEFAULT_TRIANGLE: TriangleOptions = table.freeze({
	Color = DEFAULT_COLOR,
	Transparency = 0,
	Duration = 0,
	Name = "DebugTriangle",
	ShowNormal = false,
	EdgeThickness = 0.05,
})

local DEFAULT_PLANE: PlaneOptions = table.freeze({
	Color = DEFAULT_COLOR,
	Transparency = 0.7,
	Duration = 0,
	Name = "DebugPlane",
	PlaneSize = 20,
	ShowNormal = true,
})

local DEFAULT_CIRCLE: CircleOptions = table.freeze({
	Color = DEFAULT_COLOR,
	Transparency = 0,
	Thickness = 0.1,
	Duration = 0,
	Name = "DebugCircle",
	Segments = 32,
})

local DEFAULT_GRID: GridOptions = table.freeze({
	Color = Color3.fromRGB(128, 128, 128),
	Transparency = 0.5,
	Thickness = 0.05,
	Duration = 0,
	Name = "DebugGrid",
	CellSize = 4,
	CellCountX = 10,
	CellCountZ = 10,
})

local DEFAULT_CONE: ConeOptions = table.freeze({
	Color = DEFAULT_COLOR,
	Transparency = 0.5,
	Duration = 0,
	Name = "DebugCone",
	AngleDegrees = 30,
	Length = 10,
	Segments = 16,
})

local DEFAULT_FRUSTUM: FrustumOptions = table.freeze({
	Color = DEFAULT_COLOR,
	Transparency = 0,
	Duration = 0,
	Name = "DebugFrustum",
	Near = 0.1,
	Far = 100,
	FieldOfView = 70,
	AspectRatio = 16 / 9,
	Thickness = 0.05,
})

local DEFAULT_TEXT: TextOptions = table.freeze({
	Color = Color3.new(1, 1, 1),
	Duration = 0,
	Name = "DebugText",
	TextSize = 16,
	AlwaysOnTop = true,
	MaxDistance = 100,
	TextStrokeColor = Color3.new(0, 0, 0),
	TextStrokeTransparency = 0.5,
})

local DEFAULT_PATH: PathOptions = table.freeze({
	Color = DEFAULT_COLOR,
	Thickness = 0.1,
	Transparency = 0,
	Duration = 0,
	Name = "DebugPath",
	ShowPoints = true,
	PointSize = 0.2,
	ShowDirection = true,
	StartColor = Color3.fromRGB(0, 255, 0),
	EndColor = Color3.fromRGB(255, 0, 0),
})

local DEFAULT_AXES: AxesOptions = table.freeze({
	Size = 5,
	Thickness = 0.1,
	Duration = 0,
	Name = "DebugAxes",
	ShowLabels = false,
})

local DEFAULT_HIGHLIGHT: HighlightOptions = table.freeze({
	FillColor = DEFAULT_COLOR,
	OutlineColor = Color3.new(1, 1, 1),
	FillTransparency = 0.5,
	OutlineTransparency = 0,
	Duration = 0,
	Name = "DebugHighlight",
})

local DEFAULT_RAYCAST_VISUAL: RaycastVisualOptions = table.freeze({
	HitColor = Color3.fromRGB(0, 255, 0),
	MissColor = Color3.fromRGB(255, 0, 0),
	NormalColor = Color3.fromRGB(0, 128, 255),
	Thickness = 0.1,
	Duration = 0,
	Name = "DebugRaycast",
	ShowNormal = true,
})

local DEFAULT_SPATIAL_QUERY: SpatialQueryOptions = table.freeze({
	Color = Color3.fromRGB(255, 165, 0),
	HitColor = Color3.fromRGB(0, 255, 0),
	Transparency = 0.7,
	Duration = 0,
	Name = "DebugSpatialQuery",
	ShowLabels = false,
})

local DEFAULT_BLINK: BlinkOptions = table.freeze({
	Colors = table.freeze({ Color3.fromRGB(255, 0, 0), Color3.new(1, 1, 1) }),
	Interval = 0.2,
	Cycles = 5,
	Duration = 0,
	RestoreOriginal = true,
})

local DEFAULT_TERRAIN_REGION: TerrainRegionOptions = table.freeze({
	Color = Color3.fromRGB(100, 100, 255),
	OccupiedColor = Color3.fromRGB(0, 255, 0),
	SkippedColor = Color3.fromRGB(255, 100, 100),
	BoundsColor = Color3.fromRGB(255, 255, 0),
	ReadBoundsColor = Color3.fromRGB(0, 255, 255),
	Transparency = 0.8,
	OccupiedTransparency = 0.6,
	Duration = 0,
	Name = "DebugTerrainRegion",
	VisualScale = 0.9,
	SkipMinX = 0,
	SkipMaxX = 0,
	SkipMinY = 0,
	SkipMaxY = 0,
	SkipMinZ = 0,
	SkipMaxZ = 0,
	ShowOccupied = true,
	ShowEmpty = true,
	ShowSkipped = false,
	ShowBounds = true,
	ShowLabel = false,
	ShowMaterials = false,
	MaxVoxels = 2000,
	OccupancyAsOpacity = false,
	FilterMaterial = nil,
})

local DEFAULT_SOUND_RADIUS: SoundRadiusOptions = table.freeze({
	Color = Color3.fromRGB(0, 180, 255),
	Transparency = 0.8,
	Duration = 0,
	Name = "DebugSoundRadius",
	InnerColor = Color3.fromRGB(0, 255, 100),
})

local DEFAULT_LIGHT_RADIUS: LightRadiusOptions = table.freeze({
	Color = Color3.fromRGB(255, 255, 100),
	Transparency = 0.8,
	Duration = 0,
	Name = "DebugLightRadius",
})

local DEFAULT_SCREEN_TEXT: ScreenTextOptions = table.freeze({
	Position = UDim2.fromScale(0.5, 0),
	Size = UDim2.fromOffset(300, 30),
	AnchorPoint = Vector2.new(0.5, 0),
	TextColor = Color3.new(1, 1, 1),
	TextSize = 16,
	BackgroundTransparency = 0.5,
	BackgroundColor = Color3.new(0, 0, 0),
	Duration = 0,
	Name = "DebugScreenText",
})

local DEFAULT_SCREEN_LINE: ScreenLineOptions = table.freeze({
	Color = Color3.new(1, 1, 1),
	Transparency = 0,
	Thickness = 2,
	Duration = 0,
	Name = "DebugScreenLine",
})

local DEFAULT_SCREEN_RECT: ScreenRectOptions = table.freeze({
	FillColor = Color3.new(1, 1, 1),
	FillTransparency = 0.5,
	Duration = 0,
	Name = "DebugScreenRect",
})

local DEFAULT_SCREEN_CIRCLE: ScreenCircleOptions = table.freeze({
	FillColor = Color3.new(1, 1, 1),
	FillTransparency = 0.5,
	Duration = 0,
	Name = "DebugScreenCircle",
})

local DEFAULT_PROJECTILE_ARC: ProjectileArcOptions = table.freeze({
	Color = DEFAULT_COLOR,
	Transparency = 0,
	Thickness = 0.05,
	Duration = 0,
	Name = "DebugProjectileArc",
	TimeStep = 0.05,
	MaxTime = 5,
	Gravity = Vector3.new(0, -196.2, 0),
})

local MATERIAL_COLORS: { [Enum.Material]: Color3 } = table.freeze({
	[Enum.Material.Grass] = Color3.fromRGB(76, 153, 0),
	[Enum.Material.Sand] = Color3.fromRGB(235, 213, 156),
	[Enum.Material.Rock] = Color3.fromRGB(128, 128, 128),
	[Enum.Material.Water] = Color3.fromRGB(0, 128, 255),
	[Enum.Material.Ground] = Color3.fromRGB(139, 90, 43),
	[Enum.Material.Sandstone] = Color3.fromRGB(201, 168, 119),
	[Enum.Material.Slate] = Color3.fromRGB(88, 91, 96),
	[Enum.Material.Snow] = Color3.fromRGB(235, 245, 255),
	[Enum.Material.Mud] = Color3.fromRGB(90, 65, 47),
	[Enum.Material.Brick] = Color3.fromRGB(138, 97, 73),
	[Enum.Material.Concrete] = Color3.fromRGB(159, 161, 163),
	[Enum.Material.Glacier] = Color3.fromRGB(175, 221, 255),
	[Enum.Material.WoodPlanks] = Color3.fromRGB(175, 128, 79),
	[Enum.Material.CrackedLava] = Color3.fromRGB(255, 89, 0),
	[Enum.Material.Basalt] = Color3.fromRGB(48, 48, 48),
	[Enum.Material.Salt] = Color3.fromRGB(220, 220, 220),
	[Enum.Material.Pavement] = Color3.fromRGB(148, 148, 148),
	[Enum.Material.Limestone] = Color3.fromRGB(206, 203, 193),
	[Enum.Material.Asphalt] = Color3.fromRGB(62, 62, 62),
	[Enum.Material.LeafyGrass] = Color3.fromRGB(91, 154, 76),
	[Enum.Material.Cobblestone] = Color3.fromRGB(132, 123, 113),
	[Enum.Material.Ice] = Color3.fromRGB(200, 240, 255),
})

local _enabled = true
local _debugFolder: Folder? = nil
local _screenGui: ScreenGui? = nil

--- Functions ---
local ReconcileOptions = TableHelper.ReconcileOptions

local function ResolveSize(size: Size): Vector3
	return if typeof(size) == "number" then Vector3.new(size, size, size) else size
end

local function ResolveColor(color: Color3 | BrickColor): Color3
	return if typeof(color) == "BrickColor" then color.Color else color
end

local function ApplyColor(part: BasePart, color: Color3 | BrickColor)
	if typeof(color) == "BrickColor" then
		part.BrickColor = color
	else
		part.Color = color
	end
end

local function GetOrCreateDebugFolder(): Folder
	if _debugFolder and _debugFolder.Parent then
		return _debugFolder
	end
	local folder = Workspace:FindFirstChild(DEBUG_FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = DEBUG_FOLDER_NAME
		folder.Parent = Workspace
	end
	_debugFolder = folder :: Folder
	return folder :: Folder
end

local function GetOrCreateDebugScreenGui(): ScreenGui?
	if not RunService:IsClient() then
		return nil
	end
	if _screenGui and _screenGui.Parent then
		return _screenGui
	end
	local localPlayer = Players.LocalPlayer
	if not localPlayer then
		return nil
	end
	local playerGui = localPlayer:FindFirstChild("PlayerGui")
	if not playerGui then
		return nil
	end
	local gui = playerGui:FindFirstChild(SCREEN_GUI_NAME) :: ScreenGui?
	if not gui then
		gui = Instance.new("ScreenGui")
		gui.Name = SCREEN_GUI_NAME
		gui.ResetOnSpawn = false
		gui.DisplayOrder = 10000
		gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		gui.Parent = playerGui
	end
	_screenGui = gui
	return gui
end

local function ApplyDuration(instance: Instance, duration: number)
	if duration > 0 then
		Debris:AddItem(instance, duration)
	end
end

local function SafeLookAt(from: Vector3, to: Vector3): CFrame
	local direction = to - from
	if direction.Magnitude < EPSILON then
		return CFrame.new(from)
	end
	local dot = math.abs(direction.Unit:Dot(Vector3.yAxis))
	return if dot > 0.9999 then CFrame.lookAt(from, to, Vector3.xAxis) else CFrame.lookAt(from, to)
end

local function SafeCrossNormal(v1: Vector3, v2: Vector3): Vector3
	local cross = v1:Cross(v2)
	return if cross.Magnitude < EPSILON then Vector3.yAxis else cross.Unit
end

local function MakeDebugPart(): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.Size = Vector3.one
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.TopSurface = Enum.SurfaceType.Smooth
	return part
end

local function MakeBlockPart(reuse: Instance?): BasePart
	if reuse and (reuse :: Instance):IsA("BasePart") then
		return reuse :: BasePart
	end
	local part = MakeDebugPart()
	local mesh = Instance.new("BlockMesh")
	mesh.Name = "Mesh"
	mesh.Parent = part
	return part
end

local function MakeSpherePart(reuse: Instance?): BasePart
	if reuse and (reuse :: Instance):IsA("BasePart") then
		return reuse :: BasePart
	end
	local part = MakeDebugPart()
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Name = "Mesh"
	mesh.Parent = part
	return part
end

local function MakeCylinderPart(reuse: Instance?): BasePart
	if reuse and (reuse :: Instance):IsA("BasePart") then
		return reuse :: BasePart
	end
	local part = MakeDebugPart()
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Cylinder
	mesh.Name = "Mesh"
	mesh.Parent = part
	return part
end

local function SetMeshScale(part: BasePart, scale: Vector3)
	local mesh = part:FindFirstChild("Mesh")
	if mesh then
		(mesh :: any).Scale = scale
	end
end

local function CreateEdge(
	from: Vector3,
	to: Vector3,
	thickness: number,
	color: Color3,
	transparency: number,
	parent: Instance
): Part?
	local distance = (to - from).Magnitude
	if distance < EPSILON then
		return nil
	end
	local part = MakeDebugPart()
	local mesh = Instance.new("BlockMesh")
	mesh.Name = "Mesh"
	mesh.Scale = Vector3.new(thickness, thickness, distance)
	mesh.Parent = part
	part.CFrame = SafeLookAt((from + to) / 2, to)
	part.Color = color
	part.Transparency = transparency
	part.Parent = parent
	return part
end

local function CreateMarker(
	position: Vector3,
	diameter: number,
	color: Color3,
	transparency: number,
	parent: Instance
): Part
	local part = MakeDebugPart()
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Name = "Mesh"
	mesh.Scale = Vector3.new(diameter, diameter, diameter)
	mesh.Parent = part
	part.CFrame = CFrame.new(position)
	part.Color = color
	part.Transparency = transparency
	part.Parent = parent
	return part
end

local function CreateLineParts(
	from: Vector3,
	to: Vector3,
	thickness: number,
	color: Color3,
	transparency: number,
	showDirection: boolean,
	arrowSize: number,
	parent: Instance
)
	local distance = (to - from).Magnitude
	if distance < EPSILON then
		return
	end
	CreateEdge(from, to, thickness, color, transparency, parent)
	if showDirection then
		CreateMarker(to, arrowSize, color, transparency, parent)
	end
end

local function CreateWireframeBox(
	cframe: CFrame,
	size: Vector3,
	color: Color3,
	thickness: number,
	transparency: number
): Folder
	local folder = Instance.new("Folder")
	local halfSize = size / 2
	local corners = table.create(8)
	corners[1] = cframe * Vector3.new(halfSize.X, halfSize.Y, halfSize.Z)
	corners[2] = cframe * Vector3.new(halfSize.X, halfSize.Y, -halfSize.Z)
	corners[3] = cframe * Vector3.new(halfSize.X, -halfSize.Y, halfSize.Z)
	corners[4] = cframe * Vector3.new(halfSize.X, -halfSize.Y, -halfSize.Z)
	corners[5] = cframe * Vector3.new(-halfSize.X, halfSize.Y, halfSize.Z)
	corners[6] = cframe * Vector3.new(-halfSize.X, halfSize.Y, -halfSize.Z)
	corners[7] = cframe * Vector3.new(-halfSize.X, -halfSize.Y, halfSize.Z)
	corners[8] = cframe * Vector3.new(-halfSize.X, -halfSize.Y, -halfSize.Z)
	for i = 1, #BOX_EDGE_INDICES, 2 do
		CreateEdge(
			corners[BOX_EDGE_INDICES[i]],
			corners[BOX_EDGE_INDICES[i + 1]],
			thickness,
			color,
			transparency,
			folder
		)
	end
	return folder
end

local function GenerateCirclePoints(cframe: CFrame, radius: number, segments: number): { Vector3 }
	local points = table.create(segments)
	local step = (2 * math.pi) / segments
	for i = 0, segments - 1 do
		local angle = i * step
		points[i + 1] = cframe * Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
	end
	return points
end

local function CreateBillboardLabel(
	position: Vector3,
	text: string,
	color: Color3,
	textSize: number,
	parent: Instance
): Part
	local part = MakeDebugPart()
	part.Transparency = 1
	part.Size = Vector3.new(0.1, 0.1, 0.1)
	part.CFrame = CFrame.new(position)
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(0, 200, 0, 50)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 100
	billboard.Parent = part
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.TextColor3 = color
	label.TextSize = textSize
	label.Font = Enum.Font.GothamBold
	label.Text = text
	label.TextStrokeTransparency = 0.5
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.Parent = billboard
	part.Parent = parent
	return part
end

--- Debug Helper ---
local DebugHelper = {}

function DebugHelper.SetEnabled(value: boolean)
	_enabled = value
end

function DebugHelper.IsEnabled(): boolean
	return _enabled
end

function DebugHelper.ShouldDebug(): boolean
	return RunService:IsStudio() or Workspace:GetAttribute("DebugVisualsEnabled") == true
end

function DebugHelper.GetDebugFolder(): Folder
	return GetOrCreateDebugFolder()
end

function DebugHelper.ClearAll()
	local folder = Workspace:FindFirstChild(DEBUG_FOLDER_NAME)
	if folder then
		folder:ClearAllChildren()
	end
	if _screenGui and _screenGui.Parent then
		_screenGui:ClearAllChildren()
	end
end

function DebugHelper.ClearByName(name: string)
	local folder = Workspace:FindFirstChild(DEBUG_FOLDER_NAME)
	if folder then
		for _, child in folder:GetChildren() do
			if child.Name == name then
				child:Destroy()
			end
		end
	end
	if _screenGui and _screenGui.Parent then
		for _, child in _screenGui:GetChildren() do
			if child.Name == name then
				child:Destroy()
			end
		end
	end
end

function DebugHelper.GetByName(name: string): { Instance }
	local results: { Instance } = {}
	local folder = Workspace:FindFirstChild(DEBUG_FOLDER_NAME)
	if folder then
		for _, child in folder:GetChildren() do
			if child.Name == name then
				table.insert(results, child)
			end
		end
	end
	if _screenGui and _screenGui.Parent then
		for _, child in _screenGui:GetChildren() do
			if child.Name == name then
				table.insert(results, child)
			end
		end
	end
	return results
end

function DebugHelper.ApplyPartOptions(part: BasePart, color: Color3 | BrickColor, transparency: number)
	ApplyColor(part, color)
	part.Transparency = transparency
end

--- Point / Sphere ---

function DebugHelper.Point(position: Vector3, options: (Options & Partial<PointOptions>)?): BasePart?
	if not _enabled then
		return nil
	end
	local opts = ReconcileOptions(options, DEFAULT_POINT) :: Options & PointOptions
	local part = MakeSpherePart(opts.Reuse)
	local isNew = not opts.Reuse
	local diameter = opts.Size
	part.CFrame = CFrame.new(position)
	ApplyColor(part, opts.Color)
	part.Transparency = opts.Transparency
	SetMeshScale(part, Vector3.new(diameter, diameter, diameter))
	if isNew then
		part.Name = opts.Name
		part.Parent = GetOrCreateDebugFolder()
		ApplyDuration(part, opts.Duration)
	end
	return part
end

function DebugHelper.Sphere(center: Vector3, radius: number, options: (Options & Partial<SphereOptions>)?): BasePart?
	if not _enabled then
		return nil
	end
	radius = math.max(0, radius)
	if radius < EPSILON then
		return DebugHelper.Point(center, options :: any)
	end
	local opts = ReconcileOptions(options, DEFAULT_SPHERE) :: Options & SphereOptions
	local part = MakeSpherePart(opts.Reuse)
	local isNew = not opts.Reuse
	local diameter = radius * 2
	part.CFrame = CFrame.new(center)
	ApplyColor(part, opts.Color)
	part.Transparency = opts.Transparency
	SetMeshScale(part, Vector3.new(diameter, diameter, diameter))
	if isNew then
		part.Name = opts.Name
		part.Parent = GetOrCreateDebugFolder()
		ApplyDuration(part, opts.Duration)
	end
	return part
end

--- Box ---

function DebugHelper.Box(cframe: CFrame, size: Size, options: (Options & Partial<BoxOptions>)?): Instance?
	if not _enabled then
		return nil
	end
	local opts = ReconcileOptions(options, DEFAULT_BOX) :: Options & BoxOptions
	local resolvedSize = ResolveSize(size)
	local color = ResolveColor(opts.Color)
	if opts.Wireframe then
		local folder = CreateWireframeBox(cframe, resolvedSize, color, opts.WireframeThickness, opts.Transparency)
		folder.Name = opts.Name
		folder.Parent = GetOrCreateDebugFolder()
		ApplyDuration(folder, opts.Duration)
		return folder
	end
	local part = MakeBlockPart(opts.Reuse)
	local isNew = not opts.Reuse
	part.CFrame = cframe
	ApplyColor(part, opts.Color)
	part.Transparency = opts.Transparency
	SetMeshScale(part, resolvedSize)
	if isNew then
		part.Name = opts.Name
		part.Parent = GetOrCreateDebugFolder()
		ApplyDuration(part, opts.Duration)
	end
	return part
end

--- Line / Ray / Vector ---

function DebugHelper.Line(startPos: Vector3, endPos: Vector3, options: (Options & Partial<LineOptions>)?): Folder?
	if not _enabled then
		return nil
	end
	if (endPos - startPos).Magnitude < EPSILON then
		return nil
	end
	local opts = ReconcileOptions(options, DEFAULT_LINE) :: Options & LineOptions
	local color = ResolveColor(opts.Color)
	local folder = Instance.new("Folder")
	folder.Name = opts.Name
	CreateLineParts(
		startPos,
		endPos,
		opts.Thickness,
		color,
		opts.Transparency,
		opts.ShowDirection,
		opts.ArrowSize,
		folder
	)
	folder.Parent = GetOrCreateDebugFolder()
	ApplyDuration(folder, opts.Duration)
	return folder
end

function DebugHelper.Ray(origin: Vector3, direction: Vector3, options: (Options & Partial<LineOptions>)?): Folder?
	return DebugHelper.Line(origin, origin + direction, options)
end

function DebugHelper.Vector(position: Vector3, vector: Vector3, options: (Options & Partial<VectorOptions>)?): Folder?
	if not _enabled then
		return nil
	end
	local opts = ReconcileOptions(options, DEFAULT_VECTOR) :: Options & VectorOptions
	if vector.Magnitude < EPSILON then
		return nil
	end
	return DebugHelper.Line(
		position,
		position + (vector * opts.Scale),
		{
			Color = opts.Color,
			Thickness = opts.Thickness,
			Transparency = opts.Transparency,
			ShowDirection = true,
			ArrowSize = opts.ArrowSize,
			Duration = opts.Duration,
			Name = opts.Name,
		} :: any
	)
end

--- CFrame / Axes ---

function DebugHelper.CFrame(cframe: CFrame, options: (Options & Partial<CFrameOptions>)?): Folder?
	if not _enabled then
		return nil
	end
	local opts = ReconcileOptions(options, DEFAULT_CFRAME) :: Options & CFrameOptions
	local size = math.max(opts.Size, EPSILON)
	local thickness = opts.Thickness
	local arrowSize = size * 0.15
	local origin = cframe.Position
	local folder = Instance.new("Folder")
	folder.Name = opts.Name
	CreateLineParts(origin, origin + cframe.RightVector * size, thickness, AXIS_RED, 0, true, arrowSize, folder)
	CreateLineParts(origin, origin + cframe.UpVector * size, thickness, AXIS_GREEN, 0, true, arrowSize, folder)
	CreateLineParts(origin, origin - cframe.LookVector * size, thickness, AXIS_BLUE, 0, true, arrowSize, folder)
	if opts.ShowLookVector then
		CreateLineParts(
			origin,
			origin + cframe.LookVector * size,
			thickness * 0.7,
			AXIS_CYAN,
			0,
			true,
			arrowSize * 0.8,
			folder
		)
	end
	CreateMarker(origin, thickness * 3, Color3.new(1, 1, 1), 0, folder)
	folder.Parent = GetOrCreateDebugFolder()
	ApplyDuration(folder, opts.Duration)
	return folder
end

function DebugHelper.Axes(cframe: CFrame, options: (Options & Partial<AxesOptions>)?): Folder?
	if not _enabled then
		return nil
	end
	local opts = ReconcileOptions(options, DEFAULT_AXES) :: Options & AxesOptions
	local size = math.max(opts.Size, EPSILON)
	local thickness = opts.Thickness
	local origin = cframe.Position
	local folder = Instance.new("Folder")
	folder.Name = opts.Name
	CreateLineParts(origin, origin + cframe.RightVector * size, thickness, AXIS_RED, 0, true, 0.3, folder)
	CreateLineParts(origin, origin + cframe.UpVector * size, thickness, AXIS_GREEN, 0, true, 0.3, folder)
	CreateLineParts(origin, origin - cframe.LookVector * size, thickness, AXIS_BLUE, 0, true, 0.3, folder)
	if opts.ShowLabels then
		CreateBillboardLabel(origin + cframe.RightVector * size, "X", AXIS_RED, 14, folder)
		CreateBillboardLabel(origin + cframe.UpVector * size, "Y", AXIS_GREEN, 14, folder)
		CreateBillboardLabel(origin - cframe.LookVector * size, "Z", AXIS_BLUE, 14, folder)
	end
	folder.Parent = GetOrCreateDebugFolder()
	ApplyDuration(folder, opts.Duration)
	return folder
end

--- Cylinder / Capsule ---

function DebugHelper.Cylinder(
	startPos: Vector3,
	endPos: Vector3,
	radius: number,
	options: (Options & Partial<CylinderOptions>)?
): BasePart?
	if not _enabled then
		return nil
	end
	radius = math.max(radius, 0)
	local distance = (endPos - startPos).Magnitude
	if distance < EPSILON then
		return DebugHelper.Sphere(startPos, radius, options :: any)
	end
	local opts = ReconcileOptions(options, DEFAULT_CYLINDER) :: Options & CylinderOptions
	local part = MakeCylinderPart(opts.Reuse)
	local isNew = not opts.Reuse
	local midPoint = (startPos + endPos) / 2
	local diameter = radius * 2
	part.CFrame = SafeLookAt(midPoint, endPos) * CFrame.Angles(0, HALF_PI, 0)
	ApplyColor(part, opts.Color)
	part.Transparency = opts.Transparency
	SetMeshScale(part, Vector3.new(distance, diameter, diameter))
	if isNew then
		part.Name = opts.Name
		part.Parent = GetOrCreateDebugFolder()
		ApplyDuration(part, opts.Duration)
	end
	return part
end

function DebugHelper.Capsule(
	startPos: Vector3,
	endPos: Vector3,
	radius: number,
	options: (Options & Partial<CapsuleOptions>)?
): Folder?
	if not _enabled then
		return nil
	end
	radius = math.max(radius, 0)
	local opts = ReconcileOptions(options, DEFAULT_CAPSULE) :: Options & CapsuleOptions
	local color = ResolveColor(opts.Color)
	local diameter = radius * 2
	local distance = (endPos - startPos).Magnitude

	if opts.Reuse and (opts.Reuse :: Instance):IsA("Folder") then
		local folder = opts.Reuse :: Folder
		-- Update or create/destroy cylinder body
		local body = folder:FindFirstChild("Body") :: BasePart?
		if distance >= EPSILON then
			if not body then
				body = MakeCylinderPart()
				body.Name = "Body"
				body.Parent = folder
			end
			local b = body :: BasePart
			local midPoint = (startPos + endPos) / 2
			b.CFrame = SafeLookAt(midPoint, endPos) * CFrame.Angles(0, HALF_PI, 0)
			b.Color = color
			b.Transparency = opts.Transparency
			SetMeshScale(b, Vector3.new(distance, diameter, diameter))
		elseif body then
			body:Destroy()
		end
		-- Update caps
		local startCap = folder:FindFirstChild("StartCap") :: BasePart?
		if startCap then
			startCap.CFrame = CFrame.new(startPos)
			startCap.Color = color
			startCap.Transparency = opts.Transparency
			SetMeshScale(startCap, Vector3.new(diameter, diameter, diameter))
		end
		local endCap = folder:FindFirstChild("EndCap") :: BasePart?
		if endCap then
			endCap.CFrame = CFrame.new(endPos)
			endCap.Color = color
			endCap.Transparency = opts.Transparency
			SetMeshScale(endCap, Vector3.new(diameter, diameter, diameter))
		end
		return folder
	end

	local folder = Instance.new("Folder")
	folder.Name = opts.Name
	if distance >= EPSILON then
		local midPoint = (startPos + endPos) / 2
		local cylPart = MakeCylinderPart()
		cylPart.CFrame = SafeLookAt(midPoint, endPos) * CFrame.Angles(0, HALF_PI, 0)
		cylPart.Color = color
		cylPart.Transparency = opts.Transparency
		SetMeshScale(cylPart, Vector3.new(distance, diameter, diameter))
		cylPart.Name = "Body"
		cylPart.Parent = folder
	end
	local startMarker = CreateMarker(startPos, diameter, color, opts.Transparency, folder)
	startMarker.Name = "StartCap"
	local endMarker = CreateMarker(endPos, diameter, color, opts.Transparency, folder)
	endMarker.Name = "EndCap"
	folder.Parent = GetOrCreateDebugFolder()
	ApplyDuration(folder, opts.Duration)
	return folder
end

--- Triangle / Plane ---

function DebugHelper.Triangle(
	p1: Vector3,
	p2: Vector3,
	p3: Vector3,
	options: (Options & Partial<TriangleOptions>)?
): Folder?
	if not _enabled then
		return nil
	end
	local opts = ReconcileOptions(options, DEFAULT_TRIANGLE) :: Options & TriangleOptions
	local color = ResolveColor(opts.Color)
	local folder = Instance.new("Folder")
	folder.Name = opts.Name
	CreateEdge(p1, p2, opts.EdgeThickness, color, opts.Transparency, folder)
	CreateEdge(p2, p3, opts.EdgeThickness, color, opts.Transparency, folder)
	CreateEdge(p3, p1, opts.EdgeThickness, color, opts.Transparency, folder)
	if opts.ShowNormal then
		local centroid = (p1 + p2 + p3) / 3
		local normal = SafeCrossNormal(p2 - p1, p3 - p1)
		CreateLineParts(
			centroid,
			centroid + normal * 2,
			opts.EdgeThickness,
			Color3.fromRGB(255, 255, 0),
			0,
			true,
			0.3,
			folder
		)
	end
	folder.Parent = GetOrCreateDebugFolder()
	ApplyDuration(folder, opts.Duration)
	return folder
end

function DebugHelper.Plane(position: Vector3, normal: Vector3, options: (Options & Partial<PlaneOptions>)?): Folder?
	if not _enabled then
		return nil
	end
	local opts = ReconcileOptions(options, DEFAULT_PLANE) :: Options & PlaneOptions
	local normalUnit = if normal.Magnitude > 0 then normal.Unit else Vector3.yAxis
	local color = ResolveColor(opts.Color)
	local folder = Instance.new("Folder")
	folder.Name = opts.Name
	local planePart = MakeBlockPart()
	planePart.CFrame = SafeLookAt(position, position + normalUnit) * CFrame.Angles(HALF_PI, 0, 0)
	planePart.Color = color
	planePart.Transparency = opts.Transparency
	SetMeshScale(planePart, Vector3.new(opts.PlaneSize, 0.05, opts.PlaneSize))
	planePart.Name = "Plane"
	planePart.Parent = folder
	if opts.ShowNormal then
		CreateLineParts(position, position + normalUnit * 3, 0.08, Color3.fromRGB(255, 255, 0), 0, true, 0.3, folder)
	end
	folder.Parent = GetOrCreateDebugFolder()
	ApplyDuration(folder, opts.Duration)
	return folder
end

--- Bounding Boxes ---

function DebugHelper.AABB(min: Vector3, max: Vector3, options: (Options & Partial<BoxOptions>)?): Instance?
	local actualMin = Vector3.new(math.min(min.X, max.X), math.min(min.Y, max.Y), math.min(min.Z, max.Z))
	local actualMax = Vector3.new(math.max(min.X, max.X), math.max(min.Y, max.Y), math.max(min.Z, max.Z))
	return DebugHelper.Box(CFrame.new((actualMin + actualMax) / 2), actualMax - actualMin, options)
end

function DebugHelper.Region3(region: Region3, options: (Options & Partial<BoxOptions>)?): Instance?
	return DebugHelper.Box(region.CFrame, region.Size, options)
end

function DebugHelper.BoundingBox(part: BasePart, options: (Options & Partial<BoxOptions>)?): Instance?
	return DebugHelper.Box(part.CFrame, part.Size, options)
end

function DebugHelper.ModelBoundingBox(model: Model, options: (Options & Partial<BoxOptions>)?): Instance?
	if not _enabled then
		return nil
	end
	local cframe, size = model:GetBoundingBox()
	return DebugHelper.Box(cframe, size, options)
end

function DebugHelper.BoundingBoxFromCorners(
	posA: Vector3,
	posB: Vector3,
	rotation: CFrame?,
	options: (Options & Partial<BoxOptions>)?
): Folder?
	if not _enabled then
		return nil
	end
	local opts = ReconcileOptions(options, DEFAULT_BOX) :: Options & BoxOptions
	local size = Vector3.new(math.abs(posB.X - posA.X), math.abs(posB.Y - posA.Y), math.abs(posB.Z - posA.Z))
	local center = (posA + posB) / 2
	local rotationOnly = if rotation then rotation.Rotation else CFrame.identity
	local centerCFrame = CFrame.new(center) * rotationOnly
	local color = ResolveColor(opts.Color)
	local folder = CreateWireframeBox(centerCFrame, size, color, opts.WireframeThickness, opts.Transparency)
	folder.Name = opts.Name
	folder.Parent = GetOrCreateDebugFolder()
	ApplyDuration(folder, opts.Duration)
	return folder
end

--- Circle / Grid / Cone ---

function DebugHelper.Circle3D(cframe: CFrame, radius: number, options: (Options & Partial<CircleOptions>)?): Folder?
	if not _enabled then
		return nil
	end
	local opts = ReconcileOptions(options, DEFAULT_CIRCLE) :: Options & CircleOptions
	local color = ResolveColor(opts.Color)
	local folder = Instance.new("Folder")
	folder.Name = opts.Name
	local points = GenerateCirclePoints(cframe, radius, math.max(opts.Segments, 3))
	for i = 1, #points do
		local nextPoint = if i < #points then points[i + 1] else points[1]
		CreateEdge(points[i], nextPoint, opts.Thickness, color, opts.Transparency, folder)
	end
	folder.Parent = GetOrCreateDebugFolder()
	ApplyDuration(folder, opts.Duration)
	return folder
end

function DebugHelper.GridPlane(origin: CFrame, options: (Options & Partial<GridOptions>)?): Folder?
	if not _enabled then
		return nil
	end
	local opts = ReconcileOptions(options, DEFAULT_GRID) :: Options & GridOptions
	local color = ResolveColor(opts.Color)
	local folder = Instance.new("Folder")
	folder.Name = opts.Name
	local cellSize = opts.CellSize
	local countX = opts.CellCountX
	local countZ = opts.CellCountZ
	local halfX = (countX * cellSize) / 2
	local halfZ = (countZ * cellSize) / 2
	for i = 0, countX do
		local x = -halfX + i * cellSize
		CreateEdge(
			origin * Vector3.new(x, 0, -halfZ),
			origin * Vector3.new(x, 0, halfZ),
			opts.Thickness,
			color,
			opts.Transparency,
			folder
		)
	end
	for i = 0, countZ do
		local z = -halfZ + i * cellSize
		CreateEdge(
			origin * Vector3.new(-halfX, 0, z),
			origin * Vector3.new(halfX, 0, z),
			opts.Thickness,
			color,
			opts.Transparency,
			folder
		)
	end
	folder.Parent = GetOrCreateDebugFolder()
	ApplyDuration(folder, opts.Duration)
	return folder
end

function DebugHelper.Cone(origin: Vector3, direction: Vector3, options: (Options & Partial<ConeOptions>)?): Folder?
	if not _enabled or direction.Magnitude < EPSILON then
		return nil
	end
	local opts = ReconcileOptions(options, DEFAULT_CONE) :: Options & ConeOptions
	local color = ResolveColor(opts.Color)
	local folder = Instance.new("Folder")
	folder.Name = opts.Name
	local dirUnit = direction.Unit
	local baseCenter = origin + dirUnit * opts.Length
	local baseRadius = opts.Length * math.tan(math.rad(opts.AngleDegrees))
	local baseCFrame = SafeLookAt(baseCenter, baseCenter + dirUnit) * CFrame.Angles(HALF_PI, 0, 0)
	local basePoints = GenerateCirclePoints(baseCFrame, baseRadius, math.max(opts.Segments, 3))
	for i = 1, #basePoints do
		local nextPoint = if i < #basePoints then basePoints[i + 1] else basePoints[1]
		CreateEdge(basePoints[i], nextPoint, 0.05, color, opts.Transparency, folder)
		CreateEdge(origin, basePoints[i], 0.05, color, opts.Transparency, folder)
	end
	folder.Parent = GetOrCreateDebugFolder()
	ApplyDuration(folder, opts.Duration)
	return folder
end

--- Frustum / Camera ---

function DebugHelper.Frustum(origin: CFrame, options: (Options & Partial<FrustumOptions>)?): Folder?
	if not _enabled then
		return nil
	end
	local opts = ReconcileOptions(options, DEFAULT_FRUSTUM) :: Options & FrustumOptions
	local color = ResolveColor(opts.Color)
	local near = math.max(opts.Near, EPSILON)
	local far = math.max(opts.Far, near + EPSILON)
	local fovRad = math.rad(opts.FieldOfView) / 2
	local aspect = opts.AspectRatio
	local nearH = near * math.tan(fovRad)
	local nearW = nearH * aspect
	local farH = far * math.tan(fovRad)
	local farW = farH * aspect
	local nTL = origin * Vector3.new(-nearW, nearH, -near)
	local nTR = origin * Vector3.new(nearW, nearH, -near)
	local nBL = origin * Vector3.new(-nearW, -nearH, -near)
	local nBR = origin * Vector3.new(nearW, -nearH, -near)
	local fTL = origin * Vector3.new(-farW, farH, -far)
	local fTR = origin * Vector3.new(farW, farH, -far)
	local fBL = origin * Vector3.new(-farW, -farH, -far)
	local fBR = origin * Vector3.new(farW, -farH, -far)
	local folder = Instance.new("Folder")
	folder.Name = opts.Name
	local t = opts.Thickness
	CreateEdge(nTL, nTR, t, color, opts.Transparency, folder)
	CreateEdge(nTR, nBR, t, color, opts.Transparency, folder)
	CreateEdge(nBR, nBL, t, color, opts.Transparency, folder)
	CreateEdge(nBL, nTL, t, color, opts.Transparency, folder)
	CreateEdge(fTL, fTR, t, color, opts.Transparency, folder)
	CreateEdge(fTR, fBR, t, color, opts.Transparency, folder)
	CreateEdge(fBR, fBL, t, color, opts.Transparency, folder)
	CreateEdge(fBL, fTL, t, color, opts.Transparency, folder)
	CreateEdge(nTL, fTL, t, color, opts.Transparency, folder)
	CreateEdge(nTR, fTR, t, color, opts.Transparency, folder)
	CreateEdge(nBL, fBL, t, color, opts.Transparency, folder)
	CreateEdge(nBR, fBR, t, color, opts.Transparency, folder)
	folder.Parent = GetOrCreateDebugFolder()
	ApplyDuration(folder, opts.Duration)
	return folder
end

function DebugHelper.CameraFrustum(camera: Camera, options: (Options & Partial<FrustumOptions>)?): Folder?
	local viewport = camera.ViewportSize
	local cameraDefaults: any = {
		Near = math.abs(camera.NearPlaneZ),
		Far = 500,
		FieldOfView = camera.FieldOfView,
		AspectRatio = viewport.X / math.max(viewport.Y, 1),
	}
	if options then
		for key, value in options :: any do
			cameraDefaults[key] = value
		end
	end
	return DebugHelper.Frustum(camera.CFrame, cameraDefaults)
end

--- Text / Labels ---

function DebugHelper.Text(position: Vector3, text: string, options: (Options & Partial<TextOptions>)?): Part?
	if not _enabled then
		return nil
	end
	local opts = ReconcileOptions(options, DEFAULT_TEXT) :: Options & TextOptions
	if text == "" then
		text = "<empty>"
	end

	if opts.Reuse and (opts.Reuse :: Instance):IsA("BasePart") then
		local part = opts.Reuse :: Part
		part.CFrame = CFrame.new(position)
		local billboard = part:FindFirstChildOfClass("BillboardGui") :: BillboardGui?
		if billboard then
			billboard.AlwaysOnTop = opts.AlwaysOnTop
			billboard.MaxDistance = opts.MaxDistance
			local label = billboard:FindFirstChildOfClass("TextLabel") :: TextLabel?
			if label then
				label.TextColor3 = opts.Color
				label.TextSize = opts.TextSize
				label.Text = text
				label.TextStrokeTransparency = opts.TextStrokeTransparency
				label.TextStrokeColor3 = opts.TextStrokeColor
			end
		end
		return part
	end

	local part = MakeDebugPart()
	part.Transparency = 1
	part.Size = Vector3.new(0.1, 0.1, 0.1)
	part.CFrame = CFrame.new(position)
	part.Name = opts.Name
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(0, 200, 0, 50)
	billboard.AlwaysOnTop = opts.AlwaysOnTop
	billboard.MaxDistance = opts.MaxDistance
	billboard.Parent = part
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.TextColor3 = opts.Color
	label.TextSize = opts.TextSize
	label.Font = Enum.Font.GothamBold
	label.Text = text
	label.TextStrokeTransparency = opts.TextStrokeTransparency
	label.TextStrokeColor3 = opts.TextStrokeColor
	label.Parent = billboard
	part.Parent = GetOrCreateDebugFolder()
	ApplyDuration(part, opts.Duration)
	return part
end

function DebugHelper.LabeledPoint(
	position: Vector3,
	label: string,
	options: (Options & Partial<PointOptions>)?
): Folder?
	if not _enabled then
		return nil
	end
	local opts = ReconcileOptions(options, DEFAULT_POINT) :: Options & PointOptions
	local color = ResolveColor(opts.Color)
	local diameter = opts.Size
	local labelPos = position + Vector3.new(0, diameter + 0.5, 0)

	if opts.Reuse and (opts.Reuse :: Instance):IsA("Folder") then
		local folder = opts.Reuse :: Folder
		local marker = folder:FindFirstChild("Marker") :: BasePart?
		if marker then
			marker.CFrame = CFrame.new(position)
			marker.Color = color
			marker.Transparency = opts.Transparency
			SetMeshScale(marker, Vector3.new(diameter, diameter, diameter))
		end
		local labelPart = folder:FindFirstChild("Label") :: BasePart?
		if labelPart then
			labelPart.CFrame = CFrame.new(labelPos)
			local billboard = labelPart:FindFirstChildOfClass("BillboardGui")
			if billboard then
				local textLabel = billboard:FindFirstChildOfClass("TextLabel")
				if textLabel then
					textLabel.TextColor3 = color
					textLabel.Text = label
				end
			end
		end
		return folder
	end

	local folder = Instance.new("Folder")
	folder.Name = opts.Name
	local marker = CreateMarker(position, diameter, color, opts.Transparency, folder)
	marker.Name = "Marker"
	local labelPart = CreateBillboardLabel(labelPos, label, color, 14, folder)
	labelPart.Name = "Label"
	folder.Parent = GetOrCreateDebugFolder()
	ApplyDuration(folder, opts.Duration)
	return folder
end

function DebugHelper.DistanceLine(
	startPos: Vector3,
	endPos: Vector3,
	options: (Options & Partial<LineOptions>)?
): Folder?
	if not _enabled then
		return nil
	end
	local opts = ReconcileOptions(options, DEFAULT_LINE) :: Options & LineOptions
	local color = ResolveColor(opts.Color)
	local distance = (endPos - startPos).Magnitude
	local folder = Instance.new("Folder")
	folder.Name = opts.Name
	CreateLineParts(
		startPos,
		endPos,
		opts.Thickness,
		color,
		opts.Transparency,
		opts.ShowDirection,
		opts.ArrowSize,
		folder
	)
	CreateBillboardLabel(
		(startPos + endPos) / 2 + Vector3.new(0, 1, 0),
		string.format("%.2f", distance),
		color,
		14,
		folder
	)
	folder.Parent = GetOrCreateDebugFolder()
	ApplyDuration(folder, opts.Duration)
	return folder
end

--- Collections ---

function DebugHelper.PointCloud(points: { Vector3 }, options: (Options & Partial<PointOptions>)?): Folder?
	if not _enabled or #points == 0 then
		return nil
	end
	local opts = ReconcileOptions(options, DEFAULT_POINT) :: Options & PointOptions
	local color = ResolveColor(opts.Color)
	local count = math.min(#points, 1000)
	local folder = Instance.new("Folder")
	folder.Name = opts.Name
	for i = 1, count do
		CreateMarker(points[i], opts.Size, color, opts.Transparency, folder)
	end
	folder.Parent = GetOrCreateDebugFolder()
	ApplyDuration(folder, opts.Duration)
	return folder
end

function DebugHelper.Path(points: { Vector3 }, options: (Options & Partial<PathOptions>)?): Folder?
	if not _enabled or #points == 0 then
		return nil
	end
	local opts = ReconcileOptions(options, DEFAULT_PATH) :: Options & PathOptions
	local color = ResolveColor(opts.Color)
	local folder = Instance.new("Folder")
	folder.Name = opts.Name
	local nPoints = #points
	for i = 1, nPoints do
		if opts.ShowPoints then
			local isFirst = i == 1
			local isLast = i == nPoints
			local markerColor = if isFirst then opts.StartColor elseif isLast then opts.EndColor else color
			local markerSize = if isFirst or isLast then opts.PointSize * 1.5 else opts.PointSize
			CreateMarker(points[i], markerSize, markerColor, opts.Transparency, folder)
		end
		if i < nPoints then
			CreateLineParts(
				points[i],
				points[i + 1],
				opts.Thickness,
				color,
				opts.Transparency,
				opts.ShowDirection,
				opts.Thickness * 3,
				folder
			)
		end
	end
	folder.Parent = GetOrCreateDebugFolder()
	ApplyDuration(folder, opts.Duration)
	return folder
end

function DebugHelper.PathfindingPath(path: Path, options: (Options & Partial<PathOptions>)?): Folder?
	if not _enabled then
		return nil
	end
	local waypoints = path:GetWaypoints()
	if #waypoints == 0 then
		return nil
	end
	local points = table.create(#waypoints)
	for i, waypoint in waypoints do
		points[i] = waypoint.Position
	end
	return DebugHelper.Path(points, options)
end

--- Attachments ---

function DebugHelper.Attachment(attachment: Attachment, options: (Options & Partial<CFrameOptions>)?): Folder?
	return DebugHelper.CFrame(attachment.WorldCFrame, options)
end

function DebugHelper.Attachments(part: BasePart, options: (Options & Partial<CFrameOptions>)?): Folder?
	if not _enabled then
		return nil
	end
	local opts = ReconcileOptions(options, DEFAULT_CFRAME) :: Options & CFrameOptions
	local folder = Instance.new("Folder")
	folder.Name = opts.Name
	local count = 0
	for _, child in part:GetChildren() do
		if child:IsA("Attachment") then
			local vis = DebugHelper.CFrame(
				child.WorldCFrame,
				{
					Size = opts.Size,
					Thickness = opts.Thickness,
					Name = child.Name,
				} :: any
			)
			if vis then
				vis.Parent = folder
				count += 1
			end
		end
	end
	if count == 0 then
		folder:Destroy()
		return nil
	end
	folder.Parent = GetOrCreateDebugFolder()
	ApplyDuration(folder, opts.Duration)
	return folder
end

--- Highlight ---

function DebugHelper.Highlight(target: Instance, options: (Options & Partial<HighlightOptions>)?): Highlight?
	if not _enabled then
		return nil
	end
	local opts = ReconcileOptions(options, DEFAULT_HIGHLIGHT) :: Options & HighlightOptions

	local highlight: Highlight
	local isNew: boolean

	if opts.Reuse and (opts.Reuse :: Instance):IsA("Highlight") then
		highlight = opts.Reuse :: Highlight
		isNew = false
	else
		highlight = Instance.new("Highlight")
		isNew = true
	end

	highlight.Adornee = target
	highlight.FillColor = opts.FillColor
	highlight.OutlineColor = opts.OutlineColor
	highlight.FillTransparency = opts.FillTransparency
	highlight.OutlineTransparency = opts.OutlineTransparency

	if isNew then
		highlight.Name = opts.Name
		highlight.Parent = GetOrCreateDebugFolder()
		ApplyDuration(highlight, opts.Duration)
	end
	return highlight
end

--- Physics ---

function DebugHelper.Velocity(part: BasePart, options: (Options & Partial<VectorOptions>)?): Folder?
	if not _enabled then
		return nil
	end
	return DebugHelper.Vector(part.Position, part.AssemblyLinearVelocity, options)
end

function DebugHelper.AngularVelocity(part: BasePart, options: (Options & Partial<VectorOptions>)?): Folder?
	if not _enabled then
		return nil
	end
	return DebugHelper.Vector(part.Position, part.AssemblyAngularVelocity, options)
end

--- Spatial Queries ---

function DebugHelper.RaycastResult(
	origin: Vector3,
	direction: Vector3,
	result: RaycastResult?,
	options: (Options & Partial<RaycastVisualOptions>)?
): Folder?
	if not _enabled then
		return nil
	end
	local opts = ReconcileOptions(options, DEFAULT_RAYCAST_VISUAL) :: Options & RaycastVisualOptions
	local folder = Instance.new("Folder")
	folder.Name = opts.Name
	if result then
		CreateLineParts(origin, result.Position, opts.Thickness, opts.HitColor, 0, true, opts.Thickness * 3, folder)
		CreateMarker(result.Position, opts.Thickness * 4, opts.HitColor, 0, folder)
		if opts.ShowNormal then
			CreateLineParts(
				result.Position,
				result.Position + result.Normal * 2,
				opts.Thickness * 0.5,
				opts.NormalColor,
				0,
				true,
				0.2,
				folder
			)
		end
	else
		CreateLineParts(origin, origin + direction, opts.Thickness, opts.MissColor, 0, true, opts.Thickness * 3, folder)
	end
	folder.Parent = GetOrCreateDebugFolder()
	ApplyDuration(folder, opts.Duration)
	return folder
end

function DebugHelper.Raycast(
	origin: Vector3,
	direction: Vector3,
	raycastParams: RaycastParams?,
	options: (Options & Partial<RaycastVisualOptions>)?
): RaycastResult?
	local result = Workspace:Raycast(origin, direction, raycastParams)
	if _enabled then
		DebugHelper.RaycastResult(origin, direction, result, options)
	end
	return result
end

function DebugHelper.Spherecast(
	position: Vector3,
	radius: number,
	direction: Vector3,
	raycastParams: RaycastParams?,
	options: (Options & Partial<RaycastVisualOptions>)?
): RaycastResult?
	radius = math.max(radius, 0)
	if radius < EPSILON then
		return DebugHelper.Raycast(position, direction, raycastParams, options)
	end
	local result = Workspace:Spherecast(position, radius, direction, raycastParams)
	if _enabled then
		local opts = ReconcileOptions(options, DEFAULT_RAYCAST_VISUAL) :: Options & RaycastVisualOptions
		local diameter = radius * 2
		local folder = Instance.new("Folder")
		folder.Name = opts.Name
		local startSphere = MakeSpherePart()
		startSphere.CFrame = CFrame.new(position)
		startSphere.Color = Color3.fromRGB(100, 100, 100)
		startSphere.Transparency = 0.7
		SetMeshScale(startSphere, Vector3.new(diameter, diameter, diameter))
		startSphere.Name = "Start"
		startSphere.Parent = folder
		if result then
			local endSphere = MakeSpherePart()
			endSphere.CFrame = CFrame.new(result.Position)
			endSphere.Color = opts.HitColor
			endSphere.Transparency = 0.5
			SetMeshScale(endSphere, Vector3.new(diameter, diameter, diameter))
			endSphere.Name = "End"
			endSphere.Parent = folder
			CreateLineParts(position, result.Position, opts.Thickness, opts.HitColor, 0, true, 0.3, folder)
		else
			local endPos = position + direction
			local endSphere = MakeSpherePart()
			endSphere.CFrame = CFrame.new(endPos)
			endSphere.Color = opts.MissColor
			endSphere.Transparency = 0.7
			SetMeshScale(endSphere, Vector3.new(diameter, diameter, diameter))
			endSphere.Name = "End"
			endSphere.Parent = folder
			CreateLineParts(position, endPos, opts.Thickness, opts.MissColor, 0, true, 0.3, folder)
		end
		folder.Parent = GetOrCreateDebugFolder()
		ApplyDuration(folder, opts.Duration)
	end
	return result
end

function DebugHelper.Blockcast(
	cframe: CFrame,
	size: Vector3,
	direction: Vector3,
	raycastParams: RaycastParams?,
	options: (Options & Partial<RaycastVisualOptions>)?
): RaycastResult?
	local result = Workspace:Blockcast(cframe, size, direction, raycastParams)
	if _enabled then
		local opts = ReconcileOptions(options, DEFAULT_RAYCAST_VISUAL) :: Options & RaycastVisualOptions
		local folder = Instance.new("Folder")
		folder.Name = opts.Name
		local startBox = MakeBlockPart()
		startBox.CFrame = cframe
		startBox.Color = Color3.fromRGB(100, 100, 100)
		startBox.Transparency = 0.7
		SetMeshScale(startBox, size)
		startBox.Name = "Start"
		startBox.Parent = folder
		if result then
			local endCFrame = CFrame.new(result.Position) * cframe.Rotation
			local endBox = MakeBlockPart()
			endBox.CFrame = endCFrame
			endBox.Color = opts.HitColor
			endBox.Transparency = 0.5
			SetMeshScale(endBox, size)
			endBox.Name = "End"
			endBox.Parent = folder
			CreateLineParts(cframe.Position, result.Position, opts.Thickness, opts.HitColor, 0, true, 0.3, folder)
		else
			local endPos = cframe.Position + direction
			local endBox = MakeBlockPart()
			endBox.CFrame = CFrame.new(endPos) * cframe.Rotation
			endBox.Color = opts.MissColor
			endBox.Transparency = 0.7
			SetMeshScale(endBox, size)
			endBox.Name = "End"
			endBox.Parent = folder
			CreateLineParts(cframe.Position, endPos, opts.Thickness, opts.MissColor, 0, true, 0.3, folder)
		end
		folder.Parent = GetOrCreateDebugFolder()
		ApplyDuration(folder, opts.Duration)
	end
	return result
end

function DebugHelper.GetPartBoundsInBox(
	cframe: CFrame,
	size: Vector3,
	overlapParams: OverlapParams?,
	options: (Options & Partial<SpatialQueryOptions>)?
): { BasePart }
	local parts = Workspace:GetPartBoundsInBox(cframe, size, overlapParams)
	if _enabled then
		local opts = ReconcileOptions(options, DEFAULT_SPATIAL_QUERY) :: Options & SpatialQueryOptions
		local color = ResolveColor(opts.Color)
		local folder = Instance.new("Folder")
		folder.Name = opts.Name
		local queryBox = CreateWireframeBox(cframe, size, color, 0.08, opts.Transparency)
		queryBox.Name = "QueryArea"
		queryBox.Parent = folder
		for i, hitPart in parts do
			local hitBox = MakeBlockPart()
			hitBox.CFrame = hitPart.CFrame
			hitBox.Color = opts.HitColor
			hitBox.Transparency = 0.5
			SetMeshScale(hitBox, hitPart.Size)
			hitBox.Name = `Hit_{i}_{hitPart.Name}`
			hitBox.Parent = folder
			if opts.ShowLabels then
				CreateBillboardLabel(
					hitPart.Position + Vector3.new(0, hitPart.Size.Y / 2 + 1, 0),
					hitPart.Name,
					opts.HitColor,
					12,
					folder
				)
			end
		end
		folder.Parent = GetOrCreateDebugFolder()
		ApplyDuration(folder, opts.Duration)
	end
	return parts
end

function DebugHelper.GetPartBoundsInRadius(
	position: Vector3,
	radius: number,
	overlapParams: OverlapParams?,
	options: (Options & Partial<SpatialQueryOptions>)?
): { BasePart }
	radius = math.max(radius, 0)
	if radius < EPSILON then
		return {}
	end
	local parts = Workspace:GetPartBoundsInRadius(position, radius, overlapParams)
	if _enabled then
		local opts = ReconcileOptions(options, DEFAULT_SPATIAL_QUERY) :: Options & SpatialQueryOptions
		local color = ResolveColor(opts.Color)
		local diameter = radius * 2
		local folder = Instance.new("Folder")
		folder.Name = opts.Name
		local querySphere = MakeSpherePart()
		querySphere.CFrame = CFrame.new(position)
		querySphere.Color = color
		querySphere.Transparency = opts.Transparency
		SetMeshScale(querySphere, Vector3.new(diameter, diameter, diameter))
		querySphere.Name = "QueryArea"
		querySphere.Parent = folder
		for i, hitPart in parts do
			local hitBox = MakeBlockPart()
			hitBox.CFrame = hitPart.CFrame
			hitBox.Color = opts.HitColor
			hitBox.Transparency = 0.5
			SetMeshScale(hitBox, hitPart.Size)
			hitBox.Name = `Hit_{i}_{hitPart.Name}`
			hitBox.Parent = folder
			if opts.ShowLabels then
				CreateBillboardLabel(
					hitPart.Position + Vector3.new(0, hitPart.Size.Y / 2 + 1, 0),
					hitPart.Name,
					opts.HitColor,
					12,
					folder
				)
			end
		end
		folder.Parent = GetOrCreateDebugFolder()
		ApplyDuration(folder, opts.Duration)
	end
	return parts
end

function DebugHelper.GetPartsInPart(
	hitPart: BasePart,
	overlapParams: OverlapParams?,
	options: (Options & Partial<SpatialQueryOptions>)?
): { BasePart }
	local parts = Workspace:GetPartsInPart(hitPart, overlapParams)
	if _enabled then
		local opts = ReconcileOptions(options, DEFAULT_SPATIAL_QUERY) :: Options & SpatialQueryOptions
		local color = ResolveColor(opts.Color)
		local folder = Instance.new("Folder")
		folder.Name = opts.Name
		local queryBox = CreateWireframeBox(hitPart.CFrame, hitPart.Size, color, 0.08, opts.Transparency)
		queryBox.Name = "QueryPart"
		queryBox.Parent = folder
		for i, foundPart in parts do
			local box = MakeBlockPart()
			box.CFrame = foundPart.CFrame
			box.Color = opts.HitColor
			box.Transparency = 0.5
			SetMeshScale(box, foundPart.Size)
			box.Name = `Hit_{i}_{foundPart.Name}`
			box.Parent = folder
		end
		folder.Parent = GetOrCreateDebugFolder()
		ApplyDuration(folder, opts.Duration)
	end
	return parts
end

--- Line of Sight ---

function DebugHelper.LineOfSight(
	origin: Vector3,
	targets: { Vector3 },
	raycastParams: RaycastParams?,
	options: (Options & Partial<RaycastVisualOptions>)?
): Folder?
	if not _enabled or #targets == 0 then
		return nil
	end
	local opts = ReconcileOptions(options, DEFAULT_RAYCAST_VISUAL) :: Options & RaycastVisualOptions
	local folder = Instance.new("Folder")
	folder.Name = opts.Name
	for _, target in targets do
		local direction = target - origin
		if direction.Magnitude < EPSILON then
			continue
		end
		local result = Workspace:Raycast(origin, direction, raycastParams)
		if result then
			CreateLineParts(origin, result.Position, opts.Thickness, opts.MissColor, 0.3, false, 0, folder)
			CreateMarker(result.Position, opts.Thickness * 4, opts.MissColor, 0, folder)
		else
			CreateLineParts(origin, target, opts.Thickness, opts.HitColor, 0, true, opts.Thickness * 3, folder)
		end
	end
	folder.Parent = GetOrCreateDebugFolder()
	ApplyDuration(folder, opts.Duration)
	return folder
end

--- Blink ---

function DebugHelper.Blink(target: BasePart | Model, options: (Options & Partial<BlinkOptions>)?): () -> ()
	local opts = ReconcileOptions(options, DEFAULT_BLINK) :: Options & BlinkOptions
	if not _enabled then
		return function() end
	end
	local partsData: { { part: BasePart, originalColor: Color3 } } = {}
	if target:IsA("BasePart") then
		table.insert(partsData, { part = target, originalColor = target.Color })
	elseif target:IsA("Model") then
		for _, descendant in target:GetDescendants() do
			if descendant:IsA("BasePart") then
				table.insert(partsData, { part = descendant, originalColor = descendant.Color })
			end
		end
	end
	if #partsData == 0 then
		return function() end
	end
	local colors = opts.Colors
	if #colors == 0 then
		colors = { Color3.fromRGB(255, 0, 0) }
	end
	local totalBlinks: number
	if opts.Duration > 0 then
		totalBlinks = math.floor(opts.Duration / opts.Interval)
	else
		totalBlinks = opts.Cycles * #colors
	end
	local stopped = false
	local function stop()
		stopped = true
		if opts.RestoreOriginal then
			for _, data in partsData do
				if data.part and data.part.Parent then
					data.part.Color = data.originalColor
				end
			end
		end
	end
	task.spawn(function()
		local blinkCount = 0
		local colorIndex = 1
		while not stopped and blinkCount < totalBlinks do
			local c = colors[colorIndex]
			for _, data in partsData do
				if data.part and data.part.Parent then
					data.part.Color = c
				end
			end
			colorIndex = (colorIndex % #colors) + 1
			blinkCount += 1
			task.wait(math.max(opts.Interval, 0.03))
		end
		if not stopped and opts.RestoreOriginal then
			for _, data in partsData do
				if data.part and data.part.Parent then
					data.part.Color = data.originalColor
				end
			end
		end
	end)
	return stop
end

--- Terrain ---

function DebugHelper.TerrainRegion(
	region: Region3,
	options: (Options & Partial<TerrainRegionOptions>)?
): TerrainRegionResult?
	if not _enabled then
		return nil
	end
	local opts = ReconcileOptions(options, DEFAULT_TERRAIN_REGION) :: Options & TerrainRegionOptions
	local voxelSize = 4
	local visualScale = math.clamp(opts.VisualScale, 0.1, 1)
	local folder = Instance.new("Folder")
	folder.Name = opts.Name
	folder.Parent = GetOrCreateDebugFolder()
	local expandedRegion = region:ExpandToGrid(voxelSize)
	local materials, occupancies = Workspace.Terrain:ReadVoxels(expandedRegion, voxelSize)
	local gridSize = (occupancies :: any).Size
	local regionMin = expandedRegion.CFrame.Position - (expandedRegion.Size / 2)
	local skipMinX = math.max(0, math.floor(opts.SkipMinX))
	local skipMaxX = math.max(0, math.floor(opts.SkipMaxX))
	local skipMinY = math.max(0, math.floor(opts.SkipMinY))
	local skipMaxY = math.max(0, math.floor(opts.SkipMaxY))
	local skipMinZ = math.max(0, math.floor(opts.SkipMinZ))
	local skipMaxZ = math.max(0, math.floor(opts.SkipMaxZ))
	local hasSkipping = skipMinX > 0 or skipMaxX > 0 or skipMinY > 0 or skipMaxY > 0 or skipMinZ > 0 or skipMaxZ > 0
	local startX = math.clamp(1 + skipMinX, 1, gridSize.X)
	local endX = math.clamp(gridSize.X - skipMaxX, 1, gridSize.X)
	local startY = math.clamp(1 + skipMinY, 1, gridSize.Y)
	local endY = math.clamp(gridSize.Y - skipMaxY, 1, gridSize.Y)
	local startZ = math.clamp(1 + skipMinZ, 1, gridSize.Z)
	local endZ = math.clamp(gridSize.Z - skipMaxZ, 1, gridSize.Z)
	local hasValidRange = endX >= startX and endY >= startY and endZ >= startZ
	local readSizeX = if hasValidRange then endX - startX + 1 else 0
	local readSizeY = if hasValidRange then endY - startY + 1 else 0
	local readSizeZ = if hasValidRange then endZ - startZ + 1 else 0
	local totalReadVoxels = readSizeX * readSizeY * readSizeZ

	local function BuildResult(
		occupied: number,
		empty: number,
		skipped: number,
		truncated: boolean
	): TerrainRegionResult
		return {
			Folder = folder,
			GridSize = Vector3.new(gridSize.X, gridSize.Y, gridSize.Z),
			ReadSize = Vector3.new(readSizeX, readSizeY, readSizeZ),
			TotalVoxels = totalReadVoxels,
			OccupiedCount = occupied,
			EmptyCount = empty,
			SkippedCount = skipped,
			WasTruncated = truncated,
		}
	end

	if opts.ShowBounds then
		local boundsWire = CreateWireframeBox(expandedRegion.CFrame, expandedRegion.Size, opts.BoundsColor, 0.05, 0.9)
		boundsWire.Name = "FullBounds"
		boundsWire.Parent = folder
	end

	if opts.ShowLabel then
		local labelPos = expandedRegion.CFrame.Position + Vector3.new(0, expandedRegion.Size.Y / 2 + 1, 0)
		local truncText = if totalReadVoxels > opts.MaxVoxels then ` (truncated to {opts.MaxVoxels})` else ""
		local labelText =
			`Grid: {gridSize.X}x{gridSize.Y}x{gridSize.Z} | Read: {readSizeX}x{readSizeY}x{readSizeZ}{truncText}`
		CreateBillboardLabel(labelPos, labelText, opts.BoundsColor, 14, folder)
	end

	if not hasValidRange then
		ApplyDuration(folder, opts.Duration)
		return BuildResult(0, 0, 0, false)
	end

	if opts.ShowBounds and hasSkipping then
		local readMin = regionMin
			+ Vector3.new((startX - 1) * voxelSize, (startY - 1) * voxelSize, (startZ - 1) * voxelSize)
		local readMax = regionMin + Vector3.new(endX * voxelSize, endY * voxelSize, endZ * voxelSize)
		local readCenter = (readMin + readMax) / 2
		local readBoxSize = readMax - readMin
		local readWire = CreateWireframeBox(CFrame.new(readCenter), readBoxSize, opts.ReadBoundsColor, 0.08, 0.85)
		readWire.Name = "ReadBounds"
		readWire.Parent = folder
	end

	local visualBoxSize = voxelSize * visualScale
	local visualSizeVec = Vector3.new(visualBoxSize, visualBoxSize, visualBoxSize)
	local voxelCount = 0
	local occupiedCount = 0
	local emptyCount = 0
	local skippedCount = 0
	local reachedLimit = false

	local function CreateVoxel(x: number, y: number, z: number, voxelColor: Color3, voxelTransparency: number): boolean
		if voxelCount >= opts.MaxVoxels then
			reachedLimit = true
			return false
		end
		local voxelCenter = regionMin + Vector3.new((x - 0.5) * voxelSize, (y - 0.5) * voxelSize, (z - 0.5) * voxelSize)
		local voxelPart = MakeBlockPart()
		voxelPart.CFrame = CFrame.new(voxelCenter)
		voxelPart.Color = voxelColor
		voxelPart.Transparency = math.clamp(voxelTransparency, 0, 1)
		SetMeshScale(voxelPart, visualSizeVec)
		voxelPart.Parent = folder
		voxelCount += 1
		return true
	end

	for x = startX, endX do
		if reachedLimit then
			break
		end
		for y = startY, endY do
			if reachedLimit then
				break
			end
			for z = startZ, endZ do
				local occupancy = occupancies[x][y][z]
				local material = materials[x][y][z]
				local isOccupied = occupancy > 0
				if opts.FilterMaterial and isOccupied and material ~= opts.FilterMaterial then
					continue
				end
				if isOccupied then
					occupiedCount += 1
				else
					emptyCount += 1
				end
				if (isOccupied and opts.ShowOccupied) or (not isOccupied and opts.ShowEmpty) then
					local voxelColor: Color3
					if opts.ShowMaterials and isOccupied then
						voxelColor = MATERIAL_COLORS[material] or opts.OccupiedColor
					else
						voxelColor = if isOccupied then opts.OccupiedColor else opts.Color
					end
					local voxelTransparency: number
					if opts.OccupancyAsOpacity and isOccupied then
						voxelTransparency = 0.9 - (occupancy * 0.6)
					else
						voxelTransparency = if isOccupied then opts.OccupiedTransparency else opts.Transparency
					end
					if not CreateVoxel(x, y, z, voxelColor, voxelTransparency) then
						break
					end
				end
			end
		end
	end

	if opts.ShowSkipped and hasSkipping and not reachedLimit then
		for x = 1, gridSize.X do
			if reachedLimit then
				break
			end
			for y = 1, gridSize.Y do
				if reachedLimit then
					break
				end
				for z = 1, gridSize.Z do
					local isSkipped = x < startX or x > endX or y < startY or y > endY or z < startZ or z > endZ
					if isSkipped then
						skippedCount += 1
						if not CreateVoxel(x, y, z, opts.SkippedColor, 0.9) then
							break
						end
					end
				end
			end
		end
	end

	ApplyDuration(folder, opts.Duration)
	return BuildResult(occupiedCount, emptyCount, skippedCount, reachedLimit)
end

--- Sound / Light ---

function DebugHelper.SoundRadius(sound: Sound, options: (Options & Partial<SoundRadiusOptions>)?): Folder?
	if not _enabled then
		return nil
	end
	local parent = sound.Parent
	local position: Vector3
	if parent and parent:IsA("BasePart") then
		position = parent.Position
	elseif parent and parent:IsA("Attachment") then
		position = parent.WorldPosition
	else
		return nil
	end
	local opts = ReconcileOptions(options, DEFAULT_SOUND_RADIUS) :: Options & SoundRadiusOptions
	local color = ResolveColor(opts.Color)
	local folder = Instance.new("Folder")
	folder.Name = opts.Name
	local minDist = sound.RollOffMinDistance
	if minDist > EPSILON then
		local innerDiameter = minDist * 2
		local innerSphere = MakeSpherePart()
		innerSphere.CFrame = CFrame.new(position)
		innerSphere.Color = opts.InnerColor
		innerSphere.Transparency = math.min(opts.Transparency + 0.1, 1)
		SetMeshScale(innerSphere, Vector3.new(innerDiameter, innerDiameter, innerDiameter))
		innerSphere.Name = "InnerRadius"
		innerSphere.Parent = folder
	end
	local maxDist = sound.RollOffMaxDistance
	if maxDist > EPSILON then
		local outerDiameter = maxDist * 2
		local outerSphere = MakeSpherePart()
		outerSphere.CFrame = CFrame.new(position)
		outerSphere.Color = color
		outerSphere.Transparency = opts.Transparency
		SetMeshScale(outerSphere, Vector3.new(outerDiameter, outerDiameter, outerDiameter))
		outerSphere.Name = "OuterRadius"
		outerSphere.Parent = folder
	end
	folder.Parent = GetOrCreateDebugFolder()
	ApplyDuration(folder, opts.Duration)
	return folder
end

function DebugHelper.LightRadius(light: Light, options: (Options & Partial<LightRadiusOptions>)?): Folder?
	if not _enabled then
		return nil
	end
	local parent = light.Parent
	if not parent or not parent:IsA("BasePart") then
		return nil
	end
	local partParent = parent :: BasePart
	local position = partParent.Position
	local opts = ReconcileOptions(options, DEFAULT_LIGHT_RADIUS) :: Options & LightRadiusOptions
	local color = ResolveColor(opts.Color)
	local folder = Instance.new("Folder")
	folder.Name = opts.Name
	if light:IsA("PointLight") then
		local rangeDiameter = light.Range * 2
		local sphere = MakeSpherePart()
		sphere.CFrame = CFrame.new(position)
		sphere.Color = color
		sphere.Transparency = opts.Transparency
		SetMeshScale(sphere, Vector3.new(rangeDiameter, rangeDiameter, rangeDiameter))
		sphere.Name = "Range"
		sphere.Parent = folder
	elseif light:IsA("SpotLight") then
		local faceDir = Vector3.fromNormalId(light.Face)
		local worldDir = partParent.CFrame:VectorToWorldSpace(faceDir)
		local baseCenter = position + worldDir * light.Range
		local baseRadius = light.Range * math.tan(math.rad(light.Angle / 2))
		local baseCFrame = SafeLookAt(baseCenter, baseCenter + worldDir) * CFrame.Angles(HALF_PI, 0, 0)
		local basePoints = GenerateCirclePoints(baseCFrame, baseRadius, 12)
		for i = 1, #basePoints do
			local nextPoint = if i < #basePoints then basePoints[i + 1] else basePoints[1]
			CreateEdge(basePoints[i], nextPoint, 0.05, color, opts.Transparency, folder)
			CreateEdge(position, basePoints[i], 0.05, color, opts.Transparency, folder)
		end
	elseif light:IsA("SurfaceLight") then
		local faceDir = Vector3.fromNormalId(light.Face)
		local worldDir = partParent.CFrame:VectorToWorldSpace(faceDir)
		local endPos = position + worldDir * light.Range
		CreateLineParts(position, endPos, 0.1, color, opts.Transparency, true, 0.3, folder)
		local baseRadius = light.Range * math.tan(math.rad(light.Angle / 2))
		local baseCFrame = SafeLookAt(endPos, endPos + worldDir) * CFrame.Angles(HALF_PI, 0, 0)
		local basePoints = GenerateCirclePoints(baseCFrame, baseRadius, 8)
		for i = 1, #basePoints do
			local nextPoint = if i < #basePoints then basePoints[i + 1] else basePoints[1]
			CreateEdge(basePoints[i], nextPoint, 0.05, color, opts.Transparency, folder)
		end
	end
	folder.Parent = GetOrCreateDebugFolder()
	ApplyDuration(folder, opts.Duration)
	return folder
end

--- Projectile ---

function DebugHelper.ProjectileArc(
	startPosition: Vector3,
	initialVelocity: Vector3,
	options: (Options & Partial<ProjectileArcOptions>)?
): Folder?
	if not _enabled then
		return nil
	end
	local opts = ReconcileOptions(options, DEFAULT_PROJECTILE_ARC) :: Options & ProjectileArcOptions
	local gravity = opts.Gravity
	local dt = math.max(opts.TimeStep, 0.01)
	local maxTime = math.max(opts.MaxTime, dt)
	local points: { Vector3 } = { startPosition }
	local vel = initialVelocity
	local pos = startPosition
	local t = 0
	while t < maxTime do
		vel = vel + gravity * dt
		pos = pos + vel * dt
		t += dt
		table.insert(points, pos)
	end
	return DebugHelper.Path(
		points,
		{
			Color = opts.Color,
			Thickness = opts.Thickness,
			Transparency = opts.Transparency,
			Duration = opts.Duration,
			Name = opts.Name,
			ShowPoints = false,
			ShowDirection = true,
		} :: any
	)
end

--- Screen ---

function DebugHelper.ScreenText(text: string, options: (Options & Partial<ScreenTextOptions>)?): TextLabel?
	if not _enabled then
		return nil
	end
	local gui = GetOrCreateDebugScreenGui()
	if not gui then
		return nil
	end
	local opts = ReconcileOptions(options, DEFAULT_SCREEN_TEXT) :: Options & ScreenTextOptions
	local label: TextLabel
	if opts.Reuse and (opts.Reuse :: Instance):IsA("TextLabel") then
		label = opts.Reuse :: TextLabel
	else
		label = Instance.new("TextLabel")
		label.Font = Enum.Font.GothamBold
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextYAlignment = Enum.TextYAlignment.Center
		label.BorderSizePixel = 0
	end
	label.Position = opts.Position
	label.Size = opts.Size
	label.AnchorPoint = opts.AnchorPoint
	label.TextColor3 = opts.TextColor
	label.TextSize = opts.TextSize
	label.BackgroundTransparency = opts.BackgroundTransparency
	label.BackgroundColor3 = opts.BackgroundColor
	label.Text = text
	if label ~= opts.Reuse then
		label.Name = opts.Name
		label.Parent = gui
		ApplyDuration(label, opts.Duration)
	end
	return label
end

function DebugHelper.ScreenLine(from: Vector2, to: Vector2, options: (Options & Partial<ScreenLineOptions>)?): Frame?
	if not _enabled then
		return nil
	end
	local gui = GetOrCreateDebugScreenGui()
	if not gui then
		return nil
	end
	local delta = to - from
	local length = delta.Magnitude
	if length < 1 then
		return nil
	end
	local opts = ReconcileOptions(options, DEFAULT_SCREEN_LINE) :: Options & ScreenLineOptions
	local frame: Frame
	if opts.Reuse and (opts.Reuse :: Instance):IsA("Frame") then
		frame = opts.Reuse :: Frame
	else
		frame = Instance.new("Frame")
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.BorderSizePixel = 0
	end
	local mid = (from + to) / 2
	local angle = math.atan2(delta.Y, delta.X)
	frame.Position = UDim2.fromOffset(mid.X, mid.Y)
	frame.Size = UDim2.fromOffset(length, opts.Thickness)
	frame.Rotation = math.deg(angle)
	frame.BackgroundColor3 = opts.Color
	frame.BackgroundTransparency = opts.Transparency
	if frame ~= opts.Reuse then
		frame.Name = opts.Name
		frame.Parent = gui
		ApplyDuration(frame, opts.Duration)
	end
	return frame
end

function DebugHelper.ScreenRect(position: UDim2, size: UDim2, options: (Options & Partial<ScreenRectOptions>)?): Frame?
	if not _enabled then
		return nil
	end
	local gui = GetOrCreateDebugScreenGui()
	if not gui then
		return nil
	end
	local opts = ReconcileOptions(options, DEFAULT_SCREEN_RECT) :: Options & ScreenRectOptions
	local frame: Frame
	if opts.Reuse and (opts.Reuse :: Instance):IsA("Frame") then
		frame = opts.Reuse :: Frame
	else
		frame = Instance.new("Frame")
		frame.BorderSizePixel = 0
	end
	frame.Position = position
	frame.Size = size
	frame.BackgroundColor3 = opts.FillColor
	frame.BackgroundTransparency = opts.FillTransparency
	if frame ~= opts.Reuse then
		frame.Name = opts.Name
		frame.Parent = gui
		ApplyDuration(frame, opts.Duration)
	end
	return frame
end

function DebugHelper.ScreenCircle(
	center: UDim2,
	radiusPixels: number,
	options: (Options & Partial<ScreenCircleOptions>)?
): Frame?
	if not _enabled then
		return nil
	end
	local gui = GetOrCreateDebugScreenGui()
	if not gui then
		return nil
	end
	local opts = ReconcileOptions(options, DEFAULT_SCREEN_CIRCLE) :: Options & ScreenCircleOptions
	local diameter = radiusPixels * 2
	local frame: Frame
	if opts.Reuse and (opts.Reuse :: Instance):IsA("Frame") then
		frame = opts.Reuse :: Frame
	else
		frame = Instance.new("Frame")
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.BorderSizePixel = 0
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = frame
	end
	frame.Position = center
	frame.Size = UDim2.fromOffset(diameter, diameter)
	frame.BackgroundColor3 = opts.FillColor
	frame.BackgroundTransparency = opts.FillTransparency
	if frame ~= opts.Reuse then
		frame.Name = opts.Name
		frame.Parent = gui
		ApplyDuration(frame, opts.Duration)
	end
	return frame
end

--- Utility ---

function DebugHelper.DumpTable(tbl: { [any]: any }, indent: string?): string
	local function Recurse(t: { [any]: any }, pad: string, seen: { [any]: boolean }): string
		if seen[t] then
			return `{pad}<circular reference>`
		end
		seen[t] = true
		local lines: { string } = {}
		for key, value in pairs(t) do
			if type(value) == "table" then
				table.insert(lines, `{pad}{tostring(key)}: \{`)
				table.insert(lines, Recurse(value, pad .. "\t", seen))
				table.insert(lines, `{pad}\}`)
			else
				table.insert(lines, `{pad}{tostring(key)}: {tostring(value)}`)
			end
		end
		return table.concat(lines, "\n")
	end
	return Recurse(tbl, indent or "", {})
end

--- Color Schemes ---
do
	local COLOR_SCHEMES: { { Color3 } } = table.freeze({
		table.freeze({
			Color3.fromRGB(255, 0, 0), -- red
			Color3.fromRGB(255, 125, 0), -- orange
			Color3.fromRGB(255, 255, 50), -- yellow
			Color3.fromRGB(0, 255, 0), -- spring
			Color3.fromRGB(100, 175, 100), -- green
			Color3.fromRGB(0, 255, 255), -- cyan
			Color3.fromRGB(0, 0, 255), -- indigo
			Color3.fromRGB(100, 100, 255), -- blue
			Color3.fromRGB(200, 0, 255), -- purple
			Color3.fromRGB(255, 0, 150), -- magenta
		}),
		table.freeze({
			Color3.fromRGB(255, 155, 155), -- salmon
			Color3.fromRGB(255, 210, 160), -- peach
			Color3.fromRGB(250, 248, 155), -- butter
			Color3.fromRGB(175, 250, 175), -- mint
			Color3.fromRGB(155, 235, 240), -- aqua
			Color3.fromRGB(155, 190, 255), -- periwinkle
			Color3.fromRGB(195, 168, 255), -- lavender
			Color3.fromRGB(250, 175, 230), -- orchid
			Color3.fromRGB(255, 195, 215), -- rose
			Color3.fromRGB(220, 212, 180), -- linen
		}),
		table.freeze({
			Color3.fromRGB(150, 50, 50), -- brick
			Color3.fromRGB(185, 80, 20), -- terra cotta
			Color3.fromRGB(165, 115, 75), -- sienna
			Color3.fromRGB(200, 165, 60), -- amber
			Color3.fromRGB(215, 190, 130), -- sand
			Color3.fromRGB(120, 125, 20), -- olive
			Color3.fromRGB(80, 140, 55), -- moss
			Color3.fromRGB(55, 90, 55), -- forest
			Color3.fromRGB(140, 100, 55), -- tawny
			Color3.fromRGB(75, 45, 15), -- espresso
		}),
		table.freeze({
			Color3.fromRGB(5, 30, 140), -- abyss
			Color3.fromRGB(20, 70, 100), -- midnight
			Color3.fromRGB(20, 110, 80), -- deep sea
			Color3.fromRGB(70, 80, 200), -- cobalt
			Color3.fromRGB(80, 100, 160), -- slate
			Color3.fromRGB(40, 160, 170), -- teal
			Color3.fromRGB(100, 150, 110), -- seafoam
			Color3.fromRGB(40, 200, 200), -- lagoon
			Color3.fromRGB(140, 180, 230), -- sky
			Color3.fromRGB(160, 210, 240), -- ice
		}),
		table.freeze({
			Color3.fromRGB(240, 240, 240), -- near white
			Color3.fromRGB(215, 215, 215), -- silver
			Color3.fromRGB(190, 190, 190), -- light gray
			Color3.fromRGB(165, 165, 165), -- mid-light
			Color3.fromRGB(140, 140, 140), -- mid gray
			Color3.fromRGB(115, 115, 115), -- mid-dark
			Color3.fromRGB(90, 90, 90), -- dark gray
			Color3.fromRGB(65, 65, 65), -- charcoal
			Color3.fromRGB(40, 40, 40), -- near black
			Color3.fromRGB(15, 15, 15), -- deepest
		}),
		table.freeze({
			Color3.fromRGB(190, 100, 90), -- dusty coral
			Color3.fromRGB(195, 165, 100), -- dusty gold
			Color3.fromRGB(150, 170, 100), -- sage
			Color3.fromRGB(120, 140, 70), -- olive
			Color3.fromRGB(90, 160, 145), -- dusty teal
			Color3.fromRGB(95, 120, 105), -- eucalyptus
			Color3.fromRGB(100, 135, 175), -- slate blue
			Color3.fromRGB(135, 95, 155), -- dusty violet
			Color3.fromRGB(165, 140, 170), -- dusty lilac
			Color3.fromRGB(185, 115, 140), -- dusty pink
		}),
		table.freeze({
			Color3.fromRGB(120, 45, 45), -- dark red
			Color3.fromRGB(115, 60, 25), -- dark burnt orange
			Color3.fromRGB(125, 105, 35), -- dark gold
			Color3.fromRGB(80, 95, 35), -- dark olive
			Color3.fromRGB(40, 110, 50), -- dark green
			Color3.fromRGB(35, 100, 110), -- dark teal
			Color3.fromRGB(45, 55, 125), -- dark blue
			Color3.fromRGB(95, 40, 120), -- dark purple
			Color3.fromRGB(125, 60, 90), -- dark rose
			Color3.fromRGB(60, 85, 75), -- dark sage
		}),
	})
	local N_SCHEMES = #COLOR_SCHEMES

	function DebugHelper.GetColorScheme(index: number?): { Color3 }
		return if index then COLOR_SCHEMES[((index - 1) % N_SCHEMES) + 1] else COLOR_SCHEMES[1]
	end
end

return table.freeze(DebugHelper)
