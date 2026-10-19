-- Oracle for shared/imports/danish: the Lua half of the formats the MDT UI also implements.
local report = print
local function eq(got, want, label)
    if got ~= want then error(('%s: got %s, want %s'):format(label, tostring(got), tostring(want)), 0) end
end

local D = dofile('shared/imports/danish/shared.lua')

eq(D.cpr.normalize('1503922845'), '150392-2845', 'cpr digits')
eq(D.cpr.normalize('150392 2845'), '150392-2845', 'cpr space')
eq(D.cpr.normalize('320392-2845'), nil, 'cpr bad day')
eq(D.cpr.normalize('150392-284'), nil, 'cpr short')
eq(D.cpr.mask('150392-2845'), '150392-\226\128\162\226\128\162\226\128\162\226\128\162', 'cpr mask')
eq(D.plate.normalize('ab12345'), 'AB 12 345', 'plate')
eq(D.plate.normalize(' AB 12 345 '), 'AB 12 345', 'plate spaced')
eq(D.plate.normalize('A1'), nil, 'plate invalid')
eq(D.badge.normalize('x1212'), 'X1212', 'badge')
eq(D.badge.normalize('1212'), nil, 'badge invalid')
eq(D.callsign.format('mike', 10, 12), 'MIKE 10-12', 'callsign')
eq(D.callsign.format('MIKE', 10, 12, 2), 'MIKE 10-12/2', 'callsign member')
eq(D.callsign.parse('MIKE 10-12/2').member, 2, 'callsign parse member')
eq(D.callsign.parse('ZULU 10-12', { 'MIKE' }), nil, 'callsign type not allowed')
eq(D.callsign.group('MIKE 10-12/2'), 'MIKE 10-12', 'callsign group')
eq(D.format.caseNumber(2026, 1234), '2026-001234', 'case number')
eq(D.format.date(2026, 10, 19), '19.10.2026', 'date')
eq(D.format.amount(2000), '2.000 kr.', 'amount')
eq(D.format.amount(1234567), '1.234.567 kr.', 'amount big')
eq(D.format.amount(500), '500 kr.', 'amount small')
eq(D.format.displayName('Martin Hansen'), 'M. Hansen', 'name')
eq(D.format.displayName('Anna Marie Jensen'), 'A. M. Jensen', 'name two initials')
report('PASS danish: cpr, plate, badge, callsign and formats')
