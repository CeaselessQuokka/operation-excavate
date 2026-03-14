--!strict
--- Services ---
local RunService = game:GetService("RunService")

--- Types ---
export type SystemFunction = (dt: number) -> ()
export type Interval = number

--- System Scheduler ---
local SystemScheduler = {}
function SystemScheduler.Schedule(fn: SystemFunction, interval: Interval?): (SystemFunction, RBXScriptConnection)
	local connection: RBXScriptConnection
	local sanitizedInterval = interval or 0
	sanitizedInterval = if sanitizedInterval <= 1 / 60 then 0 else sanitizedInterval
	if sanitizedInterval == 0 then
		connection = RunService.Heartbeat:Connect(fn)
	else
		local accumulatedTime = 0
		connection = RunService.Heartbeat:Connect(function(dt: number)
			accumulatedTime += dt
			if accumulatedTime >= sanitizedInterval then
				fn(accumulatedTime)
				accumulatedTime = 0
			end
		end)
	end
	return fn, connection
end

return table.freeze(SystemScheduler)
