--[[
Replay implementation
--]]

local utils = require("code/utils")

local Recorder = {}

-- Recorder class
function Recorder:new(params)
  local o = { -- TODO delete?
    --finishedPlayback = false,
    --finishedRecording = false,
  }
  
  setmetatable(o, self)
  self.__index = self
  
  if params.name then 
    o:setName(params.name)
  end
	
	self.rngLogMethod = params.rngLogMethod
	
	self.RECORDER_STATES = {NONE = 0, RECORD = 1, PLAYBACK = 2}
	
	self.mode = "none"
	
	-- https://stackoverflow.com/questions/2613734/maximum-packet-size-for-a-tcp-connection | size of GameCommand struct
	self.MAX_PACKET_SIZE = 65535 -- 1272
	self.commandDataAddress = core.allocate(self.MAX_PACKET_SIZE, true)
	
	self.nextUpCommandTimeAddress = core.allocate(4)
	
	self.commandRecorderState = core.allocate(4)
	core.writeInteger(self.commandRecorderState, 0)
	
	self.rngRecorderState = core.allocate(4)
	core.writeInteger(self.rngRecorderState, 0)

	self.infoRecorderState = core.allocate(4)
	core.writeInteger(self.infoRecorderState, 0)
	
	self.cachedRNG = nil
  
  return o
end

function Recorder:setName(name)
  self.name = name
  self.commandsFileName = self.name .. "-commands.json"
  self.rngFileName = self.name .. "-rng-sync.json"
  self.infoFileName = self.name .. "-infself.json"
end

function Recorder:reset() 
  self.mode = "none"
  core.writeInteger(self.nextUpCommandTimeAddress, 0)
  -- Set SEC_CurrentPlayerSlotID back to 1
	print("reset recorder state")
	core.writeInteger(0x01a275dc, 1) -- TODO test if this is needed for multiplayer

  core.writeInteger(self.commandRecorderState, self.RECORDER_STATES.NONE)
  core.writeInteger(self.rngRecorderState, self.RECORDER_STATES.NONE)
  core.writeInteger(self.infoRecorderState, self.RECORDER_STATES.NONE)
  
  self.commandsFile:close()
  self.rngFile:close()
  self.infoFile:close()
end

function Recorder:startRecording()
  self.mode = "record"
  if io.open(self.commandsFileName, "r") then
    error("Cannot overwrite existing recording: " .. self.commandsFileName)
  end
  if io.open(self.rngFileName, "r") then
    error("Cannot overwrite existing recording: " .. self.rngFileName)
  end
  if io.open(self.infoFileName, "r") then
    error("Cannot overwrite existing recording: " .. self.infoFileName)
  end
  self.commandsFile = io.open(self.commandsFileName, "w")
  self.rngFile = io.open(self.rngFileName, "w")
  self.infoFile = io.open(self.infoFileName, "w")
  
  core.writeInteger(self.commandRecorderState, self.RECORDER_STATES.RECORD)
  core.writeInteger(self.rngRecorderState, self.RECORDER_STATES.RECORD)
  core.writeInteger(self.infoRecorderState, self.RECORDER_STATES.RECORD)
end

function Recorder:stopRecording()
  self:reset()
end

function Recorder:startPlayback()
	self.mode = "play"
  -- Makes sure no valid commands during playback from player input
  core.writeInteger(0x191de0c, -1) -- TODO move this somewhere in lobby setup

  if not io.open(self.commandsFileName, "r") then
    error("Cannot find recording: " .. self.commandsFileName)
  end
  if not io.open(self.rngFileName, "r") then
    error("Cannot find recording: " .. self.rngFileName)
  end
  if not io.open(self.infoFileName, "r") then
    error("Cannot find recording: " .. self.infoFileName)
  end
  self.commandsFile = io.open(self.commandsFileName, "r")
  self.rngFile = io.open(self.rngFileName, "r")
  self.infoFile = io.open(self.infoFileName, "r")
  
  core.writeInteger(self.commandRecorderState, self.RECORDER_STATES.PLAYBACK)
  core.writeInteger(self.rngRecorderState, self.RECORDER_STATES.PLAYBACK)
  core.writeInteger(self.infoRecorderState, self.RECORDER_STATES.PLAYBACK)
