--[[
    tLib/imports.lua
    Single entry point for consumer resources.

    Usage in consumer fxmanifest.lua:
        shared_scripts { '@tLib/imports.lua' }

    This sets up a global `tlib` table with lazy-loading:
        tlib.coords   → loads shared/imports/coords/shared.lua (Coords.*)

    Modules are loaded on first access. You can also eagerly load modules
    by listing them in your fxmanifest.lua:
        tlib_module { 'coords' }

    Heavy / stateful systems (Discovery, Menu, Dialog, Toast, Theme) are
    accessed via exports['tLib']:Method() — they run inside tLib's own VM.
]]

local resourceName = GetCurrentResourceName()
local tLibName = 'tLib'

if resourceName == tLibName then return end

if GetResourceState(tLibName) ~= 'started' then
    error('^1tLib must be started before this resource.^0', 0)
end

local context = IsDuplicityVersion() and 'server' or 'client'

-- Enforce tlib_min_version *before* anything touches tlib, so an outdated
-- tLib produces a clear "update tLib" message instead of a cryptic
-- "No such export X" when a module added in a later tLib version is used.
-- Duplicated from shared/imports/versioncheck/server.lua because this file runs
-- in consumer resource VMs, while versioncheck runs inside tLib's own VM.
local function parseVer(s)
    if not s then return { 0, 0, 0 } end
    s = s:gsub('^v', '')
    local parts = {}
    for n in s:gmatch('%d+') do parts[#parts + 1] = tonumber(n) end
    while #parts < 3 do parts[#parts + 1] = 0 end
    return parts
end

local requiredVersion = GetResourceMetadata(resourceName, 'tlib_min_version', 0)
if requiredVersion and requiredVersion ~= '' then
    local tlibVersion = GetResourceMetadata(tLibName, 'version', 0) or '0.0.0'
    local req, cur = parseVer(requiredVersion), parseVer(tlibVersion)
    local outdated = false
    for i = 1, 3 do
        if cur[i] < req[i] then outdated = true; break
        elseif cur[i] > req[i] then break end
    end
    if outdated then
        error(('\n^1[%s] requires tLib v%s or newer — installed tLib is v%s. Update tLib.^0')
            :format(resourceName, requiredVersion, tlibVersion), 0)
    end
end

local function loadModule(self, module)
    local dir = ('shared/imports/%s'):format(module)
    local chunk = LoadResourceFile(tLibName, ('%s/%s.lua'):format(dir, context))
    local shared = LoadResourceFile(tLibName, ('%s/shared.lua'):format(dir))

    if shared then
        chunk = (chunk and ('%s\n%s'):format(shared, chunk)) or shared
    end

    if chunk then
        local fn, err = load(chunk, ('@@tLib/shared/imports/%s/%s.lua'):format(module, context))

        if not fn or err then
            if shared then
                fn, err = load(shared, ('@@tLib/shared/imports/%s/shared.lua'):format(module))
            end

            if not fn or err then
                return error(('\n^1Error importing tLib module (%s): %s^0'):format(dir, err), 3)
            end
        end

        local result = fn()
        self[module] = result or true
        return self[module]
    end
end

--- Is `module` actually present in the INSTALLED tLib?
---
--- This exists because `tlib.<anything>` can never be falsy. An unresolvable name falls
--- through to the export proxy in `call` below, which returns a *function*, so the obvious
--- guard a consumer writes --
---
---     if tlib.diag then tlib.diag.info(...) end        -- WRONG
---
--- -- passes against every tLib ever released, including ones with no `diag` module at all.
--- The crash then lands one line later as "attempt to index a function value", which names
--- the consumer's file and says nothing about the real cause: a library too old to have the
--- module. That is the least debuggable place for it, because the modules most worth
--- guarding (`diag` above all) are the ones a consumer reaches for while reporting that the
--- install is already broken.
---
--- `type(tlib.diag) == 'table'` happens to work today, but only by accident of the proxy
--- being a function; it would break the moment the proxy became callable-table. Ask this
--- instead:
---
---     if tlib.has('diag') then tlib.diag.info(...) end -- RIGHT
---
--- Probes the files rather than the cache on purpose: a loaded module is cached as
--- `result or true`, so a module that legitimately returns a function would be
--- indistinguishable from the proxy by type alone.
---
--- ## `has` cannot probe for its own absence — mind the bootstrap
---
--- `has` is subject to the very proxy it exists to defeat. On any tLib released before
--- `has` landed, `tlib.has` is not a real key, so `__index` hands back the export proxy and
--- `tlib.has('diag')` calls `exports.tLib.has(nil, 'diag')` — an export that does not
--- exist. It RAISES, in the consumer's first script, which is worse than the truthiness
--- bug it replaces. A capability probe is never able to report its own absence.
---
--- What makes it safe is the version gate above, not defensive code at the call site.
--- `@tLib/imports.lua` is the FIRST entry in every consumer's `shared_scripts`, so the
--- gate runs before any consumer file is loaded: pin `tlib_min_version` at or above the
--- release that introduced `has`, and an older tLib stops with "requires tLib vX or newer"
--- instead of reaching a call site at all. That is the whole point of the gate.
---
--- So: **`tlib.has` is safe if and only if the consumer's `tlib_min_version` names a
--- release that contains it.** Consumers that must tolerate an older tLib — because their
--- pin is lower, or because they run before their own pin can be trusted — have to reach
--- it through `pcall` and treat a throw as "unknown", not as "absent":
---
---     local ok, present = pcall(function() return tlib.has('diag') end)
---     if ok and present == false then return nil end  -- definitive: not there
---     -- a throw means an old tLib; fall through to your own fallback
---
--- Note `has` answers about the FILE, not the interface: a `true` says the module exists,
--- never that it exports the function you are about to call.
local function moduleExists(module)
    if type(module) ~= 'string' or module == '' then return false end
    local dir = ('shared/imports/%s'):format(module)
    return LoadResourceFile(tLibName, ('%s/%s.lua'):format(dir, context)) ~= nil
        or LoadResourceFile(tLibName, ('%s/shared.lua'):format(dir)) ~= nil
end

local function call(self, index)
    local module = rawget(self, index)

    if not module then
        module = loadModule(self, index)

        if not module then
            -- Fall through to tLib exports for non-import modules.
            -- NOTE: this is why `tlib.<name>` is never nil -- see moduleExists above.
            local function method(...)
                return exports[tLibName][index](nil, ...)
            end
            self[index] = method
            return method
        end
    end

    return module
end

local tlib = setmetatable({
    name = tLibName,
    context = context,
    resource = resourceName,
    has = moduleExists,
}, {
    __index = call,
    __call = call,
})

_ENV.tlib = tlib

-- Eagerly load modules declared in the consumer's fxmanifest.
-- Supports both singular form:  tlib_module { 'coords' }
-- and plural form:              tlib_modules { 'coords', 'kvp' }
for _, key in ipairs({ 'tlib_module', 'tlib_modules' }) do
    for i = 1, GetNumResourceMetadata(resourceName, key) do
        local name = GetResourceMetadata(resourceName, key, i - 1)
        if name and not rawget(tlib, name) then
            loadModule(tlib, name)
        end
    end
end

