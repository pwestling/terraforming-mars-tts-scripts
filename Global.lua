function getObjectUnsafe(guid)
  return getObjectFromGUID(guid)
end

function getObjectOrCrash(guid, message)
  local obj = getObjectFromGUID(guid)
  if (obj == nil) then
    error(message)
  end
  return obj
end

LOGGING = false

function log(message)
  if (LOGGING) then
    print(message)
  end
end

function timer(id, func, params, delay)
  Timer.destroy(id)
  Timer.create({
    identifier = id,
    function_name = func,
    parameters = params,
    delay = delay
  })
end

function detailedbutton(domino, label, fn, font_size)
  local button = {}
  button.width = 1300
  button.height = 600
  button.position = { 0, -0.2, 0 }
  button.rotation = { 180, 90, 0 }
  button.click_function = fn
  button.label = label
  button.font_size = font_size
  button.function_owner = nil
  domino.createButton(button)
  state.buttons[domino.getGUID()] = button
end

function button(domino, label, fn)
  detailedbutton(domino, label, fn, 180)
end

function removeButtons(obj)
  obj.clearButtons()
  state.buttons[obj.getGUID()] = nil
end


function setContainedItemDescription(guids, desc)
  for i, guid in pairs(guids) do
    local bag = getObjectUnsafe(guid)
    if (bag ~= nil) then
      local obj = bag.takeObject({})
      obj.setDescription(desc)
      bag.reset()
      bag.putObject(obj)
    end
  end
end

DECK_ZONE = '7ef4f3'
DISCARD_ZONE = '1bda10'

function closeTo(num, target, tolerance)
  return num > (target - tolerance) and num < (target + tolerance)
end

function findDeck()
  for k, o in pairs(getObjectOrCrash(DECK_ZONE, "Could not find deck zone").getObjects()) do
    if (o.tag == "Deck" and closeTo(o.getRotation().z, 180, 2)) then
      return o
    end
  end
  error("Could not find deck")
end

function discard(card)
  local pos = getObjectOrCrash(DISCARD_ZONE, "Could not find discard zone").getPosition()
  card.setPosition({ x = pos.x, y = pos.y + 4, z = pos.z })
end

BRONZE_CUBE_DESC = "1 Resource"
SILVER_CUBE_DESC = "5 Resources"
GOLD_CUBE_DESC = "10 Resources"

BRONZE_WIDTH = 0.51
SILVER_WIDTH = 0.6
GOLD_WIDTH = 0.8

default_state = {
  cloneable = {
    bronze = nil,
    silver = nil,
    gold = nil
  },
  draft_rotation = 1,
  drafting = false,
  buttons = {},
  playerDraftQueue = {}
}

state = {}

function toTheVoid(obj)
  log("Voiding " .. obj.getGUID())
  obj.setLock(true)
  obj.setPosition({ x = -100, y = -100, z = -100 })
  obj.setLock(true)
end

function setCloneableFromInfiniteBag(bagGuid, map, key)
  local bag = getObjectOrCrash(bagGuid, "No bag with guid " .. bagGuid ..
      " was found. Can't set cloneable for key " .. key)
  local obj = bag.takeObject({ position = { x = 20, y = 20, z = 20 } })
  toTheVoid(obj)
  map[key] = obj.getGUID()
end

function onLoad(saved_state)
  state = default_state
  setContainedItemDescription({ "86cbbf", "5e0b51", "41e877", "5746bb", "4318fd" }, BRONZE_CUBE_DESC)
  setContainedItemDescription({ "8d637b", "3f225f", "ab5d85", "64360b", "ee1c20" }, SILVER_CUBE_DESC)
  setContainedItemDescription({ "093df9", "8aa743", "a6a38b", "1e2bb6", "89d52c" }, GOLD_CUBE_DESC)
  setCloneableFromInfiniteBag("86cbbf", state.cloneable, "bronze")
  setCloneableFromInfiniteBag("8d637b", state.cloneable, "silver")
  setCloneableFromInfiniteBag("093df9", state.cloneable, "gold")

  draftStartButton(getObjectOrCrash('0e761d', "Could not find button base for draft rotation button"))
  findDeck().randomize()
end

function draftStartButton(domino)
  button(domino, "Start Draft", "startDraft")
end


function getHandForObject(obj, playerColor)
  local player = Player[playerColor]
  for i = 1, player.getHandCount() do
    for k, handObj in pairs(player.getHandObjects(i)) do
      if (handObj.getGUID() == obj.getGUID()) then
        return i
      end
    end
  end
  return 0
