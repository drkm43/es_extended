Citizen.CreateThread(function()
	SetMapName('San Andreas')
	SetGameType('ESX Roleplay')
end)

local awaitingRegistration = {}
RegisterNetEvent('esx:onPlayerJoined')
if Config.Multichar then
	AddEventHandler('esx_identity:completedRegistration', function(playerId, data)
		awaitingRegistration[playerId] = data
	end)
	AddEventHandler('esx:onPlayerJoined', function(src, char, isNew)
		if not ESX.Players[src] then
			onPlayerJoined(src, char, isNew)
		end
	end)
else
	AddEventHandler('esx:onPlayerJoined', function()
		if not ESX.Players[source] then
			onPlayerJoined(source)
		end
	end)
end

function onPlayerJoined(playerId, char, isNew)
	local identifier = ESX.GetIdentifier(playerId)
	if char then identifier = 'char'..char..':'..identifier end

	if identifier then
		if ESX.GetPlayerFromIdentifier(identifier) then
			DropPlayer(playerId, ('there was an error loading your character!\nError code: identifier-active-ingame\n\nThis error is caused by a player on this server who has the same identifier as you have. Make sure you are not playing on the same Rockstar account.\n\nYour Rockstar identifier: %s'):format(identifier))
		elseif Config.Multichar and isNew then
			createESXPlayer(identifier, playerId)
		else
			MySQL.Async.fetchScalar('SELECT 1 FROM users WHERE identifier = @identifier', {
				['@identifier'] = identifier
			}, function(result)
				if result then
					loadESXPlayer(identifier, playerId, false)
				else createESXPlayer(identifier, playerId) end
			end)
		end
	else
		DropPlayer(playerId, 'there was an error loading your character!\nError code: identifier-missing-ingame\n\nThe cause of this error is not known, your identifier could not be found. Please come back later or report this problem to the server administration team.')
	end
end

function createESXPlayer(identifier, playerId)
	local accounts = {}

	for account,money in pairs(Config.StartingAccountMoney) do
		accounts[account] = money
	end

	if IsPlayerAceAllowed(playerId, "command") then
		print(('^2[INFO] ^0 Player ^5%s ^0Has been granted admin permissions via ^5Ace Perms.^7'):format(playerId))
		defaultGroup = "admin"
	else
		defaultGroup = "user"
	end

	if not Config.Multichar then
		MySQL.Async.execute('INSERT INTO users (`accounts`, `identifier`, `group`) VALUES (@accounts, @identifier, @group)', {
			['@accounts'] = json.encode(accounts),
			['@identifier'] = identifier,
			['@group'] = defaultGroup
		}, function(rowsChanged)
			loadESXPlayer(identifier, playerId, true)
		end)
	else
		local data
		awaitingRegistration[playerId] = true
		while true do
			Citizen.Wait(250)
			if awaitingRegistration[playerId] ~= true then data = awaitingRegistration[playerId] break end
		end
		awaitingRegistration[playerId] = nil
		MySQL.Async.execute('INSERT INTO users (`accounts`, `identifier`, `group`, `firstname`, `lastname`, `dateofbirth`, `sex`, `height`) VALUES (@accounts, @identifier, @group, @firstname, @lastname, @dateofbirth, @sex, @height)', {
			['@accounts'] = json.encode(accounts),
			['@identifier'] = identifier,
			['@group'] = defaultGroup,
			['@firstname'] = data.firstname,
			['@lastname'] = data.lastname,
			['@dateofbirth'] = data.dateofbirth,
			['@sex'] = data.sex,
			['@height'] = data.height,
		}, function(rowsChanged)
			loadESXPlayer(identifier, playerId, true)
		end)
	end
end

AddEventHandler('playerConnecting', function(name, setCallback, deferrals)
	deferrals.defer()
	local playerId = source
	local identifier = ESX.GetIdentifier(playerId)
	Citizen.Wait(100)

	if identifier then
		if ESX.GetPlayerFromIdentifier(identifier) then
			deferrals.done(('There was an error loading your character!\nError code: identifier-active\n\nThis error is caused by a player on this server who has the same identifier as you have. Make sure you are not playing on the same account.\n\nYour identifier: %s'):format(identifier))
		else
			deferrals.done()
		end
	else
		deferrals.done('There was an error loading your character!\nError code: identifier-missing\n\nThe cause of this error is not known, your identifier could not be found. Please come back later or report this problem to the server administration team.')
	end
end)

