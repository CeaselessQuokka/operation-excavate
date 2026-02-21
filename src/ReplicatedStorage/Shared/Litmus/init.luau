--[[
	Litmus — a lightweight test framework for Luau modules.

	Provides BDD-style `describe`/`it`/`expect` with hooks, skip/focus support,
	automatic discovery via RunAll, and clear console output.

	Usage:
		local Litmus = require(ReplicatedStorage.Shared.Litmus)

		return Litmus.Suite("MyModule", function(describe, it, expect, beforeEach, afterEach, skip)
			describe("Feature", function()
				it("should work", function()
					expect(1 + 1).To.Equal(2)
				end)

				skip("not yet implemented")
			end)
		end)

	Running:
		Litmus.RunSuite(suite)
		Litmus.RunAll(rootFolder)
--]]

--!strict

--- Imports ---
local Expect = require(script.Expect)

--- Types ---
type Expectation = Expect.Expectation

type TestCase = {
	Name: string,
	Fn: () -> (),
	IsFocused: boolean,
}

type SkippedTest = {
	Name: string,
}

export type TestNode = {
	Name: string,
	Tests: { TestCase },
	Skipped: { SkippedTest },
	Children: { TestNode },
	BeforeEach: { () -> () },
	AfterEach: { () -> () },
	IsFocused: boolean,
}

export type TestSuite = TestNode

export type SuiteResults = {
	SuiteName: string,
	Passed: number,
	Failed: number,
	Skipped: number,
	Errors: { { Test: string, Path: string, Error: string } },
	Duration: number,
}

type DescribeFn = (name: string, callback: () -> ()) -> ()
type ItFn = (name: string, callback: () -> ()) -> ()
type ExpectFn = (actual: any) -> Expectation
type HookFn = (callback: () -> ()) -> ()
type SkipFn = (name: string) -> ()
type SuiteCallback = (DescribeFn, ItFn, ExpectFn, HookFn, HookFn, SkipFn) -> ()

--- Variables ---
local SEPARATOR = string.rep("=", 70)
local DIVIDER = string.rep("-", 70)
local INDENT = "  "
local PASS_ICON = "[PASS]"
local FAIL_ICON = "[FAIL]"
local SKIP_ICON = "[SKIP]"
local FOCUS_ICON = "[ONLY]"

--- Functions ---
local function HasFocusedTests(node: TestNode): boolean
	for _, test in node.Tests do
		if test.IsFocused then
			return true
		end
	end
	if node.IsFocused then
		return true
	end
	for _, child in node.Children do
		if HasFocusedTests(child) then
			return true
		end
	end
	return false
end

--- Litmus ---
local Litmus = {}

