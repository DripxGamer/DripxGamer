-- Valores derivados das rotas (corre em cliente e servidor depois de config/routes.lua).
-- Não precisas de mexer aqui.

local depot = Config.Depot.coords
local bonuses = Config.Bonuses

for index, route in ipairs(Config.Routes) do
    local previous = vector3(depot.x, depot.y, depot.z)
    local length = 0.0
    local boarding = 0

    for _, stop in ipairs(route.stops) do
        length = length + #(stop.stop_coord - previous)
        previous = stop.stop_coord
        boarding = boarding + #stop.npc_positions
    end

    route.id = index
    route.length = length * bonuses.routeFactor
    route.boarding = boarding
    route.parTime = math.floor(
        route.length / bonuses.parSpeed
        + #route.stops * (Config.StopServiceTime / 1000)
        + bonuses.parPadding
    )
end