function loadESXPlayer(identifier, playerId, isNew)
	local tasks = {}

	local userData = {
		accounts = {},
		inventory = {},
		job = {},
		playerName = GetPlayerName(playerId),
	}

	table.insert(tasks, function(cb)
		local query
		if Config.Multichar then
			query = 'SELECT `accounts`, `job`, `job_grade`, `group`, `position`, `inventory`, `skin`, `firstname`, `lastname`, `dateofbirth`, `sex`, `height` FROM `users` WHERE identifier = @identifier'
		else
			query = 'SELECT `accounts`, `job`, `job_grade`, `group`, `position`, `inventory`, `skin` FROM `users` WHERE identifier = @identifier'
		end
		MySQL.Async.fetchAll(query, {
			['@identifier'] = identifier
		}, function(result)
			local job, grade, jobObject, gradeObject = result[1].job, tostring(result[1].job_grade)
			local foundAccounts, foundItems = {}, {}

			-- Accounts
			if result[1].accounts and result[1].accounts ~= '' then
				local accounts = json.decode(result[1].accounts)

				for account,money in pairs(accounts) do
					foundAccounts[account] = money
				end
			end

			for account,label in pairs(Config.Accounts) do
				table.insert(userData.accounts, {
					name = account,
					money = foundAccounts[account] or Config.StartingAccountMoney[account] or 0,
					label = label
				})
			end

			-- Job
			if ESX.DoesJobExist(job, grade) then
				jobObject, gradeObject = ESX.Jobs[job], ESX.Jobs[job].grades[grade]
			else
				print(('[^3WARNING^7] Ignoring invalid job for %s [job: %s, grade: %s]'):format(identifier, job, grade))
				job, grade = 'unemployed', '0'
				jobObject, gradeObject = ESX.Jobs[job], ESX.Jobs[job].grades[grade]
			end

			userData.job.id = jobObject.id
			userData.job.name = jobObject.name
			userData.job.label = jobObject.label

			userData.job.grade = tonumber(grade)
			userData.job.grade_name = gradeObject.name
			userData.job.grade_label = gradeObject.label
			userData.job.grade_salary = gradeObject.salary

			userData.job.skin_male = {}
			userData.job.skin_female = {}

			if gradeObject.skin_male then userData.job.skin_male = json.decode(gradeObject.skin_male) end
			if gradeObject.skin_female then userData.job.skin_female = json.decode(gradeObject.skin_female) end

          	-- Inventory
          	if result[1].inventory and result[1].inventory ~= '' then
				userData.inventory = json.decode(result[1].inventory)
			end

			-- Group
			if result[1].group then
				userData.group = result[1].group
			else
				userData.group = 'user'
			end

			-- Position
			if result[1].position and result[1].position ~= '' then
				userData.coords = json.decode(result[1].position)
			else userData.coords = {x = -269.4, y = -955.3, z = 31.2, heading = 205.8} end

			-- Skin
			if result[1].skin and result[1].skin ~= '' then
				userData.skin = json.decode(result[1].skin)
			else if userData.sex == 'f' then userData.skin = {sex=1} else userData.skin = {sex=0} end end

			-- Identity
			if Config.Multichar then
				if result[1].firstname and result[1].firstname ~= '' then
					userData.firstname = result[1].firstname
					userData.lastname = result[1].lastname
					userData.playerName = userData.firstname..' '..userData.lastname
					if result[1].dateofbirth then userData.dateofbirth = result[1].dateofbirth end
					if result[1].sex then userData.sex = result[1].sex end
					if result[1].height then userData.height = result[1].height end
				end
			end

			cb()
		end)
	end)

	Async.parallel(tasks, function(results)
		local xPlayer = CreateExtendedPlayer(playerId, identifier, userData.group, userData.accounts, userData.job, userData.playerName, userData.coords)
		ESX.Players[playerId] = xPlayer

		if Config.Multichar and userData.firstname then 
			xPlayer.set('firstName', userData.firstname)
			xPlayer.set('lastName', userData.lastname)
			if userData.dateofbirth then xPlayer.set('dateofbirth', userData.dateofbirth) end
			if userData.sex then xPlayer.set('sex', userData.sex) end
			if userData.height then xPlayer.set('height', userData.height) end
		end

		TriggerEvent('esx:playerLoaded', playerId, xPlayer, isNew)
		TriggerEvent('linden_inventory:setPlayerInventory', xPlayer, userData.inventory)

		xPlayer.triggerEvent('esx:playerLoaded', {
			accounts = xPlayer.getAccounts(),
			coords = xPlayer.getCoords(),
			identifier = xPlayer.getIdentifier(),
			inventory = xPlayer.getInventory(),
			job = xPlayer.getJob(),
			loadout = {},
			maxWeight = xPlayer.getMaxWeight(),
			money = xPlayer.getMoney(),
			skin = userData.skin
		}, isNew)

		xPlayer.triggerEvent('esx:registerSuggestions', ESX.RegisteredCommands)
		print(('[^2INFO^0] Player ^5"%s" ^0has connected to the server. ID: ^5%s^7'):format(xPlayer.getName(), playerId))
	end)
end

AddEventHandler('chatMessage', function(playerId, author, message)
	if message:sub(1, 1) == '/' and playerId > 0 then
		CancelEvent()
		local commandName = message:sub(1):gmatch("%w+")()
		TriggerClientEvent('chat:addMessage', playerId, {args = {'^1SYSTEM', _U('commanderror_invalidcommand', commandName)}})
	end
end)

AddEventHandler('playerDropped', function(reason)
	local playerId = source
	local xPlayer = ESX.GetPlayerFromId(playerId)

	if xPlayer then
		TriggerEvent('esx:playerDropped', playerId, reason)

		ESX.SavePlayer(xPlayer, function()
			ESX.Players[playerId] = nil
		end)
	end
end)

