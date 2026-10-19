-- Levels: 0 = none, 1 = admin (norden_lib.admin), 2 = superadmin (norden_lib.superadmin)

Permission = {}

local ACE       = "norden_lib.admin"
local SUPER_ACE = "norden_lib.superadmin"

--- Return the numeric permission level for a player (0, 1, or 2).
function Permission.getPlayerLevel(playerId)
    -- Demo mode makes everyone a superadmin. Checked first and unconditionally:
    -- this is the one fail-OPEN branch in Norden Lib, and keeping it to a single line
    -- at the top of the rule is what makes it impossible to apply by halves.
    -- See server/sv_demo.lua and shared/imports/demo/shared.lua.
    if Demo and Demo.active() then return 2 end
    if not _NORDEN_LIB_IS_FIVEM then return 0 end
    local id = tostring(playerId)
    if IsPlayerAceAllowed(id, SUPER_ACE) then return 2 end
    if IsPlayerAceAllowed(id, ACE)       then return 1 end
    return 0
end

--- Convenience: true if player has at least admin level.
function Permission.isPlayerAdmin(playerId)
    return Permission.getPlayerLevel(playerId) >= 1
end

Platform.AddNetEventHandler("norden_lib:requestAdminPermission", function()
    local src = source
    -- Send the numeric level; client handles both number (new) and bool (legacy).
    Platform.TriggerClientEvent("norden_lib:receiveAdminPermission", src, Permission.getPlayerLevel(src))
end)

--- Register a net event that only fires the handler if the source player
--- has norden_lib.admin permission. Denied attempts are logged automatically.
--- @param eventName string   The net event name to register
--- @param handler function   function(src, ...) called only for admins
function Permission.registerAdminEvent(eventName, handler)
    RegisterNetEvent(eventName, function(...)
        local src = source
        local ok, isAdm = pcall(Permission.isPlayerAdmin, src)
        if not ok or not isAdm then
            print(("[norden_lib] %s: player %s denied (no norden_lib.admin)"):format(eventName, tostring(src)))
            return
        end
        handler(src, ...)
    end)
end

function Permission.registerExports()
    Platform.export('norden_lib', 'IsPlayerAdmin', function(src)
        return Permission.isPlayerAdmin(src)
    end)
    Platform.export('norden_lib', 'GetPlayerLevel', function(src)
        return Permission.getPlayerLevel(src)
    end)
    Platform.export('norden_lib', 'RegisterAdminEvent', function(eventName, handler)
        Permission.registerAdminEvent(eventName, handler)
    end)
end
