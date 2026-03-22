--!strict
--- Services ---
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--- Imports ---
local Jecs = require(ReplicatedStorage.Packages.Jecs)
local Remote = require(ReplicatedStorage.Shared.Common.Classes.Remote)
local Signal = require(ReplicatedStorage.Packages.Signal)

local DiagnosticHelper = require(ReplicatedStorage.Shared.Helpers.DiagnosticHelper)
local JecsCommon = require(ReplicatedStorage.Shared.Common.JecsCommon)
local Planet = require(ReplicatedStorage.Shared.Common.Planet)
local ResourceOffsets = require(ReplicatedStorage.Shared.Common.ResourceOffsets)

--- Types ---
type Signal<Params...> = Signal.Signal<Params...>
type SignalConnection = { Disconnect: (any) -> () }
type ServerApi<Params..., Return...> = Remote.ServerApi<Params..., Return...>

--- Variables ---
local N_RESOURCE_OFFSETS = #ResourceOffsets

local World = JecsCommon.World
local Pair = Jecs.pair

local OwnedBy = JecsCommon.Tags.OwnedBy
local ResourceChunk = JecsCommon.Components.ResourceChunk
local Resource = JecsCommon.Components.Resource

--- Functions ---

--- Planet Resource Service ---
local PlanetResourceService = {}

-- TODO: will need to have different frontiers: a terrain frontier that generates terrain, a resource frontier that generates resources
local diag = DiagnosticHelper.new("PlanetResourceService")
local totalChunks, totalResources = 0, 0
function PlanetResourceService.CreateChunk(chunkIndex: number)
	diag:StartTimer("CreateChunk")
	local chunk = World:entity()
	World:add(chunk, Pair(OwnedBy, PlanetResourceService.Grid))
	World:set(chunk, ResourceChunk, chunkIndex)
	totalChunks += 1
	for _ = 1, 1024 do
		local resource = World:entity()
		World:add(resource, Pair(OwnedBy, chunk))
		World:set(resource, Resource, math.random(1, N_RESOURCE_OFFSETS))
		totalResources += 1
	end
	diag:StopTimer("CreateChunk")
end
task.defer(function()
	for t = 40, 1, -1 do
		print(t)
		task.wait(1)
	end
	diag:PrintBreakdown(true)
end)
do -- Service initialization.
	local grid = World:entity()
	local planetTerrain = Planet.Terrain
	World:set(grid, JecsCommon.Components.Grid, {
		Center = planetTerrain.Grid.Center,
		Size = planetTerrain.Grid.GridWorldSize,
	})
	PlanetResourceService.Grid = grid
	task.spawn(function()
		while true do
			task.wait(5)
			print(totalChunks, totalResources)
		end
	end)
end

return PlanetResourceService
