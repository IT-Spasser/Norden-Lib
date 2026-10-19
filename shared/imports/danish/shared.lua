--[[ Danish identifiers and formats: CPR, plates, badge numbers, callsigns, dates, amounts. Pure Lua, no natives. ]]

local M = { cpr = {}, plate = {}, badge = {}, callsign = {}, format = {} }

local function digits(s) return (tostring(s):gsub('%D', '')) end

--- `1503922845`, `150392-2845` and `150392 2845` all become `150392-2845`; anything else is nil.
function M.cpr.normalize(input)
    if type(input) ~= 'string' then return nil end
    local d = digits(input)
    if #d ~= 10 then return nil end
    local day, month = tonumber(d:sub(1, 2)), tonumber(d:sub(3, 4))
    if day < 1 or day > 31 or month < 1 or month > 12 then return nil end
    return d:sub(1, 6) .. '-' .. d:sub(7)
end

function M.cpr.mask(cpr)
    local n = M.cpr.normalize(cpr)
    if not n then return cpr end
    return n:sub(1, 6) .. '-\226\128\162\226\128\162\226\128\162\226\128\162'
end

--- `ab12345` -> `AB 12 345`. Nil when it is not a Danish plate.
function M.plate.normalize(input)
    if type(input) ~= 'string' then return nil end
    local s = input:gsub('%s+', ''):upper()
    local a, b, c = s:match('^(%u%u)(%d%d)(%d%d%d)$')
    if not a then return nil end
    return ('%s %s %s'):format(a, b, c)
end

function M.badge.normalize(input)
    if type(input) ~= 'string' then return nil end
    local s = input:gsub('%s+', ''):upper()
    if s:match('^%u%d%d%d%d$') then return s end
    return nil
end

--- `MIKE 10-12` or `MIKE 10-12/2`.
function M.callsign.format(kind, a, b, member)
    local base = ('%s %02d-%02d'):format(tostring(kind):upper(), a, b)
    if member and member > 0 then return base .. '/' .. member end
    return base
end

function M.callsign.parse(input, allowedTypes)
    if type(input) ~= 'string' then return nil end
    local kind, a, b, member = input:upper():match('^(%u+) (%d%d)%-(%d%d)/?(%d*)$')
    if not kind then return nil end
    if allowedTypes then
        local ok = false
        for _, t in ipairs(allowedTypes) do if t:upper() == kind then ok = true end end
        if not ok then return nil end
    end
    return { type = kind, a = tonumber(a), b = tonumber(b), member = tonumber(member) }
end

--- The part before the slash: what a group shares.
function M.callsign.group(input)
    local p = M.callsign.parse(input)
    return p and M.callsign.format(p.type, p.a, p.b) or nil
end

function M.format.caseNumber(year, seq) return ('%d-%06d'):format(year, seq) end

function M.format.date(y, m, d) return ('%02d.%02d.%04d'):format(d, m, y) end

function M.format.time(h, m) return ('%02d:%02d'):format(h, m) end

function M.format.amount(kr)
    local s = tostring(math.floor(kr + 0.5))
    local out = s:reverse():gsub('(%d%d%d)', '%1.'):reverse()
    return (out:gsub('^%.', '')) .. ' kr.'
end

--- `Martin Hansen` -> `M. Hansen`; at most two initials.
function M.format.displayName(full)
    local parts = {}
    for w in tostring(full):gmatch('%S+') do parts[#parts + 1] = w end
    if #parts < 2 then return (tostring(full):gsub('^%s+', ''):gsub('%s+$', '')) end
    local initials = {}
    for i = 1, math.min(#parts - 1, 2) do initials[i] = parts[i]:sub(1, 1):upper() .. '.' end
    return table.concat(initials, ' ') .. ' ' .. parts[#parts]
end

return M
