--!strict
--- Services ---
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--- Imports ---
local Jecs = require(ReplicatedStorage.Packages.Jecs)

--- Types ---

--- Variables ---
local Climbing = Jecs.tag()
local OwnedBy = Jecs.tag()
local Private = Jecs.tag()

local World = Jecs.world(true)

--- Functions ---

--- Jecs Common ---
return {
	World = World,
	Components = {
		-- Climbing System
		Climbable = World:component() :: Jecs.Id<{
			ClimbSpeedMultiplier: number,
			GripDecayMultiplier: number,
		}?>,

		-- Gravity System
		Gravity = World:component() :: Jecs.Id<VectorForce>,

		-- Items
		Item = World:component() :: Jecs.Id<{
			Type: string,
			CFrameIndex: number?,
			Stack: number?,
		}>,
	},
	Tags = {
		-- General
		OwnedBy = OwnedBy,
		Private = Private,

		-- Climbing System
		Climbing = Climbing,
	},
}
