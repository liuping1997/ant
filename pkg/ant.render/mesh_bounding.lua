local ecs = ...
local world = ecs.world
local w = world.w

local math3d = require "math3d"
local mc = import_package "ant.math".constant
local serialization = require "bee.serialization"

local b = ecs.system "mesh_bounding_system"

local function init_bounding(bounding, bb)
    if bb and bb.aabb ~= mc.NULL then
		local aabb = bb.aabb
		math3d.unmark(bounding.aabb)
        bounding.aabb = math3d.marked_aabb(aabb[1], aabb[2])
		math3d.unmark(bounding.scene_aabb)
        bounding.scene_aabb = math3d.marked_aabb(math3d.array_index(bounding.aabb, 1), math3d.array_index(bounding.aabb, 2))
    end
end

function b:entity_init()
	for e in w:select "INIT bounding:update mesh?in simplemesh?in" do
		local m = e.mesh or e.simplemesh
		if m then
			init_bounding(e.bounding, m.bounding)
		end
	end
end

local b = ecs.component "bounding"

function b.init(v)
	if not v then
		v = {}
	end
	if v.aabb then
		v.aabb = math3d.marked_aabb(v.aabb[1], v.aabb[2])
		v.scene_aabb = math3d.marked_aabb()
	else
		v.aabb = mc.NULL
		v.scene_aabb = mc.NULL
	end
	return v
end

function b.remove(v)
    math3d.unmark(v.aabb)
    math3d.unmark(v.scene_aabb)
end

function b.marshal(v)
	return serialization.packstring(v)
end

function b.demarshal(s)
	local bounding = serialization.unpack(s)
	math3d.unmark(bounding.aabb)
	math3d.unmark(bounding.scene_aabb)
end

function b.unmarshal(v)
	local bounding = serialization.unpack(v)
	math3d.mark(bounding.aabb)
	math3d.mark(bounding.scene_aabb)
	return bounding
end