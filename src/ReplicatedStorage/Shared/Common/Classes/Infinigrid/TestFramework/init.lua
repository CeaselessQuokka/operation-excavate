--[[
	Test framework for unit testing Luau modules.

	Usage:
		local TestFramework = require(path.to.TestFramework)
		local Grid = require(path.to.Infinigrid)

		return TestFramework.Suite("Infinigrid", function(describe, it, expect, beforeEach, afterEach, skip)
			describe("Grid.new", function()
				it("should create a grid with aligned origin", function()
					local grid = Grid.new(Vector3.zero, 8)
					expect(grid.Origin).To.Equal(Vector3.zero)
				end)

				skip("not yet implemented")
			end)
		end)

	Running:
		TestFramework.RunSuite(suite)
		TestFramework.RunAll(rootFolder) -- discovers and runs all .test / .spec ModuleScripts
--]]

--!strict

--- Imports ---
local Expect = require(script.Expect)

--- Types ---
type Expectation = Expect.Expectation

type TestCase = {
	Name: string,
	Fn: () -> (),
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
}

export type TestSuite = TestNode

export type SuiteResults = {
	Passed: number,
	Failed: number,
	Skipped: number,
	Errors: { { Test: string, Error: string } },
	Duration: number,
}

type DescribeFn = (name: string, callback: () -> ()) -> ()
type ItFn = (name: string, callback: () -> ()) -> ()
type ExpectFn = (actual: any) -> Expectation
type HookFn = (callback: () -> ()) -> ()
type SkipFn = (name: string) -> ()
type SuiteCallback = (DescribeFn, ItFn, ExpectFn, HookFn, HookFn, SkipFn) -> ()

--- Variables ---
local SEPARATOR = string.rep("=", 60)
local DIVIDER = string.rep("-", 60)
local INDENT = "  "
local PASS_TAG = "[PASS]"
local FAIL_TAG = "[FAIL]"
local SKIP_TAG = "[SKIP]"

--- Test Framework ---
local TestFramework = {}

function TestFramework.Suite(name: string, callback: SuiteCallback): TestSuite
	local root: TestNode = {
		Name = name,
		Tests = {},
		Skipped = {},
		Children = {},
		BeforeEach = {},
		AfterEach = {},
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
		}
		table.insert(current().Children, child)
		table.insert(stack, child)
		fn()
		table.remove(stack)
	end

	local function it(testName: string, fn: () -> ())
		table.insert(current().Tests, { Name = testName, Fn = fn })
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

function TestFramework.RunSuite(suite: TestSuite): SuiteResults
	local results: SuiteResults = {
		Passed = 0,
		Failed = 0,
		Skipped = 0,
		Errors = {},
		Duration = 0,
	}

	local startTime = os.clock()

	local function runNode(
		node: TestNode,
		depth: number,
		inheritedBeforeEach: { () -> () },
		inheritedAfterEach: { () -> () }
	)
		local prefix = string.rep(INDENT, depth)
		local testPrefix = string.rep(INDENT, depth + 1)

		print(`{prefix}{node.Name}`)

		local allBeforeEach: { () -> () } = table.clone(inheritedBeforeEach)
		for _, fn in node.BeforeEach do
			table.insert(allBeforeEach, fn)
		end

		local allAfterEach: { () -> () } = table.clone(inheritedAfterEach)
		for _, fn in node.AfterEach do
			table.insert(allAfterEach, fn)
		end

		for _, test in node.Tests do
			local hookFailed = false

			for _, hook in allBeforeEach do
				local ok, err = pcall(hook :: any)
				if not ok then
					hookFailed = true
					results.Failed += 1
					warn(`{testPrefix}{FAIL_TAG} {test.Name} (beforeEach: {err})`)
					table.insert(results.Errors, { Test = test.Name, Error = `beforeEach: {err}` })
					break
				end
			end

			if not hookFailed then
				local ok, err = pcall(test.Fn :: any)
				if ok then
					results.Passed += 1
					print(`{testPrefix}{PASS_TAG} {test.Name}`)
				else
					results.Failed += 1
					warn(`{testPrefix}{FAIL_TAG} {test.Name}`)
					warn(`{testPrefix}  {err}`)
					table.insert(results.Errors, { Test = test.Name, Error = tostring(err) })
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
			print(`{testPrefix}{SKIP_TAG} {skipped.Name}`)
		end

		for _, child in node.Children do
			runNode(child, depth + 1, allBeforeEach, allAfterEach)
		end
	end

	print(`\n{SEPARATOR}`)
	runNode(suite, 0, {}, {})

	results.Duration = os.clock() - startTime

	print(DIVIDER)
	local total = results.Passed + results.Failed + results.Skipped
	print(
		`Results: {results.Passed}/{total} passed, {results.Failed} failed, {results.Skipped} skipped ({string.format(
			"%.3f",
			results.Duration
		)}s)`
	)

	if results.Failed > 0 then
		warn("\nFailed tests:")
		for _, entry in results.Errors do
			warn(`  {entry.Test}: {entry.Error}`)
		end
	end

	print(`{SEPARATOR}\n`)

	return results
end

function TestFramework.RunAll(root: Instance): { SuiteResults }
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
			table.insert(allResults, TestFramework.RunSuite(suite :: TestSuite))
		else
			warn(
				`[TestFramework] Failed to load "{descendant:GetFullName()}": {if not ok then suite else "invalid suite"}`
			)
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
		print(`All suites: {totalPassed} passed, {totalFailed} failed, {totalSkipped} skipped`)
		print(SEPARATOR)
	end

	return allResults
end

TestFramework.Expect = Expect.new

return table.freeze(TestFramework)
