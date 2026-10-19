--[[
    License client. Activates and refreshes a licence against the licence server, verifies
    the signed token locally, and keeps a 72 h grace when the server cannot be reached.
    The client holds no secret: only the public key and the licence key the operator sets.
]]

local M = {}

local BLOCKING = { LICENSE_NOT_FOUND = true, LICENSE_EXPIRED = true, LICENSE_SUSPENDED = true }

--- deps: http(method, path, body, cb(status, decodedTable|nil)), verify(token, graceSeconds) -> claims|nil,
--- now() -> seconds, load() -> cached table|nil, save(table), log(msg)
function M.create(deps, opts)
    opts = opts or {}
    local graceSeconds = (opts.graceHours or 72) * 3600
    local self = {}
    local s = { state = 'unknown', code = nil, token = nil, communityCode = nil, lastOkAt = nil, serverName = opts.serverName }

    local cached = deps.load and deps.load()
    if type(cached) == 'table' and cached.token then
        s.token, s.communityCode, s.lastOkAt = cached.token, cached.communityCode, cached.lastOkAt
    end

    local function block(code) s.state, s.code = 'blocked', code end

    local function accept(token, communityCode)
        local claims = deps.verify(token, 0)
        if not claims then return false end
        s.state, s.code, s.token, s.lastOkAt = 'ok', nil, token, deps.now()
        s.communityCode = communityCode or claims.cc or s.communityCode
        if deps.save then deps.save({ token = token, communityCode = s.communityCode, lastOkAt = s.lastOkAt }) end
        return true
    end

    --- Called when the server could not be reached or answered with a failure that is not a verdict.
    local function unreachable()
        if s.token and s.lastOkAt and deps.now() - s.lastOkAt <= graceSeconds and deps.verify(s.token, graceSeconds) then
            s.state, s.code = 'grace', 'LICENSE_UNREACHABLE'
            if deps.log then deps.log('licence server unreachable; running on the last valid token') end
        else
            block('LICENSE_UNREACHABLE')
        end
    end

    local function handle(status, body, done)
        local code = type(body) == 'table' and type(body.error) == 'table' and body.error.code or nil
        if status == 200 and type(body) == 'table' and type(body.token) == 'string' then
            if not accept(body.token, body.communityCode) then block('LICENSE_NOT_FOUND') end
        elseif code and BLOCKING[code] then
            s.token, s.lastOkAt = nil, nil
            block(code)
        else
            unreachable()
        end
        if done then done(self.status()) end
    end

    function self.activate(licenseKey, serverName, endpointUrl, done)
        s.serverName = serverName or s.serverName
        deps.http('POST', '/v1/license/activate', { licenseKey = licenseKey, serverName = s.serverName, endpointUrl = endpointUrl },
            function(status, body) handle(status, body, done) end)
    end

    function self.refresh(done)
        if not s.token then return self.status() end
        deps.http('POST', '/v1/license/refresh', { token = s.token }, function(status, body) handle(status, body, done) end)
    end

    --- Re-evaluates local state without network: a token past grace blocks.
    function self.status()
        if s.state == 'ok' or s.state == 'grace' then
            if not (s.lastOkAt and deps.now() - s.lastOkAt <= graceSeconds and deps.verify(s.token, graceSeconds)) then
                block('LICENSE_UNREACHABLE')
            elseif s.state == 'ok' and not deps.verify(s.token, 0) then
                s.state, s.code = 'grace', 'LICENSE_UNREACHABLE'
            end
        end
        return { state = s.state, code = s.code, ok = s.state == 'ok' or s.state == 'grace', communityCode = s.communityCode, serverName = s.serverName }
    end

    function self.isLicensed() return self.status().ok end

    return self
end

return M
