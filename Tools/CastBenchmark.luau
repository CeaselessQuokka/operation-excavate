--!strict
--- Services ---
local Workspace = game:GetService("Workspace")

--- Imports ---
local Benchmark = require(Workspace.Camera.Benchmark)

--- Setup ---
local ORIGIN = Vector3.new(0, 500, 0)
local DIRECTION = Vector3.new(0, -1000, 0)
local BLOCK_SIZE = Vector3.new(4, 4, 4)
local SPHERE_RADIUS = 2
local BLOCK_CFRAME = CFrame.new(ORIGIN)

local PARAMS = RaycastParams.new()
PARAMS.FilterType = Enum.RaycastFilterType.Exclude
PARAMS.FilterDescendantsInstances = {}

local ITERATIONS = 10000
local RUNS = 1

--- Benchmark ---
Benchmark.CompareMany({
	{
		Name = "Raycast",
		Fn = function()
			Workspace:Raycast(ORIGIN, DIRECTION, PARAMS)
		end,
	},
	{
		Name = "Blockcast",
		Fn = function()
			Workspace:Blockcast(BLOCK_CFRAME, BLOCK_SIZE, DIRECTION, PARAMS)
		end,
	},
	{
		Name = "Spherecast",
		Fn = function()
			Workspace:Spherecast(ORIGIN, SPHERE_RADIUS, DIRECTION, PARAMS)
		end,
	},
}, ITERATIONS, RUNS)
