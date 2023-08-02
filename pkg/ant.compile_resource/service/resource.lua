local ltask   = require "ltask"
import_package "ant.service".init_bgfx()

local bgfx = require "bgfx"
bgfx.init()

local cr = require "thread.compile"
cr.init()

local texture = require "thread.texture"
local material = require "thread.material"

local S = require "thread.main"

function S.compile(path)
    return cr.compile(path):string()
end

local quit

ltask.fork(function ()
    bgfx.encoder_create "resource"
    while not quit do
        texture.update()
        material.update()
        bgfx.encoder_frame()
    end
    bgfx.encoder_destroy()
    ltask.wakeup(quit)
end)

function S.quit()
    quit = {}
    ltask.wait(quit)
    bgfx.shutdown()
    ltask.quit()
end

return S
