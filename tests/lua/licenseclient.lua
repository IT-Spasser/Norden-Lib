-- Oracle for shared/imports/licenseclient: verdicts block at once, unreachability gets 72 h grace.
local report = print
local function eq(got, want, label)
    if got ~= want then error(('%s: got %s, want %s'):format(label, tostring(got), tostring(want)), 0) end
end

local LC = dofile('shared/imports/licenseclient/server.lua')

local t = 1000
local reply
local saved
local valid = { good = true }
local deps = {
    now = function() return t end,
    http = function(_, _, _, cb) cb(reply.status, reply.body) end,
    -- A token verifies while its expiry (stored as the token's name suffix) plus grace is in the future.
    verify = function(token, grace)
        local exp = tonumber(token:match('exp(%d+)$'))
        if not exp or exp + grace < t then return nil end
        return { cc = 'ABCD-EFGH' }
    end,
    save = function(v) saved = v end,
}

local function client() return LC.create(deps, { graceHours = 72 }) end
local H = 3600

local c = client()
reply = { status = 200, body = { token = 'tok-exp' .. (t + 24 * H), communityCode = 'ABCD-EFGH' } }
local st
c.activate('KEY', '55 Politi', nil, function(r) st = r end)
eq(st.state, 'ok', 'activates')
eq(st.communityCode, 'ABCD-EFGH', 'community code')
eq(saved.token, 'tok-exp' .. (t + 24 * H), 'token cached')

reply = { status = 500, body = nil }
t = t + 30 * H
c.refresh(function(r) st = r end)
eq(st.state, 'grace', 'unreachable with an expired token runs on grace')
eq(st.ok, true, 'grace still licensed')

t = t + 60 * H
eq(c.status().state, 'blocked', 'grace over blocks')
eq(c.status().code, 'LICENSE_UNREACHABLE', 'blocked code')

local fresh = client()
eq(fresh.status().state, 'unknown', 'fresh client has no verdict')
reply = { status = 500 }
fresh.activate('KEY', 'x', nil, function(r) st = r end)
eq(st.state, 'blocked', 'unreachable with nothing cached blocks')

reply = { status = 402, body = { error = { code = 'LICENSE_SUSPENDED' } } }
local c2 = client()
c2.activate('KEY', 'x', nil, function(r) st = r end)
eq(st.code, 'LICENSE_SUSPENDED', 'verdict blocks at once')
eq(c2.isLicensed(), false, 'not licensed')

reply = { status = 200, body = { token = 'forged' } }
c2.activate('KEY', 'x', nil, function(r) st = r end)
eq(st.state, 'blocked', 'unverifiable token is refused')

t = 1000
reply = { status = 200, body = { token = 'tok-exp' .. (t + 24 * H) } }
c.activate('KEY', 'x', nil, function() end)
reply = { status = 402, body = { error = { code = 'LICENSE_EXPIRED' } } }
c.refresh(function(r) st = r end)
eq(st.state, 'blocked', 'verdict beats grace')
report('PASS licenseclient: activate, grace, verdicts, forged token')
