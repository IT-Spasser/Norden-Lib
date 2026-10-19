local report = print
local function eq(got, want, label)
    if got ~= want then error(('%s: got %s, want %s'):format(label, tostring(got), tostring(want)), 0) end
end

local F = dofile('shared/imports/framework/server.lua')

eq(F.detect(function(n) return n == 'es_extended' and 'started' or 'missing' end), 'esx', 'detects esx')
eq(F.detect(function(n) return (n == 'qb-core' or n == 'qbx_core') and 'started' or 'missing' end), 'qbox', 'qbox wins over qb')
eq(F.detect(function() return 'missing' end), 'standalone', 'standalone fallback')

local seen
local json = { decode = function(s) if s == '{"model":123}' then return { model = 123 } end; return { firstname = 'Anna', lastname = 'Jensen', birthdate = '1990-01-02', phone = '12345678' } end }
local deps = {
    json = json,
    resourceState = function() return 'missing' end,
    hasAce = function() return true end,
    playerName = function() return 'Fallback' end,
    identifier = function(src) return 'license:' .. src end,
    db = { query = function(sql, params)
        seen = { sql = sql, params = params }
        if sql:find('FROM users') then return { { identifier = 'u1', firstname = 'Martin', lastname = 'Hansen', dateofbirth = '1992-03-15', phone_number = '555' } } end
        if sql:find('owned_vehicles') then return { { plate = 'AB 12 345', owner = 'u1', vehicle = '{"model":123}' } } end
        if sql:find('FROM players') then return { { citizenid = 'C1', charinfo = '{}' } } end
        if sql:find('player_vehicles') then return { { plate = 'CD 67 890', citizenid = 'C1', vehicle = 'sultan' } } end
        return {}
    end },
    esx = function() return { GetPlayerFromId = function(src) return { identifier = 'u' .. src, getName = function() return 'Martin Hansen' end, job = { name = 'police', grade = 3 } } end } end,
    qb = function() return { Functions = { GetPlayer = function() return { PlayerData = { citizenid = 'C1', charinfo = { firstname = 'Anna', lastname = 'Jensen' }, job = { name = 'police', grade = { level = 2 } } } } end } } end,
    qbox = function() return { GetPlayer = function() return { PlayerData = { citizenid = 'Q1', charinfo = { firstname = 'Q', lastname = 'Box' }, job = { name = 'police', grade = 1 } } } end } end,
}

local esx = F.create(deps, 'esx')
local p = esx.getPlayer(7)
eq(p.identifier, 'u7', 'esx identifier'); eq(p.job.name, 'police', 'esx job'); eq(p.job.grade, 3, 'esx grade')
local people = esx.searchPeople('Mart_in', 10)
eq(people[1].name, 'Martin Hansen', 'esx person name')
eq(seen.params[1], '%Mart\\_in%', 'search term escaped')
eq(esx.getVehicle('AB 12 345').ownerId, 'u1', 'esx vehicle owner')
eq(seen.params[1], 'AB12345', 'plate spaces removed for lookup')

local q = F.create(deps, 'qb')
eq(q.getPlayer(1).job.grade, 2, 'qb grade level')
eq(q.getPlayer(1).identifier, 'C1', 'qb identifier')
eq(q.getVehicle('CD 67 890').model, 'sultan', 'qb vehicle')
eq(F.create(deps, 'qbox').getPlayer(1).identifier, 'Q1', 'qbox player')

local s = F.create(deps, 'standalone')
eq(s.getPlayer(3).identifier, 'license:3', 'standalone identifier')
eq(#s.searchPeople('x'), 0, 'standalone has no people')
eq(F.create(deps, 'auto').name, 'standalone', 'auto resolves')
report('PASS framework bridge: detect, esx, qb, qbox, standalone')
