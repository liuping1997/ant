local ecs = ...
local world = ecs.world
local w = world.w

local math3d = require "math3d"

----iscenespace----
local iss = ecs.interface "iscenespace"
function iss.set_parent(eid, peid)
	local e = world[eid]
	local pe = world[peid]
	if (not e or e.scene_entity) and (not pe or pe.scene_entity) then
		e.parent = peid
		world:pub {"old_parent_changed", eid, peid}
	end
end

local m = ecs.action "mount"
function m.init(prefab, i, value)
	iss.set_parent(prefab[i], prefab[value])
end


----scenespace_system----
local s = ecs.system "scenespace_system"

local evOldParentChanged = world:sub {"old_parent_changed"}
local evNewParentChanged = world:sub {"new_parent_changed"}

local function inherit_render_object(r, pr)
	if r.fx == nil then
		r.fx = pr.fx
	end
	if r.state == nil then
		r.state = pr.state
	end
	if r.properties == nil then
		r.properties = pr.properties
	end
	local pstate = pr.entity_state
	if pstate then
		local MASK <const> = (1 << 32) - 1
		local state = r.entity_state or 0
		r.entity_state = ((state>>32) | state | pstate) & MASK
	end
end

local current_changed = 1
local current_sceneid = 0

local function new_sceneid()
	current_sceneid = current_sceneid + 1
	return current_sceneid
end

local function update_worldmat_noparent(node)
	if node.srt == nil then
		node._worldmat = nil
	else
		node._worldmat = math3d.matrix(node.srt)
	end
end

local function update_worldmat(node, parent)
	if parent.changed > node.changed then
		node.changed = parent.changed
	end
	if parent._worldmat then
		if node.srt == nil then
			node._worldmat = math3d.matrix(parent._worldmat)
		else
			node._worldmat = math3d.mul(parent._worldmat, math3d.matrix(node.srt))
		end
	else
		if node.srt == nil then
			node._worldmat = nil
		else
			node._worldmat = math3d.matrix(node.srt)
		end
	end
end

local function update_aabb(node)
	if node._worldmat == nil or node.aabb == nil then
		node._aabb = nil
	else
		node._aabb = math3d.aabb_transform(node._worldmat, node.aabb)
	end
end

local function findScene(hashmap, eid)
	local scene = hashmap[eid]
	if scene then
		return scene
	end
	local e
	if type(eid) == "table" then
		e = eid
	else
		for v in w:select "eid:in" do
			if v.eid == eid then
				e = v
				break
			end
		end
	end
	w:sync("scene:in", e)
	scene = e.scene
	hashmap[eid] = scene
	return scene
end

local function findSceneNode(eid)
	for v in w:select "eid:in" do
		if v.eid == eid then
			w:sync("scene:in", v)
			return v.scene
		end
	end
end

local function isValidReference(reference)
    return reference[1] ~= nil
end

