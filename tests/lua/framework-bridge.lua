local report = print
local function eq(got, want, label)
    if got ~= want then error(('%s: got %s, want %s'):format(label, tostring(got), tostring(want)), 0) end
end

local F = dofile('shared/imports/framework/server.lua')

eq(F.detect(function(n) return n == 'es_extended' and 'started' or 'missing' end), 'esx', 'detects esx')
eq(F.detect(function(n) return (n == 'qb-core' or n == 'qbx_core') and 'started' or 'missing' end), 'qbox', 'qbox wins over qb')
eq(F.detect(function() return 'missing' end), 'standalone', 'standalone fallback')

local seen
local sqlLog, paramLog = {}, {}
local json = { decode = function(s) if s == '{"model":123}' then return { model = 123 } end; return { firstname = 'Anna', lastname = 'Jensen', birthdate = '1990-01-02', phone = '12345678' } end }
local deps = {
    json = json,
    resourceState = function() return 'missing' end,
    hasAce = function() return true end,
    playerName = function() return 'Fallback' end,
    identifier = function(src) return 'license:' .. src end,
    db = { query = function(sql, params)
        seen = { sql = sql, params = params }
        sqlLog[#sqlLog + 1] = sql
        paramLog[#paramLog + 1] = params or {}
        if sql:find('COUNT%(') then return { { n = 42 } } end
        if sql:find('FROM users') then return { { identifier = 'u1', firstname = 'Martin', lastname = 'Hansen', dateofbirth = '1992-03-15', phone_number = '555' } } end
        if sql:find('owned_vehicles') then return { { plate = 'AB 12 345', owner = 'u1', vehicle = '{"model":123}' } } end
        if sql:find('FROM players') then return { { citizenid = 'C1', charinfo = '{}' } } end
        if sql:find('player_vehicles') then return { { plate = 'CD 67 890', citizenid = 'C1', vehicle = 'sultan' } } end
        return {}
    end },
    esx = function() return { GetPlayerFromId = function(src)
        local variables = { firstName = 'Martin', lastName = 'Hansen' }
        return { identifier = 'u' .. src, getName = function() return 'xX_SteamNavn_Xx' end, get = function(k) return variables[k] end, job = { name = 'police', grade = 3 } }
    end } end,
    qb = function() return { Functions = { GetPlayer = function() return { PlayerData = { citizenid = 'C1', charinfo = { firstname = 'Anna', lastname = 'Jensen' }, job = { name = 'police', grade = { level = 2 } } } } end } } end,
    qbox = function() return { GetPlayer = function() return { PlayerData = { citizenid = 'Q1', charinfo = { firstname = 'Q', lastname = 'Box' }, job = { name = 'police', grade = 1 } } } end } end,
}

local esx = F.create(deps, 'esx')
local p = esx.getPlayer(7)
eq(p.name, 'Martin Hansen', 'esx: the character name, not the FiveM/Steam name'); eq(p.identifier, 'u7', 'esx identifier'); eq(p.job.name, 'police', 'esx job'); eq(p.job.grade, 3, 'esx grade')
local people = esx.searchPeople('Mart_in', 10)
eq(people[1].name, 'Martin Hansen', 'esx person name')
eq(seen.params[1], '%Mart\\_in%', 'search term escaped')
eq(esx.getVehicle('AB 12 345').ownerId, 'u1', 'esx vehicle owner')
eq(seen.params[1], 'AB12345', 'plate spaces removed for lookup')

-- Paged lists: a stable order for the day, a total, and sane limits
local listed, total = esx.listPeople(20, 10, '2026-10-21')
eq(listed[1].name, 'Martin Hansen', 'esx list rows are people'); eq(total, 42, 'esx list total')
local listSql = sqlLog[#sqlLog - 1]
eq(listSql:find('ORDER BY CRC32%(CONCAT%(identifier, %?%)%), identifier LIMIT %? OFFSET %?') ~= nil, true, 'esx list orders by a seeded hash with a tie-break')
local _, _t = esx.listPeople(-5, 9999, nil)
local lp = paramLog[#paramLog - 1]
eq(lp[2], 50, 'limit is capped'); eq(lp[3], 0, 'offset cannot be negative'); eq(lp[1], '', 'no seed is an empty seed')
local cars, carTotal = esx.listVehicles(0, 10, 'x')
eq(cars[1].plate, 'AB 12 345', 'esx list vehicles'); eq(carTotal, 42, 'and their total')

local q = F.create(deps, 'qb')
eq(q.listPeople(0, 10, 'x')[1].identifier, 'C1', 'qb list people'); eq(select(2, q.listVehicles(0, 10, 'x')), 42, 'qb list vehicles total')
eq(q.getPlayer(1).job.grade, 2, 'qb grade level')
eq(q.getPlayer(1).identifier, 'C1', 'qb identifier'); eq(q.getPlayer(1).name, 'Anna Jensen', 'qb: charinfo name')
eq(q.getVehicle('CD 67 890').model, 'sultan', 'qb vehicle')
eq(F.create(deps, 'qbox').getPlayer(1).identifier, 'Q1', 'qbox player')

-- ESX without firstName on the player: the users table is used, and asked once per identifier
do
    local asked = 0
    local d2 = setmetatable({
        esx = function() return { GetPlayerFromId = function(src) return { identifier = 'u' .. src, getName = function() return 'xX_SteamNavn_Xx' end, job = { name = 'police', grade = 1 } } end } end,
        db = { query = function(sql) asked = asked + 1; return { { firstname = 'Anna', lastname = 'Jensen' } } end },
    }, { __index = deps })
    local e2 = F.create(d2, 'esx')
    eq(e2.getPlayer(3).name, 'Anna Jensen', 'esx falls back to the users table'); e2.getPlayer(3); eq(asked, 1, 'and remembers it')
    local d3 = setmetatable({
        esx = d2.esx, db = { query = function() return {} end },
    }, { __index = deps })
    local nameless = F.create(d3, 'esx').getPlayer(4).name
    eq(nameless, nil, 'esx never falls back to the FiveM/Steam name when no character exists')
end

-- A configured resolver wins, for any framework
do
    local d4 = setmetatable({ characterName = function(src) return src == 5 and '  Kim Larsen ' or nil end }, { __index = deps })
    eq(F.create(d4, 'esx').getPlayer(5).name, 'Kim Larsen', 'characterName overrides and is trimmed')
    eq(F.create(d4, 'esx').getPlayer(6).name, 'Martin Hansen', 'and leaves other players alone')
    eq(F.create(d4, 'qb').getPlayer(5).name, 'Kim Larsen', 'also on qb')
    local d5 = setmetatable({ characterName = function() error('boom') end }, { __index = deps })
    eq(F.create(d5, 'esx').getPlayer(5).name, 'Martin Hansen', 'a failing resolver does not break the bridge')
end

local logged = {}
deps.log = function(m) logged[#logged + 1] = m end
local s = F.create(deps, 'standalone')
eq(s.getPlayer(3).identifier, 'license:3', 'standalone identifier'); s.getPlayer(4)
eq(#logged, 1, 'standalone says once that it has no character names')
eq(#s.searchPeople('x'), 0, 'standalone has no people')
eq(select(2, s.listPeople(0, 10, 'x')), 0, 'and no list')
eq(F.create(deps, 'auto').name, 'standalone', 'auto resolves')
report('PASS framework bridge: detect, esx, qb, qbox, standalone')
