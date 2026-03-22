--!strict

--[[
	Lightweight benchmarking utility for comparing code performance.

	Runs a function for a configurable number of iterations across multiple
	runs, computes detailed statistics, and prints formatted breakdowns
	matching the Diagnostic module's output style.

	Usage:
		local result = Benchmark.Bench(fn, 1000, 5)
		local resultB = Benchmark.Bench(fnB, 1000, 5)
		Benchmark.Compare(result, resultB)
		-- or compare many:
		Benchmark.Compare(result, resultB, resultC)
--]]

--- Types ---

export type BenchResult = {
	Name: string,
	Iterations: number,
	Runs: number,
	RunTimes: { number }, -- Per-run total durations (seconds)
	AllTimes: { number }, -- Every individual iteration timing (seconds), sorted
	Count: number, -- Total iterations across all runs (Iterations * Runs)
	Total: number, -- Sum of all iteration durations
	Average: number,
	Median: number,
	Min: number,
	Max: number,
	StdDev: number,
	Jitter: number,
	CoV: number,
	Percentiles: { [number]: number },
	SamplesPerSecond: number,
	MemoryDelta: number?, -- Total memory delta in bytes (nil when tracking is off)
}

export type BenchOptions = {
	Name: string?,
	TrackMemory: boolean?,
	Warmup: number?, -- Warmup iterations before measurement (default: 0)
	TimeUnit: ("s" | "ms" | "us" | "ns")?,
	DecimalPlaces: number?,
	Percentiles: { number }?,
	Silent: boolean?, -- Suppress automatic print after bench
}

--- Constants ---
type TimeUnit = "s" | "ms" | "us" | "ns"

local SEPARATOR = string.rep("=", 60)
local DASH = string.rep("-", 58)
local FRAME_TIME_60FPS = 1 / 60

local DEFAULT_PERCENTILES = table.freeze({ 50, 90, 95, 99, 99.9 })
local DEFAULT_TIME_UNIT: TimeUnit = "ms"
local DEFAULT_DECIMAL_PLACES = 4
local DEFAULT_ITERATIONS = 1000
local DEFAULT_RUNS = 1

local TIME_UNIT_MULTIPLIERS = table.freeze({
	s = 1,
	ms = 1000,
	us = 1000000,
	ns = 1000000000,
})

--- Internal Helpers ---

local function FormatTime(seconds: number, unit: TimeUnit, dp: number): string
	local multiplier = TIME_UNIT_MULTIPLIERS[unit] or TIME_UNIT_MULTIPLIERS.ms
	return string.format(`%.{dp}f{unit}`, seconds * multiplier)
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

local function GetMemoryUsage(): number
	return gcinfo() * 1024
end

local function ResolveOptions(options: BenchOptions?): (string, boolean, number, TimeUnit, number, { number }, boolean)
	local opts = options or {}
	local name: string = opts.Name or "Unnamed"
	local trackMemory: boolean = opts.TrackMemory == true
	local warmup: number = if opts.Warmup and opts.Warmup > 0 then opts.Warmup :: number else 0
	local unit: TimeUnit = (opts.TimeUnit or DEFAULT_TIME_UNIT) :: TimeUnit
	local dp: number = if opts.DecimalPlaces and opts.DecimalPlaces >= 0
		then opts.DecimalPlaces :: number
		else DEFAULT_DECIMAL_PLACES
	local percentiles: { number } = opts.Percentiles or DEFAULT_PERCENTILES
	local silent: boolean = opts.Silent == true

	if not TIME_UNIT_MULTIPLIERS[unit] then
		unit = DEFAULT_TIME_UNIT
	end

	return name, trackMemory, warmup, unit, dp, percentiles, silent
end

