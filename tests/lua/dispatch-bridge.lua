local function eq(got, want, label)
    if got ~= want then error(('%s: got %s, want %s'):format(label, tostring(got), tostring(want)), 0) end
end
local D = dofile('shared/imports/dispatch/server.lua')

local calls, pushed, closed, nextId, idOf = {}, {}, {}, 0, {}
local deps = {
    callExport = function(resource, name) eq(resource, 'some-dispatch', 'resource'); eq(name, 'GetCalls', 'export'); return calls end,
    push = function(c) nextId = nextId + 1; pushed[#pushed + 1] = c; if c.title == 'reject' then return nil end; idOf[c.title] = nextId; return { id = nextId } end,
    close = function(id) closed[#closed + 1] = id end,
    every = function() end,
}
local p = D.poller(deps, {
    resource = 'some-dispatch', export = 'GetCalls',
    map = function(raw) if raw.skip then return nil end; return { key = raw.id, priority = raw.prio, title = raw.msg, location = raw.street } end,
})

calls = { { id = 'a', prio = 1, msg = 'Skud', street = 'Havnen' }, { id = 'b', prio = 3, msg = 'Uheld' }, { id = 'c', skip = true } }
eq(p.poll(), true, 'poll ok')
eq(#pushed, 2, 'two calls mirrored, the unmappable one skipped'); eq(pushed[1].source, 'some-dispatch', 'source recorded')
p.poll()
eq(#pushed, 2, 'a call already mirrored is not pushed again')
calls = { { id = 'b', prio = 3, msg = 'Uheld' } }
p.poll()
eq(#closed, 1, 'a call that disappeared is closed'); eq(closed[1], idOf['Skud'], 'the right one')
calls = {}
p.poll()
eq(closed[2], idOf['Uheld'], 'and the next')

local broken = D.poller({ callExport = function() error('resource not started') end, push = deps.push, close = deps.close, every = deps.every }, { resource = 'x', export = 'y', map = function() end })
eq(broken.poll(), false, 'a missing script is not an error')
eq(#closed, 2, 'and closes nothing')
calls = { { id = 'r', prio = 2, msg = 'reject' } }
p.poll(); p.poll()
eq(#pushed, 5, 'a rejected push is retried on the next poll, not forgotten')
print('PASS dispatch bridge')
