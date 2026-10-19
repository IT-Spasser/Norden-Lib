--[[
    Framework bridge (server): one interface over ESX, QBCore, QBox and standalone.
    deps: db.query(sql, params) -> rows, resourceState(name), esx(), qb(), qbox(), json, identifier(src), playerName(src), hasAce(src, ace)
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

local function esx(deps)
    local B = { name = 'esx' }

    function B.getPlayer(src)
        local p = deps.esx().GetPlayerFromId(src)
        if not p then return nil end
        return {
            source = src, identifier = p.identifier, name = p.getName and p.getName() or deps.playerName(src),
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

    function B.getPerson(identifier)
        local r = deps.db.query('SELECT citizenid, charinfo FROM players WHERE citizenid = ? LIMIT 1', { identifier })
        return r and r[1] and person(r[1]) or nil
    end

    local function vehicle(r) return { plate = r.plate, ownerId = r.citizenid, model = r.vehicle, color = nil } end

    function B.getVehicle(plate)
        local r = deps.db.query('SELECT plate, citizenid, vehicle FROM player_vehicles WHERE REPLACE(plate, " ", "") = ? LIMIT 1', { (plate:gsub('%s', '')) })
        return r and r[1] and vehicle(r[1]) or nil
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
        return { source = src, identifier = id, name = deps.playerName(src), job = { name = nil, grade = 0 }, hasAce = function(ace) return deps.hasAce(src, ace) end }
    end
    function B.searchPeople() return {} end
    function B.getPerson() return nil end
    function B.getVehicle() return nil end
    function B.searchVehicles() return {} end
    function B.vehiclesOf() return {} end
    return B
end

--- framework: 'auto' | 'esx' | 'qb' | 'qbox' | 'standalone'
function M.create(deps, framework)
    if not framework or framework == 'auto' then framework = M.detect(deps.resourceState) end
    if framework == 'esx' then return esx(deps) end
    if framework == 'qb' or framework == 'qbox' then return qb(deps, framework) end
    return standalone(deps)
end

return M