local function ComputeStats(
	allTimes: { number },
	runTimes: { number },
	count: number,
	percentilesList: { number },
	trackMemory: boolean,
	memDelta: number?
): (number, number, number, number, number, number, number, number, { [number]: number })
	local total = 0
	local sumSquared = 0
	local minVal = math.huge
	local maxVal = 0

	for i = 1, count do
		local d = allTimes[i]
		total += d
		sumSquared += d * d
		if d < minVal then
			minVal = d
		end
		if d > maxVal then
			maxVal = d
		end
	end

	local average = total / count
	local variance = math.max(0, (sumSquared / count) - (average * average))
	local stdDev = if count > 1 then math.sqrt(variance * count / (count - 1)) else 0
	local jitter = maxVal - minVal
	local coV = if average > 0 then stdDev / average else 0
	local median = CalculateMedian(allTimes, count)

	local percentiles: { [number]: number } = {}
	for _, p in percentilesList do
		percentiles[p] = CalculatePercentile(allTimes, count, p)
	end

	return total, average, median, minVal, maxVal, stdDev, jitter, coV, percentiles
end

--- Printing ---

local function PrintBenchResult(result: BenchResult, unit: TimeUnit, dp: number)
	local function ft(s: number): string
		return FormatTime(s, unit, dp)
	end

	local buf: { string } = {}
	local i = 0

	i += 1
	buf[i] = ""
	i += 1
	buf[i] = SEPARATOR
	i += 1
	buf[i] = `  BENCHMARK: {result.Name}`
	i += 1
	buf[i] = SEPARATOR

	i += 1
	buf[i] = string.format("    %-14s%-20s%-14s%d", "Iterations:", tostring(result.Iterations), "Runs:", result.Runs)
	i += 1
	buf[i] = string.format(
		"    %-14s%s  (%s, %s/frame)",
		"Total:",
		ft(result.Total),
		FormatBudgetPercent(result.Total),
		FormatCallsPerFrame(result.Total)
	)
	i += 1
	buf[i] = string.format("    %-14s%-20s%-14s%s", "Average:", ft(result.Average), "Median:", ft(result.Median))
	i += 1
	buf[i] = string.format("    %-14s%-20s%-14s%s", "Min:", ft(result.Min), "Max:", ft(result.Max))
	i += 1
	buf[i] = string.format("    %-14s%-20s%-14s%s", "Std Dev:", ft(result.StdDev), "Jitter:", ft(result.Jitter))
	i += 1
	buf[i] = string.format(
		"    %-14s%-20s%-14s%s",
		"CoV:",
		string.format("%.2f%%", result.CoV * 100),
		"Rate:",
		string.format("%.2f/sec", result.SamplesPerSecond)
	)

	if result.MemoryDelta then
		i += 1
		buf[i] = `    Memory:   {FormatMemory(result.MemoryDelta)} total delta`
	end

	-- Per-run breakdown
	if result.Runs > 1 then
		i += 1
		buf[i] = "    -- Per-Run Totals --"
		for runIdx, runTime in result.RunTimes do
			i += 1
			buf[i] = string.format("    Run %-4d   %s  (%s)", runIdx, ft(runTime), FormatBudgetPercent(runTime))
		end
	end

	-- Frame budget
	i += 1
	buf[i] = "    -- Frame Budget (60 FPS) --"
	i += 1
	buf[i] = string.format(
		"    %-14s%-20s%-14s%s",
		"Avg Budget:",
		FormatBudgetPercent(result.Average),
		"Max Budget:",
		FormatBudgetPercent(result.Max)
	)

	local pKeys: { number } = {}
	for p in result.Percentiles do
		table.insert(pKeys, p)
	end
	table.sort(pKeys)

	if #pKeys > 0 then
		local budgetParts: { string } = {}
		for _, p in pKeys do
			table.insert(budgetParts, string.format("p%g: %s", p, FormatBudgetPercent(result.Percentiles[p])))
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
		FormatCallsPerFrame(result.Min),
		"From Avg:",
		FormatCallsPerFrame(result.Average),
		"From Max:",
		FormatCallsPerFrame(result.Max)
	)
	if #pKeys > 0 then
		local cfParts: { string } = {}
		for _, p in pKeys do
			table.insert(cfParts, string.format("p%g: %s", p, FormatCallsPerFrame(result.Percentiles[p])))
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
			parts[j] = string.format("p%g: %s", p, ft(result.Percentiles[p]))
		end
		i += 1
		buf[i] = "    " .. table.concat(parts, "   ")
	end

	i += 1
	buf[i] = SEPARATOR
	i += 1
	buf[i] = ""

	print(table.concat(buf, "\n", 1, i))
