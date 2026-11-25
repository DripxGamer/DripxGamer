# gg_busjob_advanced v8.2

Emprego de motorista de autocarro para **Qbox**, **QBCore** e **ESX**, em **7 idiomas**.

- Terminal desenhado como **sinalética de transportes**: sem uma única fotografia. O que identifica
  cada rota é o número, o destino e o **traçado real da linha**, desenhado a partir das coordenadas
  das paragens
- **5 cores de painel** à escolha de cada jogador, e **7 idiomas** (pt, pt-br, en, es, fr, de, it)
- **Trabalhadores em serviço**, **rotas** (com bloqueio por nível) e **histórico**
- Painel do turno com **velocímetro em arco** (fica vermelho acima do limite de multa), próxima paragem e lista de paragens
- **Passageiros visíveis**: a porta da frente abre, formam bicha, entram a pé um de cada vez e
  só depois de estarem dentro é que se sentam no lugar deles. Saem pela mesma porta. Nunca são
  teletransportados, nunca ocupam o lugar do condutor nem o tiram de lá
- **Chave do autocarro** dada ao jogador ao começar (qbx, qb, qs, wasabi e Renewed já vêm tratados)
- Sistema de níveis e XP, conquistas, meta diária e classificação
- **Multas** por colisões e excesso de velocidade, medidas no servidor
- **Contagem decrescente** se saíres do autocarro a meio da rota
- Passageiros, avaliação por estrelas, gorjetas e sequência de rotas

## Instalação

1. Copia a pasta `gg_busjob_advanced` para `resources/`.
2. Garante que `ox_lib` e `oxmysql` arrancam **antes** deste recurso.
3. No `server.cfg`, depois do teu framework (`qbx_core`, `qb-core` ou `es_extended`):

```cfg
ensure ox_lib
ensure oxmysql
ensure qbx_core            # ou qb-core, ou es_extended
ensure gg_busjob_advanced
```

4. Opcional, ainda no `server.cfg`:

```cfg
setr gg_busjob_advanced:locale pt          # pt | pt-br | en | es | fr | de | it
setr gg_busjob_advanced:framework auto     # auto | qbx_core | qb-core | es_extended
setr gg_busjob_advanced:speedUnit kmh      # kmh | mph
```

Ao arrancar, a consola do servidor diz qual o framework que encontrou:

```
[gg_busjob_advanced] framework: es_extended
```

## O que mudou na v8.2 — o modo que nunca falha

`Config.Passengers.mode` escolhe como é que os passageiros entram:

| Modo | O que se vê | Risco |
| --- | --- | --- |
| **`'door'`** (por omissão) | Caminham até à porta e entram por ela. Na largada aparecem à porta e afastam-se a pé. | **Nenhum.** Nunca se pede ao jogo para sentar ninguém, por isso não há nada que ele possa teletransportar. |
| `'seated'` | Entram e **sentam-se nos bancos**, vêem-se pelas janelas. | Depende de o motor do GTA colaborar com a animação de entrada. É o modo que dava os teletransportes. |
| `'off'` | Sem passageiros à vista. A rota conta na mesma. | Nenhum. |

Se alguma vez vires alguém a saltar para dentro, é porque estás em `'seated'`. Põe `'door'` e o
problema desaparece por construção, não por afinação.

A bateria de testes do cliente corre agora **duas vezes, uma em cada modo**. No `'door'`
verifica-se que o `SetPedIntoVehicle` **não é chamado nem uma única vez**.

## O que mudou na v8.1

**Só entravam dois pela porta.** Dois erros meus, ambos na bicha:

1. **Quem ficava atrás nunca tinha vez.** A entrada só era pedida quando o passageiro
   estivesse a menos de 2,5 m da porta — mas os lugares da bicha ficavam a 0, 0,95, 1,9 e
   2,85 m. Do terceiro em diante nunca cumpriam a condição e esperavam os 12 segundos todos.
   Agora há uma **ordem de vez** explícita: o primeiro da bicha que ainda está à espera entra
   a seguir, esteja onde estiver. A distância deixou de decidir fosse o que fosse.
2. **A bicha não andava para a frente.** Cada um ficava parado no lugar onde começou, por isso
   o quarto tinha de percorrer 4 metros quando chegava a vez dele, e não chegava a tempo.
   Agora **a bicha avança**: à medida que os da frente entram, os de trás dão um passo em
   frente, como numa paragem a sério.

