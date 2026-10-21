--[[
    Framework bridge (server): one interface over ESX, QBCore, QBox and standalone.
    deps: db.query(sql, params) -> rows, resourceState(name), esx(), qb(), qbox(), json, identifier(src), playerName(src), hasAce(src, ace)
          characterName(src) -> 'Fornavn Efternavn' | nil   optional override for any framework
    A player's name is always the ROLEPLAY name (the character), never the FiveM/Steam name. ESX reads firstName/lastName from the
    player and falls back to the users table; QBCore and QBox read charinfo. Only when no character name can be found at all, and
    only for standalone, the platform name is used (and logged once), because that is all there is.
]]

local M = {}

local function trim(s) return (tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', '')) end
local function like(term) return '%' .. tostring(term):gsub('[\\%%_]', '\\%0') .. '%' end

function M.detect(resourceState)
    local function started(name) return resourceState(name) == 'started' end
    if started('qbx_core') then return 'qbox' end
    if started('qb-core') then return 'qb' end
    if started('es_extended') then return 'esx' end
    return 'standalone'
end

local function decode(deps, v)
    if type(v) == 'table' then return v end
    if type(v) ~= 'string' or v == '' then return {} end
    local ok, t = pcall(deps.json.decode, v)
    return ok and type(t) == 'table' and t or {}
end

local warned = {}
local function warnOnce(deps, key, msg)
    if warned[key] or not deps.log then return end
    warned[key] = true
    deps.log(msg)
end

local function esx(deps)
    local B = { name = 'esx' }
    local cache = {}

    --- The character's name: the player object first, then the users table (cached per identifier).
    local function rpName(p)
        local first = p.get and p.get('firstName')
        local last = p.get and p.get('lastName')
        if type(first) == 'string' and first ~= '' then return trim(first .. ' ' .. (type(last) == 'string' and last or '')) end
        if cache[p.identifier] then return cache[p.identifier] end
        local rows = deps.db.query('SELECT firstname, lastname FROM users WHERE identifier = ? LIMIT 1', { p.identifier })
        local r = rows and rows[1]
        local name = r and trim((r.firstname or '') .. ' ' .. (r.lastname or '')) or ''
        if name ~= '' then cache[p.identifier] = name end
        return name ~= '' and name or nil
    end

    function B.getPlayer(src)
        local p = deps.esx().GetPlayerFromId(src)
        if not p then return nil end
        return {
            source = src, identifier = p.identifier, name = rpName(p),
            job = { name = p.job and p.job.name, grade = p.job and p.job.grade or 0 },
            hasAce = function(ace) return deps.hasAce(src, ace) end,
        }
    end

    local function person(r)
        return { identifier = r.identifier, name = trim((r.firstname or '') .. ' ' .. (r.lastname or '')), dob = r.dateofbirth, phone = r.phone_number }
    end

    function B.searchPeople(term, limit)
        local rows = deps.db.query(
            "SELECT identifier, firstname, lastname, dateofbirth, phone_number FROM users WHERE CONCAT(firstname, ' ', lastname) LIKE ? ESCAPE '\\\\' LIMIT ?",
            { like(term), limit or 25 })
        local out = {}
        for i, r in ipairs(rows or {}) do out[i] = person(r) end
        return out
    end

    --- One page of everyone, in an order that looks random but is the same on every page for a given seed (use the date).
    function B.listPeople(offset, limit, seed)
        offset, limit = math.max(0, math.floor(offset or 0)), math.max(1, math.min(50, math.floor(limit or 10)))
        local rows = deps.db.query('SELECT identifier, firstname, lastname, dateofbirth, phone_number FROM users ORDER BY CRC32(CONCAT(identifier, ?)), identifier LIMIT ? OFFSET ?', { tostring(seed or ''), limit, offset })
        local count = deps.db.query('SELECT COUNT(*) AS n FROM users')
        local out = {}
        for i, r in ipairs(rows or {}) do out[i] = person(r) end
        return out, tonumber(count and count[1] and count[1].n) or 0
    end

    function B.getPerson(identifier)
        local r = deps.db.query('SELECT identifier, firstname, lastname, dateofbirth, phone_number FROM users WHERE identifier = ? LIMIT 1', { identifier })
        return r and r[1] and person(r[1]) or nil
    end

    local function vehicle(r)
        local props = decode(deps, r.vehicle)
        return { plate = r.plate, ownerId = r.owner, model = props.model and tostring(props.model) or nil, color = nil }
    end

    function B.getVehicle(plate)
        local r = deps.db.query('SELECT plate, owner, vehicle FROM owned_vehicles WHERE REPLACE(plate, " ", "") = ? LIMIT 1', { (plate:gsub('%s', '')) })
        return r and r[1] and vehicle(r[1]) or nil
    end

    function B.listVehicles(offset, limit, seed)
        offset, limit = math.max(0, math.floor(offset or 0)), math.max(1, math.min(50, math.floor(limit or 10)))
        local rows = deps.db.query('SELECT plate, owner, vehicle FROM owned_vehicles ORDER BY CRC32(CONCAT(plate, ?)), plate LIMIT ? OFFSET ?', { tostring(seed or ''), limit, offset })
        local count = deps.db.query('SELECT COUNT(*) AS n FROM owned_vehicles')
        local out = {}
        for i, r in ipairs(rows or {}) do out[i] = vehicle(r) end
        return out, tonumber(count and count[1] and count[1].n) or 0
    end

    function B.searchVehicles(term, limit)
        local rows = deps.db.query('SELECT plate, owner, vehicle FROM owned_vehicles WHERE REPLACE(plate, " ", "") LIKE ? LIMIT ?', { like((term:gsub('%s', ''))), limit or 25 })
        local out = {}
        for i, r in ipairs(rows or {}) do out[i] = vehicle(r) end
        return out
    end

    function B.vehiclesOf(identifier)
        local rows = deps.db.query('SELECT plate, owner, vehicle FROM owned_vehicles WHERE owner = ? LIMIT 100', { identifier })
        local out = {}
        for i, r in ipairs(rows or {}) do out[i] = vehicle(r) end
        return out
    end

    return B
end

local function qb(deps, core)
    local B = { name = core }

    local function playerData(src)
        local c = core == 'qbox' and deps.qbox() or deps.qb().Functions
        local p = c.GetPlayer(src)
        return p and p.PlayerData
    end

    function B.getPlayer(src)
        local d = playerData(src)
        if not d then return nil end
        local ci = d.charinfo or {}
        local grade = d.job and d.job.grade
        return {
            source = src, identifier = d.citizenid, name = trim((ci.firstname or '') .. ' ' .. (ci.lastname or '')),
            job = { name = d.job and d.job.name, grade = type(grade) == 'table' and grade.level or tonumber(grade) or 0 },
            hasAce = function(ace) return deps.hasAce(src, ace) end,
        }
    end

    local function person(r)
        local ci = decode(deps, r.charinfo)
        return { identifier = r.citizenid, name = trim((ci.firstname or '') .. ' ' .. (ci.lastname or '')), dob = ci.birthdate, phone = ci.phone }
    end

    function B.searchPeople(term, limit)
        local rows = deps.db.query('SELECT citizenid, charinfo FROM players WHERE charinfo LIKE ? ESCAPE \'\\\\\' LIMIT ?', { like(term), limit or 25 })
        local out, needle = {}, term:lower()
        for _, r in ipairs(rows or {}) do
            local p = person(r)
            if p.name:lower():find(needle, 1, true) then out[#out + 1] = p end
        end
        return out
    end

    function B.listPeople(offset, limit, seed)
        offset, limit = math.max(0, math.floor(offset or 0)), math.max(1, math.min(50, math.floor(limit or 10)))
        local rows = deps.db.query('SELECT citizenid, charinfo FROM players ORDER BY CRC32(CONCAT(citizenid, ?)), citizenid LIMIT ? OFFSET ?', { tostring(seed or ''), limit, offset })
        local count = deps.db.query('SELECT COUNT(*) AS n FROM players')
        local out = {}
        for i, r in ipairs(rows or {}) do out[i] = person(r) end
        return out, tonumber(count and count[1] and count[1].n) or 0
    end

    function B.getPerson(identifier)
        local r = deps.db.query('SELECT citizenid, charinfo FROM players WHERE citizenid = ? LIMIT 1', { identifier })
        return r and r[1] and person(r[1]) or nil
    end

    local function vehicle(r) return { plate = r.plate, ownerId = r.citizenid, model = r.vehicle, color = nil } end

    function B.getVehicle(plate)
        local r = deps.db.query('SELECT plate, citizenid, vehicle FROM player_vehicles WHERE REPLACE(plate, " ", "") = ? LIMIT 1', { (plate:gsub('%s', '')) })
        return r and r[1] and vehicle(r[1]) or nil
    end

    function B.listVehicles(offset, limit, seed)
        offset, limit = math.max(0, math.floor(offset or 0)), math.max(1, math.min(50, math.floor(limit or 10)))
        local rows = deps.db.query('SELECT plate, citizenid, vehicle FROM player_vehicles ORDER BY CRC32(CONCAT(plate, ?)), plate LIMIT ? OFFSET ?', { tostring(seed or ''), limit, offset })
        local count = deps.db.query('SELECT COUNT(*) AS n FROM player_vehicles')
        local out = {}
        for i, r in ipairs(rows or {}) do out[i] = vehicle(r) end
        return out, tonumber(count and count[1] and count[1].n) or 0
    end

    function B.searchVehicles(term, limit)
        local rows = deps.db.query('SELECT plate, citizenid, vehicle FROM player_vehicles WHERE REPLACE(plate, " ", "") LIKE ? LIMIT ?', { like((term:gsub('%s', ''))), limit or 25 })
        local out = {}
        for i, r in ipairs(rows or {}) do out[i] = vehicle(r) end
        return out
    end

    function B.vehiclesOf(identifier)
        local rows = deps.db.query('SELECT plate, citizenid, vehicle FROM player_vehicles WHERE citizenid = ? LIMIT 100', { identifier })
        local out = {}
        for i, r in ipairs(rows or {}) do out[i] = vehicle(r) end
        return out
    end

    return B
end

local function standalone(deps)
    local B = { name = 'standalone' }
    function B.getPlayer(src)
        local id = deps.identifier(src)
        if not id then return nil end
        -- Without a framework there is no character; the platform name is all there is unless characterName is supplied.
        warnOnce(deps, 'standalone-name', 'standalone: no character names exist, using the FiveM name. Set Config.CharacterName to supply roleplay names.')
        return { source = src, identifier = id, name = deps.playerName(src), job = { name = nil, grade = 0 }, hasAce = function(ace) return deps.hasAce(src, ace) end }
    end
    function B.searchPeople() return {} end
    function B.listPeople() return {}, 0 end
    function B.listVehicles() return {}, 0 end
    function B.getPerson() return nil end
    function B.getVehicle() return nil end
    function B.searchVehicles() return {} end
    function B.vehiclesOf() return {} end
    return B
end

--- framework: 'auto' | 'esx' | 'qb' | 'qbox' | 'standalone'
function M.create(deps, framework)
    if not framework or framework == 'auto' then framework = M.detect(deps.resourceState) end
    local B
    if framework == 'esx' then B = esx(deps)
    elseif framework == 'qb' or framework == 'qbox' then B = qb(deps, framework)
    else B = standalone(deps) end

    -- A configured resolver wins over everything: it is how a server with its own character system says who is who.
    if deps.characterName then
        local inner = B.getPlayer
        function B.getPlayer(src)
            local p = inner(src)
            if not p then return nil end
            local ok, name = pcall(deps.characterName, src)
            if ok and type(name) == 'string' and name ~= '' then p.name = trim(name) end
            return p
        end
    end
    return B
end

return M
