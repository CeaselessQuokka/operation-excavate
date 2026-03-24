--!strict
--- Services ---
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--- Imports ---
local PlayerService = require(script.Parent.PlayerService)

local Jecs = require(ReplicatedStorage.Packages.Jecs)
local Signal = require(ReplicatedStorage.Packages.Signal)

local JecsCommon = require(ReplicatedStorage.Shared.Common.JecsCommon)
local Planet = require(ReplicatedStorage.Shared.Common.Planet)
local Remote = require(ReplicatedStorage.Shared.Common.Classes.Remote)

--- Types ---
type Signal<Params...> = Signal.Signal<Params...>
type SignalConnection = { Disconnect: (any) -> () }
type ServerApi<Params..., Return...> = Remote.ServerApi<Params..., Return...>

--- Variables ---
local N_RESOURCE_TYPES = JecsCommon.NResourceTypes

local World = JecsCommon.World
local ChildOf = Jecs.ChildOf
local Pair = Jecs.pair

local ReplicateTo = JecsCommon.Tags.ReplicateTo
local ResourceChunk = JecsCommon.Components.ResourceChunk

local resourceId = 1

--- Planet Resource Service ---
local PlanetResourceService = {}

function PlanetResourceService.PermissionTerraform(player: Player, point: Vector3): boolean
	return true
end

-- TODO: need to support shapes like box, ball, cone (drills), etc
function PlanetResourceService.Terraform(point: Vector3, radius: number) end

-- TODO: need a general way to track frontiers (one for terrain, one for resources, and one for chunk debugging)
function PlanetResourceService.CreateChunk(chunkIndex: number)
	local chunk = World:entity()
	World:add(chunk, Pair(ChildOf, PlanetResourceService.ResourceGrid))
	local resources: { number } = table.create(512) :: any
	for i = 1, 512 do
		resources[resourceId] = math.random(1, N_RESOURCE_TYPES)
		resourceId += 1
	end
	World:set(chunk, ResourceChunk, { ChunkIndex = chunkIndex, Resources = resources })
	local playerEntity = PlayerService.GetPlayerEntity(game.Players:FindFirstChild("CeaselessQuokka")) :: Jecs.Id
	World:add(chunk, Pair(ReplicateTo, playerEntity)) -- TODO: remove
	World:add(chunk, JecsCommon.Tags.ChunkDebug) -- TODO: remove
end

do -- Service initialization.
	local grid = World:entity()
	local planetTerrain = Planet.Terrain
	World:set(grid, JecsCommon.Components.Grid, planetTerrain.Grid)
	PlanetResourceService.ResourceGrid = grid
end

return PlanetResourceService