Além disso, cada passageiro tem agora um **tempo repartido** à porta
(`tempo que sobra ÷ quantos faltam`). Antes, um que se atrapalhasse podia ocupar a porta
18 segundos e deixar todos os outros de fora.

**O meu simulador não apanhou isto** porque os bonecos andavam instantaneamente. Agora andam
a uma velocidade a sério, e há um teste do pior caso da rota — **4 a sair e 4 a entrar na
mesma paragem** — que verifica que entram os quatro pela porta, nenhum sentado à força, e que
tudo cabe no tempo da paragem.

## O que mudou na v8

### ESX

O recurso passou a correr em **Qbox, QBCore e ESX**. Não tens de mudar nada: em `auto`
procura por esta ordem `qbx_core`, `qb-core`, `es_extended`, e escreve na consola qual
encontrou. Para forçar:

```cfg
setr gg_busjob_advanced:framework es_extended   # auto | qbx_core | qb-core | es_extended
```

No ESX o identificador do personagem é o `identifier` em vez do `citizenid`, o nome vem do
`xPlayer`, e o pagamento usa `addAccountMoney('bank')` ou `addMoney` conforme
`Config.PaymentAccount` for `bank` ou `cash`. O ESX também obtém o objeto de duas maneiras
diferentes consoante a versão: tentam-se as duas.

**Atenção:** o recurso usa `oxmysql`. Quase todos os servidores ESX já o têm; se estiveres em
`mysql-async`, acrescenta o `oxmysql` (podem correr lado a lado).

A simulação corre agora **a bateria toda duas vezes, uma em Qbox e outra em ESX**: rota
completa, pagamento, recusa do banco, fallback para dinheiro vivo e chaves.

### Idiomas

Já eram 7 e continuam: **pt, pt-br, en, es, fr, de, it**. O que mudou é que deixou de assumir
português: se não disseres nada, segue o idioma do ESX ou do QB (`esx:locale`, `qb_locale`) e
só depois inglês. Para escolher:

```cfg
setr gg_busjob_advanced:locale pt     # pt | pt-br | en | es | fr | de | it
```

Aceita maiúsculas e underscore (`PT_BR` também serve). Se faltar uma frase num idioma, cai
para inglês. Os textos estão todos em `config/locales.lua`.

### Passageiros: ninguém fica de fora e ninguém salta à vista

Já entravam pela porta, mas quando o motor do jogo não conseguia meter alguém lá dentro a
tempo, esse passageiro **desaparecia** — era isso que fazia faltarem passageiros. Agora, se a
entrada pela porta falhar e ainda houver lugar, ele **apaga-se um instante à porta e aparece
já sentado**. Não é um salto à vista: é um corte, como numa montagem. Só desaparece de vez se
o autocarro estiver mesmo cheio. Controla-se em `Config.Passengers.seatQuietly`.

## O que mudou na v7.3

1. **Passageiros que nem chegavam a andar.** Ficam parados num cenário
   (`WORLD_HUMAN_STAND_IMPATIENT`) com os eventos bloqueados, e nesse estado o
   `ClearPedTasks` é só um **pedido**: o cenário ignora-o. Por isso havia passageiros que
   nunca saíam do passeio e acabavam por desaparecer. Agora desbloqueiam-se os eventos e
   usa-se `ClearPedTasksImmediately`, que corta mesmo.
2. **A entrada só é pedida à porta.** Antes bastava estar a 4,5 m; agora são 2,5 m, por isso
   o jogo tem muito menos margem para decidir teletransportá-los.
3. **O script diz-te o que se passou.** Com `Config.Debug = true`, a consola do jogo (F8)
   escreve quando um passageiro não chega à porta, quando não consegue entrar, e **quando foi
   o próprio motor do jogo a metê-lo lá dentro à força** (com a distância a que estava).
   Se ainda acontecer, essas linhas dizem exatamente onde apertar.
