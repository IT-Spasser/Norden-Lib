-- NLib/server/lib/adapter/utils.lua
-- HTTP fetch and misc utils


if _NLIB_IS_FIVEM then
    function Platform.Fetch(opts, callback)
        PerformHttpRequest(
            opts.url,
            callback,
            opts.method or 'GET',
            opts.body or '',
            opts.headers or {},
            { followLocation = true }
        )
    end
else
    Platform.Fetch = Platform._stub('Fetch')
end

Platform.export('NLib', 'Fetch', function(opts, callback)
    Platform.Fetch(opts, callback)
end)
