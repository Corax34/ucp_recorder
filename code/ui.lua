local menuItemSize = 0x50

local originalMenuItemArraySize = 0x1D10
local originalMenuItemArrayAddress = 0x005e9848

local newSize = originalMenuItemArraySize + 2 * menuItemSize -- 2 additional MenuItems
local newMenuItemArrayAddress = core.allocate(newSize, true)

local newItem1Address = newMenuItemArrayAddress + newSize - 3 * menuItemSize
local newItem2Address = newMenuItemArrayAddress + newSize - 2 * menuItemSize
local newTerminatorAddress = newMenuItemArrayAddress + newSize - 1 * menuItemSize

local placeRecordButton = function(recorder)
		-- init button
		
		local recordButtonCallback = function()
			if recorder.mode == "none" then
				recorder:startRecording()
				core.writeInteger(newItem1Address + 32, 0x40000239) -- buttonGraphic
				print("Starting new recording!")
			elseif recorder.mode == "record" then
				recorder:stopRecording()
				recorder:discardFiles()
				core.writeInteger(newItem1Address + 32, 0x4000023A) -- buttonGraphic
				print("discarded")
			end
		end
		
		core.writeInteger(newItem1Address + 0, 0x00000003) -- type
		core.writeInteger(newItem1Address + 4, 380) -- xPos
		core.writeInteger(newItem1Address + 8, 560) -- yPos
		core.writeInteger(newItem1Address + 12, 80) -- width
		core.writeInteger(newItem1Address + 16, 80) -- height
		core.writeInteger(newItem1Address + 20, utils.createLuaFunctionWrapper(recordButtonCallback)) -- 
		core.writeInteger(newItem1Address + 24, 2) -- callbackParam
		core.writeInteger(newItem1Address + 28, 0x0042AE90) -- renderFunc
		core.writeInteger(newItem1Address + 32, 0x4000023A) -- unkown | buttonGraphic 23A off 239 on
		core.writeInteger(newItem1Address + 36, 0x00000003) -- unknown
		core.writeInteger(newItem1Address + 40, 0x00000000) -- unknown
		core.writeInteger(newItem1Address + 44, 0x00000000) -- unknown
		core.writeInteger(newItem1Address + 48, 0x0000FFF0) -- unknown
		
		core.writeInteger(newItem1Address + 72, 0x00000045) -- unknown
end

local placePlaybackButton = function(recorder)
		-- init button
		
		local playbackButtonCallback = function()
			print("playback button")
			if recorder.mode == "none" then
				recorder:startPlayback()
				core.writeInteger(newItem2Address + 32, 0x40000239) -- buttonGraphic
				print("Starting new playback!")
			elseif recorder.mode == "play" then
				recorder:stopPlayback()
				core.writeInteger(newItem2Address + 32, 0x4000023A) -- buttonGraphic
				print("discarded playback")
			end
		end
		
		core.writeInteger(newItem2Address + 0, 0x00000003) -- type
		core.writeInteger(newItem2Address + 4, 290) -- xPos
		core.writeInteger(newItem2Address + 8, 560) -- yPos
		core.writeInteger(newItem2Address + 12, 80) -- width
		core.writeInteger(newItem2Address + 16, 80) -- height
		core.writeInteger(newItem2Address + 20, utils.createLuaFunctionWrapper(playbackButtonCallback)) -- 
		core.writeInteger(newItem2Address + 24, 2) -- callbackParam
		core.writeInteger(newItem2Address + 28, 0x0042AE90) -- renderFunc
		core.writeInteger(newItem2Address + 32, 0x4000023A) -- unkown | buttonGraphic 23A off 239 on
		core.writeInteger(newItem2Address + 36, 0x00000003) -- unknown
		core.writeInteger(newItem2Address + 40, 0x00000000) -- unknown
		core.writeInteger(newItem2Address + 44, 0x00000000) -- unknown
		core.writeInteger(newItem2Address + 48, 0x0000FFF0) -- unknown
		
		core.writeInteger(newItem2Address + 72, 0x00000045) -- unknown
end

return {
	createButtons = function(recorder)
				-- copy original ui array to new array
		core.copyMemory(newMenuItemArrayAddress, originalMenuItemArrayAddress, originalMenuItemArraySize)
		
		-- copy 0x66 terminator one element further back
		core.copyMemory(newTerminatorAddress, 
										newItem1Address, 
										menuItemSize)
		
		placeRecordButton(recorder)
		placePlaybackButton(recorder)
		
		-- overwrite reference
		core.writeCode(0x0059AB30, { core.AssemblyLambda([[
			push newMenuItemArrayAddress
		]], 
		{ newMenuItemArrayAddress = newMenuItemArrayAddress, }) })
		
	end,
	
	resetButtons = function()
		core.writeInteger(newItem1Address + 32, 0x4000023A) -- reset recording button graphic
		core.writeInteger(newItem2Address + 32, 0x4000023A) -- reset playback button graphic
	end,
}