4. **Chaves.** O `Config.GiveKeys` foi refeito: tenta `qbx_vehiclekeys` (as duas assinaturas,
   que mudaram entre versões), `qb-vehiclekeys`, `qs-vehiclekeys` (duas), `wasabi_carlock`,
   `Renewed-Vehiclekeys`, `MrNewbVehicleKeys` (duas), `t1ger_keys`, `vehicles_keys`,
   `okokGarage` e `cd_garage`. Escreve na consola do **servidor** qual é que pegou e, se
   nenhum pegar, **lista os recursos de chaves/garagem que tens a correr** para saberes o que
   falta acrescentar. Há agora também um `Config.GiveKeysClient` para os sistemas que só
   reagem do lado do cliente.
5. **Paragens com o tempo certo.** Como entram e saem um de cada vez, o tempo da paragem
   passou a contar com os dois: quem sai mais quem entra. Antes contava só um dos lados e o
   último a entrar era cortado pelo fim do tempo.

### Se a chave continuar a não aparecer

Põe `Config.Debug = true` (já vem ligado), começa um turno e olha para a consola do
**servidor**. Vais ver uma destas:

```
[gg_busjob_advanced] chaves do BUS01234 entregues por: qbx_vehiclekeys (GiveKeys(src, veh))
[gg_busjob_advanced] NENHUM sistema de chaves respondeu. Recursos de chaves/garagem a correr: xyz_keys
```

A segunda linha diz-te o nome do teu sistema. Acrescenta-o em `Config.GiveKeys`.

## O que mudou na v7.2

Três coisas, e as duas primeiras tinham a mesma raiz.

1. **Ninguém entra senão pela porta.** O que se pedia ao jogo era: "mete este
   passageiro naquele lugar lá atrás". Esse lugar corresponde a uma porta que o autocarro
   não tem, e o jogo resolve à maneira dele — teletransporta o ped para o banco. Era isso
   que vias. Agora **toda a gente entra pelo lugar da frente do lado do passeio**
   (`boardSeat`), que é o que o jogo liga à porta da frente, e só **depois de já estar
   dentro** é que muda para o lugar dela, o que da rua não se vê. Para sair faz-se o
   inverso: volta ao lugar da porta por dentro e só depois desce a pé.
   Para a paragem não demorar uma eternidade, caminham todos ao mesmo tempo e formam
   bicha junto à porta; **só a entrada em si é que é um de cada vez**.
2. **A mala já não abre.** Abriam-se as portas 1 e 3 e, se o modelo não as tivesse,
   todas de 1 a 5 — e no GTA a 4 é o capô e a 5 é a mala. Agora só abre o que estiver em
   `Config.Passengers.doors` (só a porta da frente, por omissão) e os índices 4 e 5 são
   recusados pelo código, mesmo que alguém os meta no config.
3. **Entregar o autocarro é entregar mesmo.** Na garagem o motorista sai sozinho e o
   autocarro desvanece-se e desaparece, em vez de ficares lá dentro à espera.

## O que mudou na v7.1

A **Frota** passou a mostrar os autocarros a sério: capturas dos três modelos do jogo, recortadas
do fundo, em `web/img/bus-coach.webp`, `bus-city.webp` e `bus-airport.webp` (65 KB ao todo).
Só os três modelos base é que têm foto; qualquer outro que acrescentes a `Config.Vehicles`
continua a ser desenhado em SVG, para não mostrares um autocarro que não é o teu.

## O que mudou na v7

1. **Entrega na garagem.** Depois da última paragem os passageiros saem todos, e aí falta levar o
   autocarro à garagem (`Config.Return`, em `vector3(465.9, -644.5, 27.42)`). **É lá que recebes**:
   a rota só fecha quando o autocarro estiver entregue. A garagem é a 9.ª etapa da rota, com marcador,
   blip e linha próprios.
2. **Passageiros a entrar em fila.** Entravam todos ao mesmo tempo pela mesma porta, tropeçavam uns
   nos outros e os que ficavam presos eram teletransportados para o lugar. Agora entram no máximo
   `boardAtOnce` de cada vez (2 por omissão), cada um tem `enterTimeout` para conseguir e uma segunda
   tentativa se a porta estiver bloqueada. **O teletransporte desapareceu**: quem o jogo não consegue
   sentar vai até à porta e desvanece-se (`warpFallback = false`). A saída também já não usa o salto
   instantâneo. A paragem dura o tempo que a gente precisar (mínimo + tempo por pessoa, até ao máximo).
