local Base = {}

function Base:new(data)
	local o = data or {}
	-- Can do other setup here: argument checking, initialization, etc.

	-- Bind the new object to the Base class
	setmetatable(o, self)
	self.__index = self
	return o
end

return Base
