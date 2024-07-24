local this = {}

--- @param p ffiImagePixel
function this.pixel(p)
	return string.format("{ r = %s, g = %s, b = %s }", p.r, p.g, p.b)
end
--- @param c ffiHSV
function this.hsv(c)
	return string.format("{ h = %s, s = %s, v = %s }", c.h, c.s, c.v)
end

--- @param image Image
function this.imageData(image)
	local r = {}
	for y = 0, image.height - 1 do
		local offset = image:getOffset(y)
		for x = 1, image.width do
			table.insert(r, this.pixel(image.data[offset + x]))
		end
	end
	return "{" .. table.concat(r, "\n\t") .. "}"
end

return this