3. **Um só traçado no mapa.** O jogo desenhava duas linhas por cima uma da outra, a roxa do ponto de
   destino e a amarela da rota, porque o recurso marcava as duas. Agora só fica a da rota.
4. **Painel novo, sem imagens.** As ilustrações 3D saíram todas (menos 1,2 MB no recurso). Em vez
   delas:
   - o **cartaz** passou a ser o letreiro de destino da linha escolhida mais o **traçado dela**,
     desenhado a partir das coordenadas reais das paragens, com a saída e a volta à garagem a tracejado;
   - cada **cartão de rota** tem o número num roundel, o destino e uma **faixa de paragens** como a
     que está por cima das portas do autocarro (cheio = recolha, vazado = largada, branco = destino,
     quadrado = garagem);
   - cada linha tem a **sua cor**, como numa rede de metro, em tons de mapa impresso que não competem
     com a cor do painel; os escalões do motorista passaram a ser uma progressão de aço a ouro;
   - os autocarros da **Frota** são desenhados em SVG, um perfil por tipo;
   - superfícies de chapa com cantos a direito e filetes finos, em vez de cartões com sombras.

## O que mudou na v6

**O problema:** na última paragem os passageiros saíam, o autocarro desaparecia e não recebias nada.

**Porque acontecia.** A paragem só era confirmada ao servidor *depois* de toda a animação dos
passageiros. E, no fim, se o pagamento falhasse (ou se o servidor não conseguisse ler o perfil
naquele instante), o código fazia `removeSession` sem margem: a sessão morria e o autocarro era
apagado no mesmo segundo, sem dinheiro, sem bilhete e sem mensagem que explicasse nada.
O vigia do servidor tinha o mesmo problema: bastavam 8 segundos a não encontrar o autocarro na
rede, ou uma leitura errada do lugar do condutor, para o turno falhar e o autocarro sumir.

**O que mudou:**

1. **A paragem é confirmada no servidor ANTES da animação.** Primeiro o servidor valida a posição,
   a velocidade e o lugar do condutor, marca a paragem e (no destino) paga. Só depois as portas
   abrem e os passageiros se mexem. Nada do que os passageiros façam — ou não consigam fazer —
   pode roubar a paragem nem o pagamento.
2. **O pagamento nunca se perde.** Tenta a API do objeto do jogador e o export do Qbox, três vezes
   em cada conta, e se o banco recusar paga em dinheiro vivo. Se ainda assim falhar, **o turno fica
   de pé**: ficas no destino com o autocarro e basta carregar outra vez em **E** para receber.
   Já não há forma de a rota acabar sem pagamento.
3. **O autocarro nunca desaparece contigo lá dentro.** No fim do turno as portas abrem, aparece o
   aviso para sair e ele só é recolhido depois de o lugar do condutor estar vazio
   (`Config.Finish`).
4. **O vigia do servidor deixou de dar falsos positivos.** O lugar do condutor é confirmado de duas
   maneiras diferentes, o autocarro é seguido mesmo se mudar de identificador de rede, e só desiste
   depois de 30 segundos sem o encontrar — e nunca enquanto estiveres dentro de um autocarro.
   Perder o autocarro por culpa da rede também já não te tira a sequência de rotas.
5. **Um erro de Lua no servidor já não deixa o cliente pendurado.** O pedido da paragem responde
   sempre, e o erro aparece na consola do servidor.
6. **Lugares a rodar.** Numa paragem de recolha também sai gente, e liberta-se exatamente o número
   de lugares que os novos precisam. Antes, a partir da 3ª paragem, os passageiros chegavam à
   porta e desvaneciam-se porque o autocarro já estava cheio.
7. **Paragens que nunca encravam.** Se o jogo não deixar um passageiro entrar ou sair, ele é
   resolvido no fim da paragem em vez de a deixar à espera até ao tempo máximo.
8. **`/busjobinfo`** escreve o estado do turno na consola do jogo (F8): rota, paragem, passageiros,
   lugares livres, se o autocarro existe e se estás ao volante. `Config.Debug` faz o mesmo no
   servidor, paragem a paragem e pagamento a pagamento.

Testado com uma simulação do servidor e do cliente (63 verificações): rota completa de ponta a
ponta, pagamento recusado, banco em baixo, erro de Lua a meio do pagamento, autocarro cheio e
passageiro encravado.

