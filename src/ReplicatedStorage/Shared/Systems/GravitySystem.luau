--!strict
--- Services ---
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--- Imports ---
local SystemScheduler = require(script.Parent)

local JecsCommon = require(ReplicatedStorage.Shared.Common.JecsCommon)

--- Variables ---
local GRAVITY = -196.2

local World = JecsCommon.World
local Components = JecsCommon.Components
local Tags = JecsCommon.Tags

local Gravity = Components.Gravity

local Climbing = Tags.Climbing

--- Gravity System ---
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
