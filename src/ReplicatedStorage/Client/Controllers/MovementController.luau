--!strict
--- Services ---
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

--- Imports ---
local CharacterHelper = require(ReplicatedStorage.Shared.Helpers.CharacterHelper)
local Knit = require(ReplicatedStorage.Packages.Knit)

local PlayerController = require(script.Parent.PlayerController)

local PlayerModule = (require)(Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"))

--- Types ---
type CustomController = ControllerManager & {
	AirController: AirController,
	GroundController: GroundController,
	GroundSensor: ControllerPartSensor,
}

--- Variables ---

--- Functions ---

--- MovementController Controller ---
local MovementController = {
	Name = "MovementController",
}
Knit.CreateController(MovementController)

function MovementController:KnitInit()
	local self = MovementController
end

function MovementController:KnitStart()
	local self = MovementController
	PlayerController.OnCharacterAdded:Connect(function(character)
		-- TODO: need a better way to do this, it's quite ugly
		-- UNRELATED TODO: need to change lighting based off point on planet to have a smooth transition from day to night or vice versa
		local manager = PlayerController:WaitForInstance<<ControllerManager>>(">ControllerManager", character)
		if not manager then
			return
		end

		local groundController = PlayerController:WaitForInstance<<GroundController>>("GroundController", character)
		if not groundController then
			return
		end

		local airController = PlayerController:WaitForInstance<<AirController>>("AirController", character)
		if not airController then
			return
		end

		local groundSensor =
			PlayerController:WaitForInstance<<ControllerPartSensor>>("ControllerPartSensor#GroundSensor", character)
		if not groundSensor then
			return
		end

		local jumpAnim = PlayerController:WaitForInstance<<Animation>>("Animation#JumpAnim", character)
		if not jumpAnim then
			return
		end

		local movementAttachment =
			PlayerController:WaitForInstance<<Attachment>>("Attachment#MovementAttachment", character)
		if not movementAttachment then
			return
		end

		-- TODO: need to check if on water or a non-cancollide part, so they can't walk on top of it (could be cool to have walk on water boots or something)
		-- TODO: need to properly cleanup
		-- TODO: make more efficient
		-- TODO: need to fix this in TableEditor: `local view = TableEditor.View("Tracks", TableHelper.ArrayToSet(character.Humanoid.Animator:GetPlayingAnimationTracks()))`; it doesn't remove old keys
		local movementVelocity = Instance.new("LinearVelocity")
		movementVelocity.Attachment0 = movementAttachment
		movementVelocity.RelativeTo = Enum.ActuatorRelativeTo.Attachment0
		movementVelocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Line
		movementVelocity.MaxForce = 10000
		movementVelocity.Parent = movementAttachment.Parent
		local searchDistance = groundSensor.SearchDistance
		local params = RaycastParams.new()
		local jumpTrack = (CharacterHelper.GetAnimator(character, true) :: Animator):LoadAnimation(jumpAnim)
		jumpTrack.Priority = Enum.AnimationPriority.Action
		jumpTrack.Looped = false
		params:AddToFilter(character)
		RunService.Heartbeat:Connect(function()
			local origin = character.HumanoidRootPart.CFrame
			manager.UpDirection = origin.Position.Unit

			-- Compute movement direction from raw input + camera tangent-plane vectors
			-- instead of Humanoid.MoveDirection, which Roblox projects onto world XZ (flat world).
			local moveDir = Vector3.zero
			if cameraForward then
				local up = manager.UpDirection
				local forward = cameraForward
				local right = forward:Cross(up).Unit
				local rawInput = PlayerModule:GetControls():GetMoveVector() -- X=right, Z=forward
				if rawInput.Magnitude > 0.001 then
					moveDir = (forward * -rawInput.Z + right * rawInput.X)
					if moveDir.Magnitude > 0.001 then
						moveDir = moveDir.Unit
						movementAttachment.WorldAxis = moveDir
						movementVelocity.LineVelocity = manager.BaseMoveSpeed
						manager.FacingDirection = moveDir
					else
						movementVelocity.LineVelocity = 0
					end
				else
					movementVelocity.LineVelocity = 0
				end
			end

			if
				manager.ActiveController == airController
				and character.HumanoidRootPart.AssemblyLinearVelocity.Y < 0
			then
				jumpTrack:Stop()
			end
			local result = Workspace:Raycast(origin.Position, origin.UpVector * -searchDistance, params)
			if result then
				groundSensor.HitFrame = CFrame.new(result.Position)
				groundSensor.HitNormal = result.Normal
				groundSensor.SensedPart = result.Instance
				character.Humanoid:ChangeState(Enum.HumanoidStateType.Running)
				manager.ActiveController = groundController
			else
				character.Humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
				manager.ActiveController = airController
			end
		end)
		-- TODO: use inputcontext and support all modalities
		UserInputService.InputBegan:Connect(function(input, gameProcessed)
			if gameProcessed or manager.ActiveController ~= groundController then
				return
			end

			if input.KeyCode == Enum.KeyCode.Space then
				character.HumanoidRootPart:ApplyImpulse(
					character.HumanoidRootPart.CFrame.UpVector
						* (character.Humanoid.JumpPower * character.HumanoidRootPart.AssemblyMass)
				)
				jumpTrack:Play()
			end
		end)
		character.Humanoid.EvaluateStateMachine = false
	end)
end

return MovementController