## O que mudou na v5.2

- **Chave do autocarro**: ao começar o turno o jogador recebe a chave (ver `Config.GiveKeys`).
- **Condutor protegido**: enquanto o turno decorre o condutor não pode ser arrancado do lugar, o autocarro fica destrancado para ele e os passageiros nunca usam o lugar -1.
- **Porta e entrada a pé**: a porta da frente abre, os passageiros caminham até ela e entram com `TaskEnterVehicle` (sem teletransporte). O teletransporte para o lugar só serve de último recurso, quando o jogo não os deixa entrar a tempo.
- **Saída a pé**: saem pela porta, afastam-se e só depois desvanecem.
- **Paragens mais rápidas**: terminam logo que todos entraram ou saíram (`Config.StopServiceMin` no mínimo, `Config.StopServiceTime` no máximo).
- **Imagens novas**: todas as ilustrações são agora renderizadas em 3D (Blender/Cycles), em vez das ilustrações planas da v5.

## Se vens da v2, v3, v4 ou v5.x

Não precisas de fazer nada. A tabela `gg_busjob_advanced_profiles` mantém-se e o recurso acrescenta sozinho o que falta. Na v4 cria também a tabela `gg_busjob_advanced_history` (uma linha por rota concluída). XP, rotas feitas, dinheiro ganho e meta diária ficam como estavam.

## Como se joga

- Vai ao terminal (blip no mapa) e carrega em **E** no motorista, ou usa `/busjob` perto dele.
- No terminal: **1 a 4** mudam de separador, **ESC** fecha. Em **Motorista** escolhes a cor do painel.
- Em **Trabalho** escolhes a rota (as bloqueadas mostram o nível que pedem), o autocarro e carregas em **Começar a trabalhar**.
- Pára dentro da zona da paragem (velocidade quase nula) e carrega em **E**. Carrega em **X** para cancelar o embarque.
- Cada rota tem três tipos de paragem, com cores e avisos diferentes:
  - **Recolha** (marcador e blip amarelos): os passageiros caminham até à porta da frente do lado do passeio e sentam-se.
  - **Largada** (verde): metade dos passageiros sai pela mesma porta e afasta-se a pé.
  - **Destino** (verde): a última paragem da rota. Saem todos. Se uma rota tiver passageiros
    configurados na última paragem, são ignorados.
  - **Garagem** (azul): a etapa final, no terminal. O pagamento é confirmado logo que carregas em
    **E** e o autocarro só é recolhido quando saíres dele.
- Depois do último embarque aparece o aviso "Todos a bordo".
- Os passageiros são locais: só o motorista os vê. Nas paragens de recolha sai gente para libertar
  lugares, por isso o autocarro mantém-se com gente lá dentro em vez de ficar cheio de fantasmas.
  Se mesmo assim não houver lugar, quem não cabe chega à porta e desvanece-se.
- Se saíres do autocarro, aparece uma contagem decrescente (45 s por defeito). Voltas a tempo e continua; se não voltares, o turno falha e a sequência volta a zero.
- `/buscancel` termina o turno. Terminar de propósito faz a sequência voltar a zero.
- `/busjobinfo` escreve o estado do turno na consola do jogo (F8). Serve para perceber o que se
  passou se algo correr mal.
- Se o pagamento falhar no destino (banco em baixo, framework a reiniciar), **não perdes nada**:
  a mensagem diz-te para carregar outra vez em **E** e o autocarro fica onde está.

## Multas

O servidor vigia o autocarro uma vez por segundo.

| Infração | Como é detetada | Multa (por defeito) |
| --- | --- | --- |
| Colisão | A carroçaria perde pelo menos 12 pontos de vida num segundo | $15 + $0,35 por ponto perdido, máximo $90, com 3 s de intervalo |
| Excesso de velocidade | Mais de 22 m/s (~80 km/h) durante 4 s seguidos | $35, com 15 s de intervalo |

As multas aparecem no painel durante a rota e no bilhete final. O total descontado nunca passa de `(1 - MinimumConditionMultiplier)` do pagamento base (35% por defeito), por isso um mau turno nunca fica a dever dinheiro. Para desligar tudo põe `Config.Penalties.enabled = false`.