end

function Recorder:stopPlayback()
  self:reset()
end

function Recorder:discardFiles()
	os.remove(self.commandsFileName)
	os.remove(self.rngFileName)
	os.remove(self.infoFileName)
end

function Recorder:saveCommand(commandCategory, time, address, size, player)
  local data = json:encode({
    commandCategory = commandCategory,
    time = time,
    data = utils.tableToHex(core.readBytes(address, size)),
    size = size,
    player = player,
  })
  self.commandsFile:write(data .. "\n")
  self.commandsFile:flush()
end

function Recorder:loadCommand()
  local data = self.commandsFile:read() -- reads a line 
  if data == nil then
    return nil
  end
  return json:decode(data) -- note that data is returned, not an address to data
end

function Recorder:saveRNG(time, index1, rng1, index2, rng2, extra)
  local data = json:encode({
    time = time,
    index1 = index1,
    rng1 = rng1,
    index2 = index2,
    rng2 = rng2,
    extra = extra,
  })
  self.rngFile:write(data .. "\n")
  self.rngFile:flush()  
end

function Recorder:loadRNG()
  local data = self.rngFile:read()
  if data == nil then
    return nil
  end
  return json:decode(data)
end

function Recorder:saveInfo(gameType, mapSeed, matchSeed, RNGvalue1, RNGvalue2, RNGindex1, RNGindex2) -- Saves RNG starting values to replicate game later
  local data = json:encode({
    gameType = gameType,
	mapSeed = mapSeed,
	matchSeed = matchSeed,
	RNGvalue1 = RNGvalue1,
	RNGvalue2 = RNGvalue2,
	RNGindex1 = RNGindex1,
	RNGindex2 = RNGindex2,
  })
  self.infoFile:write(data .. "\n")
  self.infoFile:flush()    
end

function Recorder:loadInfo()
  local data = self.infoFile:read()
  if data == nil then
    return nil
  end
  self.info = json:decode(data) -- store in this object I suppose. It is state
  return self.info
end

function Recorder:ScheduleCommandWrapper(commandCategory, player, time, address) 
  self._scheduleCommand(0x191d768, commandCategory, player, time, address)
end 

function Recorder:scheduleCommand(command) -- TODO test
  if command.size > self.MAX_PACKET_SIZE then
    print("Not enough memory for data")
    error("EXCEEDED MAX PACKET SIZE");
  end
  
  core.writeBytes(self.commandDataAddress, utils.hexToTable(command.data))
  
  self:ScheduleCommandWrapper(command.commandCategory, command.player, command.time, self.commandDataAddress)
  
end

function Recorder:peekCommand()
  
  if self.nextCommand == nil then
    self.nextCommand = self:loadCommand()
  end
  
  if self.nextCommand == nil then
    -- We have reached the end of file: EOF
    core.writeInteger(self.commandRecorderState, self.RECORDER_STATES.NONE)
  end
  
  return self.nextCommand
end

function Recorder:peekCommandTime()
  local c = self:peekCommand()
  if c == nil then
    return nil
  end
  return c.time 
end

function Recorder:consumeSavedCommand()
  local c = self.nextCommand
  
  if c == nil then
    c = self:peekCommand()  
  end
  
  self.nextCommand = nil
  
  return c
end

