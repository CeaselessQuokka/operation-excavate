--!strict
--- Services ---
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

--- Imports ---
local PlayerService = require(script.Parent.PlayerService)

local Jecs = require(ReplicatedStorage.Packages.Jecs)
local Signal = require(ReplicatedStorage.Packages.Signal)

local DebugHelper = require(ReplicatedStorage.Shared.Helpers.DebugHelper)
local DiagnosticHelper = require(ReplicatedStorage.Shared.Helpers.DiagnosticHelper)
local JecsCommon = require(ReplicatedStorage.Shared.Common.JecsCommon)
local Planet = require(ReplicatedStorage.Shared.Common.Planet)
local Remote = require(ReplicatedStorage.Shared.Common.Classes.Remote)
local ResourceOffsets = require(ReplicatedStorage.Shared.Common.ResourceOffsets)

--- Types ---
type ChunkIndex = Planet.ChunkIndex
type ResourceId = Planet.ResourceId
type ResourceChunkData = Planet.ResourceChunkData
type Signal<Params...> = Signal.Signal<Params...>
type SignalConnection = { Disconnect: (any) -> () }
type ServerApi<Params..., Return...> = Remote.ServerApi<Params..., Return...>

--- Variables ---
local Y_X_MASK = Vector3.new(0, 1, 1)
local X_Z_MASK = Vector3.new(1, 0, 1)
local X_Y_MASK = Vector3.new(1, 1, 0)

local N_OFFSETS = #ResourceOffsets
local RESOURCE_OFFSET_BITS = Planet.ResourceOffsetBits
local MAX_RESOURCE_OFFSETS = Planet.MaxResourceOffsets
local RESOURCE_TYPE_TO_SIZE = Planet.ResourceIdToSize
local N_RESOURCE_TYPES = Planet.NResourceTypes

local TERRAIN_PARAMS = RaycastParams.new()
TERRAIN_PARAMS.IgnoreWater = true
TERRAIN_PARAMS.FilterType = Enum.RaycastFilterType.Include
TERRAIN_PARAMS:AddToFilter(Planet.RobloxTerrain) -- TODO: will need to add Buildings to this in the future (put it all under a folder and just set the folder)

local resourceGrid = Planet.Terrain.Grid
local resourceChunks: { [ChunkIndex]: ResourceChunkData } = {}

--- Functions ---
local function IsResourceExposed(typeId: number, offsetId: number, chunkCenter: Vector3): boolean
	local origin = ResourceOffsets[offsetId] + chunkCenter
	local size = RESOURCE_TYPE_TO_SIZE[typeId]
	local halfWorldSize = size / 2
	local left = origin * CFrame.new(-halfWorldSize.X, 0, 0)
	if Workspace:Blockcast(left, size * Y_X_MASK, origin.RightVector * size.X) then
		-- Check left to right.
		return true
	end
	local right = origin * CFrame.new(halfWorldSize.X, 0, 0)
	if Workspace:Blockcast(right, size * Y_X_MASK, origin.RightVector * -size.X) then
		-- Check right to left.
		return true
	end
	local top = origin * CFrame.new(0, halfWorldSize.Y, 0)
	if Workspace:Blockcast(top, size * X_Z_MASK, origin.UpVector * -size.Y) then
		-- Check top to bottom.
		return true
	end
	local bottom = origin * CFrame.new(0, -halfWorldSize.Y, 0)
	if Workspace:Blockcast(bottom, size * X_Z_MASK, origin.UpVector * size.Y) then
		-- Check bottom to top.
		return true
	end
	local back = origin * CFrame.new(0, 0, halfWorldSize.Z)
	if Workspace:Blockcast(back, size * X_Y_MASK, origin.LookVector * size.Z) then
		-- Check back to front.
		return true
	end
	local front = origin * CFrame.new(0, 0, -halfWorldSize.Z)
	if Workspace:Blockcast(front, size * X_Y_MASK, origin.LookVector * -size.Z) then
		-- Check front to back.
		return true
	end
	return false
end

-- TODO: add each chunk to a multithreading queue, and in that actor it task.waits every 32 resources or so

local function ShouldRemoveResource(offsetId: number, chunkCenter: Vector3): boolean
	local from = ResourceOffsets[offsetId].Position + chunkCenter
	local direction = from.Unit
	local to = direction * -10000
	local floorResult = Workspace:Raycast(from, to, TERRAIN_PARAMS)
	if floorResult then
		local newFrom = floorResult.Position
		local shouldRemove = Workspace:Raycast(newFrom, direction * (newFrom - from).Magnitude, TERRAIN_PARAMS) == nil
		return shouldRemove
	end
	return false
