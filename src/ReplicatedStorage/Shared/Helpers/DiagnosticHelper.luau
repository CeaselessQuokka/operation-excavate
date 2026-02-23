--!strict

--[[
	Diagnostic profiling utility for measuring code performance.

	Supports named timers with circular buffer sampling, counters,
	checkpoints, parent timer aggregation, memory tracking, and
	MicroProfiler integration.

	Client-side: Press F3 (configurable) to interactively select
	and print diagnostic breakdowns.
--]]

--- Services ---
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

--- Types ---
type TimeUnit = "s" | "ms" | "us" | "ns"

export type TimerData = {
	Durations: { number }, -- Circular buffer of durations (SoA for cache-friendly stats)
	Timestamps: { number }, -- Parallel buffer: os.clock() when each sample was recorded
	MemoryDeltas: { number }?, -- Parallel buffer: memory delta per sample (lazily allocated)
	WriteIndex: number, -- Next write position (1-based, wraps at MaxSamples)
	SampleCount: number, -- Number of valid entries in the buffer (capped at MaxSamples)
	TotalRecorded: number, -- Lifetime total samples recorded (never capped)
	ActiveStart: number?, -- os.clock() when StartTimer was called
	ActiveMemBefore: number?, -- Memory snapshot at start (when TrackMemory is on)
	UseProfiler: boolean?, -- Whether a profiler region is open for this timer
	AccumulatedTime: number?, -- Time accumulated before pause (for pause/resume)
	IsPaused: boolean?, -- Whether the timer is currently paused
	ParentTimer: string?, -- Name of parent timer to propagate durations into
	ReportOwnStats: boolean, -- Whether this timer appears in breakdowns (false = parent-only)
}

export type TimerStats = {
	Count: number,
	TotalTime: number,
	Average: number,
	Min: number,
	Max: number,
	Median: number,
	StdDev: number,
	Jitter: number,
	CoV: number,
	Percentiles: { [number]: number },
	SamplesPerSecond: number?,
	MemoryDelta: number?,
}

export type CheckpointData = {
	Name: string,
	Timestamp: number,
	Timers: { [string]: TimerStats },
	Counters: { [string]: number },
	TotalElapsedTime: number,
}

export type DiagnosticOptionKey =
	"Enabled"
	| "DecimalPlaces"
	| "TimeUnit"
	| "WarnThreshold"
	| "ErrorThreshold"
	| "MaxSamples"
	| "TrackMemory"
	| "AutoPrint"
	| "AutoPrintInterval"
	| "Percentiles"
	| "UseProfiler"

export type DiagnosticOptions = {
	Enabled: boolean?,
	DecimalPlaces: number?,
	TimeUnit: TimeUnit?,
	WarnThreshold: number?,
	ErrorThreshold: number?,
	MaxSamples: number?,
	TrackMemory: boolean?,
	AutoPrint: boolean?,
	AutoPrintInterval: number?,
	Percentiles: { number }?,
	UseProfiler: boolean?,
}

export type QuickBenchmarkStats = {
	Count: number,
	Total: number,
	Average: number,
	Median: number,
	Min: number,
	Max: number,
	StdDev: number,
	Jitter: number,
	CoV: number,
	P95: number,
	P99: number,
	P99_9: number,
}

export type Diagnostic = {
	Name: string,
	Options: DiagnosticOptions,
	Timers: { [string]: TimerData },
	Counters: { [string]: number },
	Checkpoints: { CheckpointData },
	StartTime: number,

	StartTimer: (self: Diagnostic, name: string, from: number?) -> (),
	StopTimer: (self: Diagnostic, name: string, recordTime: boolean?) -> number?,
	GetTimerAccumulation: (self: Diagnostic, name: string) -> number?,
	DropTimer: (self: Diagnostic, name: string) -> (),
	PauseTimer: (self: Diagnostic, name: string) -> number?,
	ResumeTimer: (self: Diagnostic, name: string) -> (),
	Time: <T...>(self: Diagnostic, name: string, fn: () -> T...) -> T...,
	RecordTime: (self: Diagnostic, name: string, duration: number) -> (),
	SetParentTimer: (self: Diagnostic, name: string, parentName: string?, reportOwnStats: boolean?) -> (),
	GetStats: (self: Diagnostic, name: string) -> TimerStats?,
	GetAllStats: (self: Diagnostic) -> { [string]: TimerStats },
	GetSampleCount: (self: Diagnostic, name: string) -> number,
	GetElapsedTime: (self: Diagnostic) -> number,
	Increment: (self: Diagnostic, name: string, amount: number?) -> number,
	Decrement: (self: Diagnostic, name: string, amount: number?) -> number,
	SetCounter: (self: Diagnostic, name: string, value: number) -> (),
	GetCounter: (self: Diagnostic, name: string) -> number,
	GetAllCounters: (self: Diagnostic) -> { [string]: number },
	ResetCounter: (self: Diagnostic, name: string) -> (),
	Checkpoint: (self: Diagnostic, checkpointName: string?) -> CheckpointData,
	GetCheckpoints: (self: Diagnostic) -> { CheckpointData },
	Reset: (self: Diagnostic) -> (),
	ResetTimer: (self: Diagnostic, name: string) -> (),
	PrintBreakdown: (self: Diagnostic, detailed: boolean?) -> (),
	PrintCheckpoint: (self: Diagnostic, checkpointIndex: number?, detailed: boolean?) -> (),
	SetOption: (self: Diagnostic, key: DiagnosticOptionKey, value: any) -> (),
	IsEnabled: (self: Diagnostic) -> boolean,
	Enable: (self: Diagnostic) -> (),
	Disable: (self: Diagnostic) -> (),
	Destroy: (self: Diagnostic) -> (),
}

--- Variables ---
local SCRIPT_NAME = script.Name

local DEFAULT_KEYBIND = Enum.KeyCode.F3
local currentKeybind: Enum.KeyCode = DEFAULT_KEYBIND

local DEFAULT_PERCENTILES = table.freeze({ 50, 90, 95, 99, 99.9 })
local DEFAULT_OPTIONS: DiagnosticOptions = table.freeze({
	Enabled = true,
	DecimalPlaces = 4,
	TimeUnit = "ms" :: "ms",
	WarnThreshold = nil,
	ErrorThreshold = nil,
	MaxSamples = 10000,
	TrackMemory = false,
	AutoPrint = false,
	AutoPrintInterval = 60,
	Percentiles = DEFAULT_PERCENTILES,
	UseProfiler = false,
})

local DEFAULT_TIME_UNIT: TimeUnit = DEFAULT_OPTIONS.TimeUnit :: TimeUnit
local DEFAULT_DECIMAL_PLACES: number = DEFAULT_OPTIONS.DecimalPlaces :: number
local DEFAULT_MAX_SAMPLES: number = DEFAULT_OPTIONS.MaxSamples :: number
local DEFAULT_AUTO_PRINT_INTERVAL: number = DEFAULT_OPTIONS.AutoPrintInterval :: number
local DEFAULT_BENCHMARK_ITERATIONS: number = 1000
local DEFAULT_SELECTION_TIMEOUT: number = 5
local FRAME_TIME_60FPS = 1 / 60