-- 0x004428b5 SHC
function Recorder:onStartSkirmish(registers) -- SINGLEPLAYER ONLY (TODO make this work for multiplayer too)
	if core.readInteger(self.commandRecorderState) == self.RECORDER_STATES.RECORD then
		local gameRNG1index = core.readInteger(0x01a3160c)
		local gameRNG2index = core.readInteger(0x01a31608)
		local gameRNG1 = core.readSmallInteger(0x01a279c0)
		local gameRNG2 = core.readSmallInteger(0x01a279c2)
		local mapSeed = self.mapSeed
		local matchSeed = core.readInteger(0x01a279c4)
		
		self:saveInfo(0, mapSeed, matchSeed, gameRNG1, gameRNG2, gameRNG1index, gameRNG2index)
		
		print("Saved skirmish information:")
		print(string.format("Gametype=%d, mapSeed=%d, matchSeed=%d, gameRNG1=%d, gameRNG2=%d, gameRNG1index=%d, gameRNG2index=%d", 0, mapSeed, matchSeed, gameRNG1, gameRNG2, gameRNG1index, gameRNG2index))
		
	elseif core.readInteger(self.commandRecorderState) == self.RECORDER_STATES.PLAYBACK then
		local skirmishInfo = self:loadInfo()
		local populateRNG1040 = core.exposeCode(0x0046a760, 1, 1)
	
		-- Set SEC_CurrentPlayerSlotID to 0 (Disallows actions during playback) TODO move this
		print("recorder in Playback state")
		--core.writeInteger(0x01a275dc, 0)
		
		-- Load mapSeed and fill RNG table
		core.writeInteger(0x01a279c4, skirmishInfo.mapSeed)
		populateRNG1040(0x01a279c0);
		
		-- Load matchSeed (populateRNG1040() is called later in LaunchGame() after the map is setup)
		core.writeInteger(0x01a279c4, skirmishInfo.matchSeed)
		
		-- Load starting RNG values
		core.writeInteger(0x01a3160c, skirmishInfo.RNGindex1)
		core.writeInteger(0x01a31608, skirmishInfo.RNGindex2)
		core.writeSmallInteger(0x01a279c0, skirmishInfo.RNGvalue1)
		core.writeSmallInteger(0x01a279c2, skirmishInfo.RNGvalue2)
	
		print("Loaded skirmish information:")
		print(string.format("Gametype=%d, mapSeed=%d, matchSeed=%d, gameRNG1=%d, gameRNG2=%d, gameRNG1index=%d, gameRNG2index=%d", skirmishInfo.gameType, skirmishInfo.mapSeed, skirmishInfo.matchSeed, skirmishInfo.RNGvalue1, skirmishInfo.RNGvalue2, skirmishInfo.RNGindex1, skirmishInfo.RNGindex2))
		
  end
  return registers
end

-- 0x00442877 SHC
function Recorder:onBeforeSetMatchSeed(registers) -- SINGLEPLAYER ONLY (TODO make this work for multiplayer too)
  self.mapSeed = core.readInteger(0x01a279c4)
	local setTimeBasedSeed = core.exposeCode(0x0046a740, 1, 1)
	
  -- original code
  setTimeBasedSeed(0x01a279c0)
  return registers
end

-- 0x0042bf4c SHC
function Recorder:onCustomSkirmishGame(registers) -- SINGLEPLAYER ONLY (TODO test if playerIDs work fine in multiplayer)
  -- Make singleplayer skirmishes use real playerID for commands, not -1
  local DAT_QueuedCommandPlayer = 0x191de0c 
  core.writeInteger(DAT_QueuedCommandPlayer, 01) -- In Singleplayer multiplayerID is always 01
  return registers
end

function Recorder:scheduleNextCommand(registers)
  print("Consuming command")
  local c = self:consumeSavedCommand()
  if c == nil then
    print("... no command left")
    --self.finishedPlayback = true -- already done by peekCommand higher up in the call hierarchy
    core.writeInteger(self.commandRecorderState, self.RECORDER_STATES.NONE)
    return
  end
  
  print(string.format("Matchtime now: %d", core.readInteger(0x01fe7da8)))
  print(string.format("Scheduling the command: Command<type=%d,time=%d,address=%X,size=%d,multiplayerID=%d>", c.commandCategory, c.time, self.commandDataAddress, c.size, c.player))
  self:scheduleCommand(c)
  
  print("Peeking at the next command")
  local c = self:peekCommand()
  if c == nil then
    print("... no command left")
    --self.finishedPlayback = true -- already done by peekCommand higher up in the call hierarchy
    core.writeInteger(self.commandRecorderState, self.RECORDER_STATES.NONE)
    return
  end
  
  print(string.format("Setting next trigger time: %d", c.time))
  core.writeInteger(self.nextUpCommandTimeAddress, c.time)
