--!strict
--- Services ---
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

--- Types ---
export type SpringOptions = {
	SmoothTime: number?,
	MaxSpeed: number?,
	Threshold: number?,
	Sustained: boolean?, -- If true, will not stop the spring until manually cancelled, even if it reaches the target.
}

--- Variables ---
local DEFAULT_SMOOTH_TIME = 0.3
local DEFAULT_THRESHOLD = 0.001

--- Tween Helper ---
local TweenHelper = {}

function TweenHelper.TweenModelPivot(model: Model, to: CFrame, tweenInfo: TweenInfo)
	local runningThread = coroutine.running()
	TweenHelper.TweenModelPivotAsync(model, to, tweenInfo, function()
		task.spawn(runningThread)
	end)
	coroutine.yield()
end

function TweenHelper.TweenModelScaleTo(model: Model, to: number, tweenInfo: TweenInfo)
	local runningThread = coroutine.running()
	TweenHelper.TweenModelScaleToAsync(model, to, tweenInfo, function()
		task.spawn(runningThread)
	end)
	coroutine.yield()
end

-- Note: Does not support repeatCount, reverse, or delayTime.
function TweenHelper.TweenModelPivotAsync(
	model: Model,
	to: CFrame,
	tweenInfo: TweenInfo,
	onComplete: ((wasCancelled: boolean) -> ())?
): (moveToPosition: boolean?) -> ()
	local fromCFrame = model:GetPivot()
	local tweenConnection: RBXScriptConnection
	local duration = tweenInfo.Time
	local easingStyle = tweenInfo.EasingStyle
	local easingDirection = tweenInfo.EasingDirection
	local elapsedTime = 0
	tweenConnection = RunService.PreRender:Connect(function(dt)
		elapsedTime += dt
		local alpha = math.clamp(elapsedTime / duration, 0, 1)
		local easedAlpha = TweenService:GetValue(alpha, easingStyle, easingDirection)
		model:PivotTo(fromCFrame:Lerp(to, math.clamp(easedAlpha, 0, 1)))
		if alpha >= 1 then
			tweenConnection:Disconnect()
			if onComplete then
				task.defer(onComplete, false)
			end
		end
	end)
	return function(moveToPosition: boolean?)
		tweenConnection:Disconnect()
		if moveToPosition then
			model:PivotTo(to)
		end
		if onComplete then
			task.defer(onComplete, true)
		end
	end
end

function TweenHelper.TweenModelScaleToAsync(
	model: Model,
	to: number,
	tweenInfo: TweenInfo,
	onComplete: ((wasCancelled: boolean) -> ())?
): ()
	local from = model:GetScale()
	local tweenConnection: RBXScriptConnection
	local duration = tweenInfo.Time
	local easingStyle = tweenInfo.EasingStyle
	local easingDirection = tweenInfo.EasingDirection
	local elapsedTime = 0
	tweenConnection = RunService.PreRender:Connect(function(dt)
		elapsedTime += dt
		local alpha = math.clamp(elapsedTime / duration, 0, 1)
		local easedAlpha = TweenService:GetValue(alpha, easingStyle, easingDirection)
		model:ScaleTo(from + ((to - from) * math.clamp(easedAlpha, 0, 1)))
		if alpha >= 1 then
			tweenConnection:Disconnect()
			if onComplete then
				task.defer(onComplete, false)
			end
		end
	end)
	return function(moveToPosition: boolean?)
		tweenConnection:Disconnect()
		if moveToPosition then
			model:ScaleTo(to)
		end
		if onComplete then
			task.defer(onComplete, true)
		end
	end
end

function TweenHelper.SpringTo(instance: PVInstance, to: CFrame, options: SpringOptions?)
	local runningThread = coroutine.running()
	TweenHelper.SpringToAsync(instance, to, options, function()
		task.spawn(runningThread)
	end)
	coroutine.yield()
end

function TweenHelper.SpringToAsync(
	instance: PVInstance,
	to: CFrame,
	options: SpringOptions?,
	onComplete: ((wasCancelled: boolean) -> ())?
): ((moveToPosition: boolean?) -> (), (newTo: CFrame) -> ())
	local smoothTime = if options then options.SmoothTime or DEFAULT_SMOOTH_TIME else DEFAULT_SMOOTH_TIME
	local maxSpeed = if options then options.MaxSpeed else nil
	local threshold = if options then options.Threshold or DEFAULT_THRESHOLD else DEFAULT_THRESHOLD
	local sustained = if options then options.Sustained else false
	local maxTime = smoothTime * 10
	local velocity = CFrame.identity
	local elapsedTime = 0
	local springConnection: RBXScriptConnection
	springConnection = RunService.PreRender:Connect(function(dt)
		elapsedTime += dt
		local currentCFrame = instance:GetPivot()
		local newCFrame, newVelocity = TweenService:SmoothDamp(currentCFrame, to, velocity, smoothTime, maxSpeed, dt)
		instance:PivotTo(newCFrame)
		velocity = newVelocity
		if not sustained and (to:FuzzyEq(newCFrame, threshold) or elapsedTime >= maxTime) then
			instance:PivotTo(to)
			springConnection:Disconnect()
			if onComplete then
				task.defer(onComplete, false)
			end
		end
	end)
	return function(moveToPosition: boolean?)
		springConnection:Disconnect()
		if moveToPosition then
			instance:PivotTo(to)
		end
		if onComplete then
			task.defer(onComplete, true)
		end
	end, function(newTo: CFrame)
		to = newTo
	end
end

return table.freeze(TweenHelper)
