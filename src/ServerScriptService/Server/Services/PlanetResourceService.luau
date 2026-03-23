--!strict
--- Services ---
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--- Imports ---
local Jecs = require(ReplicatedStorage.Packages.Jecs)
local Remote = require(ReplicatedStorage.Shared.Common.Classes.Remote)
local Signal = require(ReplicatedStorage.Packages.Signal)

local JecsCommon = require(ReplicatedStorage.Shared.Common.JecsCommon)
local Planet = require(ReplicatedStorage.Shared.Common.Planet)

--- Types ---
type Signal<Params...> = Signal.Signal<Params...>
type SignalConnection = { Disconnect: (any) -> () }
type ServerApi<Params..., Return...> = Remote.ServerApi<Params..., Return...>

--- Variables ---
local N_RESOURCE_TYPES = JecsCommon.NResourceTypes

local World = JecsCommon.World
local Pair = Jecs.pair

local ChildOf = Jecs.ChildOf
local ResourceChunk = JecsCommon.Components.ResourceChunk

--- Planet Resource Service ---
local PlanetResourceService = {}

function PlanetResourceService.PermissionTerraform(player: Player, point: Vector3): boolean
	return true
end

-- TODO: need to support shapes like box, ball, cone (drills), etc
function PlanetResourceService.Terraform(point: Vector3, radius: number) end

-- TODO: will need to have different frontiers: a terrain frontier that generates terrain, a resource frontier that generates resources
function PlanetResourceService.CreateChunk(chunkIndex: number)
	local chunk = World:entity()
	World:add(chunk, Pair(ChildOf, PlanetResourceService.Grid))
	local resources: { number } = table.create(512) :: any
	for i = 1, 512 do
		resources[i] = math.random(1, N_RESOURCE_TYPES)
	end
	World:set(chunk, ResourceChunk, { ChunkIndex = chunkIndex, Resources = resources })
end

do -- Service initialization.
	local grid = World:entity()
	local planetTerrain = Planet.Terrain
	World:set(grid, JecsCommon.Components.Grid, {
		Center = planetTerrain.Grid.Center,
		Size = planetTerrain.Grid.GridWorldSize,
	})
	PlanetResourceService.Grid = grid
end

return PlanetResourceService
