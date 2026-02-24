--!strict
--- Services ---
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

--- Imports ---
local CharacterHelper = require(ReplicatedStorage.Modules.Helpers.CharacterHelper)

--- Types ---
export type TweenOptions = {
	Duration: number?,
	EasingStyle: Enum.EasingStyle?,
	EasingDirection: Enum.EasingDirection?,
	DelayTime: number?,
}

export type SpringOptions = {
	SmoothTime: number?,
	MaxSpeed: number?,
	Threshold: number?,
}

export type PathPoint = {
	CFrame: CFrame,
	Wait: number?,
	Mode: ("Tween" | "Spring")?,
	Duration: number?,
	EasingStyle: Enum.EasingStyle?,
	EasingDirection: Enum.EasingDirection?,
	SmoothTime: number?,
	MaxSpeed: number?,
	Threshold: number?,
}

export type ShakeOptions = {
	Duration: number?,
	Magnitude: number?,
	Frequency: number?,
	FadeIn: number?,
	FadeOut: number?,
	Seed: number?,
}

export type OrbitOptions = {
	Duration: number?,
	Radius: number?,
	Height: number?,
	Rotations: number?,
	StartAngle: number?,
	Clockwise: boolean?,
	EasingStyle: Enum.EasingStyle?,
	EasingDirection: Enum.EasingDirection?,
	LookAtCenter: boolean?,
}

export type BezierOptions = {
	Duration: number?,
	EasingStyle: Enum.EasingStyle?,
	EasingDirection: Enum.EasingDirection?,
	DelayTime: number?,
	LookAt: Vector3?,
	LookAhead: boolean?,
	LookAheadOffset: number?,
}

export type CleanupOptions = {
	RestoreCharacterCamera: boolean?,
	TransitionOptions: TweenOptions?,
}

export type FreecamOptions = {
	MoveSpeed: number?,
	FastMultiplier: number?,
	SlowMultiplier: number?,
	Sensitivity: number?,
	SmoothTime: number?,
	Keybind: Enum.KeyCode?,
}

export type CancelFunction = (cleanupOptions: CleanupOptions?) -> ()
type UsableCharacter = CharacterHelper.UsableCharacter

--- Variables ---
local DEFAULT_DURATION = 1
local DEFAULT_EASING_STYLE = Enum.EasingStyle.Quad
local DEFAULT_EASING_DIRECTION = Enum.EasingDirection.Out
local DEFAULT_SMOOTH_TIME = 0.3
local DEFAULT_SHAKE_MAGNITUDE = 0.5
local DEFAULT_SHAKE_FREQUENCY = 10
local DEFAULT_RESTORE_DURATION = 0.5

-- Freecam defaults
local DEFAULT_FREECAM_KEYBIND = Enum.KeyCode.F4
local DEFAULT_FREECAM_MOVE_SPEED = 50
local DEFAULT_FREECAM_FAST_MULTIPLIER = 3
local DEFAULT_FREECAM_SLOW_MULTIPLIER = 0.25
local DEFAULT_FREECAM_SENSITIVITY = 0.01
local DEFAULT_FREECAM_SMOOTH_TIME = 0.1

-- Freecam state
local freecamActive = false
local freecamConnection: RBXScriptConnection? = nil
local freecamKeybindConnection: RBXScriptConnection? = nil
local freecamMouseConnection: RBXScriptConnection? = nil
local freecamPreviousCameraType: Enum.CameraType? = nil
local freecamPreviousWalkSpeed: number? = nil
local freecamPreviousJumpPower: number? = nil
local freecamOptions: FreecamOptions = {}
local freecamVelocity = Vector3.zero
local freecamRightMouseDown = false

-- NESTED SCRIPTABLE PROTECTION
local scriptableDepth = 0
local originalCameraType: Enum.CameraType? = nil

local camera = Workspace.CurrentCamera or Workspace:GetPropertyChangedSignal("CurrentCamera"):Wait()
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	camera = Workspace.CurrentCamera
end)

--- Functions ---
local function GetCharacterCFrame(): CFrame?
	local player = Players.LocalPlayer

	local character: UsableCharacter = CharacterHelper.GetCharacter(player) :: any
	if not CharacterHelper.IsUsable(character) then
		return nil
	end

	local rootPart = character.HumanoidRootPart
	local head = if character then character:FindFirstChild("Head") :: BasePart? else nil
	local headPosition = if head then head.Position else rootPart.Position + Vector3.new(0, 2, 0)
	local offset = rootPart.CFrame.LookVector * -10 + Vector3.new(0, 3, 0)
	return CFrame.lookAt(headPosition + offset, headPosition)
end