end

function Recorder:onReceiveAllTransmittedCommandsASM(scheduleNextCommandAddress)
	-- Schedules saved commands if commandRecorderState is in PLAYBACK mode
	return { 
  core.AssemblyLambda([[
    startOfFunction:
      mov eax, [commandRecorderState]
      cmp eax, 2
      jne endOfFunction

    checkStarted:
      mov eax, dword [SEC_MatchTime]
      cmp eax, 0
      jle endOfFunction
    
    checkTime:
      add eax, 64
      mov edx, dword [nextUpCommandTimeAddress]
      cmp eax, edx
      jg takeCommand
      jmp endOfFunction

    takeCommand:
      call scheduleNextCommandAddress  
      jmp startOfFunction
      
    endOfFunction:
  ]], {
    commandRecorderState = self.commandRecorderState, 
    SEC_MatchTime = 0x01fe7da8, 
    nextUpCommandTimeAddress = self.nextUpCommandTimeAddress, 
    scheduleNextCommandAddress = scheduleNextCommandAddress,
  })
}
end

function Recorder:onCommand(commandCategory, time, address, size, player)
  if core.readInteger(self.commandRecorderState) == 1 and time > 0 then
    print(string.format("Recording Command<type=%d,time=%d,address=%X,size=%d,multiplayerID=%d>", commandCategory, time, address, size, player))
    self:saveCommand(commandCategory, time, address, size, player)
  end
end

 -- on sent commands
function Recorder:onTransmitCommand(registers)
  local commandCategory = core.readInteger(registers.ESP + 4)
  local time = core.readInteger(registers.ESP + 8)
  local address = core.readInteger(registers.ESP + 12)
  local size = core.readInteger(registers.ESP + 16)
  -- local idTo = core.readInteger(registers.ESP + 20)
  local player = core.readInteger(0x0191de0c)
  print(string.format("Transmitted Command<type=%d,time=%d,address=%X,size=%d,multiplayerID=%d>", commandCategory, time, address, size, player))
  
  self:onCommand(commandCategory, time, address, size, player)
end

-- on received commands
function Recorder:onScheduleCommand(registers)
  local commandCategory = core.readInteger(registers.ESP + 4 + 0x10)
  local player = core.readInteger(registers.ESP + 8 + 0x10)
  local time = core.readInteger(registers.ESP + 12 + 0x10)
  local address = core.readInteger(registers.ESP + 16 + 0x10)
  local size = core.readInteger(0x0194af98)
  print(string.format("Received Command<type=%d,time=%d,address=%X,size=%d,multiplayerID=%d>", commandCategory, time, address, size, player))  
  
  self:onCommand(commandCategory, time, address, size, player)
end

function Recorder:fakeMultiplayerIdentities(registers)
  if originalInMultiplayer then
    registers.EDX = 1 -- multiplayer
  else
    registers.EDX = core.readInteger(registers.ECX + 0x618) -- original game mode
  end
  return registers
end

