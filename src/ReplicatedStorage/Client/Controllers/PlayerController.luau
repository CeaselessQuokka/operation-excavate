--!strict
--- Services ---
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

--- Imports ---
local CameraHelper = require(ReplicatedStorage.Shared.Helpers.CameraHelper)
local Knit = require(ReplicatedStorage.Packages.Knit)
local Signal = require(ReplicatedStorage.Packages.Signal)

local CharacterHelper = require(ReplicatedStorage.Shared.Helpers.CharacterHelper)
local ThreadingHelper = require(ReplicatedStorage.Shared.Helpers.ThreadingHelper)

local PlayerModule = (require)(Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"))

--- Types ---
type Character = CharacterHelper.Character
type UsableCharacter = CharacterHelper.UsableCharacter
type Signal<T...> = Signal.Signal<T...>
type SignalConnection = Signal.Connection

export type Area = BasePart | { CFrame: CFrame, Size: Vector3 }
export type AreaCheckMode = "Box" | "XZ" | "Magnitude"
export type AreaOptions = {
	CheckMode: AreaCheckMode?,
	YThreshold: number?,
	Radius: number?,
	CheckInterval: number?,
}

--- Variables ---
local localPlayer = Players.LocalPlayer

local DEFAULT_CHECK_INTERVAL = 0.125
local DEFAULT_Y_THRESHOLD = 6

local areaSignals: { [string]: { OnEntered: Signal<>, OnLeft: Signal<> } } = {}

--- Player Controller ---
local PlayerController = {
	Name = "PlayerController",

	Player = Players.LocalPlayer,
	PlayerGui = localPlayer:WaitForChild("PlayerGui") :: PlayerGui,
	Character = nil :: UsableCharacter?,

	OnCharacterAdded = Signal.new() :: Signal<UsableCharacter>,
	OnDied = Signal.new() :: Signal<>,
}
Knit.CreateController(PlayerController)

function PlayerController:KnitStart()
	local self = PlayerController
	local function OnCharacterAdded(character: Character)
		local usable = false
		while character == localPlayer.Character do
			task.wait()
			if CharacterHelper.IsUsable(character) then
				usable = true
				break
			end
		end
		if not usable then
			return
		end

		local humanoid = CharacterHelper.GetHumanoid(character) :: Humanoid
		humanoid.Died:Once(function()
			self.Character = nil
			self.OnDied:FireDeferred()
		end)

		self:_InitializeCharacter(character)
		self.Character = character :: UsableCharacter
		self.OnCharacterAdded:FireDeferred(character :: UsableCharacter)
	end

	localPlayer.CharacterAdded:Connect(OnCharacterAdded)
	if localPlayer.Character then
		task.defer(OnCharacterAdded, localPlayer.Character)
	end

	-- do -- Handle character rotation about planet. (TODO: Check for water)
	-- 	local gyro: AlignOrientation?
	-- 	local gyroAttachment: Attachment?
	-- 	local function CleanupGyro()
	-- 		if gyro then
	-- 			pcall(game.Destroy, gyro)
	-- 			gyro = nil
	-- 		end
	-- 		if gyroAttachment then
	-- 			pcall(game.Destroy, gyroAttachment)
	-- 			gyroAttachment = nil
	-- 		end
	-- 	end
	-- 	self:CharacterAdded(function(character)
	-- 		gyro = Instance.new("AlignOrientation")
	-- 		gyroAttachment = Instance.new("Attachment")
	-- 		gyro.Name = "PlanetAlignOrientation"
	-- 		gyro.Mode = Enum.OrientationAlignmentMode.OneAttachment
	-- 		gyro.MaxTorque = 1e9
	-- 		gyro.Responsiveness = 75
	-- 		gyro.Attachment0 = gyroAttachment
	-- 		gyroAttachment.Name = "PlanetAlignOrientationAttachment"
	-- 		gyroAttachment.Parent = character.PrimaryPart
	-- 		gyro.Enabled = false
	-- 		gyro.Parent = character.PrimaryPart
	-- 	end)
	-- 	self.OnDied:Connect(CleanupGyro)
	-- 	localPlayer.CharacterRemoving:Connect(CleanupGyro)

	-- 	-- Handle actual rotation logic.
	-- 	RunService.PreRender:Connect(function()
	-- 		local character = self.Character
	-- 		if not character or not gyro or not gyroAttachment then
	-- 			return
	-- 		end

	-- 		local origin = character:GetPivot()
	-- 		local normal = origin.Position.Unit -- Assumes origin is (0, 0, 0); otherwise you'd need to subtract position by the origin.
	-- 		local zDir = origin.ZVector
	-- 		local xDir = normal:Cross(zDir)
	-- 		local moveDirection = character.Humanoid.MoveDirection
	-- 		local projected = moveDirection - (normal * moveDirection:Dot(normal))
	-- 		if projected.Magnitude > 0.1 then
	-- 			projected = projected.Unit
	-- 			local rightDir = projected:Cross(normal)
	-- 			gyro.CFrame = CFrame.fromMatrix(Vector3.zero, rightDir, normal)
	-- 		else
	-- 			gyro.CFrame = CFrame.fromMatrix(Vector3.zero, xDir, normal)
	-- 		end
	-- 		-- gyro.CFrame = CFrame.fromMatrix(Vector3.zero, xDir, normal)
	-- 		-- local moveDirection = character.Humanoid.MoveDirection
	-- 		-- if moveDirection.Magnitude > 0.1 then
	-- 		-- 	character:PivotTo(CFrame.lookAlong(origin.Position, moveDirection, normal))
	-- 		-- end
	-- 	end)
	-- end
end

function PlayerController:CharacterAdded(callback: (character: UsableCharacter) -> ()): SignalConnection
	if localPlayer.Character then
		task.defer(callback, localPlayer.Character)
	end
	return self.OnCharacterAdded:Connect(callback)
end

-- TODO: replace with generic, and call with <<ControllerManager>> once StyLua fixes styling (currently the styler breaks with the <<TYPE>> syntax)
-- TODO: replace character with "from", that way it supports any path
function PlayerController:WaitForInstance(query: string, character: UsableCharacter?): any?
	local s = os.clock()
	-- Resolve character.
	local self = PlayerController
	character = character or self.Character or localPlayer.CharacterAdded:Wait()
	if not character then
		return nil
	end

	-- Resolve instance.
	while character == localPlayer.Character do
		local instance = character:QueryDescendants(query)[1]
		if instance then
			print(`Resolved instance with query "{query}" after {os.clock() - s} seconds.`)
			return instance
		end
		ThreadingHelper.WaitForAny(
			nil,
			character.DescendantAdded,
			self.OnDied,
			localPlayer.CharacterRemoving,
			localPlayer.CharacterAdded
		)
	end
	warn(`[{script.Name}] Failed to find instance with query "{query}" in character.`)
	return nil
end

function PlayerController:DisableControls()
	PlayerModule:GetControls():Disable()
end

function PlayerController:EnableControls()
	PlayerModule:GetControls():Enable()
end

function PlayerController:EnteredArea(
	name: string,
	area: Area,
	options: AreaOptions?,
	onEnteredCallback: (() -> ())?,
	onLeftCallback: (() -> ())?
): (Signal<>, Signal<>, () -> ())
	if areaSignals[name] then
		local cleanup = function()
			self:StopAreaCheck(name)
		end
		return areaSignals[name].OnEntered, areaSignals[name].OnLeft, cleanup
	end

	local function GetAreaCFrameAndSize(): (CFrame, Vector3)
		if typeof(area) == "Instance" and area:IsA("BasePart") then
			return area.CFrame, area.Size
		elseif typeof(area) == "table" then
			return area.CFrame, area.Size
		else
			error(`Invalid area given: "{area}" ({typeof(area)})`)
		end
	end

	local function IsInArea(): boolean
		local character = self.Character
		if not character then
			return false
		end

		local rootPart = CharacterHelper.GetRootPart(character)
		if not rootPart then
			return false
		end

		local position = rootPart.Position
		local areaCFrame, areaSize = GetAreaCFrameAndSize()
		local checkMode = if options and options.CheckMode then options.CheckMode else "Box"
		if checkMode == "Magnitude" then
			local radius = if options and options.Radius then options.Radius else (areaSize.Magnitude / 2)
			return CharacterHelper.DistanceFrom(character, areaCFrame.Position, false) <= radius
		elseif checkMode == "XZ" then
			local yThreshold = if options and options.YThreshold then options.YThreshold else DEFAULT_Y_THRESHOLD
			local radius = if options and options.Radius then options.Radius else math.max(areaSize.X, areaSize.Z) / 2
			return CharacterHelper.DistanceFrom(character, areaCFrame.Position, true, yThreshold) <= radius
		else
			local localPosition = areaCFrame:PointToObjectSpace(position)
			local halfSize = areaSize / 2
			return math.abs(localPosition.X) <= halfSize.X
				and math.abs(localPosition.Y) <= halfSize.Y
				and math.abs(localPosition.Z) <= halfSize.Z
		end
	end

	local onEntered = Signal.new()
	local onLeft = Signal.new()
	areaSignals[name] = {
		OnEntered = onEntered,
		OnLeft = onLeft,
	}
	if onEnteredCallback then
		onEntered:Connect(onEnteredCallback)
	end
	if onLeftCallback then
		onLeft:Connect(onLeftCallback)
	end

	task.spawn(function()
		local checkInterval = if options and options.CheckInterval
			then options.CheckInterval
			else DEFAULT_CHECK_INTERVAL
		local wasInArea = false
		while areaSignals[name] do
			local isInArea = IsInArea()
			if isInArea and not wasInArea then
				onEntered:FireDeferred()
			elseif not isInArea and wasInArea then
				onLeft:FireDeferred()
			end
			wasInArea = isInArea
			task.wait(checkInterval)
		end
	end)
	return onEntered, onLeft, function()
		self:StopAreaCheck(name)
	end
end

function PlayerController:StopAreaCheck(name: string)
	local areaData = areaSignals[name]
	if areaData then
		areaData.OnEntered:Destroy()
		areaData.OnLeft:Destroy()
		areaSignals[name] = nil
	end
end

function PlayerController:_InitializeCharacter(character: UsableCharacter)
	local self = PlayerController
	do -- Handle custom controller logic.
		local manager: ControllerManager = self:WaitForInstance(">ControllerManager", character)
		if not manager then
			return
		end

		local groundController: GroundController = self:WaitForInstance("GroundController", character)
		if not groundController then
			return
		end

		local airController: AirController = self:WaitForInstance("AirController", character)
		if not airController then
			return
		end

		local groundSensor: ControllerPartSensor = self:WaitForInstance("ControllerPartSensor#GroundSensor", character)
		if not groundSensor then
			return
		end

		local jumpAnim: Animation = self:WaitForInstance("Animation#JumpAnim", character)
		if not jumpAnim then
			return
		end

		-- TODO: need to properly cleanup
		-- TODO: make more efficient
		-- TODO: need to fix this in TableEditor: `local view = TableEditor.View("Tracks", TableHelper.ArrayToSet(character.Humanoid.Animator:GetPlayingAnimationTracks()))`; it doesn't remove old keys
		local searchDistance = groundSensor.SearchDistance
		local params = RaycastParams.new()
		local jumpTrack = (CharacterHelper.GetAnimator(character, true) :: Animator):LoadAnimation(jumpAnim)
		jumpTrack.Priority = Enum.AnimationPriority.Action
		jumpTrack.Looped = false
		params:AddToFilter(character)
		RunService.Heartbeat:Connect(function()
			local origin = character.HumanoidRootPart.CFrame
			manager.MovingDirection = character.Humanoid.MoveDirection
			manager.UpDirection = origin.Position.Unit
			if character.Humanoid.MoveDirection.Magnitude > 0.1 then
				manager.FacingDirection = character.Humanoid.MoveDirection
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
	end

	do -- Handle custom camera (orbital, supports spherical planet).
		local MIN_ZOOM = 5
		local MAX_ZOOM = 100
		local ZOOM_STEP = 2
		local SENSITIVITY = Vector2.new(1, 1) * math.rad(0.5)
		local MIN_PITCH = math.rad(-80)
		local MAX_PITCH = math.rad(80)
		local HEAD_OFFSET = Vector3.new(0, 1.5, 0) -- offset from HumanoidRootPart to head

		local camera = CameraHelper.GetCamera()
		local zoomLevel = 16
		local pitch = 0 -- vertical angle (radians), 0 = horizon
		local yawDelta = 0 -- accumulated mouse yaw since last frame
		local pitchDelta = 0 -- accumulated mouse pitch since last frame

		-- Camera's own forward direction on the tangent plane (world space).
		-- Initialized from character look on first frame and then maintained independently.
		local cameraForward: Vector3? = nil

		CameraHelper.SetScriptable()

		-- Accumulate mouse/touch delta for camera rotation.
		local rotateConnection = UserInputService.InputChanged:Connect(function(input, gameProcessed)
			if
				input.UserInputType == Enum.UserInputType.MouseMovement
				and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
			then
				local delta = input.Delta
				yawDelta -= delta.X * SENSITIVITY.X
				pitchDelta -= delta.Y * SENSITIVITY.Y
			elseif input.UserInputType == Enum.UserInputType.Touch then
				local delta = input.Delta
				yawDelta -= delta.X * SENSITIVITY.X
				pitchDelta -= delta.Y * SENSITIVITY.Y
			end
		end)

		-- Zoom via scroll wheel.
		local zoomConnection = UserInputService.InputChanged:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseWheel then
				zoomLevel = math.clamp(zoomLevel - input.Position.Z * ZOOM_STEP, MIN_ZOOM, MAX_ZOOM)
			end
		end)

		-- Right-click hides cursor for look, like default camera.
		local mbDownConn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
			if gameProcessed then
				return
			end
			if input.UserInputType == Enum.UserInputType.MouseButton2 then
				UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
			end
		end)
		local mbUpConn = UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton2 then
				UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			end
		end)

		RunService.PreRender:Connect(function()
			if not character or not character.HumanoidRootPart then
				return
			end

			local rootCF = character.HumanoidRootPart.CFrame
			local up = rootCF.Position.Unit -- surface normal on a sphere centered at origin
			local focusPoint = rootCF.Position + rootCF:VectorToWorldSpace(HEAD_OFFSET)

			-- Initialize camera forward from character look on first frame.
			if not cameraForward then
				local charLook = rootCF.LookVector
				local proj = charLook - up * charLook:Dot(up)
				if proj.Magnitude < 0.001 then
					proj = Vector3.xAxis:Cross(up)
					if proj.Magnitude < 0.001 then
						proj = Vector3.zAxis:Cross(up)
					end
				end
				cameraForward = proj.Unit
			else
				-- Re-project onto current tangent plane (up changes as we walk on the sphere).
				local proj = cameraForward - up * cameraForward:Dot(up)
				if proj.Magnitude < 0.001 then
					proj = Vector3.xAxis:Cross(up)
					if proj.Magnitude < 0.001 then
						proj = Vector3.zAxis:Cross(up)
					end
				end
				cameraForward = proj.Unit
			end

			-- Apply yaw delta: rotate cameraForward around the surface normal.
			if yawDelta ~= 0 then
				cameraForward = CFrame.fromAxisAngle(up, yawDelta):VectorToWorldSpace(cameraForward)
				yawDelta = 0
			end

			-- Apply pitch delta.
			if pitchDelta ~= 0 then
				pitch = math.clamp(pitch + pitchDelta, MIN_PITCH, MAX_PITCH)
				pitchDelta = 0
			end

			-- Build camera frame from the independent forward direction.
			local right = cameraForward:Cross(up).Unit
			local refFrame = CFrame.fromMatrix(focusPoint, right, up)

			-- Apply pitch (tilt up/down). Yaw is already baked into cameraForward.
			local rotated = refFrame * CFrame.Angles(pitch, 0, 0)

			-- Place camera behind the focus point along the rotated look direction.
			local cameraPos = focusPoint - rotated.LookVector * zoomLevel
			camera.CFrame = CFrame.lookAt(cameraPos, focusPoint, up)
			camera.Focus = CFrame.new(focusPoint)
		end)
	end
end

return PlayerController