local function GetHumanoid(): Humanoid?
	local player = Players.LocalPlayer
	local character = player and player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function RestoreCamera(previousType: Enum.CameraType, cleanupOptions: CleanupOptions?)
	-- Decrement depth and determine what type to restore
	scriptableDepth = math.max(0, scriptableDepth - 1)

	local typeToRestore: Enum.CameraType
	if scriptableDepth == 0 then
		-- We're fully unwound, use the original type we saved
		typeToRestore = originalCameraType or Enum.CameraType.Custom
		originalCameraType = nil
	else
		-- Still nested, don't actually restore camera yet
		return
	end

	-- Never restore to Scriptable - that would leave camera stuck
	if typeToRestore == Enum.CameraType.Scriptable then
		typeToRestore = Enum.CameraType.Custom
	end

	if cleanupOptions and cleanupOptions.RestoreCharacterCamera then
		local characterCFrame = GetCharacterCFrame()
		if characterCFrame then
			local transitionOpts = cleanupOptions.TransitionOptions
			local duration = if transitionOpts
				then transitionOpts.Duration or DEFAULT_RESTORE_DURATION
				else DEFAULT_RESTORE_DURATION
			local easingStyle = if transitionOpts
				then transitionOpts.EasingStyle or Enum.EasingStyle.Quad
				else Enum.EasingStyle.Quad
			local easingDirection = if transitionOpts
				then transitionOpts.EasingDirection or Enum.EasingDirection.Out
				else Enum.EasingDirection.Out
			local tweenInfo = TweenInfo.new(duration, easingStyle, easingDirection)
			local tween = TweenService:Create(camera, tweenInfo, { CFrame = characterCFrame })
			tween:Play()
			tween.Completed:Wait()
		end
	end

	-- CRITICAL FIX: Always restore CameraSubject to player's Humanoid
	local humanoid = GetHumanoid()
	if humanoid then
		camera.CameraSubject = humanoid
	end

	camera.CameraType = typeToRestore
end

local function SetScriptable(): Enum.CameraType
	local previousType = camera.CameraType

	-- Track the ORIGINAL type before any scriptable calls
	if scriptableDepth == 0 then
		originalCameraType = if previousType ~= Enum.CameraType.Scriptable then previousType else Enum.CameraType.Custom
	end
	scriptableDepth += 1

	camera.CameraType = Enum.CameraType.Scriptable
	return previousType
end

local function Lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function SafeLookAt(from: Vector3, to: Vector3, fallbackRotation: CFrame?): CFrame
	if (to - from).Magnitude < 0.001 then
		return CFrame.new(from) * (fallbackRotation or CFrame.identity)
	end
	return CFrame.lookAt(from, to)
end

local function EvaluateBezier(points: { Vector3 }, t: number): Vector3
	local n = #points
	if n == 1 then
		return points[1]
	end

	local newPoints = table.create(n - 1)
	for i = 1, n - 1 do
		newPoints[i] = points[i]:Lerp(points[i + 1], t)
	end
	return EvaluateBezier(newPoints, t)
end

local function CreateTweenInfo(options: TweenOptions?): TweenInfo
	if options then
		return TweenInfo.new(
			options.Duration or DEFAULT_DURATION,
			options.EasingStyle or DEFAULT_EASING_STYLE,
			options.EasingDirection or DEFAULT_EASING_DIRECTION,
			0,
			false,
			options.DelayTime or 0
		)
	else
		return TweenInfo.new(DEFAULT_DURATION, DEFAULT_EASING_STYLE, DEFAULT_EASING_DIRECTION)
	end
end

--- Camera Helper ---
local CameraHelper = {}

function CameraHelper.TweenTo(goal: CFrame, options: TweenOptions?): CancelFunction
	local runningThread = coroutine.running()
	local cancel = CameraHelper.TweenToAsync(goal, options, task.spawn, runningThread)
	coroutine.yield()
	return cancel
end

function CameraHelper.TweenToAsync(
	goal: CFrame,
	options: TweenOptions?,
	onComplete: ((...any) -> ())?,
	...
): CancelFunction
	local previousType = SetScriptable()
	local tweenInfo = CreateTweenInfo(options)
	local tween = TweenService:Create(camera, tweenInfo, { CFrame = goal })
	local args = { ... }
	tween:Play()
	tween.Completed:Once(function()
		if onComplete then
			onComplete(table.unpack(args))
		end
	end)
	return function(cleanupOptions: CleanupOptions?)
		tween:Cancel()
		RestoreCamera(previousType, cleanupOptions)
	end
end

function CameraHelper.TweenLookAt(target: Vector3, options: TweenOptions?): CancelFunction
	local runningThread = coroutine.running()
	local goal = SafeLookAt(camera.CFrame.Position, target, camera.CFrame.Rotation)
	local cancel = CameraHelper.TweenToAsync(goal, options, task.spawn, runningThread)
	coroutine.yield()
	return cancel
end

function CameraHelper.TweenLookAtAsync(
	target: Vector3,
	options: TweenOptions?,
	onComplete: ((...any) -> ())?,
	...
): CancelFunction
	local goal = SafeLookAt(camera.CFrame.Position, target, camera.CFrame.Rotation)
	return CameraHelper.TweenToAsync(goal, options, onComplete, ...)
end

function CameraHelper.TweenToLookAt(position: Vector3, lookAt: Vector3, options: TweenOptions?): CancelFunction
	local runningThread = coroutine.running()
	local goal = SafeLookAt(position, lookAt, camera.CFrame.Rotation)
	local cancel = CameraHelper.TweenToAsync(goal, options, task.spawn, runningThread)
	coroutine.yield()
	return cancel
