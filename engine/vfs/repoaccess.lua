local access = {}

local lfs = require "bee.filesystem"
local platform = require "bee.platform"
local datalist = require "datalist"

local isWindows <const> = platform.os == "windows"

function access.addmount(repo, path)
	if not lfs.exists(path) then
		return
	end
	for _, value in ipairs(repo._mountpoint) do
		if value:string() == path then
			return
		end
	end
	repo._mountpoint[#repo._mountpoint+1] = lfs.absolute(path):lexically_normal()
end

local MountConfig <const> = [[
mount:
    %engine%
    %project%
    %project%/mod
engine:
    engine
    pkg
extension:
    .settings
    .prefab
    .ecs
    .lua
    .rcss
    .rml
    .efk
    .ttf
    .otf
    .ttc
    .bank
    .event
    .anim
    .bin
    .cfg
    .ozz
    .vbbin
    .vb2bin
    .ibbin
    .meshbin
    .skinbin
]]

local function loadmount(repo)
	local f <close> = io.open((repo._root / ".mount"):string(), "rb")
	if f then
		local cfg = datalist.parse(f:read "a")
		if cfg then
			return cfg
		end
	end
	return datalist.parse(MountConfig)
end

function access.readmount(repo)
	local cfg = loadmount(repo)
	repo._mountengine = cfg.engine
	repo._mountextension = cfg.extension
	repo._mountpoint = {}
	for _, line in ipairs(cfg.mount) do
		access.addmount(repo, line:gsub("%%([^%%]*)%%", {
			engine = lfs.current_path():string(),
			project = repo._root:string():gsub("(.-)[/\\]?$", "%1"),
		}))
	end
end

function access.realpath(repo, pathname)
	local mountpoint = repo._mountpoint
	for i = #mountpoint, 1, -1 do
		local path = #pathname > 1 and mountpoint[i] / pathname:sub(2) or mountpoint[i]
		if lfs.exists(path) then
			return path
		end
	end
end

local function is_resource(path)
	path = path:string()
	local ext = path:match "[^/]%.([%w*?_%-]*)$"
	if ext ~= "material" and ext ~= "glb"  and ext ~= "texture" then
		return false
	end
	if path:sub(1,8) == "/.build/" then
		return false
	end
	return true
end

local function get_type(path)
	if lfs.is_directory(path) then
		return "dir"
	elseif is_resource(path) then
		return "dir"
	elseif lfs.is_regular_file(path) then
		return "file"
	end
end

function access.type(repo, pathname)
	local rpath = access.realpath(repo, pathname)
	if rpath then
		return get_type(rpath)
	end
end

local path_eq; do
	if isWindows then
		function path_eq(a, b)
			return a:lower() == b:lower()
		end
	else
		function path_eq(a, b)
			return a == b
		end
	end
end

function access.virtualpath(repo, pathname)
	pathname = lfs.absolute(pathname):lexically_normal():string()
	for _, mpath in ipairs(repo._mountpoint) do
		mpath = mpath:string()
		if path_eq(pathname, mpath) then
			return "/"
		end
		local n = #mpath + 1
		if path_eq(pathname:sub(1,n), mpath .. '/') then
			return pathname:sub(n)
		end
	end
end

function access.list_files(repo, pathname)
	local files = {}
	local start = 1
	if pathname == "/" and not repo._resource then
		local mountpoint = repo._mountpoint[1]
		for _, name in ipairs(repo._mountengine) do
			files[name] = lfs.status(mountpoint / name)
		end
		start = 2
	end
	for i = start, #repo._mountpoint do
		local mountpoint = repo._mountpoint[i]
		local path = mountpoint / pathname:sub(2)
		if lfs.is_directory(path) then
			for name, status in lfs.pairs(path) do
				local filename = name:filename():string()
				if filename:sub(1,1) ~= "." then
					files[filename] = status
				end
			end
		end
	end
	return files
end

return access
