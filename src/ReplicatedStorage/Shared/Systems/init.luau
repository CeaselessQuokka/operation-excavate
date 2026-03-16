--!strict
--- Services ---
local RunService = game:GetService("RunService")

--- Types ---
export type SystemFunction = (dt: number) -> ()
export type Interval = number

--- Functions ---
local function WarnError(err: string)
	warn(`[{script.Name}] An error occurred in a system: {debug.traceback(err)}`)
end

--- System Scheduler ---
local SystemScheduler = {}
function SystemScheduler.Schedule(
	fn: SystemFunction, -- The function to run on the specified interval.
	interval: Interval?, -- Time in seconds (default 0; every frame) between each call to the system function. If not provided, defaults to every frame.
	block: boolean? -- Whether to block (default true) any subsequent calls to the system function until the previous one has finished.
): (SystemFunction, RBXScriptConnection)
	local connection: RBXScriptConnection
	local sanitizedInterval = interval or 0
	sanitizedInterval = if sanitizedInterval <= 1 / 60 then 0 else sanitizedInterval
	if sanitizedInterval == 0 then
		if block ~= false then
			local scheduledTask = task.spawn(function()
				while true do
					xpcall(fn, WarnError, task.wait())
				end
			end)
			connection = (
				{
					Disconnect = function()
						task.cancel(scheduledTask)
					end,
				} :: any
			) :: RBXScriptConnection
		else
			connection = RunService.Heartbeat:Connect(fn)
		end
	else
		local accumulatedTime = 0
		if block ~= false then
			local scheduledTask = task.spawn(function()
				while true do
					accumulatedTime += task.wait()
					if accumulatedTime >= sanitizedInterval then
						xpcall(fn, WarnError, accumulatedTime)
						accumulatedTime = 0
					end
				end
			end)
			connection = (
				{
					Disconnect = function()
						task.cancel(scheduledTask)
					end,
				} :: any
			) :: RBXScriptConnection
		else
			connection = RunService.Heartbeat:Connect(function(dt: number)
				accumulatedTime += dt
				if accumulatedTime >= sanitizedInterval then
					fn(accumulatedTime)
					accumulatedTime = 0
				end
			end)
		end
	end
	return fn, connection
end

return table.freeze(SystemScheduler)
