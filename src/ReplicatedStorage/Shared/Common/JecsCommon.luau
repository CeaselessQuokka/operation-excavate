--!strict
--- Services ---
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--- Imports ---
local Jecs = require(ReplicatedStorage.Packages.Jecs)

local CharacterHelper = require(ReplicatedStorage.Shared.Helpers.CharacterHelper)

local Grid = require(ReplicatedStorage.Shared.Common.Classes.Grid)
local Planet = require(ReplicatedStorage.Shared.Common.Planet)

--- Types ---
type ResourceChunkData = Planet.ResourceChunkData
type UsableCharacter = CharacterHelper.UsableCharacter

--- Variables ---
local Climbing = Jecs.tag()
local OwnedBy = Jecs.tag()
local Private = Jecs.tag()
local Alive = Jecs.tag()

local ChunkDebug = Jecs.tag()
local ReplicateTo = Jecs.tag()
local Dropped = Jecs.tag()

local World = Jecs.world(true)

--- Jecs Common ---
local JecsCommon = {
	World = World,
	Components = {
		-- Player
		Player = World:component() :: Jecs.Id<Player>,
		Character = World:component() :: Jecs.Id<UsableCharacter?>,

		-- Climbing System
		Climbable = World:component() :: Jecs.Id<{
			ClimbSpeedMultiplier: number,
			GripDecayMultiplier: number,
		}?>,

		-- Gravity System
		Gravity = World:component() :: Jecs.Id<VectorForce?>,

		-- Resource Grid
		Grid = World:component() :: Jecs.Id<Grid.Grid>,
		ResourceChunk = World:component() :: Jecs.Id<ResourceChunkData>,
		Resource = World:component() :: Jecs.Id<number>, -- number is the CFrame index.
	},
	Tags = {
		-- General
		OwnedBy = OwnedBy,
		Private = Private,

		-- Entity
		Alive = Alive,

		-- Climbing System
		Climbing = Climbing,

		-- Resource Grid
		ChunkDebug = ChunkDebug,
		ReplicateTo = ReplicateTo,
		Dropped = Dropped,
		ResourceType = ResourceType,
		Dirt = Dirt,
		Stone = Stone,
		Bauxite = Bauxite,
		Coal = Coal,
	},

	WaitForCache = function<ComponentData>(component: Jecs.Id<ComponentData>): ({ ComponentData }, Jecs.Archetype)
		local archetype: Jecs.Archetype? = World:query(component):cached():archetypes()[1]
		if archetype then
			return archetype.columns_map[component], archetype
		end

		local pausedThread = coroutine.running()
		local componentValues: { ComponentData }
		local setCache: (() -> ())?
		setCache = World:added(component, function()
			if setCache then
				-- Set cache after archetype has been made.
				setCache()
				setCache = nil
				archetype = World:query(component):cached():archetypes()[1]
				componentValues = archetype.columns_map[component]
				task.spawn(pausedThread)
			end
		end)
		coroutine.yield()
		return componentValues, (archetype :: any) :: Jecs.Archetype
	end,
}
do -- Register names for debugging purposes.
	for name: string, component: Jecs.Id in JecsCommon.Components :: { [any]: any } do
		World:set(component, Jecs.Name, name)
	end
	for name: string, tag: Jecs.Id in JecsCommon.Tags :: { [any]: any } do
		World:set(tag, Jecs.Name, name)
	end
end

return JecsCommon
