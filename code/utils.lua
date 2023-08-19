
return {

	tableToHex = function(t)
		local r = ""
		for k, v in ipairs(t) do
			local h = string.format("%X", v)
			if h:len() == 1 then 
				h = "0" .. h 
			end
			r = r .. h
		end
		return r
	end,

	hexToTable = function(h)
		local r = {}
		if h:len() % 2 ~= 0 then
			error("invalid hex string, not of even size")
		end
		
		for i=1,h:len()-1,2 do --TODO: -1?
			table.insert(r, tonumber(h:sub(i, i + 1), 16))
		end
		
		return r
	end,

}