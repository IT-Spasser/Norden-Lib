-- loads the real Coords table from Norden Lib's shared/sh_coords.lua into this VM.
-- consumer VMs don't share Norden Lib's globals so we load it via LoadResourceFile.
if not Coords then
    local NordenLibName = 'norden_lib'
    local source = LoadResourceFile(NordenLibName, 'shared/sh_coords.lua')
    if source then
        local fn, err = load(source, '@@norden_lib/shared/sh_coords.lua')
        if fn then fn() end
    end
end

return Coords
