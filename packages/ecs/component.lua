local foreach_init

local function foreach_single_init(c, schema)
    if c.method and c.method.init then
        return c.method.init()
    end
    if schema.map[c.type] then
        return foreach_init(schema.map[c.type], schema)
    end
    if c.type == 'int' then
        return 0
    elseif c.type == 'real' then
        return 0.0
    elseif c.type == 'string' then
        return ""
    elseif c.type == 'boolean' then
        return false
    elseif c.type == 'primtype' then
        return nil
    else
        error("unknown type:" .. c.type)
    end
end

function foreach_init(c, schema)
    if not c.type then
        local ret = {}
        for _, v in ipairs(c) do
            ret[v.name] = foreach_init(v, schema)
        end
        if c.method and c.method.init then
            return c.method.init(ret)
        end
        return ret
    end
    if c.default then
        return c.default
    end
    if c.array then
        if c.array == 0 then
            return {}
        end
        local ret = {}
        for i = 1, c.array do
            ret[i] = foreach_single_init(c, schema)
        end
        return ret
    end
    if c.map then
        return {}
    end
    return foreach_single_init(c, schema)
end

local function gen_init(c, schema)
    return function()
        return foreach_init(c, schema)
    end
end

local foreach_delete
local function foreach_single_delete(component, c, schema)
    if c.method and c.method.delete then
        c.method.delete(component)
        return
    end
    if schema.map[c.type] then
        foreach_delete(component, schema.map[c.type], schema)
        return
    end
end

function foreach_delete(component, c, schema)
    if not c.type then
        for _, v in ipairs(c) do
            foreach_delete(component, v, schema)
        end
        return
    end
    if c.array then
        local n = c.array == 0 and #component or c.array
        for i = 1, n do
            foreach_single_delete(component[i], c, schema)
        end
        return
    end
    if c.map then
        for _, v in pairs(component) do
            foreach_single_delete(v, c, schema)
        end
        return
    end
    foreach_single_delete(component, c, schema)
end

local function gen_delete(c, schema)
    return function(component)
        return foreach_delete(component, c, schema)
    end
end

return function(c, schema)
    return {
        init = gen_init(c, schema),
        delete = gen_delete(c, schema),
    }
end
