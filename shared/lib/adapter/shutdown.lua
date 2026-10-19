-- norden_lib/shared/lib/adapter/shutdown.lua
-- resource shutdown / cleanup hooks


local log = Logger.create('norden_lib/adapter/shutdown')

local _shutdownCallbacks = {}

function Platform.onShutdown(cb)
    table.insert(_shutdownCallbacks, cb)
end

local function _runShutdown()
    for _, cb in ipairs(_shutdownCallbacks) do
        local ok, err = pcall(cb)
        if not ok then
            log('onShutdown callback error: ' .. tostring(err), 4)
        end
    end
end

if _NORDEN_LIB_IS_FIVEM then
    if not _NORDEN_LIB_SHUTDOWN_REGISTERED then
        _NORDEN_LIB_SHUTDOWN_REGISTERED = true
        local resourceName = GetCurrentResourceName and GetCurrentResourceName() or 'norden_lib'
        AddEventHandler('onResourceStop', function(res)
            if res == resourceName then
                _runShutdown()
            end
        end)
    end
end
