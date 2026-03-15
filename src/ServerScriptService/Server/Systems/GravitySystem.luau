--!strict
--- Services ---
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--- Imports ---
local SystemScheduler = require(script.Parent)

local Common = require(ReplicatedStorage.Shared.Common.Jecs)
local DiagnosticHelper = require(ReplicatedStorage.Shared.Helpers.DiagnosticHelper)

--- Variables ---
local GRAVITY = -196.2

local World = Common.World
local Components = Common.Components

local Climbing = Components.Climbing
local Gravity = Components.Gravity

local GravityForce = Components.GravityForce

--- Gravity System ---
task.delay(0, function() -- Test give vector force
	local player = game.Players:WaitForChild("CeaselessQuokka") :: Player
	local character = player.Character or player.CharacterAdded:Wait() :: Model
	local force = Instance.new("VectorForce")
	local attachment = Instance.new("Attachment")
	attachment.Name = "CustomGravityAttachment"
	attachment.Parent = character.HumanoidRootPart
	attachment.Axis = Vector3.new(0, 0, -1)
	force.Force = vector.zero :: any
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.Attachment0 = attachment
	force.Parent = character.HumanoidRootPart
	local forceEntity = World:entity()
	World:set(forceEntity, GravityForce, force)
	World:add(forceEntity, Gravity)

	-- place balls in a grid to test performance (30x30)
	local ballTemplate = Instance.new("Part")
	ballTemplate.CastShadow = false
	ballTemplate.TopSurface = 0
	ballTemplate.BottomSurface = 0
	ballTemplate.Shape = Enum.PartType.Ball
	ballTemplate.Size = vector.one * 2 :: any
	local origin = character:GetPivot() * CFrame.new(0, 25, 0)
	local gridSizeSquare = 300
	local padding = 128
	for i = 1, gridSizeSquare * gridSizeSquare do
		local x = (i % gridSizeSquare) - 1
		local z = math.floor(i / gridSizeSquare)
		local ball = ballTemplate:Clone()
		ball.Position = origin.Position
			+ Vector3.new((x - (gridSizeSquare / 2)) * padding, 0, (z - (gridSizeSquare / 2)) * padding)
		-- create attachment and vector force for each ball
		local ballAttachment = Instance.new("Attachment")
		ballAttachment.Name = "CustomGravityAttachment"
		ballAttachment.Parent = ball
		ballAttachment.Axis = Vector3.new(0, 0, -1)
		local ballForce = Instance.new("VectorForce")
		ballForce.Force = vector.zero :: any
		ballForce.RelativeTo = Enum.ActuatorRelativeTo.World
		ballForce.Attachment0 = ballAttachment
		ballForce.Parent = ball
		-- register with jecs
		local ballEntity = World:entity()
		World:set(ballEntity, GravityForce, ballForce)
		World:add(ballEntity, Gravity)
		ball.Parent = workspace
		ball:SetNetworkOwner(player)
	end
end)

for t = 15, 1, -1 do
	print(t)
	task.wait(1)
end
local diag = DiagnosticHelper.new("Test")
local gravityQuery = World:query(GravityForce, Gravity):without(Climbing):cached():archetypes()
local gravityArchetype = gravityQuery[1]
local gravityForceColumn = gravityArchetype.columns_map[GravityForce]
print("Ntities", #gravityArchetype.entities)
task.delay(30, function()
	diag:PrintBreakdown(true)
end)
return (
	SystemScheduler.Schedule(function(dt: number)
		diag:StartTimer("T")
		for row in gravityArchetype.entities do
			local vectorForce: VectorForce = gravityForceColumn[row]
			local rootPart = vectorForce.Parent :: BasePart
			local rootPosition = rootPart.Position
			vectorForce.Force = rootPosition.Unit * (rootPart.AssemblyMass * GRAVITY)
			if row % 1000 == 0 then
				diag:StopTimer("T")
				task.wait()
				diag:StartTimer("T")
			end
		end
		diag:StopTimer("T")
	end, 1 / 10)
)