## Pagamento

```
total = base + bónus de tempo + bónus de sequência + gorjetas - multas
```

- **Multas e danos**: o desconto é o maior entre as multas apanhadas e o desconto por estado do autocarro, até ao limite de 35%.
- **Bónus de tempo**: até +15% se terminares dentro do tempo de referência da rota (calculado a partir das distâncias reais). Perde-se por completo quando passas 60% desse tempo.
- **Sequência**: +2% por cada rota seguida, máximo +20%.
- **Avaliação** (1 a 5 estrelas): mistura estado do autocarro (65%) e tempo (35%). Com 5 estrelas ganhas +10% de XP.
- **Gorjetas**: por passageiro, a partir das 3 estrelas.

Está tudo em `Config.Bonuses` e `Config.Penalties` (`config/config.lua`). Para acertar a dificuldade do bónus de tempo mexe em `parSpeed`: um valor maior encurta o tempo de referência (bónus mais difícil), um valor menor alarga-o.

## Configuração

| Ficheiro | O que tem |
| --- | --- |
| `config/config.lua` | Idioma, conta de pagamento, teclas, raios, multas, contagem de saída, histórico, bónus, passageiros, classificação, aparência, conquistas, terminal, veículos, níveis, chaves do veículo |
| `config/routes.lua` | As rotas (paragens, posições dos passageiros, pagamento, nível) |
| `config/locales.lua` | Textos em pt, pt-br, en, es, fr, de e it |

Ajustes dos passageiros (`Config.Passengers`) e das paragens:

```lua
Config.StopServiceTime = 24000  -- ms máximos de uma paragem
Config.StopServiceMin  = 2500   -- ms mínimos
Config.StopServicePer  = 2400   -- ms por pessoa a entrar ou a sair

Config.Return = {               -- entrega do autocarro: é aqui que a rota fecha e se recebe
    enabled = true,
    coords  = vector3(465.9, -644.5, 27.42),
    radius  = 14.0,
}

Config.Passengers = {
    seated = true,              -- sentam-se no autocarro; false = desvanecem-se ao entrar
    alightAtPickup = 2,         -- quantos saem numa paragem de recolha (liberta lugares); 0 desliga
    seatWait = 3500,            -- ms à espera de um lugar livre antes de desistir e se desvanecer à porta
    boardSeat = 0,              -- lugar ligado à porta: é por aqui que todos entram e saem
    doors = { 1 },              -- portas que abrem. NUNCA 4 nem 5: são o capô e a mala
    queueSpacing = 0.85,        -- espaço (m) entre cada um na bicha à porta
    enterTimeout = 9000,        -- ms que o jogo tem para meter um passageiro dentro
    enterRetries = 1,           -- tentativas extra se a porta estiver bloqueada
    mode = 'door',              -- 'door' (seguro) | 'seated' (bonito) | 'off'
    seatQuietly = true,         -- só no 'seated': se a porta falhar, aparece sentado sem salto visível
    doorBone = 'door_pside_f',  -- osso da porta: é aí que se forma a bicha
    doorOffset = 1.0,           -- distância (m) à porta onde a bicha se encosta
    walkSpeed = 1.5,            -- 1.0 caminhar, 2.0 correr
    exitTimeout = 4500,         -- ms para os deixar sair antes de os tirar à força
    alightSpeed = 1.0,          -- velocidade a afastarem-se depois de saírem
    alightWalk = 7.0,           -- distância (m) que percorrem antes de desaparecerem
    alightLinger = 2000,        -- ms que ficam à vista depois de saírem
}
```

As cores dos marcadores estão em `Config.UI.markerColor` (recolha) e `Config.UI.dropoffColor` (largada e destino).

Blocos da v4 e v5:

```lua
Config.Penalties = { enabled, collision = {...}, speeding = {...} }
Config.ExitTimer = { enabled = true, seconds = 45 }
Config.Debug     = true                        -- escreve cada paragem e cada pagamento na consola do servidor
Config.Finish    = {                           -- fim do turno; o autocarro nunca desaparece contigo lá dentro
    leaveSeconds   = 45,                       -- tempo para sares antes de te tirar do lugar
    graceSeconds   = 15,                       -- mínimo que o autocarro fica no destino depois de pago
    hardCapSeconds = 180,                      -- limite absoluto antes de o servidor o apagar
}
Config.History   = { limit = 12, keep = 40 }   -- o que se mostra / o que se guarda
Config.UI.backdrop = 'game'                    -- 'game' vês o jogo por trás | 'scene' cenário noturno desenhado
Config.UI.theme    = 'amber'                   -- amber | emerald | azure | violet | rose
```