end

function CameraHelper.TweenToLookAtAsync(
	position: Vector3,
	lookAt: Vector3,
	options: TweenOptions?,
	onComplete: ((...any) -> ())?,
	...
): CancelFunction
	local goal = SafeLookAt(position, lookAt, camera.CFrame.Rotation)
	return CameraHelper.TweenToAsync(goal, options, onComplete, ...)
end

function CameraHelper.TweenToWhileLookingAt(
	goalPosition: Vector3,
	lookAt: Vector3,
	options: TweenOptions?
): CancelFunction
	local runningThread = coroutine.running()
	local cancel = CameraHelper.TweenToWhileLookingAtAsync(goalPosition, lookAt, options, task.spawn, runningThread)
	coroutine.yield()
	return cancel
end

function CameraHelper.TweenToWhileLookingAtAsync(
	goalPosition: Vector3,
	lookAt: Vector3,
	options: TweenOptions?,
	onComplete: ((...any) -> ())?,
	...
): CancelFunction
	local duration = if options then math.max(options.Duration or DEFAULT_DURATION, 0.001) else DEFAULT_DURATION
	local easingStyle = if options then options.EasingStyle or DEFAULT_EASING_STYLE else DEFAULT_EASING_STYLE
	local easingDirection = if options
		then options.EasingDirection or DEFAULT_EASING_DIRECTION
		else DEFAULT_EASING_DIRECTION
	local delayTime = if options then options.DelayTime or 0 else 0

	local cam = camera
	local previousType = SetScriptable()
	local startPosition = cam.CFrame.Position
	local originalRotation = cam.CFrame.Rotation
	local elapsed = -delayTime
	local running = true
	local args = { ... }
	local connection: RBXScriptConnection

	connection = RunService.PreRender:Connect(function(dt)
		if not running then
			return
		end

		elapsed += dt
		if elapsed < 0 then
			return
		end

		local alpha = math.min(elapsed / duration, 1)
		local easedAlpha = TweenService:GetValue(alpha, easingStyle, easingDirection)
		local currentPosition = startPosition:Lerp(goalPosition, easedAlpha)
		cam.CFrame = SafeLookAt(currentPosition, lookAt, originalRotation)

		if elapsed >= duration then
			cam.CFrame = SafeLookAt(goalPosition, lookAt, originalRotation)
			running = false
			connection:Disconnect()
			if onComplete then
				onComplete(table.unpack(args))
			end
		end
	end)

	return function(cleanupOptions: CleanupOptions?)
		running = false
		connection:Disconnect()
		RestoreCamera(previousType, cleanupOptions)
	end
end

function CameraHelper.SpringTo(goal: CFrame, options: SpringOptions?): CancelFunction
	local runningThread = coroutine.running()
	local cancel = CameraHelper.SpringToAsync(goal, options, task.spawn, runningThread)
	coroutine.yield()
	return cancel
end

function CameraHelper.SpringToAsync(
	goal: CFrame,
	options: SpringOptions?,
	onComplete: ((...any) -> ())?,
	...
): CancelFunction
	local smoothTime = if options then options.SmoothTime or DEFAULT_SMOOTH_TIME else DEFAULT_SMOOTH_TIME
	local maxSpeed = if options then options.MaxSpeed else nil
	local threshold = if options then options.Threshold or 0.001 else 0.001
	local previousType = SetScriptable()
	local velocity = CFrame.identity
	local running = true
	local args = { ... }
	local elapsed = 0
	local maxTime = smoothTime * 10
	local connection: RBXScriptConnection
	connection = RunService.PreRender:Connect(function(dt)
		if not running then
			return
		end

		elapsed += dt
		local newCFrame, newVelocity = TweenService:SmoothDamp(camera.CFrame, goal, velocity, smoothTime, maxSpeed, dt)

		camera.CFrame = newCFrame
		velocity = newVelocity

		if goal:FuzzyEq(newCFrame, threshold) or elapsed >= maxTime then
			camera.CFrame = goal
			running = false
			connection:Disconnect()
			if onComplete then
				onComplete(table.unpack(args))
			end
		end
	end)
	return function(cleanupOptions: CleanupOptions?)
		running = false
		connection:Disconnect()
		RestoreCamera(previousType, cleanupOptions)
	end
end

function CameraHelper.SpringFollow(getTarget: () -> CFrame, options: SpringOptions?): CancelFunction
	local smoothTime = if options then options.SmoothTime or DEFAULT_SMOOTH_TIME else DEFAULT_SMOOTH_TIME
	local maxSpeed = if options then options.MaxSpeed else nil
	local previousType = SetScriptable()
	local velocity = CFrame.identity
	local running = true
	local connection: RBXScriptConnection
	connection = RunService.PreRender:Connect(function(dt)
		if not running then
			return
		end

		local goal = getTarget()
		if not goal then
			return
		end
		local newCFrame, newVelocity = TweenService:SmoothDamp(camera.CFrame, goal, velocity, smoothTime, maxSpeed, dt)
		camera.CFrame = newCFrame
		velocity = newVelocity
	end)
	return function(cleanupOptions: CleanupOptions?)
		running = false
		connection:Disconnect()
		RestoreCamera(previousType, cleanupOptions)
	end
