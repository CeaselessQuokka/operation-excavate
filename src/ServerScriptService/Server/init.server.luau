--!strict
--- Services ---
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--- Imports ---
local TableEditor = require(ReplicatedStorage.Shared.TableEditor)

local JecsCommon = require(ReplicatedStorage.Shared.Common.JecsCommon)
local LoadingHelper = require(ReplicatedStorage.Shared.Helpers.LoadingHelper)

--- Server Initialization ---
LoadingHelper.LoadModules(script.Services)
LoadingHelper.LoadModules(script.Systems)
LoadingHelper.LoadModules(ReplicatedStorage.Shared.Systems, true)

-- Jecs world viewer.
while true do
	TableEditor.TrueServerView(Players:GetPlayers(), "[Server] Jecs World", { World = JecsCommon.World })
	task.wait(2.5)
end
