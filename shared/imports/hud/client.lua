-- Load this in the consumer VM with '@norden_lib/shared/imports/hud/client.lua'.
-- Its own NUI keeps rendering; this bridge only transports shared layout state.
NordenLibHud = {}
local definitions, latest, committed, installed = {}, {}, {}, {}
local ready, retrying = false, false
-- A refused registration is retried for a minute, then given up on.
local RETRY_ATTEMPTS, RETRY_INTERVAL_MS = 60, 1000
local function send(data)
    latest[data.id] = data
    if data.phase == 'restore' or data.phase == 'commit' or data.phase == 'rollback' then committed[data.id] = data end
    if ready then SendNUIMessage({ nordenLibHud = data }) end
end
local function install(id, definition)
    if GetResourceState('norden_lib') ~= 'started' then return false, 'norden_lib is not started' end
    local ok, err = exports['norden_lib']:RegisterHudComponent(id, definition, function(data) send(data) end)
    installed[id] = ok == true or nil
    return ok, err
end
local function installAll()
    local pending = false
    for id, definition in pairs(definitions) do
        if not installed[id] and not install(id, definition) then pending = true end
    end
    return pending
end
-- Why a retry exists at all
--
-- Norden Lib refuses registration while the HUD editor is open: the editor is a
-- transaction over every component at once. So a consumer that starts, or
-- re-registers, during the seconds a player spends positioning their HUD gets a
-- refusal -- and the definition used to be DROPPED on that refusal, which meant
-- the widget was never registered, never rendered and never retried. The HUD was
-- simply absent until the resource restarted, with nothing said anywhere.
--
-- The definition is kept now, and this walks it in. Bounded, because a refusal
-- can also mean the definition is invalid, which no amount of waiting fixes.
local function retryPending()
    if retrying then return end
    retrying = true
    CreateThread(function()
        for _ = 1, RETRY_ATTEMPTS do
            Wait(RETRY_INTERVAL_MS)
            if not installAll() then break end
        end
        retrying = false
    end)
end
function NordenLibHud.register(id, definition)
    if type(id) ~= 'string' or type(definition) ~= 'table' then return false, 'Invalid HUD definition' end
    definitions[id] = definition
    local ok, err = install(id, definition)
    if not ok and GetResourceState('norden_lib') == 'started' then retryPending() end
    return ok, err
end
function NordenLibHud.unregister(id)
    local ok = false
    if GetResourceState('norden_lib') == 'started' then ok = exports['norden_lib']:UnregisterHudComponent(id) end
    definitions[id], latest[id], committed[id], installed[id] = nil, nil, nil, nil
    return ok
end
-- Write a placement the player produced in the consumer's OWN UI -- dragging the
-- surface by its background -- into Norden Lib's store, so it is the same placement
-- the editor would have made: healed, persisted, and cleared by Reset.
function NordenLibHud.set(id, layout)
    if type(id) ~= 'string' or type(layout) ~= 'table' then return false, 'Invalid HUD layout' end
    if GetResourceState('norden_lib') ~= 'started' then return false, 'norden_lib is not started' end
    local ok, applied, err = pcall(function() return exports['norden_lib']:SetHudLayout(id, layout) end)
    if not ok then return false, tostring(applied) end
    return applied == true, err
end
function NordenLibHud.edit()
    if GetResourceState('norden_lib') ~= 'started' then return false, 'norden_lib is not started' end
    return exports['norden_lib']:OpenHudEditor()
end
RegisterNUICallback('__norden_lib_hud_ready', function(_, cb)
    ready = true
    for _, data in pairs(latest) do SendNUIMessage({ nordenLibHud = data }) end
    cb({ ok = true })
end)
AddEventHandler('onClientResourceStart', function(name)
    if name ~= 'norden_lib' then return end
    -- A restarted Norden Lib remembers nothing, so every previous install is void.
    installed = {}
    if installAll() then retryPending() end
end)
AddEventHandler('onClientResourceStop', function(name)
    if name ~= 'norden_lib' then return end
    -- A hard stop must not leave the consumer in preview/input-suspended mode.
    for id, data in pairs(committed) do
        local restored = { id = id, layout = data.layout, width = data.width, height = data.height,
            phase = 'rollback', editing = false }
        send(restored)
    end
end)
