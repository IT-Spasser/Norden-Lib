-- loads the real Coords table from NLib's shared/sh_coords.lua into this VM.
-- consumer VMs don't share NLib's globals so we load it via LoadResourceFile.
if not Coords then
    local NLibName = 'NLib'
    local source = LoadResourceFile(NLibName, 'shared/sh_coords.lua')
    if source then
        local fn, err = load(source, '@@NLib/shared/sh_coords.lua')
        if fn then fn() end
    end
end

return Coords
