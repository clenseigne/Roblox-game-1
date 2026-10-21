-- Pulls every script listed in manifest.json from the local dev server (python -m http.server
-- serving the game/ folder on 127.0.0.1:8765) and rebuilds the managed script folders in Studio.
-- HttpService is only enabled for the duration of the sync.
local HttpService = game:GetService("HttpService")
local BASE = "http://127.0.0.1:8765/src/"

-- The top-level folder under each service is owned by the sync and replaced wholesale.
local ROOT_SERVICES = {
	ReplicatedStorage = game:GetService("ReplicatedStorage"),
	ServerScriptService = game:GetService("ServerScriptService"),
	StarterPlayerScripts = game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts"),
}

local was = HttpService.HttpEnabled
HttpService.HttpEnabled = true
local ok, result = pcall(function()
	local manifest = HttpService:JSONDecode(HttpService:GetAsync(BASE .. "manifest.json", true))
	local sources = {}
	for _, e in manifest do
		sources[e.url] = HttpService:GetAsync(BASE .. e.url, true)
	end
	return { manifest = manifest, sources = sources }
end)
HttpService.HttpEnabled = was
if not ok then
	return "sync failed: " .. tostring(result)
end

-- Build everything detached first, then swap folders in, so a failed sync never half-applies.
local built: { [string]: Folder } = {}
for _, e in result.manifest do
	local service = e.parents[1]
	local top = e.parents[2]
	local key = service .. "/" .. top
	if not built[key] then
		local f = Instance.new("Folder")
		f.Name = top
		built[key] = f
	end
	local parent: Instance = built[key]
	for i = 3, #e.parents do
		parent = parent:FindFirstChild(e.parents[i]) or (function()
			local f = Instance.new("Folder")
			f.Name = e.parents[i]
			f.Parent = parent
			return f
		end)()
	end
	local s = Instance.new(e.class)
	s.Name = e.name;
	(s :: any).Source = result.sources[e.url]
	s.Parent = parent
end

local summary = {}
for key, folder in built do
	local service, top = string.match(key, "([^/]+)/(.+)")
	local root = ROOT_SERVICES[service]
	local old = root:FindFirstChild(top)
	if old then
		old:Destroy()
	end
	folder.Parent = root
	table.insert(summary, key .. " (" .. #folder:GetDescendants() .. ")")
end
return "synced " .. #result.manifest .. " scripts: " .. table.concat(summary, ", ")
