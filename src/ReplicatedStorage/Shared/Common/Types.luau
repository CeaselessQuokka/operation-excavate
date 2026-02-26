--- Types ---
--- Knit remote types.
-- When the client fires the server.
export type ServerRemoteSignal<Params...> = {
	Fire: (self: ServerRemoteSignal<Params...>, Params...) -> (),
	Connect: (self: ServerRemoteSignal<Params...>, (Player, Params...) -> ()) -> RBXScriptConnection,
}

-- When the server fires the client.
export type ClientRemoteSignal<Params...> = {
	Fire: (self: ClientRemoteSignal<Params...>, Player, Params...) -> (),
	FireAll: (self: ClientRemoteSignal<Params...>, Params...) -> (),
	Connect: (self: ClientRemoteSignal<Params...>, (Params...) -> ()) -> RBXScriptConnection,
}

return true
