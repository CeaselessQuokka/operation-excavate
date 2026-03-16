--!strict
--- Services ---
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StudioTestService = game:GetService("StudioTestService")

--- Imports ---
local Jecs = require(ReplicatedStorage.Packages.Jecs)
local SystemScheduler = require(script.Parent)

local JecsCommon = require(ReplicatedStorage.Shared.Common.Jecs)

--- Variables ---
local GRAVITY = -196.2

local World = JecsCommon.World
local Components = JecsCommon.Components
local Tags = JecsCommon.Tags

local Gravity = Components.Gravity

local Climbing = Tags.Climbing

--- Gravity System ---
do
	local Item = World:component() :: Jecs.Id<{
		Type: string,
	}>
	local ItemChunk = World:component() :: Jecs.Id<{
		Center: Vector3,
		MaxItems: number,
	}>

	local OwnedBy = Jecs.tag()
	local Private = Jecs.tag()

	local player = World:entity()

	local chunk1 = World:entity()
	World:set(chunk1, ItemChunk, { Center = Vector3.new(0, 0, 0), MaxItems = 10 })
	World:add(chunk1, Private)

	local playerOwns = Jecs.pair(OwnedBy, player)
	World:add(chunk1, playerOwns)

	for index = 1, math.random(1, 10) do
		local item = World:entity()
		World:set(item, Item, { Type = "Dirt" })
		World:add(item, Jecs.pair(Jecs.ChildOf, chunk1))
	end

	for entity, chunk in World:query(ItemChunk) do
		print("Chunk:", entity, chunk.Center, chunk.MaxItems)
	end
	for entity, item in World:query(Item) do
		print("Item:", entity, item.Type)
	end
	task.wait()
	StudioTestService:EndTest(true)
end
local gravityQuery = World:query(Gravity):without(Climbing):cached():archetypes()
return (
	SystemScheduler.Schedule(function(dt: number)
		for _, archetype in gravityQuery do
			local gravityColumn = archetype.columns_map[Gravity]
			for row in archetype.entities do
				local vectorForce: VectorForce = gravityColumn[row]
				local rootPart = vectorForce.Parent :: BasePart
				vectorForce.Force = rootPart.Position.Unit * (rootPart.AssemblyMass * GRAVITY)
				if row % 500 == 0 then
					task.wait(1 / 60)
				end
			end
		end
	end, 1 / 8)
)
