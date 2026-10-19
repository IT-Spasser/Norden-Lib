--[[
    Dispatch bridge (server). Polls another script's export for its open calls and mirrors them into a consumer through push/close.
    The mapping from that script's call shape to { key, priority, title, location } is supplied by the caller, because every
    dispatch script has its own shape.
    deps: callExport(resource, name) -> list|nil, push(call) -> stored|nil, close(id), every(seconds, fn), log(msg)
    opts: { resource, export, map = function(raw) -> { key, priority, title, location }|nil, interval = seconds }
]]

local M = {}

function M.poller(deps, opts)
    assert(type(opts.resource) == 'string' and type(opts.export) == 'string' and type(opts.map) == 'function', 'resource, export and map are required')
    local known = {}
    local P = {}

    function P.poll()
        local ok, raw = pcall(deps.callExport, opts.resource, opts.export)
        if not ok or type(raw) ~= 'table' then return false end
        local present = {}
        for _, item in pairs(raw) do
            local mapped = opts.map(item)
            if type(mapped) == 'table' and mapped.key ~= nil then
                local key = tostring(mapped.key)
                present[key] = true
                if not known[key] then
                    local stored = deps.push({ priority = mapped.priority, title = mapped.title, location = mapped.location, source = opts.resource })
                    if stored then known[key] = stored.id end
                end
            end
        end
        for key, id in pairs(known) do
            if not present[key] then
                deps.close(id)
                known[key] = nil
            end
        end
        return true
    end

    function P.start()
        deps.every(opts.interval or 5, P.poll)
        P.poll()
    end

    return P
end

return M
