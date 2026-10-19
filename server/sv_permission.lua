-- Levels: 0 = none, 1 = admin (nlib.admin), 2 = superadmin (nlib.superadmin)

Permission = {}

local ACE       = "nlib.admin"
local SUPER_ACE = "nlib.superadmin"

--- Return the numeric permission level for a player (0, 1, or 2).
function Permission.getPlayerLevel(playerId)
    -- Demo mode makes everyone a superadmin. Checked first and unconditionally:
    -- this is the one fail-OPEN branch in NLib, and keeping it to a single line
    -- at the top of the rule is what makes it impossible to apply by halves.
    -- See server/sv_demo.lua and shared/imports/demo/shared.lua.
    if Demo and Demo.active() then return 2 end
    if not _NLIB_IS_FIVEM then return 0 end
    local id = tostring(playerId)
    if IsPlayerAceAllowed(id, SUPER_ACE) then return 2 end
    if IsPlayerAceAllowed(id, ACE)       then return 1 end
    return 0
end

--- Convenience: true if player has at least admin level.
function Permission.isPlayerAdmin(playerId)
    return Permission.getPlayerLevel(playerId) >= 1
end

Platform.AddNetEventHandler("NLib:requestAdminPermission", function()
    local src = source
    -- Send the numeric level; client handles both number (new) and bool (legacy).
    Platform.TriggerClientEvent("NLib:receiveAdminPermission", src, Permission.getPlayerLevel(src))
end)

--- Register a net event that only fires the handler if the source player
--- has nlib.admin permission. Denied attempts are logged automatically.
--- @param eventName string   The net event name to register
--- @param handler function   function(src, ...) called only for admins
function Permission.registerAdminEvent(eventName, handler)
    RegisterNetEvent(eventName, function(...)
        local src = source
        local ok, isAdm = pcall(Permission.isPlayerAdmin, src)
        if not ok or not isAdm then
            print(("[NLib] %s: player %s denied (no nlib.admin)"):format(eventName, tostring(src)))
            return
        end
        handler(src, ...)
    end)
end

function Permission.registerExports()
    Platform.export('NLib', 'IsPlayerAdmin', function(src)
        return Permission.isPlayerAdmin(src)
    end)
    Platform.export('NLib', 'GetPlayerLevel', function(src)
        return Permission.getPlayerLevel(src)
    end)
    Platform.export('NLib', 'RegisterAdminEvent', function(eventName, handler)
        Permission.registerAdminEvent(eventName, handler)
    end)
end
