--[[
    norden_lib/imports.lua
    Single entry point for consumer resources.

    Usage in consumer fxmanifest.lua:
        shared_scripts { '@norden_lib/imports.lua' }

    Modules lazy-load on first access of `norden_lib.<name>`.
    Design notes: docs/internal/imports-entrypoint.md

]]

local resourceName = GetCurrentResourceName()
local NordenLibName = 'norden_lib'

if resourceName == NordenLibName then return end

if GetResourceState(NordenLibName) ~= 'started' then
    error('^1NordenLib must be started before this resource.^0', 0)
end

local context = IsDuplicityVersion() and 'server' or 'client'

-- Enforce norden_lib_min_version *before* anything touches norden_lib, so an outdated Norden Lib
-- says "update norden_lib" instead of "No such export X". Duplicated from
-- versioncheck/server.lua: this file runs in consumer VMs, that one in Norden Lib's.
local function parseVer(s)
    if not s then return { 0, 0, 0 } end
    s = s:gsub('^v', '')
    local parts = {}
    for n in s:gmatch('%d+') do parts[#parts + 1] = tonumber(n) end
    while #parts < 3 do parts[#parts + 1] = 0 end
    return parts
end

local requiredVersion = GetResourceMetadata(resourceName, 'norden_lib_min_version', 0)
if requiredVersion and requiredVersion ~= '' then
    local nordenLibVersion = GetResourceMetadata(NordenLibName, 'version', 0) or '0.0.0'
    local req, cur = parseVer(requiredVersion), parseVer(nordenLibVersion)
    local outdated = false
    for i = 1, 3 do
        if cur[i] < req[i] then outdated = true; break
        elseif cur[i] > req[i] then break end
    end
    if outdated then
        error(('\n^1[%s] requires Norden Lib v%s or newer — installed Norden Lib is v%s. Update Norden Lib.^0')
            :format(resourceName, requiredVersion, nordenLibVersion), 0)
    end
end

local function loadModule(self, module)
    local dir = ('shared/imports/%s'):format(module)
    local chunk = LoadResourceFile(NordenLibName, ('%s/%s.lua'):format(dir, context))
    local shared = LoadResourceFile(NordenLibName, ('%s/shared.lua'):format(dir))

    if shared then
        chunk = (chunk and ('%s\n%s'):format(shared, chunk)) or shared
    end

    if chunk then
        local fn, err = load(chunk, ('@@norden_lib/shared/imports/%s/%s.lua'):format(module, context))

        if not fn or err then
            if shared then
                fn, err = load(shared, ('@@norden_lib/shared/imports/%s/shared.lua'):format(module))
            end

            if not fn or err then
                return error(('\n^1Error importing Norden Lib module (%s): %s^0'):format(dir, err), 3)
            end
        end

        local result = fn()
        self[module] = result or true
        return self[module]
    end
end

--- Is `module` actually present in the INSTALLED Norden Lib?
---
--- `norden_lib.<anything>` is never falsy -- an unknown name returns the export proxy,
--- a function -- so `if norden_lib.diag then` is not a guard. Probes files, not the
--- module cache. Safe only behind the version gate above: see
--- docs/internal/imports-entrypoint.md.
local function moduleExists(module)
    if type(module) ~= 'string' or module == '' then return false end
    local dir = ('shared/imports/%s'):format(module)
    return LoadResourceFile(NordenLibName, ('%s/%s.lua'):format(dir, context)) ~= nil
        or LoadResourceFile(NordenLibName, ('%s/shared.lua'):format(dir)) ~= nil
end

local function call(self, index)
    local module = rawget(self, index)

    if not module then
        module = loadModule(self, index)

        if not module then
            -- Fall through to Norden Lib exports for non-import modules.
            local function method(...)
                return exports[NordenLibName][index](nil, ...)
            end
            self[index] = method
            return method
        end
    end

    return module
end

local norden_lib = setmetatable({
    name = NordenLibName,
    context = context,
    resource = resourceName,
    has = moduleExists,
}, {
    __index = call,
    __call = call,
})

_ENV.norden_lib = norden_lib

--- Modules whose LOADING IS THEIR WIRING, loaded by Norden Lib itself: their file
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
    local chunk = LoadResourceFile(NordenLibName, 'shared/sh_branding.lua')
    if chunk then
        local fn = load(chunk, '@@norden_lib/shared/sh_branding.lua', 't',
            setmetatable({}, { __index = _ENV }))
        local ok, branding = pcall(fn)
        if ok and type(branding) == 'table' then
            isStudio = branding.isStudioResource(resourceName) == true
        end
    end
    return isStudio
end

--- Can this VM read Norden Lib's files AT ALL? The discriminator between "one module
--- is missing" and "I cannot read norden_lib", which have different fixes. Asked only
--- after a module has already failed.
local function nordenLibReadable()
    return LoadResourceFile(NordenLibName, 'fxmanifest.lua') ~= nil
end

for _, entry in ipairs(AUTOLOAD) do
    if (not entry.studioOnly or studioResource()) and not rawget(norden_lib, entry.name) then
        -- These names are Norden Lib's own, so one that resolves to no file is a Norden Lib
        -- packaging bug rather than a consumer typo.
        if not loadModule(norden_lib, entry.name) and nordenLibReadable() then
            -- A print, not error(): this is a shared_script in every consumer,
            -- so raising here stops every t* resource on the server at once.
            print(('^1[norden_lib] cannot load its own module "%s" — no '
                .. 'shared/imports/%s/%s.lua and no shared.lua. Norden Lib v%s is packaged '
                .. 'wrong; %s is running WITHOUT it.^0')
                :format(entry.name, entry.name, context,
                    GetResourceMetadata(NordenLibName, 'version', 0) or '?', resourceName))
        end
    end
end

-- Eagerly load modules declared in the consumer's fxmanifest:
--   norden_lib_module { 'coords' }   /   norden_lib_modules { 'coords', 'kvp' }
--
-- Not load-bearing any more except for `realtime`, which Norden Lib's server bundle
-- reads off the manifest to decide whether to install the realtime hub. Kept as
-- an auditable parts list. See docs/internal/imports-entrypoint.md.
--
for _, key in ipairs({ 'norden_lib_module', 'norden_lib_modules' }) do
    for i = 1, GetNumResourceMetadata(resourceName, key) do
        local name = GetResourceMetadata(resourceName, key, i - 1)
        if name and not rawget(norden_lib, name) then
            loadModule(norden_lib, name)
        end
    end
end

