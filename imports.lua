--[[
    NLib/imports.lua
    Single entry point for consumer resources.

    Usage in consumer fxmanifest.lua:
        shared_scripts { '@NLib/imports.lua' }

    Modules lazy-load on first access of `nlib.<name>`.
    Design notes: docs/internal/imports-entrypoint.md

]]

local resourceName = GetCurrentResourceName()
local NLibName = 'NLib'

if resourceName == NLibName then return end

if GetResourceState(NLibName) ~= 'started' then
    error('^1NLib must be started before this resource.^0', 0)
end

local context = IsDuplicityVersion() and 'server' or 'client'

-- Enforce nlib_min_version *before* anything touches nlib, so an outdated NLib
-- says "update NLib" instead of "No such export X". Duplicated from
-- versioncheck/server.lua: this file runs in consumer VMs, that one in NLib's.
local function parseVer(s)
    if not s then return { 0, 0, 0 } end
    s = s:gsub('^v', '')
    local parts = {}
    for n in s:gmatch('%d+') do parts[#parts + 1] = tonumber(n) end
    while #parts < 3 do parts[#parts + 1] = 0 end
    return parts
end

local requiredVersion = GetResourceMetadata(resourceName, 'nlib_min_version', 0)
if requiredVersion and requiredVersion ~= '' then
    local nlibVersion = GetResourceMetadata(NLibName, 'version', 0) or '0.0.0'
    local req, cur = parseVer(requiredVersion), parseVer(nlibVersion)
    local outdated = false
    for i = 1, 3 do
        if cur[i] < req[i] then outdated = true; break
        elseif cur[i] > req[i] then break end
    end
    if outdated then
        error(('\n^1[%s] requires NLib v%s or newer — installed NLib is v%s. Update NLib.^0')
            :format(resourceName, requiredVersion, nlibVersion), 0)
    end
end

local function loadModule(self, module)
    local dir = ('shared/imports/%s'):format(module)
    local chunk = LoadResourceFile(NLibName, ('%s/%s.lua'):format(dir, context))
    local shared = LoadResourceFile(NLibName, ('%s/shared.lua'):format(dir))

    if shared then
        chunk = (chunk and ('%s\n%s'):format(shared, chunk)) or shared
    end

    if chunk then
        local fn, err = load(chunk, ('@@NLib/shared/imports/%s/%s.lua'):format(module, context))

        if not fn or err then
            if shared then
                fn, err = load(shared, ('@@NLib/shared/imports/%s/shared.lua'):format(module))
            end

            if not fn or err then
                return error(('\n^1Error importing NLib module (%s): %s^0'):format(dir, err), 3)
            end
        end

        local result = fn()
        self[module] = result or true
        return self[module]
    end
end

--- Is `module` actually present in the INSTALLED NLib?
---
--- `nlib.<anything>` is never falsy -- an unknown name returns the export proxy,
--- a function -- so `if nlib.diag then` is not a guard. Probes files, not the
--- module cache. Safe only behind the version gate above: see
--- docs/internal/imports-entrypoint.md.
local function moduleExists(module)
    if type(module) ~= 'string' or module == '' then return false end
    local dir = ('shared/imports/%s'):format(module)
    return LoadResourceFile(NLibName, ('%s/%s.lua'):format(dir, context)) ~= nil
        or LoadResourceFile(NLibName, ('%s/shared.lua'):format(dir)) ~= nil
end

local function call(self, index)
    local module = rawget(self, index)

    if not module then
        module = loadModule(self, index)

        if not module then
            -- Fall through to NLib exports for non-import modules.
            local function method(...)
                return exports[NLibName][index](nil, ...)
            end
            self[index] = method
            return method
        end
    end

    return module
end

local nlib = setmetatable({
    name = NLibName,
    context = context,
    resource = resourceName,
    has = moduleExists,
}, {
    __index = call,
    __call = call,
})

_ENV.nlib = nlib

--- Modules whose LOADING IS THEIR WIRING, loaded by NLib itself: their file
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
    local chunk = LoadResourceFile(NLibName, 'shared/sh_branding.lua')
    if chunk then
        local fn = load(chunk, '@@NLib/shared/sh_branding.lua', 't',
            setmetatable({}, { __index = _ENV }))
        local ok, branding = pcall(fn)
        if ok and type(branding) == 'table' then
            isStudio = branding.isStudioResource(resourceName) == true
        end
    end
    return isStudio
end

--- Can this VM read NLib's files AT ALL? The discriminator between "one module
--- is missing" and "I cannot read NLib", which have different fixes. Asked only
--- after a module has already failed.
local function nlibReadable()
    return LoadResourceFile(NLibName, 'fxmanifest.lua') ~= nil
end

for _, entry in ipairs(AUTOLOAD) do
    if (not entry.studioOnly or studioResource()) and not rawget(nlib, entry.name) then
        -- These names are NLib's own, so one that resolves to no file is a NLib
        -- packaging bug rather than a consumer typo.
        if not loadModule(nlib, entry.name) and nlibReadable() then
            -- A print, not error(): this is a shared_script in every consumer,
            -- so raising here stops every t* resource on the server at once.
            print(('^1[NLib] cannot load its own module "%s" — no '
                .. 'shared/imports/%s/%s.lua and no shared.lua. NLib v%s is packaged '
                .. 'wrong; %s is running WITHOUT it.^0')
                :format(entry.name, entry.name, context,
                    GetResourceMetadata(NLibName, 'version', 0) or '?', resourceName))
        end
    end
end

-- Eagerly load modules declared in the consumer's fxmanifest:
--   nlib_module { 'coords' }   /   nlib_modules { 'coords', 'kvp' }
--
-- Not load-bearing any more except for `realtime`, which NLib's server bundle
-- reads off the manifest to decide whether to install the realtime hub. Kept as
-- an auditable parts list. See docs/internal/imports-entrypoint.md.
--
for _, key in ipairs({ 'nlib_module', 'nlib_modules' }) do
    for i = 1, GetNumResourceMetadata(resourceName, key) do
        local name = GetResourceMetadata(resourceName, key, i - 1)
        if name and not rawget(nlib, name) then
            loadModule(nlib, name)
        end
    end
end

