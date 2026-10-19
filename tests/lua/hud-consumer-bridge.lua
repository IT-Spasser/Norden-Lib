local events, nui, messages, installed = {}, {}, {}, {}
local state, calls = 'started', 0
-- `refuse` is Norden Lib's transaction lock: registration is refused outright while
-- the HUD editor is open. The bridge has to survive that without losing the
-- definition, which is what the last block in this file measures.
local refuse, threads = false, {}
GetResourceState = function() return state end
SendNUIMessage = function(data) messages[#messages + 1] = data end
AddEventHandler = function(name, fn) events[name] = fn end
RegisterNUICallback = function(name, fn) nui[name] = fn end
CreateThread = function(fn) threads[#threads + 1] = coroutine.create(fn) end
Wait = function() coroutine.yield() end
local function tick()
    for _, thread in ipairs(threads) do
        if coroutine.status(thread) == 'suspended' then assert(coroutine.resume(thread)) end
    end
end
exports = { norden_lib = {
    RegisterHudComponent = function(_, id, definition, fn)
        if refuse then return false, 'Close the layout editor before registering a component' end
        calls = calls + 1; installed[id] = fn
        fn({ id = id, layout = definition.defaults, width = definition.width, height = definition.height,
            phase = 'restore', editing = false })
        return true
    end,
    UnregisterHudComponent = function(_, id) installed[id] = nil; return true end,
    OpenHudEditor = function() return true end,
} }
dofile('shared/imports/hud/client.lua')
local options = { width = 200, height = 100, defaults = { x = 0.1, y = 0.1, scale = 1, visible = true, anchor = 'top-left' } }
assert(NordenLibHud.register('status', options))
assert(#messages == 0, 'Own NUI readiness must gate delivery')
local answered
nui.__norden_lib_hud_ready({}, function(reply) answered = reply.ok end)
assert(answered and #messages == 1 and messages[1].nordenLibHud.phase == 'restore')
installed.status({ id = 'status', layout = { x = 0.5, y = 0.2, scale = 1, visible = true, anchor = 'top-left' },
    width = 200, height = 100, phase = 'preview', editing = true })
assert(messages[#messages].nordenLibHud.editing)
state = 'stopped'
events.onClientResourceStop('norden_lib')
assert(messages[#messages].nordenLibHud.layout.x == 0.1 and messages[#messages].nordenLibHud.editing == false,
    'Stopping Norden Lib must restore committed geometry, not the latest preview')
assert(not NordenLibHud.edit())
state = 'started'
events.onClientResourceStart('norden_lib')
assert(calls == 2 and messages[#messages].nordenLibHud.phase == 'restore')
assert(NordenLibHud.edit())
assert(NordenLibHud.unregister('status'))
events.onClientResourceStart('norden_lib')
assert(calls == 2, 'Unregistered widgets must not return after restart')

-- A registration refused by the editor's transaction lock must not be lost.
-- It used to be: the definition was remembered only when the install SUCCEEDED
-- or when Norden Lib was absent, so a consumer that started during an edit was never
-- registered at all and its HUD never appeared until the resource restarted.
refuse = true
local before = calls
assert(not NordenLibHud.register('late', options), 'A locked Norden Lib refuses, and says so')
assert(calls == before, 'Nothing is registered while the lock is held')
tick()
assert(calls == before, 'Retrying into the held lock registers nothing either')
refuse = false
tick()
assert(calls == before + 1, 'The refused definition lands once the editor closes')
assert(installed.late, 'and it lands as a real component, with its callback')
tick()
assert(calls == before + 1, 'A satisfied retry does not register twice')
assert(NordenLibHud.unregister('late'))
tick()
events.onClientResourceStart('norden_lib')
assert(calls == before + 1, 'An unregistered pending definition does not come back')
print('PASS: consumer HUD readiness, restart registration, refusal retry and rollback transport')
