--!strict
--- Services ---
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--- Imports ---
local Knit = require(ReplicatedStorage.Packages.Knit)

local LoadingHelper = require(ReplicatedStorage.Shared.Helpers.LoadingHelper)

--- Client Initialization ---
-- Load Knit controllers.
LoadingHelper.LoadModules(script.Controllers)
Knit.Start({ ServicePromises = false }):expect()

-- Load client and shared components.
LoadingHelper.LoadModules(script.Components)
LoadingHelper.LoadModules(ReplicatedStorage.Shared.Components)