end

function CameraHelper.FollowPath(points: { PathPoint }): CancelFunction
	local runningThread = coroutine.running()
	local cancel = CameraHelper.FollowPathAsync(points, task.spawn, runningThread)
	coroutine.yield()
	return cancel
end

function CameraHelper.FollowPathAsync(points: { PathPoint }, onComplete: ((...any) -> ())?, ...): CancelFunction
	assert(#points > 0, "Path must have at least one point")

	local previousType = SetScriptable()
	local cancelled = false
	local currentTween: Tween? = nil
	local currentConnection: RBXScriptConnection? = nil
	local args = { ... }
	task.spawn(function()
		for _, point in points do
			if cancelled then
				break
			end

			local mode = point.Mode or "Tween"
			if mode == "Spring" then
				local smoothTime = point.SmoothTime or DEFAULT_SMOOTH_TIME
				local maxSpeed = point.MaxSpeed
				local threshold = point.Threshold or 0.01
				local maxTime = smoothTime * 10
				local springElapsed = 0
				local velocity = CFrame.identity
				local arrived = false
				currentConnection = RunService.PreRender:Connect(function(dt)
					if cancelled or arrived then
						return
					end

					springElapsed += dt
					local newCFrame, newVelocity =
						TweenService:SmoothDamp(camera.CFrame, point.CFrame, velocity, smoothTime, maxSpeed, dt)
					camera.CFrame = newCFrame
					velocity = newVelocity
					if point.CFrame:FuzzyEq(newCFrame, threshold) or springElapsed >= maxTime then
						camera.CFrame = point.CFrame
						arrived = true
					end
				end)

				while not arrived and not cancelled do
					task.wait()
				end
				if currentConnection then
					currentConnection:Disconnect()
					currentConnection = nil
				end
			else
				local tweenInfo = TweenInfo.new(
					point.Duration or DEFAULT_DURATION,
					point.EasingStyle or DEFAULT_EASING_STYLE,
					point.EasingDirection or DEFAULT_EASING_DIRECTION
				)

				local tween = TweenService:Create(camera, tweenInfo, { CFrame = point.CFrame })
				currentTween = tween
				tween:Play()
				tween.Completed:Wait()
				currentTween = nil
			end
			if cancelled then
				break
			end

			if point.Wait and point.Wait > 0 then
				task.wait(point.Wait)
			end
		end
		if not cancelled and onComplete then
			onComplete(table.unpack(args))
		end
	end)
	return function(cleanupOptions: CleanupOptions?)
		cancelled = true
		if currentTween then
			currentTween:Cancel()
		end
		if currentConnection then
			currentConnection:Disconnect()
		end
		RestoreCamera(previousType, cleanupOptions)
	end
end

function CameraHelper.Shake(options: ShakeOptions?): CancelFunction
	local runningThread = coroutine.running()
	local cancel = CameraHelper.ShakeAsync(options, task.spawn, runningThread)
	coroutine.yield()
	return cancel
end

function CameraHelper.ShakeAsync(options: ShakeOptions?, onComplete: ((...any) -> ())?, ...): CancelFunction
	local duration = if options then math.max(options.Duration or 0.5, 0.001) else 0.5
	local magnitude = if options then options.Magnitude or DEFAULT_SHAKE_MAGNITUDE else DEFAULT_SHAKE_MAGNITUDE
	local frequency = if options then options.Frequency or DEFAULT_SHAKE_FREQUENCY else DEFAULT_SHAKE_FREQUENCY
	local fadeIn = if options then math.max(options.FadeIn or 0, 0) else 0
	local fadeOut = if options then math.max(options.FadeOut or duration * 0.3, 0) else duration * 0.3
	local seed = if options then options.Seed or os.clock() else os.clock()

	if fadeIn + fadeOut > duration then
		local scale = duration / (fadeIn + fadeOut)
		fadeIn = fadeIn * scale
		fadeOut = fadeOut * scale
	end
	local previousType = SetScriptable()
	local originalCFrame = camera.CFrame
	local elapsed = 0
	local running = true
	local args = { ... }
	local connection: RBXScriptConnection
	connection = RunService.PreRender:Connect(function(dt)
		if not running then
			return
		end

		elapsed += dt
		if elapsed >= duration then
			camera.CFrame = originalCFrame
			running = false
			connection:Disconnect()
			RestoreCamera(previousType) -- Restore camera type when shake completes naturally
			if onComplete then
				onComplete(table.unpack(args))
			end
			return
		end
		local intensity = 1
		if fadeIn > 0 and elapsed < fadeIn then
			intensity = elapsed / fadeIn
		elseif fadeOut > 0 and elapsed > (duration - fadeOut) then
			intensity = (duration - elapsed) / fadeOut
		end

		local time = (elapsed + seed) * frequency
		local offsetX = math.sin(time * 1.0) * math.cos(time * 0.7) * magnitude * intensity
		local offsetY = math.sin(time * 1.3) * math.cos(time * 0.9) * magnitude * intensity
		local offsetZ = math.sin(time * 0.8) * math.cos(time * 1.1) * magnitude * intensity * 0.5

		local rotX = math.sin(time * 1.2) * math.rad(magnitude * intensity)
		local rotY = math.sin(time * 0.9) * math.rad(magnitude * intensity * 0.5)
		local shakeOffset = CFrame.new(offsetX, offsetY, offsetZ) * CFrame.Angles(rotX, rotY, 0)
		camera.CFrame = originalCFrame * shakeOffset
	end)
	return function(cleanupOptions: CleanupOptions?)
		running = false
		connection:Disconnect()
		camera.CFrame = originalCFrame
		RestoreCamera(previousType, cleanupOptions)
	end
end

function CameraHelper.Orbit(center: Vector3, options: OrbitOptions?): CancelFunction
	local runningThread = coroutine.running()
	local cancel = CameraHelper.OrbitAsync(center, options, task.spawn, runningThread)
	coroutine.yield()
	return cancel
end

function CameraHelper.OrbitAsync(
	center: Vector3,
	options: OrbitOptions?,
	onComplete: ((...any) -> ())?,
	...
): CancelFunction
	local duration = if options then math.max(options.Duration or 3, 0.001) else 3
	local radius = if options then math.max(options.Radius or 10, 0.001) else 10
	local height = if options then options.Height or 5 else 5
	local rotations = if options then options.Rotations or 1 else 1
	local clockwise = if options then options.Clockwise else false
	local easingStyle = if options then options.EasingStyle or Enum.EasingStyle.Linear else Enum.EasingStyle.Linear
	local easingDirection = if options
		then options.EasingDirection or Enum.EasingDirection.InOut
		else Enum.EasingDirection.InOut
	local lookAtCenter = if options and options.LookAtCenter ~= nil then options.LookAtCenter else true

	local previousType = SetScriptable()

	local startAngle: number
	if options and options.StartAngle then
		startAngle = options.StartAngle
	else
		local startOffset = camera.CFrame.Position - center
		startAngle = math.atan2(startOffset.X, startOffset.Z)
	end

	local rotationAmount = math.pi * 2 * rotations
	local endAngle = if clockwise then startAngle - rotationAmount else startAngle + rotationAmount
	local originalRotation = camera.CFrame.Rotation
	local elapsed = 0
	local running = true
	local args = { ... }
	local connection: RBXScriptConnection
	connection = RunService.PreRender:Connect(function(dt)
		if not running then
			return
		end

		elapsed += dt
		if elapsed >= duration then
			local finalX = center.X + math.sin(endAngle) * radius
			local finalZ = center.Z + math.cos(endAngle) * radius
			local finalY = center.Y + height
			local finalPosition = Vector3.new(finalX, finalY, finalZ)
			camera.CFrame = if lookAtCenter
				then SafeLookAt(finalPosition, center, originalRotation)
				else CFrame.new(finalPosition) * originalRotation

			running = false
			connection:Disconnect()
			if onComplete then
				onComplete(table.unpack(args))
			end
			return
		end

		local alpha = elapsed / duration
		local easedAlpha = TweenService:GetValue(alpha, easingStyle, easingDirection)
		local angle = Lerp(startAngle, endAngle, easedAlpha)
		local x = center.X + math.sin(angle) * radius
		local z = center.Z + math.cos(angle) * radius
		local y = center.Y + height
		local position = Vector3.new(x, y, z)
		camera.CFrame = if lookAtCenter
			then SafeLookAt(position, center, originalRotation)
			else CFrame.new(position) * originalRotation
	end)

	return function(cleanupOptions: CleanupOptions?)
		running = false
		connection:Disconnect()
		RestoreCamera(previousType, cleanupOptions)
	end
end

function CameraHelper.FollowBezier(controlPoints: { Vector3 }, options: BezierOptions?): CancelFunction
	local runningThread = coroutine.running()
	local cancel = CameraHelper.FollowBezierAsync(controlPoints, options, task.spawn, runningThread)
	coroutine.yield()
	return cancel
end

function CameraHelper.FollowBezierAsync(
	controlPoints: { Vector3 },
	options: BezierOptions?,
	onComplete: ((...any) -> ())?,
	...
): CancelFunction
	assert(#controlPoints >= 2, "Bézier path must have at least 2 control points")

	local duration = if options then math.max(options.Duration or DEFAULT_DURATION, 0.001) else DEFAULT_DURATION
	local easingStyle = if options then options.EasingStyle or DEFAULT_EASING_STYLE else DEFAULT_EASING_STYLE
	local easingDirection = if options
		then options.EasingDirection or DEFAULT_EASING_DIRECTION
		else DEFAULT_EASING_DIRECTION
	local delayTime = if options then options.DelayTime or 0 else 0
	local lookAt = if options then options.LookAt else nil
	local lookAhead = if options then options.LookAhead else false
	local lookAheadOffset = if options then options.LookAheadOffset or 0.01 else 0.01

	local previousType = SetScriptable()
	local originalRotation = camera.CFrame.Rotation
	local finalPosition = controlPoints[#controlPoints]
	local elapsed = -delayTime
	local running = true
	local args = { ... }
	local connection: RBXScriptConnection
	connection = RunService.PreRender:Connect(function(dt)
		if not running then
			return
		end

		elapsed += dt
		if elapsed < 0 then
			return
		end

		local alpha = math.min(elapsed / duration, 1)
		local easedAlpha = TweenService:GetValue(alpha, easingStyle, easingDirection)
		local position = EvaluateBezier(controlPoints, easedAlpha)

		if lookAt then
			camera.CFrame = SafeLookAt(position, lookAt, originalRotation)
		elseif lookAhead then
			local aheadAlpha = math.min(easedAlpha + lookAheadOffset, 1)
			local aheadPosition = EvaluateBezier(controlPoints, aheadAlpha)
			camera.CFrame = SafeLookAt(position, aheadPosition, camera.CFrame.Rotation)
		else
			camera.CFrame = CFrame.new(position) * camera.CFrame.Rotation
		end

		if elapsed >= duration then
			if lookAt then
				camera.CFrame = SafeLookAt(finalPosition, lookAt, originalRotation)
			elseif lookAhead then
				camera.CFrame = CFrame.new(finalPosition) * camera.CFrame.Rotation
			else
				camera.CFrame = CFrame.new(finalPosition) * camera.CFrame.Rotation
			end
			running = false
			connection:Disconnect()
			if onComplete then
				onComplete(table.unpack(args))
			end
		end
	end)
	return function(cleanupOptions: CleanupOptions?)
		running = false
		connection:Disconnect()
		RestoreCamera(previousType, cleanupOptions)
	end
end

function CameraHelper.DollyZoom(
	target: CFrame,
	startFOV: number,
	endFOV: number,
	options: TweenOptions?
): CancelFunction
	local runningThread = coroutine.running()
	local cancel = CameraHelper.DollyZoomAsync(target, startFOV, endFOV, options, task.spawn, runningThread)
	coroutine.yield()
	return cancel
end

function CameraHelper.DollyZoomAsync(
	target: CFrame,
	startFOV: number,
	endFOV: number,
	options: TweenOptions?,
	onComplete: ((...any) -> ())?,
	...
): CancelFunction
	local duration = if options then math.max(options.Duration or DEFAULT_DURATION, 0.001) else DEFAULT_DURATION
	local easingStyle = if options then options.EasingStyle or DEFAULT_EASING_STYLE else DEFAULT_EASING_STYLE
	local easingDirection = if options
		then options.EasingDirection or DEFAULT_EASING_DIRECTION
		else DEFAULT_EASING_DIRECTION
	local delayTime = if options then options.DelayTime or 0 else 0
	local previousType = SetScriptable()
	local originalFOV = camera.FieldOfView
	local startCFrame = camera.CFrame

	local elapsed = -delayTime
	local running = true
	local args = { ... }
	local connection: RBXScriptConnection
	local hasStarted = false

	connection = RunService.PreRender:Connect(function(dt)
		if not running then
			return
		end

		elapsed += dt
		if elapsed < 0 then
			return
		end

		if not hasStarted then
			hasStarted = true
			camera.FieldOfView = startFOV
		end

		local alpha = math.min(elapsed / duration, 1)
		local easedAlpha = TweenService:GetValue(alpha, easingStyle, easingDirection)

		local currentCFrame = startCFrame:Lerp(target, easedAlpha)
		local currentFOV = Lerp(startFOV, endFOV, easedAlpha)

		camera.CFrame = currentCFrame
		camera.FieldOfView = currentFOV

		if elapsed >= duration then
			camera.CFrame = target
			camera.FieldOfView = endFOV
			running = false
			connection:Disconnect()
			if onComplete then
				onComplete(table.unpack(args))
			end
		end
	end)

	return function(cleanupOptions: CleanupOptions?)
		running = false
		connection:Disconnect()
		camera.FieldOfView = originalFOV
		RestoreCamera(previousType, cleanupOptions)
	end
end

function CameraHelper.Interpolate(
	startCFrame: CFrame,
	endCFrame: CFrame,
	duration: number,
	easingFunc: (alpha: number) -> number
): CancelFunction
	local runningThread = coroutine.running()
	local cancel =
		CameraHelper.InterpolateAsync(startCFrame, endCFrame, duration, easingFunc, task.spawn, runningThread)
	coroutine.yield()
	return cancel
end

function CameraHelper.InterpolateAsync(
	startCFrame: CFrame,
	endCFrame: CFrame,
	duration: number,
	easingFunc: (alpha: number) -> number,
	onComplete: ((...any) -> ())?,
	...
): CancelFunction
	local safeDuration = math.max(duration, 0.001)
	local previousType = SetScriptable()
	local elapsed = 0
	local running = true
	local args = { ... }
	local connection: RBXScriptConnection
	connection = RunService.PreRender:Connect(function(dt)
		if not running then
			return
		end

		elapsed += dt
		if elapsed >= safeDuration then
			camera.CFrame = endCFrame
			running = false
			connection:Disconnect()
			if onComplete then
				onComplete(table.unpack(args))
			end
			return
		end

		local alpha = elapsed / safeDuration
		local easedAlpha = easingFunc(alpha)
		camera.CFrame = startCFrame:Lerp(endCFrame, easedAlpha)
	end)

	return function(cleanupOptions: CleanupOptions?)
		running = false
		connection:Disconnect()
		RestoreCamera(previousType, cleanupOptions)
	end
end

function CameraHelper.SetScriptable(): CancelFunction
	local previousType = SetScriptable()
	return function(cleanupOptions: CleanupOptions?)
		RestoreCamera(previousType, cleanupOptions)
	end
end

function CameraHelper.GetCamera(): Camera
	return camera
end

function CameraHelper.GetCFrame(): CFrame
	return camera.CFrame
end

function CameraHelper.GetFOV(): number
	return camera.FieldOfView
end

function CameraHelper.SetFOV(fov: number)
	camera.FieldOfView = fov
end

function CameraHelper.GetOffsetCFrame(target: CFrame, offset: Vector3, lookAtTarget: boolean?): CFrame
	local position = (target * CFrame.new(offset)).Position
	if lookAtTarget == false then
		return CFrame.new(position)
	end
	return SafeLookAt(position, target.Position, target.Rotation)
end

function CameraHelper.SetCFrame(cframe: CFrame, offset: Vector3?, lookAtTarget: boolean?)
	camera.CFrame = if offset then CameraHelper.GetOffsetCFrame(cframe, offset, lookAtTarget) else cframe
end

function CameraHelper.LookAt(target: PVInstance | Vector3, from: Vector3?)
	local targetPosition: Vector3 = if typeof(target) == "Vector3"
		then target
		else (target :: PVInstance):GetPivot().Position
	local fromPosition = from or camera.CFrame.Position
	camera.CFrame = SafeLookAt(fromPosition, targetPosition, camera.CFrame.Rotation)
end

function CameraHelper.LookAtObject(object: PVInstance, offsetFromTarget: CFrame?, toOffset: CFrame?)
	local target = object:GetPivot()
	local from = if offsetFromTarget then (target * offsetFromTarget).Position else camera.CFrame.Position
	local to = if toOffset then (target * toOffset).Position else target.Position
	camera.CFrame = SafeLookAt(from, to, camera.CFrame.Rotation)
end

--[[
	Emergency camera recovery. Call this if camera gets stuck.
	Forces camera back to following the player's character.
]]
function CameraHelper.RecoverCamera()
	-- Reset depth tracking
	scriptableDepth = 0
	originalCameraType = nil

	-- Restore FOV to Roblox default
	camera.FieldOfView = 70

	local humanoid = GetHumanoid()
	if humanoid then
		camera.CameraSubject = humanoid
	end

	if camera.CameraType == Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Custom
	end

	warn("[CameraHelper] Camera recovered")
end

--[[
	Check if camera is currently in a scriptable state managed by CameraHelper.
]]
function CameraHelper.IsScriptableActive(): boolean
	return scriptableDepth > 0
end

--[[
	Get current scriptable depth (for debugging).
]]
function CameraHelper.GetScriptableDepth(): number
	return scriptableDepth
end

-- Internal function to update freecam each frame
local function UpdateFreecam(dt: number)
	if not freecamActive then
		return
	end

	local moveSpeed = freecamOptions.MoveSpeed or DEFAULT_FREECAM_MOVE_SPEED
	local fastMultiplier = freecamOptions.FastMultiplier or DEFAULT_FREECAM_FAST_MULTIPLIER
	local slowMultiplier = freecamOptions.SlowMultiplier or DEFAULT_FREECAM_SLOW_MULTIPLIER
	local sensitivity = freecamOptions.Sensitivity or DEFAULT_FREECAM_SENSITIVITY
	local smoothTime = freecamOptions.SmoothTime or DEFAULT_FREECAM_SMOOTH_TIME

	local speedMultiplier = 1
	if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift) then
		speedMultiplier = fastMultiplier
	elseif
		UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
	then
		speedMultiplier = slowMultiplier
	end

	local finalSpeed = moveSpeed * speedMultiplier

	local moveDirection = Vector3.zero
	if UserInputService:IsKeyDown(Enum.KeyCode.W) then
		moveDirection += Vector3.new(0, 0, -1)
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) then
		moveDirection += Vector3.new(0, 0, 1)
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.A) then
		moveDirection += Vector3.new(-1, 0, 0)
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) then
		moveDirection += Vector3.new(1, 0, 0)
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.E) or UserInputService:IsKeyDown(Enum.KeyCode.Space) then
		moveDirection += Vector3.new(0, 1, 0)
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.Q) or UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
		moveDirection += Vector3.new(0, -1, 0)
	end

	if moveDirection.Magnitude > 0 then
		moveDirection = moveDirection.Unit
	end

	local cameraRotation = camera.CFrame.Rotation
	local horizontalMove = cameraRotation * Vector3.new(moveDirection.X, 0, moveDirection.Z)
	local verticalMove = Vector3.new(0, moveDirection.Y, 0)
	local targetVelocity = (horizontalMove + verticalMove) * finalSpeed

	local alpha = math.min(1, dt / math.max(smoothTime, 0.001))
	freecamVelocity = freecamVelocity:Lerp(targetVelocity, alpha)

	camera.CFrame = camera.CFrame + freecamVelocity * dt

	if freecamRightMouseDown then
		local delta = UserInputService:GetMouseDelta()
		local rotY = -delta.X * sensitivity
		local rotX = -delta.Y * sensitivity

		local currentCFrame = camera.CFrame
		local lookVector = currentCFrame.LookVector
		local currentPitch = math.asin(math.clamp(lookVector.Y, -1, 1))

		local maxPitch = math.rad(89)
		local newPitch = math.clamp(currentPitch + rotX, -maxPitch, maxPitch)
		local clampedRotX = newPitch - currentPitch

		local yawRotation = CFrame.Angles(0, rotY, 0)
		local pitchRotation = CFrame.Angles(clampedRotX, 0, 0)

		local newRotation = yawRotation * currentCFrame.Rotation * pitchRotation
		camera.CFrame = CFrame.new(currentCFrame.Position) * newRotation
	end
