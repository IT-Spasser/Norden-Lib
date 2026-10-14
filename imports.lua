--[[
    tLib/imports.lua
    Single entry point for consumer resources.

    Usage in consumer fxmanifest.lua:
        shared_scripts { '@tLib/imports.lua' }

    Modules lazy-load on first access of `tlib.<name>`.
    Design notes: docs/internal/imports-entrypoint.md

]]

local resourceName = GetCurrentResourceName()
local tLibName = 'tLib'

if resourceName == tLibName then return end

if GetResourceState(tLibName) ~= 'started' then
    error('^1tLib must be started before this resource.^0', 0)
end

local context = IsDuplicityVersion() and 'server' or 'client'

-- Enforce tlib_min_version *before* anything touches tlib, so an outdated tLib
-- says "update tLib" instead of "No such export X". Duplicated from
-- versioncheck/server.lua: this file runs in consumer VMs, that one in tLib's.
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
--- `tlib.<anything>` is never falsy -- an unknown name returns the export proxy,
--- a function -- so `if tlib.diag then` is not a guard. Probes files, not the
--- module cache. Safe only behind the version gate above: see
--- docs/internal/imports-entrypoint.md.
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

--- Modules whose LOADING IS THEIR WIRING, loaded by tLib itself: their file
--- scope registers the handler, and a consumer may have no Lua call to trigger
--- the lazy load. `studioOnly` is a default, not a permission. See
--- docs/internal/imports-entrypoint.md.
local AUTOLOAD = {
    { name = 'occupancy' },
    { name = 'telemetry', studioOnly = true },
}

--- Does this consumer's manifest credit the studio? Loaded by path into a
--- private env, because sh_branding.lua assigns a global `StudioBranding`.
local isStudio
local function studioResource()
    if isStudio ~= nil then return isStudio end
    isStudio = false
    -- An authorless manifest cannot be the studio, and answering from metadata
    -- avoids compiling sh_branding.lua into every third-party consumer's VM.
    if GetNumResourceMetadata(resourceName, 'author') == 0
        and GetNumResourceMetadata(resourceName, 'authors') == 0 then
        return false
    end
    local chunk = LoadResourceFile(tLibName, 'shared/sh_branding.lua')
    if chunk then
        local fn = load(chunk, '@@tLib/shared/sh_branding.lua', 't',
            setmetatable({}, { __index = _ENV }))
        local ok, branding = pcall(fn)
        if ok and type(branding) == 'table' then
            isStudio = branding.isStudioResource(resourceName) == true
        end
    end
    return isStudio
end

--- Can this VM read tLib's files AT ALL? The discriminator between "one module
--- is missing" and "I cannot read tLib", which have different fixes. Asked only
--- after a module has already failed.
local function tlibReadable()
    return LoadResourceFile(tLibName, 'fxmanifest.lua') ~= nil
end

for _, entry in ipairs(AUTOLOAD) do
    if (not entry.studioOnly or studioResource()) and not rawget(tlib, entry.name) then
        -- These names are tLib's own, so one that resolves to no file is a tLib
        -- packaging bug rather than a consumer typo.
        if not loadModule(tlib, entry.name) and tlibReadable() then
            -- A print, not error(): this is a shared_script in every consumer,
            -- so raising here stops every t* resource on the server at once.
            print(('^1[tLib] cannot load its own module "%s" — no '
                .. 'shared/imports/%s/%s.lua and no shared.lua. tLib v%s is packaged '
                .. 'wrong; %s is running WITHOUT it.^0')
                :format(entry.name, entry.name, context,
                    GetResourceMetadata(tLibName, 'version', 0) or '?', resourceName))
        end
    end
end

-- Eagerly load modules declared in the consumer's fxmanifest:
--   tlib_module { 'coords' }   /   tlib_modules { 'coords', 'kvp' }
--
-- Not load-bearing any more except for `realtime`, which tLib's server bundle
-- reads off the manifest to decide whether to install the realtime hub. Kept as
-- an auditable parts list. See docs/internal/imports-entrypoint.md.
--
for _, key in ipairs({ 'tlib_module', 'tlib_modules' }) do
    for i = 1, GetNumResourceMetadata(resourceName, key) do
        local name = GetResourceMetadata(resourceName, key, i - 1)
        if name and not rawget(tlib, name) then
            loadModule(tlib, name)
        end
    end
end