end

DRAFT_HAND_INDEX = 3
DEAL_HAND_INDEX = 1
REAL_HAND_INDEX = 2

PLAYER_ORDER = { "Red", "White", "Blue", "Green", "Yellow" }

function getNextPlayer(currPlayer, direction)
  local dir = 1
  if (direction == "Clockwise") then
    dir = -1
  end
  local hitCurrent = false
  local index = 0
  for i = 1, 20 do
    local p = PLAYER_ORDER[index + 1]
    if (not hitCurrent and p == currPlayer) then
      hitCurrent = true
    elseif (hitCurrent and Player[p].seated) then
      return p
    end
    index = (index + dir) % #PLAYER_ORDER
  end
  error("Could not find next player")
end

DRAFT_QUEUE_BAG = 'e51789'

function startDraft()
  if (not state.drafting) then
    local deck = findDeck()
    state.drafting = true
    state.draft_rotation = state.draft_rotation * -1
    if (state.draft_rotation == -1) then
      broadcastToAll("Drafting Clockwise", { 1, 1, 1 })
    else
      broadcastToAll("Drafting Counter-Clockwise", { 1, 1, 1 })
    end
    for k, player in pairs(PLAYER_ORDER) do
      if (Player[player].seated) then
        deck.deal(4, player, DEAL_HAND_INDEX)
      end
    end
  end
end

function forceDealToHand(playerColor, handIndex, card)
  local handTransform = Player[playerColor].getHandTransform(handIndex)
  local handRotation = handTransform.rotation
  local rot = { x = handRotation.x, y = (handRotation.y + 180) % 360, z = handRotation.z }
  card.setPosition(handTransform.position)
  card.setRotation(rot)
end

function dealFromQueue(playerColor, handIndex, guid)
  local queueBag = getObjectOrCrash(DRAFT_QUEUE_BAG, "Could not find draft queue bag")
  local handTransform = Player[playerColor].getHandTransform(handIndex)
  local handRotation = handTransform.rotation
  local rot = { x = handRotation.x, y = (handRotation.y + 180) % 360, z = handRotation.z }
  queueBag.takeObject({ guid = guid, position = handTransform.position, rotation = rot, smooth = false })
end

