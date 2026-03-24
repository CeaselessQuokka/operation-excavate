--[[
	Legacy proxy — re-exports Litmus so existing require paths still resolve.
	Prefer requiring ReplicatedStorage.Shared.Litmus directly.
--]]

--!strict

return require(game:GetService("ReplicatedStorage").Shared.Litmus)