local SEPARATOR = string.rep("=", 60)
local DASH = string.rep("-", 58)
local DOT_MAX_WIDTH = 32

local TIME_UNIT_MULTIPLIERS = table.freeze({
	s = 1,
	ms = 1000,
	us = 1000000,
	ns = 1000000000,
})

local KEYCODE_TO_NUMBER: { [Enum.KeyCode]: number } = table.freeze({
	[Enum.KeyCode.Zero] = 0,
	[Enum.KeyCode.KeypadZero] = 0,
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.KeypadOne] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.KeypadTwo] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.KeypadThree] = 3,
	[Enum.KeyCode.Four] = 4,
	[Enum.KeyCode.KeypadFour] = 4,
	[Enum.KeyCode.Five] = 5,
	[Enum.KeyCode.KeypadFive] = 5,
	[Enum.KeyCode.Six] = 6,
	[Enum.KeyCode.KeypadSix] = 6,
	[Enum.KeyCode.Seven] = 7,
	[Enum.KeyCode.KeypadSeven] = 7,
	[Enum.KeyCode.Eight] = 8,
	[Enum.KeyCode.KeypadEight] = 8,
	[Enum.KeyCode.Nine] = 9,
	[Enum.KeyCode.KeypadNine] = 9,
})

local allDiagnostics: { [string]: Diagnostic } = {}
local isKeybindConnected = false
local keybindConnection: RBXScriptConnection? = nil
local activeSelectionConnection: RBXScriptConnection? = nil

--- Functions ---

-- Formatting --

local function FormatTime(seconds: number, unit: TimeUnit, dp: number): string
	local multiplier = TIME_UNIT_MULTIPLIERS[unit] or TIME_UNIT_MULTIPLIERS.ms
	return string.format("%." .. dp .. "f" .. unit, seconds * multiplier)
end

local function FormatMemory(bytes: number): string
	local abs = math.abs(bytes)
	local sign = if bytes < 0 then "-" else "+"
	if abs < 1024 then
		return string.format("%s%dB", sign, abs)
	elseif abs < 1048576 then
		return string.format("%s%.2fKB", sign, abs / 1024)
	else
		return string.format("%s%.2fMB", sign, abs / 1048576)
	end
end

local function FormatCallsPerFrame(duration: number): string
	if duration <= 0 then
		return "inf"
	end
	local calls = FRAME_TIME_60FPS / duration
	if calls >= 1000000 then
		return string.format("%.2fM", calls / 1000000)
	elseif calls >= 1000 then
		return string.format("%.2fK", calls / 1000)
	elseif calls >= 1 then
		return string.format("%.2f", calls)
	else
		return string.format("%.4f", calls)
	end
end

local function FormatBudgetPercent(duration: number): string
	if duration <= 0 then
		return "0.00%"
	end
	local percent = (duration / FRAME_TIME_60FPS) * 100
	if percent >= 100 then
		return string.format("%.1f%% (OVER BUDGET)", percent)
	elseif percent >= 50 then
		return string.format("%.1f%% (HIGH)", percent)
	else
		return string.format("%.2f%%", percent)
	end
end