end

local function OnFreecamInput(input: InputObject, gameProcessed: boolean)
	if not freecamActive then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		freecamRightMouseDown = true
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
	end
end

local function OnFreecamInputEnd(input: InputObject, gameProcessed: boolean)
	if not freecamActive then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		freecamRightMouseDown = false
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end
end

local function StartFreecam()
	if freecamActive then
		return
	end

	freecamActive = true
	freecamPreviousCameraType = camera.CameraType
	camera.CameraType = Enum.CameraType.Scriptable
	freecamVelocity = Vector3.zero
	freecamRightMouseDown = false

	local player = Players.LocalPlayer
	local character = player and player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		freecamPreviousWalkSpeed = humanoid.WalkSpeed
		freecamPreviousJumpPower = humanoid.JumpPower
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
	end

	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	freecamMouseConnection = UserInputService.InputBegan:Connect(OnFreecamInput)
	local inputEndConnection = UserInputService.InputEnded:Connect(OnFreecamInputEnd)

	freecamConnection = RunService.PreRender:Connect(UpdateFreecam)

	local oldMouseConnection = freecamMouseConnection
	freecamMouseConnection = {
		Disconnect = function()
			(oldMouseConnection :: RBXScriptConnection):Disconnect()
			inputEndConnection:Disconnect()
		end,
	} :: any

	print("[CameraHelper] Freecam enabled - Hold right mouse button to look around")