function Recorder:syncCheck(registers, traceF)
  local gameTime = core.readInteger(0x01fe7da8)
  local gameRNG1 = core.readSmallInteger(0x01a279c0)
  local gameRNG2 = core.readSmallInteger(0x01a279c2)
  local gameRNG1index = core.readInteger(0x01a3160c)
  local gameRNG2index = core.readInteger(0x01a31608)
  
  if self.mode == "record" then
    
    if core.readInteger(self.rngRecorderState) ~= self.RECORDER_STATES.RECORD then
      return
    end

    -- print("Recording sync data: " .. string.format("%0.16X\t%0.16X\t%0.16X", gameTime, gameRNG1, gameRNG2))
    if self.rngLogMethod == "trace" then
      local returnAddress = core.readInteger(registers.ESP)
      local returnAddress1 = nil
      local returnAddress2 = nil
      if traceF == 1 then
        returnAddress1 = returnAddress
      end
      if traceF == 2 then
        returnAddress2 = returnAddress
      end
      self:saveRNG(gameTime, gameRNG1index, gameRNG1, gameRNG2index, gameRNG2, {ra1 = returnAddress1, ra2 = returnAddress2})
    else
      self:saveRNG(gameTime, gameRNG1index, gameRNG1, gameRNG2index, gameRNG2)
    end

  elseif self.mode == "play" then
    
    if core.readInteger(self.rngRecorderState) ~= self.RECORDER_STATES.PLAYBACK then
      return
    end
  
    if self.cachedRNG == nil then
      self.cachedRNG = self:loadRNG()
    end
    
    if self.cachedRNG == nil then
      print("No more sync data left")
      core.writeInteger(self.rngRecorderState, self.RECORDER_STATES.NONE)
      return
    end

    if gameTime > self.cachedRNG.time then
      while (self.cachedRNG ~= nil) and (gameTime > self.cachedRNG.time) do
        print("Game is ahead of rng info, skipping...")
        self.cachedRNG = self:loadRNG()
      end
    end
    
    if self.cachedRNG == nil then
      print("No more sync data left")
      core.writeInteger(self.rngRecorderState, self.RECORDER_STATES.NONE)
      return
    end
    
    if self.cachedRNG.time > gameTime then
      return
    end
    
    local data = self.cachedRNG
    self.cachedRNG = nil
    
    if data.time ~= gameTime then
      print("time mismatch between data: " .. tonumber(data.time) .. " and game: " .. tonumber(gameTime))
      return
    end
    
    -- print(string.format("SYNC data at (time, rng1, rng2): %d, %d, %d", data.time, data.rng1, data.rng2))
    
    local anyDesync = false
    
    if traceRNG1 then
      if data.rng1 ~= gameRNG1 then
        anyDesync = true
        print(string.format("DESYNC in RNG1: data = time %d, rng1 %d, rng2 %d; game = time %d, %d, %d", data.time, data.rng1, data.rng2, gameTime, gameRNG1, gameRNG2))
      end    
    end
    
    if traceRNG2 then
      if data.rng2 ~= gameRNG2 then
        anyDesync = true
        print(string.format("DESYNC in RNG2: data = time %d, rng1 %d, rng2 %d; game = time %d, %d, %d", data.time, data.rng1, data.rng2, gameTime, gameRNG1, gameRNG2))
      end
    end
    
    local returnAddress = 0

    if self.rngLogMethod == "trace" then
      returnAddress = core.readInteger(registers.ESP)
      local returnAddress1 = data.extra.ra1
      local returnAddress2 = data.extra.ra2
      
      -- print(returnAddress, returnAddress1, returnAddress2)
      
      if traceF == 1 then
        if returnAddress1 ~= nil then 
          if (returnAddress1 ~= returnAddress) then
            anyDesync = true
            print(string.format("DESYNC returnAddress1: data = time %d, ret %X; game = time %d, ret %X", data.time, returnAddress1, gameTime, returnAddress))
          end
        else
          anyDesync = true
          print(string.format("DESYNC returnAddress, expected 2 but got 1: data = time %d, ret2 %X; game = time %d, ret1 %X", data.time, returnAddress2, gameTime, returnAddress))
        end
      end
      
      
      if traceF == 2 then
        if returnAddress2 ~= nil then
          if (returnAddress2 ~= returnAddress) then
            anyDesync = true
            print(string.format("DESYNC returnAddress2: data = time %d, ret %X; game = time %d, ret %X", data.time, returnAddress2, gameTime, returnAddress))
          end
        else
          anyDesync = true
          print(string.format("DESYNC returnAddress, expected 1 but got 2: data = time %d, ret1 %X; game = time %d, ret2 %X", data.time, returnAddress1, gameTime, returnAddress))
        end
      end
    end
    
    if not anyDesync then
      --print(string.format("SYNCED: data = time %d, rng1 %d, rng2 %d; game = time %d, %d, %d", data.time, data.rng1, data.rng2, gameTime, gameRNG1, gameRNG2))
    else
      --print("<entering debug mode>")
      --debug.debug() -- TODO decide
    end

  end
end

return Recorder