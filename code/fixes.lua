--[[
	Fixes which might be needed for stable recordings
	Test this
]]--

return {
	apply = function() 
		--- faulty randomness line? This one is called extra when loading from the load game menu
		-- dust clouds arising from removed keeps...
		core.writeCode(0x004fc4a3, {0x90, 0x90, 0x90, 0x90, 0x90})
		core.writeCode(0x004fc627, {core.AssemblyLambda([[sub esp, 48]], {})})

		--- Mother RNG fix, nopping out. Could also switch with RNG1 to keep the baby cry noise
		core.writeCode(0x005474a3, {0x90, 0x90, 0x90, 0x90, 0x90})

		-- removing all function calls to RNG1 that come from the music thread.
		core.writeCode(0x0047a8d5, {0x90, 0x90, 0x90, 0x90, 0x90})
		core.writeCode(0x0047a86b, {0x90, 0x90, 0x90, 0x90, 0x90})
		
		core.writeCode(0x0047c348, {0x90, 0x90, 0x90, 0x90, 0x90})

		--- Right click menu fixes (during pause):
		-- Do not process tick when game is paused and pull down terrain or flatten terrain is used
		core.writeCode(0x0045ceff, {0x90, 0x90})

		-- Do not increase match time when game is paused and flatten terrain is used
		core.writeCode(0x0045ce34, {0xEB, 0x46})

		-- Removing mothers and children (TODO test without this)
		core.writeCode(0x004582ed, {0xEB})
	end
}