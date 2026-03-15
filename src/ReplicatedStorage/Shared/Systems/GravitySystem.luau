--!strict
--- Services ---
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--- Imports ---
local SystemScheduler = require(script.Parent)

local Common = require(ReplicatedStorage.Shared.Common.Jecs)

--- Variables ---
local GRAVITY = -196.2

local World = Common.World
local Components = Common.Components

local Climbing = Components.Climbing
local Gravity = Components.Gravity

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
