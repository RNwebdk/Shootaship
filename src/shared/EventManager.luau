--[[
	EventManager
	============
	Creates and finds RemoteEvents defined in EventDefs.
	
	WHY this exists:
	  Instead of manually creating RemoteEvent objects in Studio or scattering
	  Instance.new("RemoteEvent") calls everywhere, we create them all in one
	  place from our EventDefs list.
	
	HOW it works:
	  - Server calls EventManager.createEvents() once at startup
	    → Creates a RemoteEvent for each name in EventDefs
	    → Puts them all in ReplicatedStorage.Events folder
	  
	  - Both client and server call EventManager.getEvent("EventName")
	    → Finds and returns the RemoteEvent object
	    → Errors if it doesn't exist (catches typos early)
	
	ANALOGY:
	  Think of this like setting up API routes. The server "registers" all
	  the endpoints at startup, and both sides can look them up by name.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local EventDefs = require(ReplicatedStorage.Shared.EventDefs)

local EventManager = {}

-- Lazily resolved: we don't fetch the folder at module load time
-- because on the server, it may not exist yet (we create it in createEvents).
-- On the client, we use WaitForChild when needed.
local eventsFolder = nil

-- Helper to get the events folder (resolves it once)
local function getEventsFolder()
	if eventsFolder then return eventsFolder end
	
	if RunService:IsServer() then
		-- On server: FindFirstChild or create it
		eventsFolder = ReplicatedStorage:FindFirstChild("Events")
		if not eventsFolder then
			eventsFolder = Instance.new("Folder")
			eventsFolder.Name = "Events"
			eventsFolder.Parent = ReplicatedStorage
		end
	else
		-- On client: wait for it to replicate from the server
		eventsFolder = ReplicatedStorage:WaitForChild("Events", 15)
		if not eventsFolder then
			error("[EventManager] Timed out waiting for Events folder from server")
		end
	end
	
	return eventsFolder
end

--[[
	Creates all RemoteEvents defined in EventDefs.
	ONLY call this from the server, and only once at startup.
	
	Why server-only? In Roblox, the server is the authority.
	Clients cannot create objects that replicate to everyone —
	only the server can. This is a security feature.
]]
function EventManager.createEvents()
	local folder = getEventsFolder()
	for eventName, _description in EventDefs do
		-- Check if it already exists (in case of hot-reload)
		if not folder:FindFirstChild(eventName) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = eventName
			remote.Parent = folder
		end
	end

	print("[EventManager] Created", #EventManager.getEventNames(), "remote events")
end

--[[
	Gets a RemoteEvent by name.
	Call from EITHER client or server.
	
	Throws an error if the event doesn't exist — this catches typos
	at development time instead of causing silent bugs.
]]
function EventManager.getEvent(eventName: string): RemoteEvent
	local folder = getEventsFolder()
	local event = folder:FindFirstChild(eventName)
	if not event then
		error("[EventManager] No RemoteEvent named '" .. eventName .. "'. Check EventDefs.luau")
	end
	return event
end

--[[
	Waits for a RemoteEvent by name (useful on the client).
	
	WHY wait? When a client joins, the RemoteEvents may not have
	replicated from the server yet. WaitForChild pauses until
	the object appears (with a timeout to avoid infinite hangs).
]]
function EventManager.waitForEvent(eventName: string, timeout: number?): RemoteEvent
	local folder = getEventsFolder()
	local event = folder:WaitForChild(eventName, timeout or 10)
	if not event then
		error("[EventManager] Timed out waiting for RemoteEvent '" .. eventName .. "'")
	end
	return event
end

-- Helper: get all event names for logging
function EventManager.getEventNames(): { string }
	local names = {}
	for eventName, _ in EventDefs do
		table.insert(names, eventName)
	end
	return names
end

return EventManager
