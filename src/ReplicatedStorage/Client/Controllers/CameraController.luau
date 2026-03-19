--!strict
--- Services ---
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

--- Imports ---
local Knit = require(ReplicatedStorage.Packages.Knit)

local PlayerController = require(script.Parent.PlayerController)

--- Types ---

--- Variables ---

--- Functions ---

--- CameraController Controller ---
local CameraController = {
	Name = "CameraController",
}
Knit.CreateController(CameraController)

function CameraController:KnitInit()
	local self = CameraController
end

function CameraController:KnitStart()
	local self = CameraController
end

return CameraController