end

local function StopFreecam()
	if not freecamActive then
		return
	end

	freecamActive = false
	freecamRightMouseDown = false

	if freecamConnection then
		freecamConnection:Disconnect()
		freecamConnection = nil
	end

	if freecamMouseConnection then
		freecamMouseConnection:Disconnect()
		freecamMouseConnection = nil
	end

	if freecamPreviousCameraType then
		camera.CameraType = freecamPreviousCameraType
		freecamPreviousCameraType = nil
	end

	local player = Players.LocalPlayer
	local character = player and player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		if freecamPreviousWalkSpeed then
			humanoid.WalkSpeed = freecamPreviousWalkSpeed
			freecamPreviousWalkSpeed = nil
		end
		if freecamPreviousJumpPower then
			humanoid.JumpPower = freecamPreviousJumpPower
			freecamPreviousJumpPower = nil
		end
	end

	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	freecamVelocity = Vector3.zero

	print("[CameraHelper] Freecam disabled")
end

function CameraHelper.ToggleFreecam()
	if freecamActive then
		StopFreecam()
	else
		StartFreecam()
	end
end

function CameraHelper.EnableFreecam(options: FreecamOptions?)
	if options then
		freecamOptions = options
	end
	StartFreecam()
end

function CameraHelper.DisableFreecam()
	StopFreecam()
end

function CameraHelper.IsFreecamActive(): boolean
	return freecamActive
end

function CameraHelper.SetupFreecamKeybind(options: FreecamOptions?): () -> ()
	if options then
		freecamOptions = options
	end

	local keybind = (options and options.Keybind) or DEFAULT_FREECAM_KEYBIND

	if freecamKeybindConnection then
		freecamKeybindConnection:Disconnect()
	end

	freecamKeybindConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.KeyCode == keybind then
			CameraHelper.ToggleFreecam()
		end
	end)

	print(`[CameraHelper] Freecam keybind set to {keybind.Name}`)

	return function()
		if freecamKeybindConnection then
			freecamKeybindConnection:Disconnect()
			freecamKeybindConnection = nil
		end
		StopFreecam()
	end
end

function CameraHelper.SetFreecamOptions(options: FreecamOptions)
	freecamOptions = options
end

if RunService:IsStudio() then
	task.defer(CameraHelper.SetupFreecamKeybind)
end

return table.freeze(CameraHelper)