end

local function PrintComparison(results: { BenchResult }, unit: TimeUnit, dp: number)
	local function ft(s: number): string
		return FormatTime(s, unit, dp)
	end

	local buf: { string } = {}
	local i = 0

	i += 1
	buf[i] = ""
	i += 1
	buf[i] = SEPARATOR
	i += 1
	buf[i] = `  COMPARISON ({#results} benchmarks)`
	i += 1
	buf[i] = SEPARATOR

	-- Find the baseline (fastest average)
	local baselineIdx = 1
	local baselineAvg = results[1].Average
	for idx = 2, #results do
		if results[idx].Average < baselineAvg then
			baselineAvg = results[idx].Average
			baselineIdx = idx
		end
	end

	-- Summary table header
	i += 1
	buf[i] = ""
	i += 1
	buf[i] = string.format("    %-24s %-14s %-14s %-14s %-10s %s", "Name", "Average", "Min", "Max", "CoV", "vs Fastest")
	i += 1
	buf[i] = "  " .. DASH

	-- Sort by average ascending for display
	local indices: { number } = table.create(#results)
	for idx = 1, #results do
		indices[idx] = idx
	end
	table.sort(indices, function(a, b)
		return results[a].Average < results[b].Average
	end)

	for _, idx in indices do
		local r = results[idx]
		local ratio: string
		if idx == baselineIdx then
			ratio = "baseline"
		else
			local mult = r.Average / baselineAvg
			if mult >= 100 then
				ratio = string.format("%.0fx slower", mult)
			elseif mult >= 10 then
				ratio = string.format("%.1fx slower", mult)
			else
				ratio = string.format("%.2fx slower", mult)
			end
		end
		i += 1
		buf[i] = string.format(
			"    %-24s %-14s %-14s %-14s %-10s %s",
			r.Name,
			ft(r.Average),
			ft(r.Min),
			ft(r.Max),
			string.format("%.2f%%", r.CoV * 100),
			ratio
		)
	end

	-- Detailed per-benchmark sections
	i += 1
	buf[i] = ""
	i += 1
	buf[i] = "  " .. DASH
	i += 1
	buf[i] = "  DETAILED BREAKDOWN"
	i += 1
	buf[i] = "  " .. DASH

	for _, idx in indices do
		local r = results[idx]
		local tag = if idx == baselineIdx then " (fastest)" else ""

		i += 1
		buf[i] = ""
		i += 1
		buf[i] = `  [{r.Name}]{tag}`
		i += 1
		buf[i] = string.format("    %-14s%-20s%-14s%d", "Iterations:", tostring(r.Iterations), "Runs:", r.Runs)
		i += 1
		buf[i] = string.format(
			"    %-14s%s  (%s, %s/frame)",
			"Total:",
			ft(r.Total),
			FormatBudgetPercent(r.Total),
			FormatCallsPerFrame(r.Total)
		)
		i += 1
		buf[i] = string.format("    %-14s%-20s%-14s%s", "Average:", ft(r.Average), "Median:", ft(r.Median))
		i += 1
		buf[i] = string.format("    %-14s%-20s%-14s%s", "Min:", ft(r.Min), "Max:", ft(r.Max))
		i += 1
		buf[i] = string.format("    %-14s%-20s%-14s%s", "Std Dev:", ft(r.StdDev), "Jitter:", ft(r.Jitter))
		i += 1
		buf[i] = string.format(
			"    %-14s%-20s%-14s%s",
			"CoV:",
			string.format("%.2f%%", r.CoV * 100),
			"Rate:",
			string.format("%.2f/sec", r.SamplesPerSecond)
		)

		if r.MemoryDelta then
			i += 1
			buf[i] = `    Memory:   {FormatMemory(r.MemoryDelta)} total delta`
		end

		-- Budget & calls/frame
		i += 1
		buf[i] = "    -- Frame Budget (60 FPS) --"
		i += 1
		buf[i] = string.format(
			"    %-14s%-20s%-14s%s",
			"Avg:",
			FormatBudgetPercent(r.Average),
			"Max:",
			FormatBudgetPercent(r.Max)
		)

		local pKeys: { number } = {}
		for p in r.Percentiles do
			table.insert(pKeys, p)
		end
		table.sort(pKeys)

		if #pKeys > 0 then
			local budgetParts: { string } = {}
			for _, p in pKeys do
				table.insert(budgetParts, string.format("p%g: %s", p, FormatBudgetPercent(r.Percentiles[p])))
			end
			i += 1
			buf[i] = "    " .. table.concat(budgetParts, "   ")
		end

		i += 1
		buf[i] = "    -- Calls/Frame (60 FPS) --"
		i += 1
		buf[i] = string.format(
			"    %-14s%-18s%-14s%-18s%-14s%s",
			"From Min:",
			FormatCallsPerFrame(r.Min),
			"From Avg:",
			FormatCallsPerFrame(r.Average),
			"From Max:",
			FormatCallsPerFrame(r.Max)
		)
		if #pKeys > 0 then
			local cfParts: { string } = {}
			for _, p in pKeys do
				table.insert(cfParts, string.format("p%g: %s", p, FormatCallsPerFrame(r.Percentiles[p])))
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
				parts[j] = string.format("p%g: %s", p, ft(r.Percentiles[p]))
			end
			i += 1
			buf[i] = "    " .. table.concat(parts, "   ")
		end
	end

	-- Winner declaration
	i += 1
	buf[i] = ""
	i += 1
	buf[i] = "  " .. DASH
	local winner = results[baselineIdx]
	local secondIdx: number? = nil
	for _, idx in indices do
		if idx ~= baselineIdx then
			secondIdx = idx
			break
		end
	end

	if secondIdx then
		local second = results[secondIdx]
		local speedup = second.Average / winner.Average
		i += 1
		buf[i] = string.format(`  Winner: %s (%.2fx faster than %s)`, winner.Name, speedup, second.Name)
	else
		i += 1
		buf[i] = `  Winner: {winner.Name}`
	end

	i += 1
	buf[i] = SEPARATOR
	i += 1
	buf[i] = ""

	print(table.concat(buf, "\n", 1, i))
end

--- Module ---
local Benchmark = {}

--[[
	Benchmarks a function over the given iterations and runs.

	@param fn         The function to benchmark. Called with no arguments each iteration.
	@param iterations Number of times to call fn per run. Default: 1000.
	@param runs       Number of independent runs. Default: 1.
	@param options    Optional configuration (name, memory tracking, warmup, display, etc.)
	@return BenchResult  Structured result data for use with Compare.

	Example:
		local result = Benchmark.Bench(function()
			local t = {}
			for i = 1, 100 do t[i] = i end
		end, 10000, 3, { Name = "TableInsert" })
--]]
function Benchmark.Bench(
	fn: (...any) -> ...any,
	iterations: number?,
	runs: number?,
	options: BenchOptions?
): BenchResult
	local iters = if iterations and iterations >= 1 then iterations else DEFAULT_ITERATIONS
	local runCount = if runs and runs >= 1 then runs else DEFAULT_RUNS
	local name, trackMemory, warmup, unit, dp, percentilesList, silent = ResolveOptions(options)

	-- Warmup phase (not measured)
	if warmup > 0 then
		for _ = 1, warmup do
			fn()
		end
	end

	local totalCount = iters * runCount
	local allTimes: { number } = table.create(totalCount)
	local runTimes: { number } = table.create(runCount)
	local writeIdx = 0

	local memBefore: number? = if trackMemory then GetMemoryUsage() else nil

	for run = 1, runCount do
		local runTotal = 0
		for _ = 1, iters do
			local t0 = os.clock()
			fn()
			local elapsed = os.clock() - t0
			writeIdx += 1
			allTimes[writeIdx] = elapsed
			runTotal += elapsed
		end
		runTimes[run] = runTotal
	end

	local memDelta: number? = if trackMemory and memBefore then GetMemoryUsage() - memBefore else nil

	table.sort(allTimes)

	local total, average, median, minVal, maxVal, stdDev, jitter, coV, percentiles =
		ComputeStats(allTimes, runTimes, totalCount, percentilesList, trackMemory, memDelta)

	local samplesPerSecond = if total > 0 then totalCount / total else 0

	local result: BenchResult = {
		Name = name,
		Iterations = iters,
		Runs = runCount,
		RunTimes = runTimes,
		AllTimes = allTimes,
		Count = totalCount,
		Total = total,
		Average = average,
		Median = median,
		Min = minVal,
		Max = maxVal,
		StdDev = stdDev,
		Jitter = jitter,
		CoV = coV,
		Percentiles = percentiles,
		SamplesPerSecond = samplesPerSecond,
		MemoryDelta = memDelta,
	}

	if not silent then
		PrintBenchResult(result, unit, dp)
	end

	return result
end

--[[
	Compares two or more BenchResults side-by-side.
	Automatically determines the fastest as the baseline and shows multipliers.

	@param ... BenchResult values to compare (minimum 2).

	Example:
		local a = Benchmark.Bench(fnA, 10000, 3, { Name = "Approach A" })
		local b = Benchmark.Bench(fnB, 10000, 3, { Name = "Approach B" })
		Benchmark.Compare(a, b)
--]]
function Benchmark.Compare(...: BenchResult)
	local results: { BenchResult } = { ... }
	assert(#results >= 2, "Compare requires at least 2 BenchResults")

	-- Deduplicate names if needed
	local nameCounts: { [string]: number } = {}
	for _, r in results do
		nameCounts[r.Name] = (nameCounts[r.Name] or 0) + 1
	end

	local nameIndices: { [string]: number } = {}
	for i, r in results do
		if nameCounts[r.Name] > 1 then
			nameIndices[r.Name] = (nameIndices[r.Name] or 0) + 1
			results[i] = table.clone(r)
			results[i].Name = `{r.Name} #{nameIndices[r.Name]}`
		end
	end

	-- Use the unit/dp from the first result's options, or defaults
	local unit: TimeUnit = DEFAULT_TIME_UNIT
	local dp: number = DEFAULT_DECIMAL_PLACES

	PrintComparison(results, unit, dp)
end

--[[
	Convenience: benchmarks multiple functions and compares them in one call.

	@param entries  A table of { Name: string, Fn: () -> () } entries.
	@param iterations  Iterations per run for all entries.
	@param runs  Runs for all entries.
	@param options  Shared BenchOptions (Name field is ignored; per-entry names are used).

	Example:
		Benchmark.CompareMany({
			{ Name = "table.create", Fn = function() table.create(100, 0) end },
			{ Name = "manual fill",  Fn = function() local t = {} for i = 1,100 do t[i] = 0 end end },
		}, 10000, 5)
--]]
function Benchmark.CompareMany(
	entries: { { Name: string, Fn: (...any) -> ...any } },
	iterations: number?,
	runs: number?,
	options: BenchOptions?
)
	assert(#entries >= 2, "CompareMany requires at least 2 entries")

	local results: { BenchResult } = table.create(#entries)
	for i, entry in entries do
		local opts: BenchOptions = if options then table.clone(options) :: any else {}
		opts.Name = entry.Name
		opts.Silent = true -- Suppress individual prints; we'll do a combined comparison
		results[i] = Benchmark.Bench(entry.Fn, iterations, runs, opts)
	end

	Benchmark.Compare(table.unpack(results))
end

return table.freeze(Benchmark)