function s:entity_init()
	local needsync = false

	local hashmap = {}
	for v in w:select "INIT camera:in scene:out" do
		local camera = v.camera
		local viewmat = math3d.lookto(camera.eyepos, camera.viewdir, camera.updir)
		v.scene = {
			srt = math3d.inverse(viewmat),
			updir = camera.updir
		}
	end
	for v in w:select "INIT scene:in eid?in scene_sorted?new" do
		local scene = v.scene
		if scene.srt then
			scene.srt = math3d.ref(math3d.matrix(scene.srt))
		end
		if scene.updir then
			scene.updir = math3d.ref(math3d.vector(scene.updir))
		end
		scene.changed = current_changed

		scene.id = new_sceneid()
		if v.eid then
			hashmap[v.eid] = scene
		end
		v.scene_sorted = true
		needsync = true
	end
	for v in w:select "INIT camera:in scene:in" do
		v.camera.srt = v.scene.srt
	end
	for v in w:select "INIT render_object:in scene:in" do
		v.render_object.srt = v.scene.srt
	end

	for v in w:select "scene_unsorted scene:in scene_sorted?new" do
		v.scene_sorted = true
		v.scene.changed = current_changed
	end
	w:clear "scene_unsorted"

	for _, eid, peid in evOldParentChanged:unpack() do
		local scene = findScene(hashmap, eid)
		scene.changed = current_changed
		if peid then
			scene.parent = findScene(hashmap, peid).id
		else
			scene.parent = nil
		end
		needsync = true
	end

	for _, e, parent in evNewParentChanged:unpack() do
		if isValidReference(e) then
			w:sync("scene:in", e)
			e.scene.changed = current_changed
			if not parent or not isValidReference(parent) then
				e.scene.parent = nil
			else
				w:sync("scene:in", parent)
				e.scene.parent = parent.scene.id
			end
			needsync = true
		end
	end

	if needsync then
		local cache = {}
		for v in w:select "scene_sorted scene:in render_object?in INIT?in" do
			local scene = v.scene
			if scene.parent == nil then
				cache[scene.id] = v.render_object or false
			else
				local parent = cache[scene.parent]
				if parent ~= nil then
					cache[scene.id] = v.render_object or false
					if v.INIT then
						local r = v.render_object
						local pr = cache[scene.parent]
						if r and pr then
							inherit_render_object(r, pr)
						end
					end
				else
					v.scene_sorted = false -- yield
				end
			end
		end
	end
end

function s:update_hierarchy()
end

local evSceneChanged = world:sub {"scene_changed"}

function s:update_transform()
	for _, eid in evSceneChanged:unpack() do
		local scene
		if type(eid) == "table" then
			local ref = eid
			w:sync("scene:in", ref)
			scene = ref.scene
		else
			scene = findSceneNode(eid)
		end
		scene.changed = current_changed
	end

	local cache = {}
	for v in w:select "scene_sorted scene:in scene_changed?out" do
		local scene = v.scene
		if scene.parent == nil then
			cache[scene.id] = scene
			update_worldmat_noparent(scene)
			update_aabb(scene)
			if scene.changed == current_changed then
				v.scene_changed = true
			end
		else
			local parent = cache[scene.parent]
			if parent then
				cache[scene.id] = scene
				update_worldmat(scene, parent)
				update_aabb(scene)
				if scene.changed == current_changed then
					v.scene_changed = true
				end
			else
				v.scene_sorted = false -- yield
			end
		end
	end
	for v in w:select "render_object:in scene:in" do
		local r, n = v.render_object, v.scene
		r.aabb = n._aabb
		r.worldmat = n._worldmat
	end
	for v in w:select "camera:in scene:in" do
		local r, n = v.camera, v.scene
		r.worldmat = n._worldmat
		r.updir = n.updir
	end
	current_changed = current_changed + 1
end

local function hasSceneRemove()
	for _ in w:select "REMOVED scene" do
		return true
	end
end

function s:scene_remove()
	w:clear "scene_changed"
	if hasSceneRemove() then
		local cache = {}
		for v in w:select "scene_sorted scene:in" do
			local scene = v.scene
			if scene.parent == nil then
				cache[scene.id] = scene
			else
				local parent = cache[scene.parent]
				if parent then
					cache[scene.id] = scene
					if not scene.removed and parent.removed then
						scene.removed = true
						w:remove(v)
					end
				else
					v.scene_sorted = false -- yield
				end
			end
		end
	end
end

function ecs.method.init_scene(e)
	e.scene_unsorted = true
	w:sync("scene:in scene_unsorted?out", e)
	local scene = e.scene
	scene.id = new_sceneid()
	if scene.srt then
		scene.srt = math3d.ref(math3d.matrix(scene.srt))
	end
	if scene.updir then
		scene.updir = math3d.ref(math3d.vector(scene.updir))
	end
end

function ecs.method.set_parent(e, parent)
	world:pub {"new_parent_changed", e, parent}
end
