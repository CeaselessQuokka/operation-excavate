--!strict

--- Services ---
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--- Imports ---
local Knit = require(ReplicatedStorage.Packages.Knit)

--- Load Services ---
local servicesFolder = script:FindFirstChild("Services")
assert(servicesFolder, "[Server] Services folder not found")

for _, module in servicesFolder:GetChildren() do
	if module:IsA("ModuleScript") and module:GetAttribute("Enabled") ~= false then
		local success, err = pcall(require, module :: ModuleScript)
		if not success then
			warn(`[Server] Failed to load service "{module.Name}": {err}`)
		end
	end
end

--- Start Knit ---
Knit.Start():expect()

-- do
-- 	return
-- end

for t = 3, 1, -1 do
	print(`[Server] Starting in {t}...`)
	task.wait(1)
end

-- Run tests.
local Litmus = require(ReplicatedStorage.Shared.Litmus)
Litmus.RunSuite(require(ReplicatedStorage.Shared.Common.Classes.Infinigrid.TestFramework["Infinigrid.test"]))

-- Run benchmark.
-- require(ReplicatedStorage.Shared.Common.Classes.Infinigrid.TestFramework["Infinigrid.bench"])

-- Generate planet infinigrid for testing.
-- require(ReplicatedStorage.Shared.Common.Classes.Infinigrid).new(Vector3.zero, Vector3.new(4224, 4224, 4224), 64)

-- local Infinigrid = require(ReplicatedStorage.Shared.Common.Classes.Infinigrid)
-- local grid = Infinigrid.new(Vector3.zero, Vector3.new(4224, 4224, 4224), 64)
-- print(grid:GetChunkAtPosition(Vector3.zero))
