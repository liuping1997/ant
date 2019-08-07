local fs = require "filesystem"

local resources = {
	sc		= {},
	mesh 	= {},
	state 	= {},
	material= {},
	texture = {},
	hierarchy = {},--scene hierarchy info, using ozz-animation runtime struct
	lk 		= {},
	ozz 	= {},
	sm 		= {},	--animation state machine
	terrain = {},
}

local accessors = {}

local assetmgr = {}
assetmgr.__index = assetmgr
assetmgr.__gc = function()
	for name, subres in pairs(resources) do
		if next(subres) then
			print("sub resource not remove:", name)
			for reskey in pairs(subres) do
				print("resource:", reskey)
			end
		end
	end
end

local function get_accessor(name)
	local accessor = accessors[name]
	if accessor == nil then
		if resources[name] then
			accessor 		= require ("ext_" .. name)
			accessors[name] = accessor
		else
			error("Unsupport asset type: " .. name)
		end
	end
	return accessor
end

function assetmgr.get_loader(name)
	return get_accessor(name).loader
end

function assetmgr.get_unloader(name)
	return get_accessor(name).unloader
end

local function rawtable(filepath)
	local env = {}
	local r = assert(fs.loadfile(filepath, "t", env))
	r()
	return env
end

function assetmgr.get_depiction_path(fullpath)	
	if not fs.exists(fullpath) then
		local pkgdir = fs.path("/pkg") / fullpath:package_name()
		fullpath = pkgdir / "depiction" / fs.relative(fullpath, pkgdir)
		if not fs.exists(fullpath) then
			return nil
		end
	end

	return fullpath
end

function assetmgr.get_depiction(fullpath)
	local newfullpath = assetmgr.get_depiction_path(fullpath)
	if newfullpath == nil then
		error(string.format("not found file:%s", fullpath:string()))
	end
	return rawtable(newfullpath)
end

local function res_key(filename)
	-- TODO, should use vfs to get the resource file unique key(resource hash), for cache same content file	
	return filename:string()
end

local function module_name(filepath)
	return filepath:extension():string():match "%.(.+)$"
end

local function get_subres(filename)
	assert(type(filename) ~= "string")

	local modulename = module_name(filename)
	return resources[modulename]	
end

local function insert_resource(subres, reskey, content)
	local res = {
		handle 		= content,
		lastframe 	= -1,
		ref_count	= 1,
	}
	subres[reskey] = res
	return res
end

function assetmgr.load(filename, param)	
	local subres = get_subres(filename)
	if subres == nil then
		log.error(string.format("not found ext from file:%s", filename:string()))
	end

	local reskey = res_key(filename)

	local res = subres[reskey]
	if res == nil then
		local loader = assetmgr.get_loader(module_name(filename))
		local handle = loader(filename, param)
		res = insert_resource(subres, reskey, handle)
	else
		res.ref_count = res.ref_count + 1
	end

	return res.handle
end

function assetmgr.unload(filename)
	local subres = get_subres(filename)
	if subres == nil then
		log.error("not found sub resource from file:", filename:string())
	end

	local reskey = res_key(filename)
	local res = subres[reskey]

	if res then
		if res.ref_count <= 0 then
			log.error("unload a resource which ref count low or equal to 0", filename:string())
		end
	
		res.ref_count = res.ref_count - 1
		if res.ref_count == 0 then
			subres[reskey] = nil
			local unloader = assetmgr.get_unloader(module_name(filename))
			if unloader then
				unloader(res, filename)
			end
		end
	else
		log.warn("unload a not reference resource:", filename:string(), "resource maybe loading from asyn_asset_loader")
	end
end

function assetmgr.register_resource(reffile, content)
	local subres = get_subres(reffile)
	if subres == nil then
		log.error("try register resource, but not found subres from reference filename:", reffile:string())
	end

	local reskey = res_key(reffile)
	if subres[reskey] then
		log.error("register duplicate resource:", reffile:string())
	end
	insert_resource(subres, res_key(reffile), content)
	return reffile
end

local function get_resource(subres, key)
	assert(type(key) ~= "string")
	local reskey = res_key(key)
	local res = subres[reskey]
	if res then
		assert(res.ref_count > 0)
		return res.handle
	end
end

for _, subname in ipairs {"texture", "mesh", "material"} do
	local subres = resources[subname]
	assetmgr["get_" .. subname] = function (key)
		return get_resource(subres, key)
	end
end

function assetmgr.get_resource(key)
	local modulename = module_name(key)

	local subres = resources[modulename]
	return get_resource(subres, key)
end

function assetmgr.save(tree, filename)	
	local seri = import_package "ant.serialize"
	seri.save(filename, tree)
end

function assetmgr.has_res(filename)
	local key = res_key(filename)
	return resources[key] ~= nil
end

return assetmgr
