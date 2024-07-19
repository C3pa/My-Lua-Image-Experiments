local Class = {}

function Class:new(data)
	local o = data or {}
	-- Can do other setup here: argument checking, initialization, etc.

	-- Bind the new object to the Class
	setmetatable(o, self)
	self.__index = self
	return o
end

--- @class ImagePixel
--- @field r integer
--- @field g integer
--- @field b integer

--- @class ImagePixelA : ImagePixel
--- @field a number [0, 1]

--- @alias ImageRow ImagePixelA[]
--- @alias ImageData ImageRow[]

--- An image helper class that stores RGBA color in premultiplied alpha format.
--- @class Image
--- @field width integer
--- @field height integer
--- @field data ImageData
local Image = Class:new()

--- @class Image.new.data
--- @field width integer
--- @field height integer
--- @field data ImageData?

--- @param data Image.new.data
--- @return Image
function Image:new(data)
	local t = Base:new(data)
	setmetatable(t, self)

	-- Hack for `saveBMP`
	data.width = 200
	data.height = 100


	if not t.data then
		t.data = {}
		for y = 1, t.height do
			local row = {}
			for x = 1, t.width do
				row[x] = { r = 0, g = 0, b = 0, a = 1 }
			end
			t.data[y] = row
		end
	end

	self.__index = self
	return t
end

--- @param x integer Horizontal coordinate
--- @param y integer Vertical coordinate
function Image:getPixel(x, y)
	return self.data[y][x]
end

--- @param x integer Horizontal coordinate
--- @param y integer Vertical coordinate
--- @param color ImagePixelA
function Image:setPixel(x, y, color)
	self.data[y][x] = color
end

--- @param data ImageData
function Image:fill(data)
	for y = 1, self.height do
		for x = 1, self.width do
			table.copy(data[y][x], self.data[y][x])
		end
	end
end

--- @param pixel ImagePixelA
local function premultiply(pixel)
	pixel.r = pixel.r * pixel.a
	pixel.g = pixel.g * pixel.a
	pixel.b = pixel.b * pixel.a
end

--- @param color ImagePixel|ImagePixelA
function Image:fillColor(color)
	color.a = color.a or 1
	premultiply(color)

	for y = 1, self.height do
		local row = self.data[y]
		for x = 1, self.width do
			table.copy(color, row[x])
		end
	end
end

--- @param rowIndex integer
--- @param color ImagePixel|ImagePixelA
function Image:fillRow(rowIndex, color)
	color.a = color.a or 1
	premultiply(color)

	local row = self.data[rowIndex]
	for x = 1, self.width do
		table.copy(color, row[x])
	end
end

--- @param columnIndex integer
--- @param color ImagePixel|ImagePixelA
function Image:fillColumn(columnIndex, color)
	color.a = color.a or 1
	premultiply(color)

	for y = 1, self.height do
		table.copy(color, self.data[y][columnIndex])
	end
end

local hueSection = {
	first = 1 / 6,
	second = 2 / 6,
	third = 3 / 6,
	fourth = 4 / 6,
	fifth = 5 / 6,
	sixth = 6 / 6,
}

--- Fills the image into a vertical hue bar.
--- The image must have height of 256
function Image:verticalHueBar()
	local color = { r = 255, g = 0, b = 0 }
	for y = 1, self.height do
		local t = y / self.height
		self:fillRow(y, color)

		if t < hueSection.first then
			color.g = math.lerp(0, 255, (t / hueSection.first))
		elseif t < hueSection.second then
			color.r = math.lerp(255, 0, ((t - hueSection.first) / hueSection.first))
		elseif t < hueSection.third then
			color.b = math.lerp(0, 255, ((t - hueSection.second) / hueSection.first))
		elseif t < hueSection.fourth then
			color.g = math.lerp(255, 0, ((t - hueSection.third) / hueSection.first))
		elseif t < hueSection.fifth then
			color.r = math.lerp(0, 255, ((t - hueSection.fourth) / hueSection.first))
		else
			color.b = math.lerp(255, 0, ((t - hueSection.fifth) / hueSection.first))
		end
	end
end

--- @param leftColor ImagePixel|ImagePixelA
--- @param rightColor ImagePixel|ImagePixelA
function Image:horizontalGradient(leftColor, rightColor)
	leftColor.a = leftColor.a or 1
	rightColor.a = rightColor.a or 1
	premultiply(leftColor)
	premultiply(rightColor)

	for x = 1, self.width do
		local t = x / self.width
		local color = {
			r = math.lerp(leftColor.r, rightColor.r, t),
			g = math.lerp(leftColor.g, rightColor.g, t),
			b = math.lerp(leftColor.b, rightColor.b, t),
			a = math.lerp(leftColor.a, rightColor.a, t),
		}
		self:fillColumn(x, color)
	end
end

--- @param topColor ImagePixel|ImagePixelA
--- @param bottomColor ImagePixel|ImagePixelA
function Image:verticalGradient(topColor, bottomColor)
	topColor.a = topColor.a or 1
	bottomColor.a = bottomColor.a or 1
	premultiply(topColor)
	premultiply(bottomColor)

	for y = 1, self.height do
		local t = y / self.height
		local color = {
			r = math.lerp(topColor.r, bottomColor.r, t),
			g = math.lerp(topColor.g, bottomColor.g, t),
			b = math.lerp(topColor.b, bottomColor.b, t),
			a = math.lerp(topColor.a, bottomColor.a, t),
		}
		self:fillRow(y, color)
	end