function draftCard(cardObject, playerColor)
  if (state.drafting) then
    local cardGuid = cardObject.getGUID()
    local otherCards = Player[playerColor].getHandObjects(DEAL_HAND_INDEX)
    local queueBag = getObjectOrCrash(DRAFT_QUEUE_BAG, "Could not find draft queue bag")

    local cardGuids = {}
    for k, card in pairs(otherCards) do
      if (card.getGUID() ~= cardObject.getGUID()) then
        table.insert(cardGuids, card.getGUID())
      end
    end
    for k, card in pairs(otherCards) do
      queueBag.putObject(card)
    end
    dealFromQueue(playerColor, DRAFT_HAND_INDEX, cardGuid)
    local nextPlayer = getNextPlayer(playerColor, state.draft_rotation)
    if (state.playerDraftQueue[nextPlayer] == nil) then
      state.playerDraftQueue[nextPlayer] = {}
    end
    if (#cardGuids > 0) then
      table.insert(state.playerDraftQueue[nextPlayer], cardGuids)
    end
    timer(playerColor .. "fetchDraftQueue", "fetchFromDraftQueue", { playerColor = playerColor }, 0.2)
  end
end

function draftIsOver()
  for k, queue in pairs(state.playerDraftQueue) do
    if (#queue > 0) then
      log("Draft is not over: draftQueue")
      return false
    end
  end
  for k, player in pairs(PLAYER_ORDER) do
    if (#Player[player].getHandObjects(DEAL_HAND_INDEX) > 0) then
      log("Draft is not over: cards in deal hand")
      return false
    end
  end
  log("Draft is over")
  state.drafting = false
  return true
end

function fetchFromDraftQueue(params)
  log("Fetching")

  if (state.playerDraftQueue[params.playerColor] ~= nil and #state.playerDraftQueue[params.playerColor] > 0) then
    log("Fetch from queue")
    local cards = table.remove(state.playerDraftQueue[params.playerColor], 1)
    for k, cardGuid in pairs(cards) do
      log("Dealing to deal hand: " .. cardGuid)
      dealFromQueue(params.playerColor, DEAL_HAND_INDEX, cardGuid)
    end
  elseif (not draftIsOver()) then
    timer(params.playerColor .. "fetchDraftQueue", "fetchFromDraftQueue", { playerColor = params.playerColor }, 0.2)
  end
end


function distance2D(point1, point2)
  local x = point1.x - point2.x
  local z = point1.z - point2.z
  return math.sqrt(x * x + z * z)
end


function onObjectDrop(player_color, dropped_object)

  --  local resources = {
  --    Steel = steelStart,
  --    Titanium = titanStart,
  --    Plants = plantStart,
  --    Power = powerStart,
  --    Heat = heatStart
  --  }
  --
  --  local zone = getObjectFromGUID('702251')
  --  local pos = zone.getPosition()
  --
  --  for k, obj in pairs(zone.getObjects()) do
  --    for production, startFunc in pairs(resources) do
  --      local locs = resourceGridLocations(startFunc(pos, 1, -1), 1, -1)
  --      for value, loc in pairs(locs) do
  --        if (distance2D(obj.getPosition(), loc) < 0.1) then
  --          print(player_color .. " produces " .. value .. " " .. production)
  --        end
  --      end
  --    end
  --  end
  --  print("-------")
end

function addVec(pos, x, y, z)
  return { x = pos.x + x, y = pos.y + y, z = pos.z + z }
end

function plantStart(zoneCenter, xdir, zdir)
  return addVec(zoneCenter, (xdir * -6), 0, (zdir * 1))
end


function creditStart(zoneCenter, xdir, zdir)
  return addVec(zoneCenter, (xdir * -4.6), 0, (zdir * -0.9))
end

function powerStart(zoneCenter, xdir, zdir)
  return addVec(zoneCenter, (xdir * -1.2), 0, (zdir * 1))
end

function heatStart(zoneCenter, xdir, zdir)
  return addVec(zoneCenter, (xdir * -1.2 + 4.5), 0, (zdir * 1))
end

function steelStart(zoneCenter, xdir, zdir)
  return addVec(zoneCenter, (xdir * (-1.2 + 0.9)), 0, (zdir * -1.4))
end

function titanStart(zoneCenter, xdir, zdir)
  return addVec(zoneCenter, (xdir * (-1.2 + 0.9 + 4.0)), 0, (zdir * -1.4))
end

function resourceGridLocations(start, xdir, zdir, neg)
  local width = 0.55
  local p = addVec(start, width * xdir, 0, 0)
  local result = { [0] = start }
  local startI = 0
  if (neg ~= nil and neg) then
    startI = -5
  end
  for i = startI, 9 do
    local index = i + 1
    if (i < 0) then
      index = i
    end
    result[index] =
    addVec(p, xdir * width * (i % 5), 0, math.floor(i / 5) * zdir * width)
  end

  return result
end




function makeCube(newCubeGUID, pos)
  local newCube = getObjectUnsafe(newCubeGUID).clone({})
  if (newCube ~= nil) then
    newCube.setPosition(pos)
    newCube.setLock(false)
  end
end

function tradeCubes(cube, newCubeGUID, width, number)
  if (cube ~= nil and getObjectUnsafe(newCubeGUID) ~= nil) then
    local pos = cube.getPosition();
    toTheVoid(cube)
    local adjust = (width * number) / 2
    for i = 1, number do
      makeCube(newCubeGUID, { x = pos.x - adjust + (i * width), y = pos.y + width + 0.2, z = pos.z })
    end
  else
    error("Unable to trade cubes - either cube was null, or cloneable for guid " .. newCubeGUID .. " does not exist")
  end
end

function is1(obj)
  return obj.getDescription() == BRONZE_CUBE_DESC
end

function is5(obj)
  return obj.getDescription() == SILVER_CUBE_DESC
end

function is10(obj)
  return obj.getDescription() == GOLD_CUBE_DESC
end

function isResource(obj)
  return is1(obj) or is5(obj) or is10(obj)
end

function makeChange(obj, playerColor)
  if (obj.getPosition().y < 20) then
    if (is5(obj)) then
      tradeCubes(obj, state.cloneable.bronze, 0.51, 5)
      return
    end
    if (is10(obj)) then
      tradeCubes(obj, state.cloneable.silver, 0.7, 2)
      return
    end
  end
end

function consolidate(params)
  local total = 0
  local selected = Player[params.playerColor].getSelectedObjects();
  local mostNegX = 9999
  local y = 0
  local z = 0
  for k, obj in pairs(selected) do
    if (obj.getPosition().y < 20) then
      if (is1(obj)) then
        total = total + 1;
        mostNegX = math.min(mostNegX, obj.getPosition().x);
        y = obj.getPosition().y
        z = obj.getPosition().z
        obj.destruct()
      end
      if (is5(obj)) then
        total = total + 5;
        mostNegX = math.min(mostNegX, obj.getPosition().x);
        y = obj.getPosition().y
        z = obj.getPosition().z
        obj.destruct()
      end
      if (is10(obj)) then
        total = total + 10;
        mostNegX = math.min(mostNegX, obj.getPosition().x);
        y = obj.getPosition().y
        z = obj.getPosition().z
        obj.destruct()
      end
    end
  end
  local num10s = math.floor(total / 10);
  total = total - (10 * num10s)
  local num5s = math.floor(total / 5)
  total = total - (5 * num5s)
  local num1s = total
  local x = mostNegX
  if (num10s > 0) then
    for i = 1, num10s do
      makeCube(state.cloneable.gold, { x = x, y = y, z = z })
      x = x + GOLD_WIDTH
    end
  end
  if (num5s > 0) then
    for i = 1, num5s do
      makeCube(state.cloneable.silver, { x = x, y = y, z = z })
      x = x + SILVER_WIDTH
    end
  end
  if (num1s > 0) then
    for i = 1, num1s do
      makeCube(state.cloneable.bronze, { x = x, y = y, z = z })
      x = x + BRONZE_WIDTH
    end
  end
end

function onObjectRandomize(obj, playerColor)
  local hand = getHandForObject(obj, playerColor)
  if (isResource(obj)) then
    if (#Player[playerColor].getSelectedObjects() > 1) then
      local id = "consolidate " .. playerColor
      Timer.destroy(id)
      Timer.create({
        identifier = id,
        function_name = 'consolidate',
        parameters = {
          playerColor = playerColor
        },
        delay = 0.1
      })
    else
      makeChange(obj, playerColor)
    end
  end
  if (state.drafting == true and obj.tag == "Card" and hand == DEAL_HAND_INDEX) then
    draftCard(obj, playerColor)
  end
  if (state.drafting == false and obj.tag == "Card" and hand > 0) then
    if (closeTo(obj.getRotation().z, 180, 2)) then
      discard(obj)
    else
      forceDealToHand(playerColor, REAL_HAND_INDEX, obj)
    end
  end
end

GREEN_CARD_DIST = 0.75
BLUE_CARD_DIST = 1.7


function DIV(a, b)
  return (a - a % b) / b
end

function ROUNDDOWN(a, b)
  return DIV(a, b) * b
end


function organizeHeldCards(playerColor, separationDistance)
  local player = Player[playerColor]
  local selected = player.getSelectedObjects()
  local cardRot = 0;
  for i, obj in pairs(selected) do
    if (obj.name ~= "Card") then
      broadcastToColor(playerColor, "Can't organize non-card objects.")
    end
    cardRot = obj.getRotation().y
  end

  local start = player.getPointerPosition()
  local rotation = player.getPointerRotation();

  log("Card Y rotation is :" .. cardRot)
  local targetYRotation = ROUNDDOWN(cardRot + 45, 90) % 360
  log("Targetted Y rotation is :" .. targetYRotation)
  local translation = { x = 1, y = 0.2, z = 0 }

  if (closeTo(targetYRotation, 180, 1)) then
    translation = { x = 0, y = 0.2, z = -1 * separationDistance }
  elseif (closeTo(targetYRotation, 270, 1)) then
    translation = { x = -1 * separationDistance, y = 0.2, z = 1 }
  elseif (closeTo(targetYRotation, 0, 1) or closeTo(targetYRotation, 360, 1)) then
    translation = { x = 0, y = 0.2, z = 1 * separationDistance }
  elseif (closeTo(targetYRotation, 90, 1)) then
    translation = { x = 1 * separationDistance, y = 0.2, z = 0 }
  end


  for i, obj in pairs(selected) do
    obj.setRotation({ x = 0, y = targetYRotation, z = 0 })
    obj.setPosition(start)
    start = { x = start.x + translation.x, y = start.y + translation.y, z = start.z + translation.z }
  end
end


function onScriptingButtonDown(button_number, playerColor)
  if (button_number == 1) then
    organizeHeldCards(playerColor, GREEN_CARD_DIST)
  end
  if (button_number == 2) then
    organizeHeldCards(playerColor, BLUE_CARD_DIST)
  end
end
