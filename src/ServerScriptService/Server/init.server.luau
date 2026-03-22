--!strict
--- Services ---
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--- Imports ---
-- local Jabby = require(ReplicatedStorage.Packages.Jabby)

local JecsCommon = require(ReplicatedStorage.Shared.Common.JecsCommon)
local LoadingHelper = require(ReplicatedStorage.Shared.Helpers.LoadingHelper)

--- Server Initialization ---
LoadingHelper.LoadModules(script.Services)
LoadingHelper.LoadModules(script.Systems)
LoadingHelper.LoadModules(ReplicatedStorage.Shared.Systems, true)

-- Register Jabby world.
-- Jabby.register({
-- 	applet = Jabby.applets.world,
-- 	name = "Server",
-- 	configuration = {
-- 		world = JecsCommon.World,
-- 	},
-- })