function Litmus.Suite(name: string, callback: SuiteCallback): TestSuite
	local root: TestNode = {
		Name = name,
		Tests = {},
		Skipped = {},
		Children = {},
		BeforeEach = {},
		AfterEach = {},
		IsFocused = false,
	}

	local stack: { TestNode } = { root }

	local function current(): TestNode
		return stack[#stack]
	end

	local function describe(childName: string, fn: () -> ())
		local child: TestNode = {
			Name = childName,
			Tests = {},
			Skipped = {},
			Children = {},
			BeforeEach = {},
			AfterEach = {},
			IsFocused = false,
		}
		table.insert(current().Children, child)
		table.insert(stack, child)
		fn()
		table.remove(stack)
	end

	local function it(testName: string, fn: () -> ())
		table.insert(current().Tests, { Name = testName, Fn = fn, IsFocused = false })
	end

	local function expect(actual: any): Expectation
		return Expect.new(actual)
	end

	local function beforeEach(fn: () -> ())
		table.insert(current().BeforeEach, fn)
	end

	local function afterEach(fn: () -> ())
		table.insert(current().AfterEach, fn)
	end

	local function skip(testName: string)
		table.insert(current().Skipped, { Name = testName })
	end

	callback(describe, it, expect, beforeEach, afterEach, skip)

	return root
end

function Litmus.RunSuite(suite: TestSuite): SuiteResults
	local results: SuiteResults = {
		SuiteName = suite.Name,
		Passed = 0,
		Failed = 0,
		Skipped = 0,
		Errors = {},
		Duration = 0,
	}

	local suiteHasFocus = HasFocusedTests(suite)
	local startTime = os.clock()

	local function BuildPath(segments: { string }): string
		return table.concat(segments, " > ")
	end

	local function runNode(
		node: TestNode,
		depth: number,
		inheritedBeforeEach: { () -> () },
		inheritedAfterEach: { () -> () },
		pathSegments: { string }
	)
		local prefix = string.rep(INDENT, depth)
		local testPrefix = string.rep(INDENT, depth + 1)

		print(`{prefix}{node.Name}`)

		local currentPath = table.clone(pathSegments)
		table.insert(currentPath, node.Name)

		local allBeforeEach: { () -> () } = table.clone(inheritedBeforeEach)
		for _, fn in node.BeforeEach do
			table.insert(allBeforeEach, fn)
		end

		local allAfterEach: { () -> () } = table.clone(inheritedAfterEach)
		for _, fn in node.AfterEach do
			table.insert(allAfterEach, fn)
		end

		for _, test in node.Tests do
			-- If the suite has focused tests, skip non-focused ones.
			if suiteHasFocus and not test.IsFocused and not node.IsFocused then
				results.Skipped += 1
				print(`{testPrefix}{SKIP_ICON} {test.Name} (not focused)`)
				continue
			end

			local hookFailed = false

			for _, hook in allBeforeEach do
				local ok, err = pcall(hook :: any)
				if not ok then
					hookFailed = true
					results.Failed += 1
					warn(`{testPrefix}{FAIL_ICON} {test.Name} (beforeEach: {err})`)
					local testPath = BuildPath(currentPath) .. " > " .. test.Name
					table.insert(results.Errors, { Test = test.Name, Path = testPath, Error = `beforeEach: {err}` })
					break
				end
			end

			if not hookFailed then
				local testStart = os.clock()
				local ok, err = pcall(test.Fn :: any)
				local testDuration = os.clock() - testStart

				local durationStr = string.format("%.2fms", testDuration * 1000)

				if ok then
					results.Passed += 1
					local tag = if test.IsFocused then FOCUS_ICON .. " " .. PASS_ICON else PASS_ICON
					print(`{testPrefix}{tag} {test.Name} ({durationStr})`)
				else
					results.Failed += 1
					local testPath = BuildPath(currentPath) .. " > " .. test.Name
					warn(`{testPrefix}{FAIL_ICON} {test.Name} ({durationStr})`)
					warn(`{testPrefix}  {err}`)
					table.insert(results.Errors, { Test = test.Name, Path = testPath, Error = tostring(err) })
				end

				for _, hook in allAfterEach do
					local hookOk, hookErr = pcall(hook :: any)
					if not hookOk then
						warn(`{testPrefix}  afterEach error: {hookErr}`)
					end
				end
			end
		end

		for _, skipped in node.Skipped do
			results.Skipped += 1
			print(`{testPrefix}{SKIP_ICON} {skipped.Name}`)
		end

		for _, child in node.Children do
			runNode(child, depth + 1, allBeforeEach, allAfterEach, currentPath)
		end
	end

	print(`\n{SEPARATOR}`)
	print(`  Litmus: Running "{suite.Name}"`)
	print(SEPARATOR)
	runNode(suite, 0, {}, {}, {})

	results.Duration = os.clock() - startTime

	-- Summary
	print(DIVIDER)
	local total = results.Passed + results.Failed + results.Skipped
	local statusIcon = if results.Failed > 0 then "FAIL" else "PASS"
	print(
		`  [{statusIcon}] {results.Passed}/{total} passed, {results.Failed} failed, {results.Skipped} skipped ({string.format(
			"%.3f",
			results.Duration
		)}s)`
	)

	if results.Failed > 0 then
		warn(`\n  Failed tests:`)
		for i, entry in results.Errors do
			warn(`    {i}. {entry.Path}`)
			warn(`       {entry.Error}`)
		end
	end

	print(`{SEPARATOR}\n`)

	return results
end

function Litmus.RunAll(root: Instance): { SuiteResults }
	local allResults: { SuiteResults } = {}

	for _, descendant in root:GetDescendants() do
		if not descendant:IsA("ModuleScript") then
			continue
		end

		local name = descendant.Name
		if not (string.find(name, "%.test$") or string.find(name, "%.spec$")) then
			continue
		end

		local ok, suite = pcall(require, descendant :: ModuleScript)
		if ok and typeof(suite) == "table" and (suite :: any).Name then
			table.insert(allResults, Litmus.RunSuite(suite :: TestSuite))
		else
			warn(`[Litmus] Failed to load "{descendant:GetFullName()}": {if not ok then suite else "invalid suite"}`)
		end
	end

	if #allResults > 0 then
		local totalPassed, totalFailed, totalSkipped = 0, 0, 0
		for _, r in allResults do
			totalPassed += r.Passed
			totalFailed += r.Failed
			totalSkipped += r.Skipped
		end
		print(SEPARATOR)
		local allStatus = if totalFailed > 0 then "FAIL" else "PASS"
		print(`  [{allStatus}] All suites: {totalPassed} passed, {totalFailed} failed, {totalSkipped} skipped`)
		print(SEPARATOR)
	end

	return allResults
end

Litmus.Expect = Expect.new

return table.freeze(Litmus)
