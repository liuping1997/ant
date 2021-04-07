local imgui     = require "imgui"
local math3d    = require "math3d"
local uiconfig  = require "widget.config"
local uiutils   = require "widget.utils"
local hierarchy = require "hierarchy"
local uiproperty    = require "widget.uiproperty"
local light_gizmo
local gizmo

local m = {}
local world
local worldedit
local iom
local camera_mgr
local light_panel
local camera_panel
local material_panel
local base_panel
local slot_panel
local collider_panel
local effect_panel
local current_panel
local current_eid

local camera_ui_data = {
    target          = {-1},
    dist            = {5, speed = 0.1},
    fov_axis        = {text = "vert"},
    field_of_view   = {30, speed = 0.5},
    near_plane      = {0.1},
    far_plane       = {300},
    current_frame   = 1,
    duration        = {}
}

local function update_ui_data(eid)
    if not current_panel then return end
    -- update transform
    if current_panel.super then
        -- BaseView
        current_panel.super.update(current_panel)
    else
        current_panel:update()
    end
end

function m.update_template_tranform(eid)
    if not eid then return end
    
    local template = hierarchy:get_template(eid)
    
    if not template or not template.template then return end

    local s, r, t = math3d.srt(iom.srt(eid))
    local ts, tr, tt = math3d.totable(s), math3d.totable(r), math3d.totable(t)
    template.template.data.transform = {
        r = {tr[1], tr[2], tr[3], tr[4]},
        s = {ts[1], ts[2], ts[3]},
        t = {tt[1], tt[2], tt[3]}
    }
end

function m.update_ui(ut)
    local eid = gizmo.target_eid
    update_ui_data(eid)
    if ut then
        m.update_template_tranform(eid)
    end
end

local function on_position_dirty(eid, pos)
    local oldPos = math3d.totable(iom.get_position(eid))
    local newPos = {pos[1], pos[2], pos[3]}
    gizmo:set_position(pos)
    world:pub {"EntityEvent", "move", eid, oldPos, newPos}
    if world[eid].camera then
        local frames = camera_mgr.get_recorder_frames(eid)
        frames[camera_ui_data.current_frame].position = math3d.ref(iom.get_position(eid))
        camera_mgr.update_frustrum(eid)
    elseif world[eid].light_type then
        light_gizmo.update()
    end
end

local function on_rotate_dirty(eid, rot)
    local oldRot = math3d.totable(iom.get_rotation(eid))
    local newRot = {rot[1], rot[2], rot[3]}
    local quat = math3d.quaternion(newRot)
    gizmo:set_rotation(quat)
    world:pub {"EntityEvent", "rotate", eid, oldRot, newRot}
    if world[eid].camera then
        local frames = camera_mgr.get_recorder_frames(eid)
        frames[camera_ui_data.current_frame].rotation = math3d.ref(quat)
        camera_mgr.update_frustrum(eid)
    elseif world[eid].light_type then
        light_gizmo.update()
    end
end

local function on_scale_dirty(eid, scale)
    if world[eid].camera then
        
    else
        local oldScale = math3d.totable(iom.get_scale(eid))
        gizmo:set_scale(scale)
        world:pub {"EntityEvent", "scale", eid, oldScale, {scale[1], scale[2], scale[3]}}
    end
end

local function set_current_frame(eid, idx, force)
    if camera_ui_data.current_frame == idx and not force then return end
    camera_ui_data.current_frame = idx
    update_ui_data(eid)
    camera_mgr.set_frame(eid, idx)
end

