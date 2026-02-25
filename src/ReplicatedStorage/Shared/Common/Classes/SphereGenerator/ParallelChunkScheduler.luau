--[[
	Manages a persistent pool of Actor-based parallel workers for chunk generation.
	Workers are created once and reused across all generation requests.
	Call SetPlanet() to configure workers for a planet (instant — workers clone the
	precomputed data from the shared require() cache, no grid recomputation).

	Usage:
		local scheduler = ParallelChunkScheduler.new()
		scheduler:SetPlanet(planet) -- configure workers for this planet
		local results = scheduler:GenerateChunks({chunkIndex1, chunkIndex2, ...})
		scheduler:ScheduleChunks({chunkIndex3, chunkIndex4}) -- fire-and-forget
		scheduler:Destroy()
]]

--!strict

--- Services ---
local ServerScriptService = game:GetService("ServerScriptService")

--- Imports ---
local PlanetGeneratorModule = require(script.Parent.PlanetGenerator)

--- Types ---
type PlanetGenerator = PlanetGeneratorModule.PlanetGenerator
type GenerateChunkResult = PlanetGeneratorModule.GenerateChunkResult

type WorkerInfo = {
	Actor: Actor,
	CompletionEvent: BindableEvent,
}

--- Variables ---
local DEFAULT_WORKER_COUNT = 8

--- Parallel Chunk Scheduler Class ---
local ParallelChunkScheduler = {}
ParallelChunkScheduler.__index = ParallelChunkScheduler

export type ParallelChunkScheduler = typeof(setmetatable(
	{} :: {
		_workers: { WorkerInfo },
		_workerCount: number,
		_container: Folder,
		_connections: { RBXScriptConnection },
		_pending: { [number]: (string, number) -> () },
	},
	ParallelChunkScheduler
))

--- Creates the worker actor pool. Workers are persistent and planet-agnostic.
--- Call SetPlanet() before dispatching any generation work.
function ParallelChunkScheduler.new(workerCount: number?): ParallelChunkScheduler
	local count = workerCount or DEFAULT_WORKER_COUNT
	local workerTemplate = script.Parent:FindFirstChild("ChunkWorker") :: Script
	assert(workerTemplate, "[ParallelChunkScheduler] ChunkWorker script not found in SphereGenerator")

	local container = Instance.new("Folder")
	container.Name = "ChunkWorkerPool"
	container.Parent = ServerScriptService

	local workers: { WorkerInfo } = table.create(count)

	for i = 1, count do
		local workerActor = Instance.new("Actor")
		workerActor.Name = `ChunkWorker_{i}`

		local completionEvent = Instance.new("BindableEvent")
		completionEvent.Name = "ChunkCompleted"
		completionEvent.Parent = workerActor

		local workerScript = workerTemplate:Clone()
		workerScript.Parent = workerActor

		workerActor.Parent = container

		workers[i] = {
			Actor = workerActor,
			CompletionEvent = completionEvent,
		}
	end

	local pending: { [number]: (string, number) -> () } = {}

	local connections: { RBXScriptConnection } = table.create(count)
	for i, worker in workers do
		connections[i] = worker.CompletionEvent.Event:Connect(
			function(chunkIndex: number, chunkType: string, chunkSeed: number)
				local callback = pending[chunkIndex]
				if callback then
					pending[chunkIndex] = nil
					callback(chunkType, chunkSeed)
				end
			end
		)
	end

	local self: ParallelChunkScheduler = setmetatable({
		_workers = workers,
		_workerCount = count,
		_container = container,
		_connections = connections,
		_pending = pending,
	}, ParallelChunkScheduler)

	print(`[ParallelChunkScheduler] Created {count} worker actors`)

	return self
end

--- Configures all workers for a planet. Each worker creates its own PlanetGenerator
--- instance (Actors have isolated VMs). Construction runs serially (~0.4s per worker)
--- to guarantee deterministic results. Yields until all workers are ready.
function ParallelChunkScheduler.SetPlanet(self: ParallelChunkScheduler, planet: PlanetGenerator): ()
	local startTime = os.clock()

	-- Wait for all workers to have their message handlers bound before sending anything.
	-- SendMessage is fire-and-forget; messages are dropped if no handler is bound yet.
	for _, worker in self._workers do
		while not worker.Actor:GetAttribute("Initialized") do
			worker.Actor:GetAttributeChangedSignal("Initialized"):Wait()
		end
	end

	-- Reset ready state and send planet config.
	for _, worker in self._workers do
		worker.Actor:SetAttribute("Ready", false)
		worker.Actor:SendMessage("SetPlanet", planet.MasterSeed, planet.ChunkSize)
	end

	-- Wait for all workers to finish cloning.
	for _, worker in self._workers do
		while not worker.Actor:GetAttribute("Ready") do
			worker.Actor:GetAttributeChangedSignal("Ready"):Wait()
		end
	end

	print(
		`[ParallelChunkScheduler] {self._workerCount} workers configured in {string.format(
			"%.2f",
			os.clock() - startTime
		)}s`
	)
end

--- Generates chunks in parallel and yields until every chunk is complete.
--- Returns a map of chunkIndex → GenerateChunkResult.
function ParallelChunkScheduler.GenerateChunks(
	self: ParallelChunkScheduler,
	chunkIndices: { number }
): { [number]: GenerateChunkResult }
	local total = #chunkIndices
	if total == 0 then
		return {}
	end

	local results: { [number]: GenerateChunkResult } = {}
	local remaining = total
	local thread = coroutine.running()

	for _, chunkIndex in chunkIndices do
		self._pending[chunkIndex] = function(chunkType: string, chunkSeed: number)
			results[chunkIndex] = { ChunkType = chunkType, ChunkSeed = chunkSeed }
			remaining -= 1
			if remaining == 0 then
				task.spawn(thread)
			end
		end
	end

	local workerCount = self._workerCount
	for i, chunkIndex in chunkIndices do
		local workerIndex = ((i - 1) % workerCount) + 1
		self._workers[workerIndex].Actor:SendMessage("GenerateChunk", chunkIndex)
	end

	if remaining > 0 then
		coroutine.yield()
	end

	return results
end

--- Dispatches chunks to workers without waiting for completion (fire-and-forget).
--- Terrain is still written by workers; results are simply not tracked.
function ParallelChunkScheduler.ScheduleChunks(self: ParallelChunkScheduler, chunkIndices: { number }): ()
	local workerCount = self._workerCount
	for i, chunkIndex in chunkIndices do
		local workerIndex = ((i - 1) % workerCount) + 1
		self._workers[workerIndex].Actor:SendMessage("GenerateChunk", chunkIndex)
	end
end

--- Cleans up all worker actors and connections.
function ParallelChunkScheduler.Destroy(self: ParallelChunkScheduler): ()
	for _, conn in self._connections do
		conn:Disconnect()
	end
	self._container:Destroy()
	table.clear(self._workers)
	table.clear(self._pending)
end

return table.freeze(ParallelChunkScheduler)
