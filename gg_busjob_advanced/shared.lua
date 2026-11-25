-- Valores derivados das rotas (corre em cliente e servidor depois de config/routes.lua).
-- Não precisas de mexer aqui.

local depot = Config.Depot.coords
local bonuses = Config.Bonuses
local garage = Config.Return.enabled and Config.Return.coords or nil

-- Etapas de uma rota: as paragens e, se estiver ligada, a entrega na garagem.
-- Servem o cliente e o servidor, para os dois contarem a rota da mesma maneira.
function BusStageCount(route)
    return #route.stops + (Config.Return.enabled and 1 or 0)
end

function BusStageIsReturn(route, index)
    return Config.Return.enabled and index == #route.stops + 1
end

-- 'pickup' sobem passageiros | 'dropoff' descem alguns
-- 'destination' última paragem, descem todos | 'return' entrega na garagem
function BusStageKind(route, index)
    if BusStageIsReturn(route, index) then
        return 'return'
    end
    if index == #route.stops then
        return 'destination'
    end
    return #route.stops[index].npc_positions > 0 and 'pickup' or 'dropoff'
end

function BusStageCoord(route, index)
    if BusStageIsReturn(route, index) then
        return Config.Return.coords
    end
    local stop = route.stops[index]
    return stop and stop.stop_coord
end

function BusStageRadius(route, index)
    if BusStageIsReturn(route, index) then
        return Config.Return.radius
    end
    return Config.StopRadius
end

for index, route in ipairs(Config.Routes) do
    local previous = vector3(depot.x, depot.y, depot.z)
    local length = 0.0
    local boarding = 0

    for _, stop in ipairs(route.stops) do
        length = length + #(stop.stop_coord - previous)
        previous = stop.stop_coord
        boarding = boarding + #stop.npc_positions
    end

    -- A volta à garagem faz parte da rota.
    if garage then
        length = length + #(garage - previous)
    end

    -- Quanto tempo leva uma paragem normal, com a conta que o cliente usa.
    local stopTime = math.min(Config.StopServiceTime, Config.StopServiceMin + 4 * Config.StopServicePer) / 1000

    route.id = index
    route.length = length * bonuses.routeFactor
    route.boarding = boarding
    route.parTime = math.floor(
        route.length / bonuses.parSpeed
        + #route.stops * stopTime
        + bonuses.parPadding
    )
end