A cor que o jogador escolhe no terminal fica guardada no próprio jogo dele e tem prioridade sobre `Config.UI.theme`, que só serve de cor inicial.

`Config.GiveKeys` corre no servidor depois de o autocarro estar registado. Tenta `qbx_vehiclekeys`
(as duas assinaturas), `qb-vehiclekeys`, `qs-vehiclekeys` (duas), `wasabi_carlock`,
`Renewed-Vehiclekeys`, `MrNewbVehicleKeys` (duas), `t1ger_keys`, `vehicles_keys`, `okokGarage` e
`cd_garage`, e escreve na consola do servidor qual pegou. Se nenhum pegar, lista os recursos de
chaves/garagem que estão a correr, para saberes qual acrescentar com uma linha
`try('o_teu_recurso', 'o_que_faz', function() ... end)`. `Config.GiveKeysClient` faz o mesmo do
lado do cliente, para os sistemas que só reagem aí.

## Idiomas

`pt`, `pt-br`, `en`, `es`, `fr`, `de` e `it`. O código aceita maiúsculas e `_` (`PT_BR` também funciona). Se faltar uma chave num idioma, cai para inglês. Para acrescentar um idioma, copia um bloco `Locales.xx = { ... }` em `config/locales.lua`, traduz os valores (mantém os `%s`), acrescenta o código a `LANGS` no início de `web/js/app.js` (é o que define o formato dos números e das datas) e põe o código no convar.

## O aspeto do terminal

Tirando as três fotos dos autocarros na Frota, tudo o que se vê é desenhado em CSS e SVG a partir
dos dados da rota. Para mexer no aspeto:

| O quê | Onde |
| --- | --- |
| Cores das linhas (uma por rota) | `LINES` no início de `web/js/app.js` |
| Escalões do motorista (avatar, pódio) | `--l1` a `--l5` em `web/css/style.css` |
| Cor base do painel | `Config.UI.theme` (cada jogador escolhe a sua no terminal) |
| Chapa, filetes, cantos | `--plate`, `--edge`, `--r` em `:root` |
| Letreiro de destino | `.blind*` em `web/css/style.css` |
| Faixa de paragens dos cartões | `lineStrip()` em `web/js/app.js` e `.strip*` no CSS |
| Traçado da linha | `routeMap()` em `web/js/app.js` |
| Autocarros da Frota | fotos em `web/img/bus-*.webp` (`BUS_PHOTOS` em `web/js/app.js`); modelos sem foto são desenhados por `busArt()` |

As fontes **Barlow**, **Barlow Condensed** e **Doto** continuam em `web/fonts/`. O recurso passou de
cerca de 1,8 MB para 580 KB.

## Segurança

O servidor valida tudo o que importa: o token da sessão, o autocarro registado (rede, modelo e matrícula), a distância ao terminal, a distância e a velocidade em cada paragem, o tempo mínimo até à primeira paragem (20 s) e entre paragens (8 s). As multas e o tempo fora do autocarro também são medidos no servidor. O cliente só mostra e pede; nunca decide o pagamento.

## Ficheiros

```
fxmanifest.lua
shared.lua            tempo de referência, distância e passageiros de cada rota
server.lua            sessões, pagamento, multas, histórico, perfil, classificação
client/main.lua       fluxo da rota, marcadores, ligação à interface
client/passengers.lua passageiros locais
web/                  interface (HTML, CSS, JS, sem build)
web/fonts/            Barlow, Barlow Condensed e Doto
web/img/              os três autocarros do jogo, recortados (WebP com transparência)
```

## Créditos

Fontes **Barlow**, **Barlow Condensed** e **Doto**, sob a licença SIL Open Font License 1.1. Os textos
das licenças estão em `web/fonts/`. As imagens dos autocarros em `web/img/` são capturas do próprio
jogo, recortadas do fundo. Tudo o resto é desenhado pelo código.
