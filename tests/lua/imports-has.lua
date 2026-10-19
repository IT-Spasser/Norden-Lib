-- Run from norden_lib: bunx --bun --package fengari-node-cli fengari scripts/run-lua-suite.lua tests/lua/imports-has.lua
--
-- Oracle for `norden_lib.has(module)` in imports.lua.
--
-- The thing under test is a trap, not a feature: `norden_lib.<anything>` is NEVER falsy,
-- because an unresolvable name falls through to an export proxy. So the guard every
-- consumer reaches for first --  `if norden_lib.diag then`  -- passes against a Norden Lib that has
-- no `diag` at all, and the crash arrives a line later as "attempt to index a function
-- value" pointing at the consumer. These tests assert the trap still behaves that way
-- (so the docs on `has` stay true) AND that `has` answers correctly either side of it.
--
-- imports.lua is loaded as real source with mocked natives rather than reimplemented,
-- so this is an oracle for the shipped file. A stand-in would keep passing while the
-- real proxy changed shape, which is the entire failure this guards.

local report = print
local passed = 0

local function test(name, fn)
    local ok, err = pcall(fn)
    if not ok then
        report('FAIL ' .. name .. ': ' .. tostring(err))
        error('suite failed', 0)
    end
    passed = passed + 1
    report('PASS ' .. name)
end

