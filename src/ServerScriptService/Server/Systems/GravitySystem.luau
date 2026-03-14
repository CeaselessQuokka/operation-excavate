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

local GravityForce = Components.GravityForce

--- Gravity System ---
task.spawn(function() -- Test give vector force
	local player = game.Players:WaitForChild("CeaselessQuokka") :: Player
	local character = player.Character or player.CharacterAdded:Wait() :: Model
	local force = Instance.new("VectorForce")
	local attachment = Instance.new("Attachment")
	attachment.Name = "CustomGravityAttachment"
	attachment.Parent = character.HumanoidRootPart
	attachment.Axis = Vector3.new(0, 0, -1)
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.Attachment0 = attachment
	force.Parent = character.HumanoidRootPart
	local forceEntity = World:entity()
	World:set(forceEntity, GravityForce, force)
	World:add(forceEntity, Gravity)
end)

local gravityQuery = World:query(GravityForce, Gravity):without(Climbing):cached():archetypes()
return (
	SystemScheduler.Schedule(function(dt: number)
		for _, archetype in gravityQuery do
			local forceColumn = archetype.columns_map[GravityForce]
			for row in archetype.entities do
				local vectorForce: VectorForce = forceColumn[row]
				local rootPart = vectorForce.Parent :: BasePart
				local rootPosition = rootPart.Position
				vectorForce.Force = rootPosition.Unit * (rootPart.AssemblyMass * GRAVITY)
			end
		end
	end, 1 / 30)
)