local function FormatCounterLine(name: string, value: number): string
	local dotsNeeded = math.max(2, DOT_MAX_WIDTH - #name)
	return string.format("    %s %s %s", name, string.rep(".", dotsNeeded), tostring(value))
end

-- Memory --

local function GetMemoryUsage(): number
	return gcinfo() * 1024
end

-- Statistics --

local function CalculateMedian(sorted: { number }, count: number): number
	if count == 0 then
		return 0
	end
	if count == 1 then
		return sorted[1]
	end
	local mid = math.floor(count / 2)
	if count % 2 == 0 then
		return (sorted[mid] + sorted[mid + 1]) / 2
	end
	return sorted[mid + 1]
end

local function CalculatePercentile(sorted: { number }, count: number, p: number): number
	if count == 0 then
		return 0
	end
	local idx = math.ceil((p / 100) * count)
	return sorted[math.clamp(idx, 1, count)]
end

local function ComputeTimerStats(timer: TimerData, options: DiagnosticOptions): TimerStats
	local count = timer.SampleCount
	local percentilesList: { number } = (options.Percentiles or DEFAULT_PERCENTILES) :: { number }

	if count == 0 then
		local emptyPercentiles: { [number]: number } = {}
		for _, p in percentilesList do
			emptyPercentiles[p] = 0
		end
		return {
			Count = 0,
			TotalTime = 0,
			Average = 0,
			Min = 0,
			Max = 0,
			Median = 0,
			StdDev = 0,
			Jitter = 0,
			CoV = 0,
			Percentiles = emptyPercentiles,
			SamplesPerSecond = nil,
			MemoryDelta = nil,
		}
	end

	-- Single-pass extraction with running aggregates
	local durations = timer.Durations
	local sorted: { number } = table.create(count)
	local totalTime = 0
	local sumSquared = 0
	local minVal = math.huge
	local maxVal = 0

	for i = 1, count do
		local d = durations[i]
		sorted[i] = d
		totalTime += d
		sumSquared += d * d
		if d < minVal then
			minVal = d
		end
		if d > maxVal then
			maxVal = d
		end
	end

	table.sort(sorted)
	local average = totalTime / count

	-- Bessel-corrected variance from computational formula
	local variance = math.max(0, (sumSquared / count) - (average * average))
	local stdDev = if count > 1 then math.sqrt(variance * count / (count - 1)) else 0
	local jitter = maxVal - minVal
	local coV = if average > 0 then stdDev / average else 0

	local percentiles: { [number]: number } = {}
	for _, p in percentilesList do
		percentiles[p] = CalculatePercentile(sorted, count, p)
	end

	-- Rate from timestamps
	local timestamps = timer.Timestamps
	local earliest = math.huge
	local latest = 0
	for i = 1, count do
		local t = timestamps[i]
		if t < earliest then
			earliest = t
		end
		if t > latest then
			latest = t
		end
	end
	local span = latest - earliest

	-- Memory delta sum
	local memDelta: number? = nil
	if timer.MemoryDeltas then
		local sum = 0
		for i = 1, count do
			sum += timer.MemoryDeltas[i]
		end
		memDelta = sum
	end

	return {
		Count = count,
		TotalTime = totalTime,
		Average = average,
		Min = minVal,
		Max = maxVal,
		Median = CalculateMedian(sorted, count),
		StdDev = stdDev,
		Jitter = jitter,
		CoV = coV,
		Percentiles = percentiles,
		SamplesPerSecond = if span > 0 then count / span else nil,
		MemoryDelta = memDelta,
	}
end

-- Timer Internals --

local function CreateTimerData(shouldTrackMemory: boolean): TimerData
	return {
		Durations = {},
		Timestamps = {},
		MemoryDeltas = if shouldTrackMemory then {} else nil,
		WriteIndex = 1,
		SampleCount = 0,
		TotalRecorded = 0,
		ActiveStart = nil,
		ActiveMemBefore = nil,
		UseProfiler = nil,
		AccumulatedTime = nil,
		IsPaused = nil,
		ParentTimer = nil,
		ReportOwnStats = true,
	}
end

--[[
	Records a duration into a timer's circular buffer.
	Zero allocations: writes directly into SoA parallel arrays.
--]]
local function RecordDuration(
	timer: TimerData,
	duration: number,
	timestamp: number,
	memDelta: number?,
	maxSamples: number
)
	local idx = timer.WriteIndex
	timer.Durations[idx] = duration
	timer.Timestamps[idx] = timestamp
	if timer.MemoryDeltas then
		timer.MemoryDeltas[idx] = memDelta or 0
	end
	idx += 1
	if idx > maxSamples then
		idx = 1
	end
	timer.WriteIndex = idx
	if timer.SampleCount < maxSamples then
		timer.SampleCount += 1
	end
	timer.TotalRecorded += 1
end

-- Options --

local function ReconcileOptions(base: DiagnosticOptions, overrides: DiagnosticOptions?): DiagnosticOptions
	if not overrides then
		return table.clone(base)
	end

	local result = table.clone(base)
	for key, value in overrides :: any do
		(result :: any)[key] = value
	end

	if result.Percentiles then
		local valid: { number } = {}
		for _, p in result.Percentiles :: any do
			if typeof(p) == "number" and p >= 0 and p <= 100 then
				table.insert(valid, p)
			end
		end
		result.Percentiles = if #valid > 0 then table.freeze(valid) else DEFAULT_PERCENTILES
	end
	if result.MaxSamples and (typeof(result.MaxSamples) ~= "number" or result.MaxSamples < 1) then
		result.MaxSamples = DEFAULT_MAX_SAMPLES
	end
	if result.DecimalPlaces and (typeof(result.DecimalPlaces) ~= "number" or result.DecimalPlaces < 0) then
		result.DecimalPlaces = DEFAULT_DECIMAL_PLACES
	end
	if result.AutoPrintInterval and (typeof(result.AutoPrintInterval) ~= "number" or result.AutoPrintInterval <= 0) then
		result.AutoPrintInterval = DEFAULT_AUTO_PRINT_INTERVAL
	end
	if result.TimeUnit and not TIME_UNIT_MULTIPLIERS[result.TimeUnit] then
		result.TimeUnit = DEFAULT_TIME_UNIT
	end

	return result
end

-- Print Helpers --

--[[
	Appends detailed timer statistics to a string buffer for atomic printing.
--]]
local function WriteTimerStatsToBuffer(
	buf: { string },
	n: { n: number },
	name: string,
	stats: TimerStats,
	options: DiagnosticOptions,
	isActive: boolean?
)
	local unit: TimeUnit = options.TimeUnit or DEFAULT_TIME_UNIT
	local dp: number = options.DecimalPlaces or DEFAULT_DECIMAL_PLACES
	local function ft(s: number): string
		return FormatTime(s, unit, dp)
	end

	local header = if isActive then `  [{name}] (active)` else `  [{name}]`
	local i = n.n

	i += 1
	buf[i] = header
	i += 1
	buf[i] = string.format(
		"    %-10s%-8s %-10s%s",
		"Count:",
		tostring(stats.Count),
		"Total:",
		ft(stats.TotalTime)
			.. "  ("
			.. FormatBudgetPercent(stats.TotalTime)
			.. ", "
			.. FormatCallsPerFrame(stats.TotalTime)
			.. "/frame)"
	)
	i += 1
	buf[i] = string.format("    %-10s%-20s%-10s%s", "Average:", ft(stats.Average), "Median:", ft(stats.Median))
	i += 1
	buf[i] = string.format("    %-10s%-20s%-10s%s", "Min:", ft(stats.Min), "Max:", ft(stats.Max))
	i += 1
	buf[i] = string.format(
		"    %-10s%-20s%-10s%s",
		"Jitter:",
		ft(stats.Jitter),
		"CoV:",
		string.format("%.2f%%", stats.CoV * 100)
	)

	if stats.SamplesPerSecond then
		i += 1
		buf[i] = string.format(
			"    %-10s%-20s%-10s%s",
			"Std Dev:",
			ft(stats.StdDev),
			"Rate:",
			string.format("%.2f/sec", stats.SamplesPerSecond)
		)
	else
		i += 1
		buf[i] = string.format("    %-10s%s", "Std Dev:", ft(stats.StdDev))
	end

	if stats.MemoryDelta then
		i += 1
		buf[i] = `    Memory:   {FormatMemory(stats.MemoryDelta)} total delta`
	end

	-- Collect sorted percentile keys for reuse
	local pKeys: { number } = {}
	for p in stats.Percentiles do
		table.insert(pKeys, p)
	end
	table.sort(pKeys)

	-- Frame budget analysis
	i += 1
	buf[i] = "    -- Frame Budget (60 FPS) --"
	i += 1
	buf[i] = string.format(
		"    %-10s%-20s%-10s%s",
		"Avg:",
		FormatBudgetPercent(stats.Average),
		"Max:",
		FormatBudgetPercent(stats.Max)
	)
	if #pKeys > 0 then
		local budgetParts: { string } = {}
		for _, p in pKeys do
			table.insert(budgetParts, string.format("p%g: %s", p, FormatBudgetPercent(stats.Percentiles[p])))
		end
		i += 1
		buf[i] = "    " .. table.concat(budgetParts, "   ")
	end

	-- Calls per frame
	i += 1
	buf[i] = "    -- Calls/Frame (60 FPS) --"
	i += 1
	buf[i] = string.format(
		"    %-14s%-18s%-14s%-18s%-14s%s",
		"From Min:",
		FormatCallsPerFrame(stats.Min),
		"From Avg:",
		FormatCallsPerFrame(stats.Average),
		"From Max:",
		FormatCallsPerFrame(stats.Max)
	)
	if #pKeys > 0 then
		local cfParts: { string } = {}
		for _, p in pKeys do
			table.insert(cfParts, string.format("p%g: %s", p, FormatCallsPerFrame(stats.Percentiles[p])))
		end
		i += 1
		buf[i] = "    " .. table.concat(cfParts, "   ")
	end

	-- Percentiles
	if #pKeys > 0 then
		i += 1
		buf[i] = "    -- Percentiles --"
		local parts: { string } = table.create(#pKeys)
		for j, p in pKeys do
			parts[j] = string.format("p%g: %s", p, ft(stats.Percentiles[p]))
		end
		i += 1
		buf[i] = "    " .. table.concat(parts, "   ")
	end

	i += 1
	buf[i] = ""
	n.n = i
end

-- Keybind --

local function SetupKeybind()
	if isKeybindConnected then
		return
	end
	if not RunService:IsClient() then
		return
	end

	isKeybindConnected = true
	keybindConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or input.KeyCode ~= currentKeybind then
			return
		end

		if activeSelectionConnection then
			activeSelectionConnection:Disconnect()
			activeSelectionConnection = nil
		end

		local names: { string } = {}
		for diagName in allDiagnostics do
			table.insert(names, diagName)
		end
		table.sort(names)

		if not names[1] then
			print(`[{SCRIPT_NAME}] No diagnostics registered.`)
			return
		end

		-- Single diagnostic: print immediately
		if not names[2] then
			local diag = allDiagnostics[names[1]]
			if diag then
				diag:PrintBreakdown(true)
			end
			return
		end

		-- Multiple diagnostics: prompt selection
		local selBuf: { string } = {}
		local bi = 0
		bi += 1
		selBuf[bi] = `[{SCRIPT_NAME}] Available diagnostics:`
		for idx, diagName in names do
			local diag = allDiagnostics[diagName]
			local timerCount = 0
			if diag then
				for _ in diag.Timers do
					timerCount += 1
				end
			end
			bi += 1
			selBuf[bi] = `  [{idx}] {diagName} ({timerCount} timers, {#(diag and diag.Checkpoints or {})} checkpoints)`
		end
		bi += 1
		selBuf[bi] = `[{SCRIPT_NAME}] Press 1-9 to select, 0 for all, Escape to cancel.`
		print(table.concat(selBuf, "\n", 1, bi))

		local timeoutTask: thread? = nil
		local function cleanupSelection()
			if activeSelectionConnection then
				activeSelectionConnection:Disconnect()
				activeSelectionConnection = nil
			end
			if timeoutTask then
				task.cancel(timeoutTask)
				timeoutTask = nil
			end
		end

		activeSelectionConnection = UserInputService.InputBegan:Connect(function(selInput, _selGameProcessed)
			if selInput.KeyCode == Enum.KeyCode.Escape then
				print(`[{SCRIPT_NAME}] Selection cancelled.`)
				cleanupSelection()
				return
			end

			local keyNumber: number? = KEYCODE_TO_NUMBER[selInput.KeyCode]
			if keyNumber == nil then
				return
			end

			cleanupSelection()
			if keyNumber == 0 then
				for _, diagName in names do
					local diag = allDiagnostics[diagName]
					if diag then
						diag:PrintBreakdown(true)
					end
				end
			elseif keyNumber <= #names then
				local diag = allDiagnostics[names[keyNumber]]
				if diag then
					diag:PrintBreakdown(true)
				end
			else
				print(`[{SCRIPT_NAME}] Invalid selection: {keyNumber}`)
			end
		end)

		timeoutTask = task.delay(DEFAULT_SELECTION_TIMEOUT, function()
			if activeSelectionConnection and activeSelectionConnection.Connected then
				activeSelectionConnection:Disconnect()
				activeSelectionConnection = nil
			end
			timeoutTask = nil
		end)
	end)
end

--- Diagnostic Helper ---
local DiagnosticHelper = {}

function DiagnosticHelper.new(name: string, options: DiagnosticOptions?): Diagnostic
	assert(typeof(name) == "string" and #name > 0, "Diagnostic name must be a non-empty string")

	if allDiagnostics[name] then
		warn(`[{SCRIPT_NAME}] Diagnostic "{name}" already exists. Returning existing instance.`)
		return allDiagnostics[name]
	end

	local resolvedOptions = ReconcileOptions(DEFAULT_OPTIONS, options)
	local autoPrintTask: thread? = nil
	local trackMemory = resolvedOptions.TrackMemory == true

	local diagnostic: Diagnostic = {
		Name = name,
		Options = resolvedOptions,
		Timers = {},
		Counters = {},
		Checkpoints = {},
		StartTime = os.clock(),
	} :: any

	-- Timer Operations --

	--[[
		Starts a named timer. os.clock() is captured as the very last operation
		to minimize measurement overhead.

		@param from - Optional initial accumulation (seconds) for timer chaining.
		              Pass the result of a previous StopTimer to continue timing
		              across separate timer instances.
	--]]
	function diagnostic:StartTimer(timerName: string, from: number?)
		if not self.Options.Enabled then
			return
		end

		local timer = self.Timers[timerName]
		if not timer then
			timer = CreateTimerData(trackMemory)
			self.Timers[timerName] = timer
		end

		if timer.ActiveStart ~= nil then
			if timer.IsPaused then
				warn(`[{SCRIPT_NAME}] Timer "{timerName}" is paused. Call ResumeTimer instead.`)
			else
				warn(`[{SCRIPT_NAME}] Timer "{timerName}" is already running. Call StopTimer first.`)
			end
			return
		end

		if self.Options.TrackMemory then
			timer.ActiveMemBefore = GetMemoryUsage()
		end

		local useProfiler = self.Options.UseProfiler == true
		timer.UseProfiler = useProfiler
		if useProfiler then
			debug.profilebegin(timerName)
		end

		timer.AccumulatedTime = from or 0
		timer.IsPaused = false
		timer.ActiveStart = os.clock() -- Last: minimal overhead before measurement begins
	end

	--[[
		Stops a running timer and records the sample. os.clock() is captured as the
		very first operation to minimize measurement overhead.

		Returns the total duration (including accumulated pause time), or nil if the
		timer doesn't exist or isn't running. Duration is returned even when the
		diagnostic is disabled (for timer chaining), but the sample is not recorded.

		@param recordTime - When false, the final segment since last resume is excluded
		                    from the recorded duration (only accumulated pause time counts).
	--]]
	function diagnostic:StopTimer(timerName: string, recordTime: boolean?): number?
		local now = os.clock() -- First: capture time before any overhead
		local timer = self.Timers[timerName]
		if not timer then
			warn(`[{SCRIPT_NAME}] Timer "{timerName}" does not exist.`)
			return nil
		end

		if timer.ActiveStart == nil then
			warn(`[{SCRIPT_NAME}] Timer "{timerName}" is not running.`)
			return nil
		end

		if timer.UseProfiler then
			debug.profileend()
		end

		-- Calculate duration including any accumulated time from pause/resume cycles
		local segmentDuration = if timer.IsPaused or recordTime == false then 0 else (now - timer.ActiveStart)
		local accumulated = timer.AccumulatedTime or 0
		local duration = accumulated + segmentDuration

		-- Compute memory delta before clearing state
		local memDelta: number? = nil
		if self.Options.TrackMemory and timer.ActiveMemBefore then
			memDelta = GetMemoryUsage() - timer.ActiveMemBefore
		end

		-- Always clear active state (prevents stuck timers if Enabled toggles)
		timer.ActiveStart = nil
		timer.ActiveMemBefore = nil
		timer.UseProfiler = nil
		timer.AccumulatedTime = nil
		timer.IsPaused = nil

		if not self.Options.Enabled then
			return duration
		end

		local maxSamples: number = self.Options.MaxSamples or DEFAULT_MAX_SAMPLES

		-- Record to own buffer if reporting own stats
		if timer.ReportOwnStats then
			RecordDuration(timer, duration, now, memDelta, maxSamples)
		end

		-- Propagate to parent timer (one level)
		if timer.ParentTimer then
			local parent = self.Timers[timer.ParentTimer]
			if not parent then
				parent = CreateTimerData(self.Options.TrackMemory == true)
				self.Timers[timer.ParentTimer] = parent
			end
			RecordDuration(parent, duration, now, memDelta, maxSamples)
		end

		-- Threshold checks (only for timers that report own stats and have samples)
		if timer.ReportOwnStats and (self.Options.WarnThreshold or self.Options.ErrorThreshold) then
			local sampleCount = timer.SampleCount
			if sampleCount > 0 then
				local totalTime = 0
				for idx = 1, sampleCount do
					totalTime += timer.Durations[idx]
				end
				local average = totalTime / sampleCount

				local errorThreshold = self.Options.ErrorThreshold
				local warnThreshold = self.Options.WarnThreshold
				if errorThreshold and average > errorThreshold then
					warn(
						`[{SCRIPT_NAME}] ERROR: "{timerName}" avg ({string.format("%.4f", average * 1000)}ms)`
							.. ` exceeds error threshold ({string.format("%.4f", errorThreshold * 1000)}ms)`
					)
				elseif warnThreshold and average > warnThreshold then
					warn(
						`[{SCRIPT_NAME}] WARN: "{timerName}" avg ({string.format("%.4f", average * 1000)}ms)`
							.. ` exceeds warn threshold ({string.format("%.4f", warnThreshold * 1000)}ms)`
					)
				end
			end
		end

		return duration
	end

	--[[
		Returns accumulated time for an active timer without stopping it.
		Returns nil if the timer doesn't exist or isn't running.
	--]]
	function diagnostic:GetTimerAccumulation(timerName: string): number?
		local now = os.clock()
		local timer = self.Timers[timerName]
		if not timer or timer.ActiveStart == nil then
			return nil
		end

		local segment = if timer.IsPaused then 0 else (now - timer.ActiveStart)
		return (timer.AccumulatedTime or 0) + segment
	end

	--[[
		Completely removes a timer and all its data.
		Cleans up any active profiler region.
	--]]
	function diagnostic:DropTimer(timerName: string)
		local timer = self.Timers[timerName]
		if not timer then
			return
		end

		if timer.ActiveStart and timer.UseProfiler then
			debug.profileend()
		end
		self.Timers[timerName] = nil
	end

	--[[
		Pauses a running timer, preserving accumulated time.
		Returns accumulated time so far, or nil if not running.
	--]]
	function diagnostic:PauseTimer(timerName: string): number?
		local now = os.clock() -- First: capture time before overhead
		local timer = self.Timers[timerName]
		if not timer then
			warn(`[{SCRIPT_NAME}] Timer "{timerName}" does not exist.`)
			return nil
		end

		if timer.ActiveStart == nil then
			warn(`[{SCRIPT_NAME}] Timer "{timerName}" is not running.`)
			return nil
		end

		if timer.IsPaused then
			return timer.AccumulatedTime
		end

		if timer.UseProfiler then
			debug.profileend()
		end

		local segment = now - timer.ActiveStart
		local accumulated = (timer.AccumulatedTime or 0) + segment
		timer.AccumulatedTime = accumulated
		timer.IsPaused = true
		return accumulated
	end

	--[[
		Resumes a paused timer. os.clock() is captured last.
	--]]
	function diagnostic:ResumeTimer(timerName: string)
		local timer = self.Timers[timerName]
		if not timer then
			warn(`[{SCRIPT_NAME}] Timer "{timerName}" does not exist.`)
			return
		end

		if timer.ActiveStart == nil then
			warn(`[{SCRIPT_NAME}] Timer "{timerName}" is not running.`)
			return
		end

		if not timer.IsPaused then
			warn(`[{SCRIPT_NAME}] Timer "{timerName}" is not paused.`)
			return
		end

		if timer.UseProfiler then
			debug.profilebegin(timerName)
		end
		if self.Options.TrackMemory then
			timer.ActiveMemBefore = GetMemoryUsage()
		end

		timer.IsPaused = false
		timer.ActiveStart = os.clock() -- Last: minimal overhead before measurement resumes
	end

	--[[
		Times a synchronous function. Stops the timer even if the function errors,
		then re-throws the error with preserved stack trace.
	--]]
	function diagnostic:Time<T...>(timerName: string, fn: () -> T...): T...
		if not self.Options.Enabled then
			return fn()
		end

		self:StartTimer(timerName)
		local results = table.pack(xpcall(fn, debug.traceback))
		self:StopTimer(timerName)

		if not results[1] then
			error(results[2], 0)
		end
		return table.unpack(results :: any, 2, results.n)
	end

	--[[
		Records a pre-measured duration directly without using StartTimer/StopTimer.
		Useful for timing measured externally or from third-party APIs.
	--]]
	function diagnostic:RecordTime(timerName: string, duration: number)
		local now = os.clock()
		if not self.Options.Enabled then
			return
		end

		if duration < 0 then
			warn(`[{SCRIPT_NAME}] RecordTime: negative duration {duration}`)
			return
		end

		local timer = self.Timers[timerName]
		if not timer then
			timer = CreateTimerData(self.Options.TrackMemory == true)
			self.Timers[timerName] = timer
		end

		local maxSamples: number = self.Options.MaxSamples or DEFAULT_MAX_SAMPLES

		if timer.ReportOwnStats then
			RecordDuration(timer, duration, now, nil, maxSamples)
		end

		if timer.ParentTimer then
			local parent = self.Timers[timer.ParentTimer]
			if not parent then
				parent = CreateTimerData(self.Options.TrackMemory == true)
				self.Timers[timer.ParentTimer] = parent
			end
			RecordDuration(parent, duration, now, nil, maxSamples)
		end
	end

	--[[
		Sets a parent timer for aggregation. When the child stops, its duration is
		also recorded to the parent's buffer (one level only).

		@param reportOwnStats - When false (default when parent is set), the child
		                        timer is hidden from breakdowns. Set true for dual reporting.
	--]]
	function diagnostic:SetParentTimer(timerName: string, parentName: string?, reportOwnStats: boolean?)
		if parentName == timerName then
			warn(`[{SCRIPT_NAME}] Cannot set timer "{timerName}" as its own parent.`)
			return
		end

		-- Walk the parent chain to detect circular references
		if parentName then
			local visited: { [string]: boolean } = { [timerName] = true }
			local current: string? = parentName
			local depth = 0
			while current and depth < 100 do
				if visited[current] then
					warn(`[{SCRIPT_NAME}] Circular parent reference: "{timerName}" -> "{current}".`)
					return
				end
				visited[current] = true
				local parentTimer = self.Timers[current]
				current = if parentTimer then parentTimer.ParentTimer else nil
				depth += 1
			end
		end

		local timer = self.Timers[timerName]
		if not timer then
			timer = CreateTimerData(self.Options.TrackMemory == true)
			self.Timers[timerName] = timer
		end

		timer.ParentTimer = parentName
		timer.ReportOwnStats = if parentName then (reportOwnStats == true) else true
	end

	-- Stats Queries --

	function diagnostic:GetStats(timerName: string): TimerStats?
		local timer = self.Timers[timerName]
		if not timer or not timer.ReportOwnStats then
			return nil
		end
		return ComputeTimerStats(timer, self.Options)
	end

	function diagnostic:GetAllStats(): { [string]: TimerStats }
		local allStats: { [string]: TimerStats } = {}
		for timerName, timer in self.Timers do
			if timer.ReportOwnStats then
				allStats[timerName] = ComputeTimerStats(timer, self.Options)
			end
		end
		return allStats
	end

	function diagnostic:GetSampleCount(timerName: string): number
		local timer = self.Timers[timerName]
		return if timer then timer.SampleCount else 0
	end

	function diagnostic:GetElapsedTime(): number
		return os.clock() - self.StartTime
	end

	-- Counter Operations --

	function diagnostic:Increment(counterName: string, amount: number?): number
		local newValue = (self.Counters[counterName] or 0) + (amount or 1)
		self.Counters[counterName] = newValue
		return newValue
	end

	function diagnostic:Decrement(counterName: string, amount: number?): number
		local newValue = (self.Counters[counterName] or 0) - (amount or 1)
		self.Counters[counterName] = newValue
		return newValue
	end

	function diagnostic:SetCounter(counterName: string, value: number)
		self.Counters[counterName] = value
	end

	function diagnostic:GetCounter(counterName: string): number
		return self.Counters[counterName] or 0
	end

	function diagnostic:GetAllCounters(): { [string]: number }
		return table.clone(self.Counters)
	end

	function diagnostic:ResetCounter(counterName: string)
		self.Counters[counterName] = nil
	end

	-- Checkpoints --

	--[[
		Captures a snapshot of all timer stats and counters, then resets them.
		Active timers preserve their running state. Parent relationships are preserved.
	--]]
	function diagnostic:Checkpoint(checkpointName: string?): CheckpointData
		local now = os.clock()
		local resolvedName = checkpointName or `Checkpoint_{#self.Checkpoints + 1}`

		-- Compute stats snapshot
		local timerStats: { [string]: TimerStats } = {}
		for timerName, timer in self.Timers do
			if timer.ReportOwnStats then
				timerStats[timerName] = ComputeTimerStats(timer, self.Options)
			end
		end

		local checkpoint: CheckpointData = {
			Name = resolvedName,
			Timestamp = now,
			Timers = timerStats,
			Counters = table.clone(self.Counters),
			TotalElapsedTime = now - self.StartTime,
		}
		table.insert(self.Checkpoints, checkpoint)

		-- Reset timers but preserve hierarchy and active state
		for timerName, oldTimer in self.Timers do
			local newTimer = CreateTimerData(self.Options.TrackMemory == true)
			newTimer.ParentTimer = oldTimer.ParentTimer
			newTimer.ReportOwnStats = oldTimer.ReportOwnStats

			if oldTimer.ActiveStart then
				newTimer.ActiveStart = oldTimer.ActiveStart
				newTimer.ActiveMemBefore = oldTimer.ActiveMemBefore
				newTimer.UseProfiler = oldTimer.UseProfiler
				newTimer.AccumulatedTime = oldTimer.AccumulatedTime
				newTimer.IsPaused = oldTimer.IsPaused
			end

			self.Timers[timerName] = newTimer
		end

		self.Counters = {}
		self.StartTime = now
		return checkpoint
	end

	function diagnostic:GetCheckpoints(): { CheckpointData }
		return table.clone(self.Checkpoints)
	end

	-- Lifecycle --

	function diagnostic:Reset()
		for _, timer in self.Timers do
			if timer.ActiveStart and timer.UseProfiler then
				debug.profileend()
			end
		end
		self.Timers = {}
		self.Counters = {}
		self.Checkpoints = {}
		self.StartTime = os.clock()
	end

	--[[
		Clears recorded samples for a timer while preserving parent relationships.
		Warns if the timer is currently running.
	--]]
	function diagnostic:ResetTimer(timerName: string)
		local existing = self.Timers[timerName]

		if existing and existing.ActiveStart then
			warn(`[{SCRIPT_NAME}] Resetting timer "{timerName}" while running.`)
			if existing.UseProfiler then
				debug.profileend()
			end
		end

		local parentTimer = existing and existing.ParentTimer or nil
		local reportOwnStats = if existing then existing.ReportOwnStats else true

		local newTimer = CreateTimerData(self.Options.TrackMemory == true)
		newTimer.ParentTimer = parentTimer
		newTimer.ReportOwnStats = reportOwnStats
		self.Timers[timerName] = newTimer
	end

	-- Output --

	--[[
		Prints a formatted diagnostic breakdown using buffered output.
		Detailed mode shows full stats per timer with frame budget analysis.
		Compact mode shows a one-line-per-timer summary.
	--]]
	function diagnostic:PrintBreakdown(detailed: boolean?)
		local unit: TimeUnit = self.Options.TimeUnit or DEFAULT_TIME_UNIT
		local dp: number = self.Options.DecimalPlaces or DEFAULT_DECIMAL_PLACES

		local buf: { string } = {}
		local n = { n = 0 }
		local i = n.n

		i += 1
		buf[i] = ""
		i += 1
		buf[i] = SEPARATOR

		if detailed then
			i += 1
			buf[i] = `  DIAGNOSTIC: {self.Name}`
			i += 1
			buf[i] =
				`  Elapsed: {FormatTime(os.clock() - self.StartTime, unit, dp)}  |  Checkpoints: {#self.Checkpoints}`
		else
			i += 1
			buf[i] = `  DIAGNOSTIC: {self.Name}  ({FormatTime(os.clock() - self.StartTime, unit, dp)} elapsed)`
		end

		i += 1
		buf[i] = SEPARATOR

		-- Counters
		local counterNames: { string } = {}
		for counterName in self.Counters do
			table.insert(counterNames, counterName)
		end
		table.sort(counterNames)

		if counterNames[1] then
			if detailed or #counterNames > 3 then
				i += 1
				buf[i] = ""
				i += 1
				buf[i] = "  COUNTERS"
				i += 1
				buf[i] = "  " .. DASH
				for _, counterName in counterNames do
					i += 1
					buf[i] = FormatCounterLine(counterName, self.Counters[counterName])
				end
			else
				local parts: { string } = table.create(#counterNames)
				for j, counterName in counterNames do
					parts[j] = `{counterName}={self.Counters[counterName]}`
				end
				i += 1
				buf[i] = "  Counters: " .. table.concat(parts, ", ")
			end
		end

		-- Timers
		local timerNames: { string } = {}
		for timerName, timer in self.Timers do
			if timer.ReportOwnStats then
				table.insert(timerNames, timerName)
			end
		end
		table.sort(timerNames)

		if not timerNames[1] then
			i += 1
			buf[i] = ""
			i += 1
			buf[i] = "  (No timers recorded)"
		else
			i += 1
			buf[i] = ""
			i += 1
			buf[i] = `  TIMERS ({#timerNames} timer{if #timerNames == 1 then "" else "s"})`
			i += 1
			buf[i] = "  " .. DASH

			for _, timerName in timerNames do
				local timer = self.Timers[timerName]
				local stats = ComputeTimerStats(timer, self.Options)
				local isActive = timer.ActiveStart ~= nil

				if detailed then
					n.n = i
					WriteTimerStatsToBuffer(buf, n, timerName, stats, self.Options, isActive)
					i = n.n
				else
					local activeTag = if isActive then " *" else ""
					i += 1
					buf[i] = string.format(
						"    %-24s avg %-14s cnt %-6d min %-14s max %-14s ~%s/frame%s",
						timerName,
						FormatTime(stats.Average, unit, dp),
						stats.Count,
						FormatTime(stats.Min, unit, dp),
						FormatTime(stats.Max, unit, dp),
						FormatCallsPerFrame(stats.Average),
						activeTag
					)
				end
			end
		end

		i += 1
		buf[i] = SEPARATOR
		i += 1
		buf[i] = ""

		print(table.concat(buf, "\n", 1, i))
	end

	function diagnostic:PrintCheckpoint(checkpointIndex: number?, detailed: boolean?)
		local index = checkpointIndex or #self.Checkpoints
		if index < 1 or not self.Checkpoints[index] then
			warn(`[{SCRIPT_NAME}] No checkpoint at index {index}.`)
			return
		end

		local checkpoint = self.Checkpoints[index]
		local unit: TimeUnit = self.Options.TimeUnit or DEFAULT_TIME_UNIT
		local dp: number = self.Options.DecimalPlaces or DEFAULT_DECIMAL_PLACES

		local buf: { string } = {}
		local n = { n = 0 }
		local i = n.n

		i += 1
		buf[i] = ""
		i += 1
		buf[i] = SEPARATOR
		i += 1
		buf[i] = `  CHECKPOINT: {checkpoint.Name}`
		i += 1
		buf[i] = `  Elapsed: {FormatTime(checkpoint.TotalElapsedTime, unit, dp)}`
		i += 1
		buf[i] = SEPARATOR

		-- Counters
		local counterNames: { string } = {}
		for counterName in checkpoint.Counters do
			table.insert(counterNames, counterName)
		end
		table.sort(counterNames)

		if counterNames[1] then
			i += 1
			buf[i] = ""
			i += 1
			buf[i] = "  COUNTERS"
			i += 1
			buf[i] = "  " .. DASH
			for _, counterName in counterNames do
				i += 1
				buf[i] = FormatCounterLine(counterName, checkpoint.Counters[counterName])
			end
		end

		-- Timers
		local timerNames: { string } = {}
		for timerName in checkpoint.Timers do
			table.insert(timerNames, timerName)
		end
		table.sort(timerNames)

		if not timerNames[1] then
			i += 1
			buf[i] = ""
			i += 1
			buf[i] = "  (No timers in checkpoint)"
		else
			i += 1
			buf[i] = ""
			i += 1
			buf[i] = `  TIMERS ({#timerNames} timer{if #timerNames == 1 then "" else "s"})`
			i += 1
			buf[i] = "  " .. DASH

			for _, timerName in timerNames do
				local stats = checkpoint.Timers[timerName]
				if detailed then
					n.n = i
					WriteTimerStatsToBuffer(buf, n, timerName, stats, self.Options, false)
					i = n.n
				else
					i += 1
					buf[i] = string.format(
						"    %-24s avg %-14s cnt %-6d min %-14s max %s",
						timerName,
						FormatTime(stats.Average, unit, dp),
						stats.Count,
						FormatTime(stats.Min, unit, dp),
						FormatTime(stats.Max, unit, dp)
					)
				end
			end
		end

		i += 1
		buf[i] = SEPARATOR
		i += 1
		buf[i] = ""

		print(table.concat(buf, "\n", 1, i))
	end

	-- Configuration --

	function diagnostic:SetOption(key: DiagnosticOptionKey, value: any)
		if key == "MaxSamples" then
			if typeof(value) ~= "number" or value < 1 then
				warn(`[{SCRIPT_NAME}] Invalid MaxSamples: {value}. Must be >= 1.`)
				return
			end
			-- Cap existing timer sample counts to new limit
			for _, timer in self.Timers do
				if timer.SampleCount > value then
					timer.SampleCount = value
				end
				if timer.WriteIndex > value then
					timer.WriteIndex = 1
				end
			end
		elseif key == "Percentiles" then
			if typeof(value) ~= "table" then
				warn(`[{SCRIPT_NAME}] Invalid Percentiles: must be a table.`)
				return
			end
			for _, p in value :: any do
				if typeof(p) ~= "number" or p < 0 or p > 100 then
					warn(`[{SCRIPT_NAME}] Invalid percentile: {p}. Must be 0-100.`)
					return
				end
			end
		elseif key == "DecimalPlaces" then
			if typeof(value) ~= "number" or value < 0 then
				warn(`[{SCRIPT_NAME}] Invalid DecimalPlaces: {value}. Must be >= 0.`)
				return
			end
		elseif key == "TimeUnit" then
			if not TIME_UNIT_MULTIPLIERS[value] then
				warn(`[{SCRIPT_NAME}] Invalid TimeUnit: {value}. Use "s", "ms", "us", or "ns".`)
				return
			end
		elseif key == "AutoPrintInterval" then
			if typeof(value) ~= "number" or value <= 0 then
				warn(`[{SCRIPT_NAME}] Invalid AutoPrintInterval: {value}. Must be > 0.`)
				return
			end
		elseif key == "WarnThreshold" or key == "ErrorThreshold" then
			if value ~= nil and (typeof(value) ~= "number" or value < 0) then
				warn(`[{SCRIPT_NAME}] Invalid {key}: {value}. Must be nil or >= 0.`)
				return
			end
		elseif key == "Enabled" or key == "TrackMemory" or key == "AutoPrint" or key == "UseProfiler" then
			if typeof(value) ~= "boolean" then
				warn(`[{SCRIPT_NAME}] Invalid {key}: {value}. Must be boolean.`)
				return
			end
		end

		-- Update the trackMemory closure variable when TrackMemory changes
		if key == "TrackMemory" then
			trackMemory = value == true
		end

		(self.Options :: any)[key] = value
	end

	function diagnostic:IsEnabled(): boolean
		return self.Options.Enabled == true
	end

	function diagnostic:Enable()
		self.Options.Enabled = true
	end

	function diagnostic:Disable()
		self.Options.Enabled = false
	end

	function diagnostic:Destroy()
		for _, timer in self.Timers do
			if timer.ActiveStart and timer.UseProfiler then
				debug.profileend()
			end
		end
		allDiagnostics[self.Name] = nil
		if autoPrintTask and coroutine.status(autoPrintTask) ~= "dead" then
			task.cancel(autoPrintTask)
			autoPrintTask = nil
		end
	end

	-- Registration --

	allDiagnostics[name] = diagnostic

	if RunService:IsClient() then
		SetupKeybind()
	end

	if resolvedOptions.AutoPrint and resolvedOptions.AutoPrintInterval then
		autoPrintTask = task.spawn(function()
			while allDiagnostics[name] do
				local interval = diagnostic.Options.AutoPrintInterval
				if not interval or interval <= 0 then
					interval = DEFAULT_AUTO_PRINT_INTERVAL
				end
				task.wait(interval)
				if allDiagnostics[name] and diagnostic.Options.AutoPrint then
					diagnostic:PrintBreakdown(false)
				end
			end
		end)
	end

	return diagnostic
end

-- Static Methods --

function DiagnosticHelper.Get(name: string): Diagnostic?
	return allDiagnostics[name]
end

function DiagnosticHelper.GetAll(): { [string]: Diagnostic }
	return table.clone(allDiagnostics)
end

function DiagnosticHelper.PrintAll(detailed: boolean?)
	local names: { string } = {}
	for diagName in allDiagnostics do
		table.insert(names, diagName)
	end
	table.sort(names)

	if not names[1] then
		print(`[{SCRIPT_NAME}] No diagnostics registered.`)
		return
	end

	for _, diagName in names do
		local diag = allDiagnostics[diagName]
		if diag then
			diag:PrintBreakdown(detailed)
		end
	end
end

function DiagnosticHelper.DestroyAll()
	for _, diag in allDiagnostics do
		(diag :: any):Destroy()
	end
	if activeSelectionConnection then
		activeSelectionConnection:Disconnect()
		activeSelectionConnection = nil
	end
	if keybindConnection then
		keybindConnection:Disconnect()
		keybindConnection = nil
		isKeybindConnected = false
	end
end

function DiagnosticHelper.SetKeybind(keyCode: Enum.KeyCode)
	currentKeybind = keyCode
	if not keybindConnection and RunService:IsClient() then
		SetupKeybind()
	end
end

--[[
	One-shot timing utility. Prints the duration immediately.
--]]
function DiagnosticHelper.QuickTime<T...>(name: string, fn: () -> T...): T...
	local startTime = os.clock()
	local results = table.pack(fn())
	local duration = os.clock() - startTime
	print(`[{SCRIPT_NAME}] QuickTime "{name}": {string.format("%.4f", duration * 1000)}ms`)
	return table.unpack(results :: any, 1, results.n)
end

--[[
	Runs a function many times and prints comprehensive benchmark statistics.
--]]
function DiagnosticHelper.QuickBenchmark(name: string, fn: () -> (), iterations: number?): QuickBenchmarkStats
	local count = iterations or DEFAULT_BENCHMARK_ITERATIONS
	if count < 1 then
		count = 1
	end

	local times: { number } = table.create(count)
	for i = 1, count do
		local t = os.clock()
		fn()
		times[i] = os.clock() - t
	end

	table.sort(times)
	local total = 0
	for _, t in times do
		total += t
	end

	local average = total / count
	local median = CalculateMedian(times, count)
	local min = times[1]
	local max = times[count]
	local p95 = CalculatePercentile(times, count, 95)
	local p99 = CalculatePercentile(times, count, 99)
	local p99_9 = CalculatePercentile(times, count, 99.9)

	-- Std dev (Bessel-corrected)
	local sumSqDiff = 0
	for _, t in times do
		local diff = t - average
		sumSqDiff += diff * diff
	end
	local stdDev = if count > 1 then math.sqrt(sumSqDiff / (count - 1)) else 0
	local jitter = max - min
	local coV = if average > 0 then stdDev / average else 0

	-- Buffered output
	local buf: { string } = {}
	local i = 0
	i += 1
	buf[i] = ""
	i += 1
	buf[i] = SEPARATOR
	i += 1
	buf[i] = `  BENCHMARK: {name}`
	i += 1
	buf[i] = SEPARATOR
	i += 1
	buf[i] = string.format("    %-14s%d", "Iterations:", count)
	i += 1
	buf[i] = string.format(
		"    %-14s%s  (%s, %s/frame)",
		"Total:",
		string.format("%.4fms", total * 1000),
		FormatBudgetPercent(total),
		FormatCallsPerFrame(total)
	)
	i += 1
	buf[i] = string.format("    %-14s%sms", "Average:", string.format("%.6f", average * 1000))
	i += 1
	buf[i] = string.format("    %-14s%sms", "Median:", string.format("%.6f", median * 1000))
	i += 1
	buf[i] = string.format("    %-14s%sms", "Min:", string.format("%.6f", min * 1000))
	i += 1
	buf[i] = string.format("    %-14s%sms", "Max:", string.format("%.6f", max * 1000))
	i += 1
	buf[i] = string.format("    %-14s%sms", "Std Dev:", string.format("%.6f", stdDev * 1000))
	i += 1
	buf[i] = string.format(
		"    %-14s%-20s%-14s%s",
		"Jitter:",
		string.format("%.6fms", jitter * 1000),
		"CoV:",
		string.format("%.2f%%", coV * 100)
	)
	i += 1
	buf[i] = string.format("    %-14s%sms", "p95:", string.format("%.6f", p95 * 1000))
	i += 1
	buf[i] = string.format("    %-14s%sms", "p99:", string.format("%.6f", p99 * 1000))
	i += 1
	buf[i] = string.format("    %-14s%sms", "p99.9:", string.format("%.6f", p99_9 * 1000))
	i += 1
	buf[i] = "    -- Frame Budget (60 FPS) --"
	i += 1
	buf[i] = string.format(
		"    %-14s%-20s%-14s%s",
		"Avg Budget:",
		FormatBudgetPercent(average),
		"Max Budget:",
		FormatBudgetPercent(max)
	)
	i += 1
	buf[i] = string.format(
		"    p50: %-13sp90: %-13sp95: %-13sp99: %-13sp99.9: %s",
		FormatBudgetPercent(median),
		FormatBudgetPercent(CalculatePercentile(times, count, 90)),
		FormatBudgetPercent(p95),
		FormatBudgetPercent(p99),
		FormatBudgetPercent(p99_9)
	)
	i += 1
	buf[i] = "    -- Calls/Frame (60 FPS) --"
	i += 1
	buf[i] = string.format(
		"    %-14s%-18s%-14s%s",
		"From Min:",
		FormatCallsPerFrame(min),
		"From Avg:",
		FormatCallsPerFrame(average)
	)
	i += 1
	buf[i] = string.format(
		"    p50: %-13sp90: %-13sp95: %-13sp99: %-13sp99.9: %s",
		FormatCallsPerFrame(median),
		FormatCallsPerFrame(CalculatePercentile(times, count, 90)),
		FormatCallsPerFrame(p95),
		FormatCallsPerFrame(p99),
		FormatCallsPerFrame(p99_9)
	)
	i += 1
	buf[i] = SEPARATOR
	i += 1
	buf[i] = ""

	print(table.concat(buf, "\n", 1, i))

	return {
		Count = count,
		Total = total,
		Average = average,
		Median = median,
		Min = min,
		Max = max,
		StdDev = stdDev,
		Jitter = jitter,
		CoV = coV,
		P95 = p95,
		P99 = p99,
		P99_9 = p99_9,
	}
end

return table.freeze(DiagnosticHelper)
