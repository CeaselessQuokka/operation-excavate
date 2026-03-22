--!strict
--- Services ---
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

--- Imports ---
local CameraController = require(script.Parent.CameraController)
local PlayerController = require(script.Parent.PlayerController)

local CharacterHelper = require(ReplicatedStorage.Shared.Helpers.CharacterHelper)
local Cleaner = require(ReplicatedStorage.Shared.Helpers.Cleaner)

local PlayerModule = (require)(PlayerController.Player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"))

--- Types ---
type UsableCharacter = CharacterHelper.UsableCharacter
type CustomController = ControllerManager & {
	AirController: AirController,
	GroundController: GroundController,
	GroundSensor: ControllerPartSensor,
}

--- Movement Controller ---
local MovementController = {}

do -- Initialize controller.
	local cleaner = Cleaner.new()
	local function Cleanup()
		cleaner:Clean()
	end
	PlayerController.CharacterAdded(function(character)
		-- UNRELATED TODO: need to change lighting based off point on planet to have a smooth transition from day to night or vice versa
		local manager: ControllerManager = PlayerController.WaitForQuery(">ControllerManager")
		local groundController: GroundController = if manager
			then PlayerController.WaitForQuery("GroundController")
			else nil :: any
		local airController: AirController = if groundController
			then PlayerController.WaitForQuery("AirController")
			else nil :: any
		local groundSensor: ControllerPartSensor = if airController
			then PlayerController.WaitForQuery("ControllerPartSensor#GroundSensor")
			else nil :: any
		local jumpAnim: Animation = if groundSensor
			then PlayerController.WaitForQuery("Animation#JumpAnim")
			else nil :: any
		local movementAttachment: Attachment = if jumpAnim
			then PlayerController.WaitForQuery("Attachment#MovementAttachment")
			else nil :: any
		if not movementAttachment then
			return
		end

		-- TODO: need to check if on non-cancollide part, so they can't walk on top of it (could be cool to have walk on water boots or something)
		-- TODO: make more efficient (only run if moving and stuff if possible)
		-- TODO: try to stop their character from rotating when input stops, like normal character controls
		local movementVelocity = cleaner:Add(Instance.new("LinearVelocity"))
		movementVelocity.Attachment0 = movementAttachment
		movementVelocity.RelativeTo = Enum.ActuatorRelativeTo.Attachment0
		movementVelocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Line
		movementVelocity.MaxForce = 10000
		movementVelocity.Parent = movementAttachment.Parent
		local searchDistance = groundSensor.SearchDistance
		local params = RaycastParams.new()
		local jumpTrack =
			cleaner:Add((CharacterHelper.GetAnimator(character, true) :: Animator):LoadAnimation(jumpAnim))
		jumpTrack.Priority = Enum.AnimationPriority.Action
		jumpTrack.Looped = false
		params:AddToFilter(character)
		params.IgnoreWater = true
		local lastController = manager.ActiveController
		cleaner:Add(RunService.Heartbeat:Connect(function()
			if PlayerController.Character ~= character then
				return
			end

			local cameraForward = CameraController.CameraForward
			local origin = character.HumanoidRootPart.CFrame
			manager.UpDirection = origin.Position.Unit

			-- Compute movement direction from raw input + camera tangent-plane vectors
			-- instead of Humanoid.MoveDirection, which Roblox projects onto world XZ (flat world).
			local moveDir = Vector3.zero
			local up = manager.UpDirection
			local forward = cameraForward
			local right = forward:Cross(up).Unit
			local rawInput = PlayerModule:GetControls():GetMoveVector() -- X=right, Z=forward
			if rawInput.Magnitude > 0.01 then
				moveDir = (forward * -rawInput.Z) + (right * rawInput.X)
				if moveDir.Magnitude > 0.01 then
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
			if
				(manager.ActiveController == airController and character.HumanoidRootPart.AssemblyLinearVelocity.Y < 0)
				or (lastController == airController and manager.ActiveController == groundController)
			then
				jumpTrack:Stop()
			end
			lastController = manager.ActiveController
		end))
		-- TODO: use inputcontext and support all modalities
		cleaner:Add(UserInputService.InputBegan:Connect(function(input, gameProcessed)
			if
				gameProcessed
				or PlayerController.Character ~= character
				or manager.ActiveController ~= groundController
			then
				return
			end

			if input.KeyCode == Enum.KeyCode.Space then
				character.HumanoidRootPart:ApplyImpulse(
					manager.UpDirection * (character.Humanoid.JumpPower * character.HumanoidRootPart.AssemblyMass)
				)
				jumpTrack:Play()
			end
		end))
		character.Humanoid.EvaluateStateMachine = false
	end)
	PlayerController.OnDied:Connect(Cleanup)
	PlayerController.Player.CharacterRemoving:Connect(Cleanup)
end

return MovementController
