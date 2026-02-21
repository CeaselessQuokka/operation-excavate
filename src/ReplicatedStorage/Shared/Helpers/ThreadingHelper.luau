--!strict
--- Services ---
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--- Imports ---
local Types = require(ReplicatedStorage.Shared.Types)

--- Types ---
export type Callback = (raceFinished: boolean) -> ()
export type CancelCallback = () -> ()
export type ConnectionLike = Types.ConnectionLike
export type Waitable<Params...> = () -> () | Types.SignalLike<Params...>

--- Variables ---
local TIME_BEFORE_WARN = 60 -- In seconds, how long to wait before warning for a nil timeout (only for unfinished races).

--- Threading Helper ---
local ThreadingHelper = {}

-- Returns true if there was a winner of the race, false if timed out.
-- Note: task.spawn/task.defer fixes the coroutine.resume issue where
-- errors may not be propagated correctly.
function ThreadingHelper.WaitForAny(timeout: number?, ...: Waitable<...any>): boolean
	local runningThread = coroutine.running()
	ThreadingHelper.WaitForAnyAsync(function(raceFinished: boolean)
		pcall(task.defer, runningThread, raceFinished)
	end, timeout, ...)
	return coroutine.yield()
end

-- Returns true if all signals were fired, false if timed out.
function ThreadingHelper.WaitForAll(timeout: number?, ...: Waitable<...any>): boolean
	local runningThread = coroutine.running()
	ThreadingHelper.WaitForAllAsync(function(raceFinished: boolean)
		pcall(task.defer, runningThread, raceFinished)
	end, timeout, ...)
	return coroutine.yield()
end

function ThreadingHelper.WaitForAnyAsync(callback: Callback, timeout: number?, ...: Waitable<...any>): CancelCallback?
	if not ... then
		callback(true)
		return nil
	end

	local connections: { ConnectionLike } = {}
	local timeoutThread: thread?
	local finished = false
	local function Finish(raceFinished: boolean)
		if not finished then
			finished = true
			if timeoutThread then
				pcall(task.cancel, timeoutThread)
			end
			for _, connection in connections do
				(connection :: any):Disconnect()
			end
			callback(raceFinished)
		end
	end
	if timeout then
		timeoutThread = task.delay(timeout, Finish, false)
	else
		local traceback = debug.traceback()
		timeoutThread = task.delay(TIME_BEFORE_WARN, function()
			if not finished then
				warn(
					`[{script.Name}] It has been {TIME_BEFORE_WARN} seconds since WaitForAnyAsync was called without a timeout; are you sure this is intended?\n\tTraceback: {traceback}`
				)
			end
		end)
	end
	for _, signal in { ... } do
		if typeof(signal) == "function" then
			task.defer(function()
				xpcall(signal, function(err)
					warn(debug.traceback(`[{script.Name}] Error in WaitForAnyAsync signal: {err}`))
				end)
				Finish(true)
			end)
		else
			table.insert(
				connections,
				(signal :: any):Connect(function()
					Finish(true)
				end)
			)
		end
	end
	return function(raceFinished: boolean?)
		Finish(raceFinished == true)
	end
end

function ThreadingHelper.WaitForAllAsync(callback: Callback, timeout: number?, ...: Waitable<...any>)
	local signals = { ... }
	if not signals[1] then
		callback(true)
		return
	end

	local connections: { ConnectionLike } = {}
	local timeoutThread: thread?
	local finished = false
	local completedCount = 0
	local totalCount = #signals
	local function Finish(raceFinished: boolean)
		if not finished then
			finished = true
			if timeoutThread then
				pcall(task.cancel, timeoutThread)
			end
			for _, connection in connections do
				(connection :: any):Disconnect()
			end
			callback(raceFinished)
		end
	end
	local function Increment()
		if not finished then
			completedCount += 1
			if completedCount >= totalCount then
				Finish(true)
			end
		end
	end
	if timeout then
		timeoutThread = task.delay(timeout, Finish, false)
	else
		local traceback = debug.traceback()
		timeoutThread = task.delay(TIME_BEFORE_WARN, function()
			if not finished then
				warn(
					`[{script.Name}] It has been {TIME_BEFORE_WARN} seconds since WaitForAllAsync was called without a timeout; are you sure this is intended?\n\tTraceback: {traceback}`
				)
			end
		end)
	end
	for _, signal in signals do
		if typeof(signal) == "function" then
			task.defer(function()
				signal()
				Increment()
			end)
		else
			table.insert(connections, (signal :: any):Connect(Increment))
		end
	end
end

-- Fires callback for each key/value pair in the table, deferred.
-- Returns true if all callbacks were executed, false if timed out.
function ThreadingHelper.WaitForEachDeferred<K, V>(
	tbl: { [K]: V },
	callback: (key: K, value: V) -> (),
	timeout: number?
): boolean
	if not timeout then
		for key, value in tbl do
			task.defer(callback, key, value)
		end
		return true
	end

	local runningThread = coroutine.running()
	local timeoutThread
	if timeout then
		timeoutThread = task.delay(timeout, pcall, task.defer, runningThread)
	end
	local tasks = 0
	for key, value in tbl do
		tasks += 1
		task.defer(function()
			local successful, err = (pcall :: any)(callback, key, value)
			if not successful then
				warn(debug.traceback(`[{script.Name}] Error in WaitForEachDeferred callback: {err}`))
			end
			tasks -= 1
			if tasks <= 0 then
				pcall(task.defer, runningThread)
				pcall(task.cancel, timeoutThread)
			end
		end)
	end
	coroutine.yield()
	return tasks == 0
end

function ThreadingHelper.Wrap(fn: (...any) -> ...any, ...): () -> ()
	if not ... then
		return fn
	end

	local args = table.pack(...)
	return function()
		fn(table.unpack(args))
	end
end

return table.freeze(ThreadingHelper)
