-- TODO: convert to a more efficient form instead of purely a component
--!strict
--- Services ---
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

--- Imports ---
local Component = require(ReplicatedStorage.Packages.Component)

local Cleaner = require(ReplicatedStorage.Shared.Helpers.Cleaner)

--- Variables ---
local GRAVITY = -196.2

--- Types ---
type ComponentInstance = BasePart

type Component = {
	Instance: ComponentInstance,
	_cleaner: Cleaner.Cleaner,
}

--- Gravity Component ---
local Gravity = Component.new({
	Tag = "Gravity",
	Ancestors = { Workspace },
})

function Gravity.Construct(self: Component)
	self._cleaner = Cleaner.new()
end

function Gravity.Start(self: Component)
	local force = self._cleaner:Add(Instance.new("VectorForce"))
	local attachment = self._cleaner:Add(Instance.new("Attachment"))
	attachment.Name = "CustomGravityAttachment"
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	attachment.Parent = self.Instance
	attachment.Axis = Vector3.new(0, 0, -1)
	force.Attachment0 = attachment
	force.Parent = self.Instance
	self._cleaner:Add(RunService.Heartbeat:Connect(function()
		local position = self.Instance.Position
		if position.Magnitude > 0 then
			local mass = self.Instance.AssemblyMass
			force.Force = position.Unit * (mass * GRAVITY)
		end
	end))
end

function Gravity.Stop(self: Component)
	self._cleaner:Destroy()
end

return Gravity