end

local exposedResourceModels: { [ResourceId]: Model } = {}
-- Initially identity all exposed resources, and discard ones that are droppable.
local function ProcessChunk(chunkData: ResourceChunkData)
	local resources = chunkData.Resources
	local exposedResources = chunkData.ExposedResources
	local chunkCenter = resourceGrid:ChunkIndexToWorldPosition(chunkData.ChunkIndex)
	for resourceId in resources do
		local typeId = bit32.rshift(resourceId, RESOURCE_OFFSET_BITS)
		local offsetId = bit32.band(resourceId, MAX_RESOURCE_OFFSETS)
		if IsResourceExposed(typeId, offsetId, chunkCenter) then
			exposedResources[resourceId] = true
			local prefab = Planet.ResourceTypeToPrefab[Planet.ResourceIdToType[typeId]]:Clone()
			prefab:PivotTo(ResourceOffsets[offsetId] + chunkCenter)
			prefab.Parent = workspace
			exposedResourceModels[resourceId] = prefab
		elseif ShouldRemoveResource(offsetId, chunkCenter) then
			resources[resourceId] = nil
		end
	end
end

--- Planet Resource Service ---
local PlanetResourceService = {
	ResourceGrid = resourceGrid,
	Chunks = resourceChunks,
}

-- TODO: need to support shapes like box, ball, cone (drills), etc
function PlanetResourceService.Terraform(point: Vector3, radius: number)
	-- TODO: narrow search using items within radius? need to benchmark this
	radius = math.ceil(radius / 4) * 4
	local chunkIndex = resourceGrid:GetNearestChunkIndexAtPosition(point)
	local chunkData = resourceChunks[chunkIndex]
	if chunkData then
		local chunkCenter = resourceGrid:ChunkIndexToWorldPosition(chunkData.ChunkIndex)
		for resourceId in chunkData.Resources do
			local typeId = bit32.rshift(resourceId, RESOURCE_OFFSET_BITS)
			local offsetId = bit32.band(resourceId, MAX_RESOURCE_OFFSETS)
			local isExposed = IsResourceExposed(typeId, offsetId, chunkCenter)
			local model = exposedResourceModels[resourceId]
			if isExposed and not chunkData.ExposedResources[resourceId] then
				-- Item is embedded and exposed to the air.
				chunkData.ExposedResources[resourceId] = true
				local prefab = Planet.ResourceTypeToPrefab[Planet.ResourceIdToType[typeId]]:Clone()
				prefab:PivotTo(ResourceOffsets[offsetId] + chunkCenter)
				prefab.Parent = workspace
				exposedResourceModels[resourceId] = prefab
			elseif not isExposed and chunkData.ExposedResources[resourceId] then
				-- Can drop the resource since it was previously embedded in terrain,
				-- but now it was dug out since no terrain is surrounded it.
				chunkData.Resources[resourceId] = nil
				chunkData.ExposedResources[resourceId] = nil
				if model then
					local gaveGravity = false
					for _, part in model:QueryDescendants("BasePart") do
						if not gaveGravity then
							gaveGravity = true
							local movementAttachment: Attachment = (ServerStorage :: any).Assets.Character.MovementAttachment:Clone()
							local gravityForce: VectorForce = (ServerStorage :: any).Assets.Character.Gravity:Clone()
							movementAttachment.Parent = part
							gravityForce.Attachment0 = movementAttachment
							gravityForce.Parent = part
							JecsCommon.World:set(JecsCommon.World:entity(), JecsCommon.Components.Gravity, gravityForce)
						end
						part.Anchored = false
					end
				end
			end
		end
	end
end

-- TODO: need a general way to track frontiers (one for terrain, one for resources, and one for chunk debugging)
function PlanetResourceService.CreateChunk(chunkIndex: number)
	local resources: { [ResourceId]: true } = table.create(64) :: any
	for i = 1, 64 do
		local typeId = math.random(1, N_RESOURCE_TYPES)
		local offsetId = math.random(1, N_OFFSETS)
		local resourceId = bit32.bor(bit32.lshift(typeId, RESOURCE_OFFSET_BITS), offsetId)
		resources[resourceId] = true
	end
	local chunkData = { ChunkIndex = chunkIndex, Resources = resources, ExposedResources = {} }
	resourceChunks[chunkIndex] = chunkData
	task.delay(math.random() + 1, ProcessChunk, chunkData)
end

return PlanetResourceService