if Config.Multichar then
	AddEventHandler('esx:playerLogout', function(playerId)
		local xPlayer = ESX.GetPlayerFromId(playerId)
		awaitingRegistration[playerId] = nil
		if xPlayer then
			TriggerEvent('esx:playerDropped', playerId, reason)

			ESX.SavePlayer(xPlayer, function()
				ESX.Players[playerId] = nil
			end)
		end
		TriggerClientEvent("esx:onPlayerLogout", playerId)
	end)
end

RegisterNetEvent('esx:updateCoords')
AddEventHandler('esx:updateCoords', function(coords)
	local xPlayer = ESX.GetPlayerFromId(source)
	if xPlayer then
		if coords == nil then
			local ped = GetPlayerPed(source)
			coords = GetEntityCoords(ped)
		end
		xPlayer.updateCoords(coords)
	end
end)

RegisterNetEvent('esx:updateWeaponAmmo')
AddEventHandler('esx:updateWeaponAmmo', function(weaponName, ammoCount)
	--
end)

RegisterNetEvent('esx:giveInventoryItem')
AddEventHandler('esx:giveInventoryItem', function(target, type, itemName, itemCount)
	--
end)

RegisterNetEvent('esx:removeInventoryItem')
AddEventHandler('esx:removeInventoryItem', function(type, itemName, itemCount)
	--
end)

RegisterNetEvent('esx:useItem')
AddEventHandler('esx:useItem', function(itemName)
	--
end)

RegisterNetEvent('esx:onPickup')
AddEventHandler('esx:onPickup', function(pickupId)
	--
end)

ESX.RegisterServerCallback('esx:getPlayerData', function(source, cb)
	local xPlayer = ESX.GetPlayerFromId(source)

	cb({
		identifier   = xPlayer.identifier,
		accounts     = xPlayer.getAccounts(),
		inventory    = xPlayer.getInventory(),
		job          = xPlayer.getJob(),
		loadout      = {},
		money        = xPlayer.getMoney()
	})
end)

ESX.RegisterServerCallback('esx:getOtherPlayerData', function(source, cb, target)
	local xPlayer = ESX.GetPlayerFromId(target)

	cb({
		identifier   = xPlayer.identifier,
		accounts     = xPlayer.getAccounts(),
		inventory    = xPlayer.getInventory(),
		job          = xPlayer.getJob(),
		loadout      = {},
		money        = xPlayer.getMoney()
	})
end)

ESX.RegisterServerCallback('esx:getPlayerNames', function(source, cb, players)
	players[source] = nil

	for playerId,v in pairs(players) do
		local xPlayer = ESX.GetPlayerFromId(playerId)

		if xPlayer then
			players[playerId] = xPlayer.getName()
		else
			players[playerId] = nil
		end
	end

	cb(players)
end)

AddEventHandler('txAdmin:events:scheduledRestart', function(eventData)
  if eventData.secondsRemaining == 60 then
    Citizen.CreateThread(function()
      Citizen.Wait(40000)
      ESX.SavePlayers()
     end)
  end
end)

-- version check
Citizen.CreateThread(
	function()
		local vRaw = LoadResourceFile(GetCurrentResourceName(), 'version.json')
		if vRaw then
			local v = json.decode(vRaw)
			PerformHttpRequest(
				'https://raw.githubusercontent.com/esx-framework/es_extended/legacy/version.json',
				function(code, res, headers)
					if code == 200 then
						local rv = json.decode(res)
						if rv.version == v.version then
							if rv.commit ~= v.commit then 
							print(
								([[

^1----------------------------------------------------------------------
^1URGENT: YOUR ES_EXTENDED IS OUTDATED!
^1COMMIT UPDATE: ^5%s AVAILABLE
^1DOWNLOAD:^5 https://github.com/esx-framework/es_extended/tree/legacy
^1CHANGELOG:^5 %s
^1-----------------------------------------------------------------------
]]):format(
									rv.commit,
									rv.changelog
								)
							)
						else
							print(
								([[

^8-------------------------------------------------------
^2Your es_extended is the latest version!
^5Version:^0 %s
^5COMMIT:^0 %s
^5CHANGELOG:^0 %s
^8-------------------------------------------------------
]]):format(
								 	rv.version,
									rv.commit,
									rv.changelog
								)
							)
						end
					else
						print(
							([[
^1----------------------------------------------------------------------
^1URGENT: YOUR ES_EXTENDED IS OUTDATATED!!!
^1COMMIT UPDATE: ^5%s AVAILABLE
^1DOWNLOAD:^5 https://github.com/esx-framework/es_extended/tree/legacy
^1CHANGELOG:^5 %s
^1-----------------------------------------------------------------------
]]):format(
								rv.commit,
								rv.changelog
							)
						)
						end
					else
						print('[^1ERROR^0] es_extended unable to check version!')
					end
				end,
				'GET'
			)
		end
	end
)