local function show_camera_property(eid)
    if imgui.widget.TreeNode("Camera", imgui.flags.TreeNode { "DefaultOpen" }) then
        local what
        local value
        if imgui.widget.InputInt("Target", camera_ui_data.target) then
            if hierarchy:get_node(camera_ui_data.target[1]) then
                what = "target"
                value = camera_ui_data.target[1]
            end
        end
        if camera_ui_data.target ~= -1 then
            if imgui.widget.DragFloat("Dist", camera_ui_data.dist) then
                what = "dist"
                value = camera_ui_data.dist[1]
            end
        end
        if imgui.widget.DragFloat("FOV", camera_ui_data.field_of_view) then
            what = "fov"
            value = camera_ui_data.field_of_view[1]
        end
        if imgui.widget.DragFloat("Near", camera_ui_data.near_plane) then
            what = "near"
            value = camera_ui_data.near_plane[1]
        end
        if imgui.widget.DragFloat("Far", camera_ui_data.far_plane) then
            what = "far"
            value = camera_ui_data.far_plane[1]
        end
        imgui.cursor.Separator()
        if imgui.widget.Button("AddFrame") then
            local new_idx = camera_ui_data.current_frame + 1
            camera_mgr.add_recorder_frame(eid, new_idx)
            set_current_frame(eid, new_idx, true)
            local frames = camera_mgr.get_recorder_frames(eid)
            camera_ui_data.duration[new_idx] = {frames[new_idx].duration}
        end
        local frames = camera_mgr.get_recorder_frames(eid)
        if #frames > 1 then
            imgui.cursor.SameLine()
            if imgui.widget.Button("DeleteFrame") then
                camera_mgr.delete_recorder_frame(eid, camera_ui_data.current_frame)
                table.remove(camera_ui_data.duration, camera_ui_data.current_frame)
                if camera_ui_data.current_frame > #frames then
                    set_current_frame(eid, #frames)
                end
            end
            imgui.cursor.SameLine()
            if imgui.widget.Button("Play") then
                camera_mgr.play_recorder(eid)
            end
        end
        if #frames > 0 then
            imgui.cursor.Separator()
            if imgui.table.Begin("InspectorTable", 2, imgui.flags.Table {'Resizable', 'ScrollY'}) then
                imgui.table.SetupColumn("FrameIndex")
                imgui.table.SetupColumn("Duration")
                imgui.table.HeadersRow()
                for i, v in ipairs(frames) do
                    imgui.table.NextColumn()
                    if imgui.widget.Selectable(i, camera_ui_data.current_frame == i) then
                        set_current_frame(eid, i)
                    end
                    imgui.table.NextColumn()
                    if imgui.widget.DragFloat("##"..i, camera_ui_data.duration[i]) then
                        frames[i].duration = camera_ui_data.duration[i][1]
                    end
                end
                imgui.table.End()    
            end
        end

        if what then
            world:pub {"CameraEdit", what, eid, value}
        end
        imgui.widget.TreePop()
    end
end

local function get_camera_panel()
    if not camera_panel then
        camera_panel = require "widget.camera_view"(world)()
    end
    return camera_panel
end

local function get_light_panel()
    if not light_panel then
        light_panel = require "widget.light_view"(world)()
    end
    return light_panel
end

local function get_material_panel()
    if not material_panel then
        material_panel = require "widget.material_view"(world)()
    end
    return material_panel
end

local function get_base_panel()
    if not base_panel then
        base_panel = require "widget.base_view"(world)()
    end
    return base_panel
end

local function get_slot_panel()
    if not slot_panel then
        slot_panel = require "widget.slot_view"(world)()
    end
    return slot_panel
end

local function get_collider_panel()
    if not collider_panel then
        collider_panel = require "widget.collider_view"(world)()
    end
    return collider_panel
end
local function get_effect_panel()
    if not effect_panel then
        effect_panel = require "widget.effect_view"(world)()
    end
    return effect_panel
end
local function update_current()
    if current_eid == gizmo.target_eid then return end
    current_eid = gizmo.target_eid
    if current_eid then
        if world[current_eid].collider then
            current_panel = get_collider_panel()
        elseif world[current_eid].camera then
            current_panel = get_camera_panel()
        elseif world[current_eid].light_type then
            current_panel = get_light_panel()
        elseif world[current_eid].slot then
            current_panel = get_slot_panel()
        elseif world[current_eid].material then
            current_panel = get_material_panel()
        elseif world[current_eid].effekseer then
            current_panel = get_effect_panel()
        else
            current_panel = get_base_panel()
        end
        current_panel:set_model(current_eid)
    else
        current_panel = nil
    end
end

function m.show()
    update_current()
    local viewport = imgui.GetMainViewport()
    imgui.windows.SetNextWindowPos(viewport.WorkPos[1] + viewport.WorkSize[1] - uiconfig.PropertyWidgetWidth, viewport.WorkPos[2] + uiconfig.ToolBarHeight, 'F')
    imgui.windows.SetNextWindowSize(uiconfig.PropertyWidgetWidth, viewport.WorkSize[2] - uiconfig.BottomWidgetHeight - uiconfig.ToolBarHeight, 'F')
    for _ in uiutils.imgui_windows("Inspector", imgui.flags.Window { "NoCollapse", "NoClosed" }) do
        
        if current_panel then
            current_panel:show()
        end
    end
end

return function(w)
    world           = w
    iom             = world:interface "ant.objcontroller|obj_motion"
    icamera         = world:interface "ant.camera|camera"
    ilight          = world:interface "ant.render|light"
    worldedit       = import_package "ant.editor".worldedit(world)
    camera_mgr      = require "camera_manager"(world)
    gizmo           = require "gizmo.gizmo"(world)
    light_gizmo     = require "gizmo.light"(world)
    light_view      = require "widget.light_view"(world)
    camera_view     = require "widget.camera_view"(world)
    material_view   = require "widget.material_view"(world)
    return m
end