--- Build a norden_lib table from the REAL imports.lua against a fake Norden Lib install.
--- `files` maps resource-relative paths to contents; anything absent is absent.
local function fixture(files, ctx)
    local exportCalls = {}

    _ENV.GetCurrentResourceName = function() return 'consumer' end
    _ENV.GetResourceState = function() return 'started' end
    _ENV.GetNumResourceMetadata = function() return 0 end
    _ENV.GetResourceMetadata = function(_, key)
        if key == 'version' then return '9.9.9' end -- never the thing under test here
        return nil
    end
    local probes = {}
    _ENV.LoadResourceFile = function(_, path)
        probes[#probes + 1] = path
        return files[path]
    end
    _ENV.IsDuplicityVersion = function() return ctx == 'server' end
    _ENV.exports = setmetatable({}, {
        __index = function()
            return setmetatable({}, {
                __index = function(_, name)
                    return function(...)
                        exportCalls[#exportCalls + 1] = name
                        return 'export:' .. name
                    end
                end,
            })
        end,
    })

    -- loadfile, not io.open: fengari ships no `io` library, and versioncheck.lua
    -- loads real source the same way.
    assert(loadfile('imports.lua'))()

    -- Cleared in place, not reassigned, because the LoadResourceFile closure
    -- above holds this table. imports.lua's AUTOLOAD list probes for its own
    -- modules while it loads, and `probes` exists to answer one question only --
    -- does has() touch the filesystem for a name it should reject -- so it has to
    -- start at zero AFTER the library is up, not before.
    for i = #probes, 1, -1 do probes[i] = nil end

    return _ENV.norden_lib, exportCalls, probes
end

local SHARED_ONLY = { ['shared/imports/diag/shared.lua'] = 'return { info = function() end }' }

-- The trap itself

test('a missing module is still truthy — the reason has() exists', function()
    local norden_lib = fixture({})
    assert(norden_lib.diag, 'expected the export proxy to make norden_lib.diag truthy')
    assert(type(norden_lib.diag) == 'function', 'proxy should be a function, got ' .. type(norden_lib.diag))
end)

test('indexing a missing module throws the undebuggable error, as documented', function()
    local norden_lib = fixture({})
    local ok, err = pcall(function() return norden_lib.diag.info end)
    assert(not ok, 'expected indexing the proxy to throw')
    assert(tostring(err):find('index a function value', 1, true),
        'expected "attempt to index a function value", got: ' .. tostring(err))
end)

-- has()

test('has() is false when the module is absent', function()
    local norden_lib = fixture({})
    assert(norden_lib.has('diag') == false, 'expected false for an absent module')
end)

test('has() is true when only shared.lua exists', function()
    local norden_lib = fixture(SHARED_ONLY)
    assert(norden_lib.has('diag') == true, 'expected true when shared.lua is present')
end)

test('has() is true when only the context file exists', function()
    local norden_lib = fixture({ ['shared/imports/diag/client.lua'] = 'return {}' }, 'client')
    assert(norden_lib.has('diag') == true, 'expected true when client.lua is present')
end)

test('has() does not consult the export proxy', function()
    local norden_lib, exportCalls = fixture({})
    norden_lib.has('diag')
    assert(#exportCalls == 0, 'has() must not call into Norden Lib exports; it made ' .. #exportCalls)
end)

test('has() never loads the module it is asked about', function()
    local loaded = false
    local files = {
        ['shared/imports/diag/shared.lua'] = 'error("module body must not run", 0)',
    }
    local norden_lib = fixture(files)
    local ok = pcall(function() loaded = norden_lib.has('diag') end)
    assert(ok, 'has() must not execute the module body')
    assert(loaded == true, 'expected true for a present-but-broken module')
end)

test('has() rejects non-string and empty names WITHOUT touching the filesystem', function()
    -- Asserting the probe count, not just the answer. `('%s'):format(nil)` yields the
    -- string "nil" rather than erroring, so a bad name still produces a well-formed path
    -- that simply misses -- meaning the return value alone cannot tell whether the type
    -- guard ran. A first version of this test asserted only `== false` and survived
    -- deleting the guard entirely.
    local norden_lib, _, probes = fixture(SHARED_ONLY)
    assert(norden_lib.has(nil) == false, 'nil should be false')
    assert(norden_lib.has('') == false, 'empty string should be false')
    assert(norden_lib.has(42) == false, 'a number should be false')
    assert(norden_lib.has({}) == false, 'a table should be false')
    assert(#probes == 0, 'expected no file probes for invalid names, got ' .. #probes)
end)

-- The bootstrap trap: has() cannot probe for its own absence

test('with no has() key, norden_lib.has is the proxy and CALLING it hits exports', function()
    -- KEPT AS AN ORACLE FOR THE PROXY, NOT AS A SUPPORTED INSTALL STATE. `has` is
    -- defined in imports.lua, which must have run for `norden_lib` to exist at all, so a real
    -- Norden Lib 1.0+ always has it and consumers call it directly with no pcall. What this
    -- pins is the __index behaviour that makes `has` necessary in the first place: an
    -- unresolvable name becomes a truthy FUNCTION. If the proxy ever became a callable
    -- table, `type(norden_lib.diag) == 'table'` would start answering true for a missing
    -- module, and the docs above would be wrong.
    local norden_lib, exportCalls = fixture({})
    rawset(norden_lib, 'has', nil)                       -- as if imports.lua predated has()
    local probe = norden_lib.has
    assert(type(probe) == 'function', 'expected the proxy, got ' .. type(probe))
    probe('diag')
    assert(exportCalls[1] == 'has',
        'expected the proxy to call exports.norden_lib.has; calls: ' .. #exportCalls)
end)

test('the documented pcall form survives a has() that is not there', function()
    local norden_lib = fixture(SHARED_ONLY)
    rawset(norden_lib, 'has', nil)
    _ENV.exports = setmetatable({}, {
        __index = function()
            return setmetatable({}, {
                __index = function()
                    return function() error('No such export has in resource norden_lib', 0) end
                end,
            })
        end,
    })
    local ok, present = pcall(function() return norden_lib.has('diag') end)
    assert(not ok, 'a name resolved through the proxy should raise')
    assert(present ~= false, 'a throw must not be mistaken for a definitive false')
end)

test('has() is not fooled by a partial path match', function()
    local norden_lib = fixture(SHARED_ONLY)
    assert(norden_lib.has('dia') == false, 'a prefix of a real module must not report present')
    assert(norden_lib.has('diagnostics') == false, 'a superstring must not report present')
end)

test('the guard that works reads correctly both ways', function()
    local absent = fixture({})
    assert(not absent.has('diag'), 'absent install should refuse')

    local present = fixture(SHARED_ONLY)
    assert(present.has('diag'), 'present install should allow')
    assert(type(present.diag) == 'table', 'a real module loads as a table')
    assert(type(present.diag.info) == 'function', 'and its members are reachable')
end)

-- `imports-has: ok` is the line scripts/primitives-control.ts looks for; it
-- plants a defect that makes imports.lua raise while this fixture is building,
-- and a run that printed only a count would read as red to its baseline.
report(('imports-has: ok — %d checks passed'):format(passed))