end

--- @param color ImagePixel|ImagePixelA
function Image:horizontalColorGradient(color)
	local leftColor = { r = 255, g = 255, b = 255 }
	self:horizontalGradient(leftColor, color)
end

function Image:verticalGrayGradient()
	local topColor = { r = 0, g = 0, b = 0, a = 1 }
	local bottomColor = { r = 0, g = 0, b = 0, a = 0 }
	self:verticalGradient(topColor, bottomColor)
end

function Image:copy()
	local new = Image:new({
		height = self.height,
		width = self.width,
		data = table.deepcopy(self.data)
	})

	return new
end

--- @alias ImageBlendType
---| "plus"
---| "dissolve"

--- @alias ImageBlendFunction fun(pixel1: ImagePixelA, pixel2: ImagePixelA, coeff: number): ImagePixelA

--- @type table<ImageBlendType, ImageBlendFunction>
local blend = {}

-- See 4.5 The PLUS	operator in:
-- https://graphics.pixar.com/library/Compositing/paper.pdf
function blend.plus(pixel1, pixel2, coeff)
	return {
		r = pixel1.r + pixel2.r,
		g = pixel1.g + pixel2.g,
		b = pixel1.b + pixel2.b,
		a = pixel1.a * pixel2.a
	}
end

-- See 4.5 The PLUS	operator in:
-- https://graphics.pixar.com/library/Compositing/paper.pdf
function blend.dissolve(pixel1, pixel2, coeff)
	local inverse = 1 - coeff
	pixel1 = {
		r = pixel1.r * coeff,
		g = pixel1.g * coeff,
		b = pixel1.b * coeff,
		a = pixel1.a * coeff,
	}
	pixel2 = {
		r = pixel1.r * inverse,
		g = pixel1.g * inverse,
		b = pixel1.b * inverse,
		a = pixel1.a * inverse,
	}
	return blend.plus(pixel1, pixel2, coeff)
end

--- @param image Image
--- @param coeff number [0, 1]
--- @param type ImageBlendType
function Image:blend(image, coeff, type)
	local sameWidth = self.width == image.width
	local sameHeight = self.height == image.height
	assert(sameWidth, "Images must be of same width.")
	assert(sameHeight, "Images must be of same height.")

	local new = self:copy()
	local blend = blend[type]

	for y = 1, new.height do
		local rowA = new.data[y]
		local rowB = image.data[y]
		for x = 1, new.width do
			local pixelA = rowA[x]
			local pixelB = rowB[x]
			rowA[x] = blend(pixelA, pixelB, coeff)
		end
	end
	return new
end

--- @param file file*
--- @param ... integer
local function writeBytes(file, ...)
	file:write(string.char(...))
end

--- @param filename string
function Image:saveBMP(filename)
	local file = io.open(filename, "wb")
	if not file then
		error(string.format("Can't open %q. Traceback:%s", filename, debug.traceback()))
	end
	-- These bytes are taken straight from a hex editor for a bmp file of 200x100
	do -- BitmapFileHeader
		-- char[] bfType = "BM"
		file:write("BM")
		-- u32 bfSize = 60054
		writeBytes(file, 0x96, 0xEA, 0x00, 0x00)
		-- u16 bfReserved1
		writeBytes(file, 0x00, 0x00)
		-- u16 bf Reserved2
		writeBytes(file, 0x00, 0x00)
		-- u32 brOffBits = 54
		writeBytes(file, 0x036, 0x00, 0x00, 0x00)
	end
	do -- BitmapInfoHeaderV1
		-- u32 biSize = 40
		writeBytes(file, 0x28, 0x00, 0x00, 0x00)
		-- s32 biWidth = 200
		writeBytes(file, 0xC8, 0x00, 0x00, 0x00)
		-- s32 biHeight = 100
		writeBytes(file, 0x64, 0x00, 0x00, 0x00)
		-- u16 biPlanes = 1
		writeBytes(file, 0x01, 0x00)
		-- u16 biBitCount = 24
		writeBytes(file, 0x18, 0x00)
		-- u32 biCompression = 0 // BI_RGB
		writeBytes(file, 0x00, 0x00, 0x00, 0x00)
		-- u32 biSizeImage = 60000
		writeBytes(file, 0x60, 0xEA, 0x00, 0x00)
		-- s32 biXPelsPerMeter = 0
		writeBytes(file, 0x00, 0x00, 0x00, 0x00)
		-- s32 biYPelsPerMeter = 0
		writeBytes(file, 0x00, 0x00, 0x00, 0x00)
		-- u32 biClrUsed = 0
		writeBytes(file, 0x00, 0x00, 0x00, 0x00)
		-- u32 biClrImportant = 0
		writeBytes(file, 0x00, 0x00, 0x00, 0x00)
	end

	for y = self.height, 1, -1 do
		local row = self.data[y]
		for x = 1, self.width do
			local pixel = row[x]
			local alpha = pixel.a
			local b = math.round(pixel.b * alpha)
			local g = math.round(pixel.g * alpha)
			local r = math.round(pixel.r * alpha)
			-- mwse.log("(%s, %s, %s)", r, g, b)
			writeBytes(file, b, g, r)
		end
	end
	file:close()
end
