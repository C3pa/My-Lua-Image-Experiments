local ffi = require("ffi")

local Base = require("livecoding.Base")
local oklab = require("livecoding.oklab")

--- @class HSV
--- @field h number Hue in range [0, 360)
--- @field s number Saturation in range [0, 1]
--- @field v number Value/brightness in range [0, 1]

--- @class ImagePixel
--- @field r number Red in range [0, 1].
--- @field g number Green in range [0, 1].
--- @field b number Blue in range [0, 1].

--- @class ImagePixelA : ImagePixel
--- @field a number Alpha in range [0, 1].

--- @alias ImagePixelArgument ImagePixel|ImagePixelA

--- Pixel storing the color in premultiplied format.
--- @class PremulImagePixelA : ImagePixelA


--- An image helper class that stores RGBA color in premultiplied alpha format.
--- @class Image
--- @field width integer
--- @field height integer
--- @field data ffiImagePixel[]
--- @field alphas number[]
local Image = Base:new()

--- @class Image.new.data
--- @field width integer **Remember, to use it as an engine texture use power of 2 dimensions.**
--- @field height integer **Remember, to use it as an engine texture use power of 2 dimensions.**
--- @field data? ffiImagePixel[]
--- @field alphas? number[]

--- @alias ImagePixelArray number[] # A 1-indexed array of 3 rgb colors
--- @alias ffiImagePixelInit ImagePixelArray|ImagePixel

--- @alias hsvArray number[] # A 1-indexed array of 3 hsv values
--- @alias ffiHSVInit hsvArray|HSV

-- Defined in oklab\init.lua
local ffiPixel = ffi.typeof("RGB") --[[@as fun(init: ffiImagePixelInit?): ffiImagePixel]]
local ffiHSV = ffi.typeof("HSV") --[[@as fun(init: ffiHSVInit?): ffiHSV]]
-- Creates a 0-indexed array of ffiImagePixel
local ffiPixelArray = ffi.typeof("RGB[?]") --[[@as fun(nelem: integer, init: ffiImagePixelInit[]?): ffiImagePixel[]=]]

--- @param data Image.new.data
--- @return Image
function Image:new(data)
	local t = Base:new(data)
	setmetatable(t, self)

	-- Hack for `saveBMP`
	if EXPORT_IMAGES_BMP then
		data.width = 200
		data.height = 100
	end

	local size = t.width * t.height
	if t.data == nil then
		t.data = ffiPixelArray(size + 1)
	-- Convert given table initializer into a C-array.
	elseif not ffi.istype("RGB[?]", t.data) then
		t.data = ffiPixelArray(size + 1, t.data)
	end

	if not t.alphas then
		t.alphas = table.new(size, 0)
		for y = 0, t.height - 1 do
			local offset = y * t.width
			for x = 1, t.width do
				t.alphas[offset + x] = 1.0
			end
		end
	end

	self.__index = self
	return t
end

--- @param y number
function Image:getOffset(y)
	return y * self.width
end

--- Returns a copy of a pixel with given coordinates.
--- @param x integer Horizontal coordinate
--- @param y integer Vertical coordinate
function Image:getPixel(x, y)
	local offset = self:getOffset(y - 1)
	return self.data[offset + x]
end

--- @param x integer Horizontal coordinate
--- @param y integer Vertical coordinate
--- @param color ffiImagePixel
function Image:setPixel(x, y, color)
	local offset = self:getOffset(y - 1)
	self.data[offset + x] = color
end

--- Modifies the Image in place.
--- @param data ffiImagePixel[]
function Image:fill(data)
	self.data = data
end

--- @param pixel ffiImagePixel
--- @param alpha number
local function premultiply(pixel, alpha)
	pixel.r = pixel.r * alpha
	pixel.g = pixel.g * alpha
	pixel.b = pixel.b * alpha
end

--- Modifies the Image in place. Will premultiply the color channels with alpha value.
--- @param color ffiImagePixel
--- @param alpha number?
function Image:fillColor(color, alpha)
	alpha = alpha or 1
	premultiply(color, alpha)

	for y = 0, self.height - 1 do
		local offset = self:getOffset(y)
		for x = 1, self.width do
			self.data[offset + x] = color
			self.alphas[offset + x] = alpha
		end
	end
end

--- Modifies the Image in place. Works with **premultiplied** color.
--- @param rowIndex integer
--- @param color ffiImagePixel
--- @param alpha number?
function Image:fillRow(rowIndex, color, alpha)
	alpha = alpha or 1

	local offset = self:getOffset(rowIndex - 1)
	for x = 1, self.width do
		self.data[offset + x] = color
		self.alphas[offset + x] = alpha
	end
end

--- Modifies the Image in place. Works with **premultiplied** color.
--- @param columnIndex integer
--- @param color ffiImagePixel
--- @param alpha number?
function Image:fillColumn(columnIndex, color, alpha)
	alpha = alpha or 1

	for y = 0, self.height - 1 do
		local offset = self:getOffset(y)
		self.data[offset + columnIndex] = color
		self.alphas[offset + columnIndex] = alpha
	end
end

--- Modifies the Image in place. Fills the image into a vertical hue bar. HSV value at the top is:
--- `{ H = 0, s = 0.7, v = 0.85 }`, at the bottom `{ H = 360, s = 0.7, v = 0.85 }`
function Image:verticalHueBar()
	local hsv = ffiHSV({ 0, 0.7, 0.85 })

	-- Lower level fill method will account for the 0-indexing of the underlying data array.
	for y = 1, self.height do
		local t = y / self.height

		-- We lerp to 359.9999 since HSV { 360, 1.0, 1.0 } results in { r = 0, g = 0, b = 0 }
		-- at the bottom of the hue picker which is a undesirable.
		hsv.h = math.lerp(0, 359.9999, t)
		local color = oklab.hsvlib_hsv_to_srgb(hsv)
		self:fillRow(y, color)
	end
end

--- @param hue number Hue in range [0, 360)
function Image:mainPicker(hue)
	local hsv = ffiHSV({ hue, 0.0, 0.0 })

	for y = 0, self.height - 1 do
		local offset = self:getOffset(y)
		hsv.v = 1 - y / self.height

		for x = 1, self.width do
			hsv.s = x / self.width
			local color = oklab.hsvlib_hsv_to_srgb(hsv)
			self.data[offset + x] = color
		end
	end
end

--- @param pixel ImagePixelA
local function premultiplyLuaPixel(pixel)
	pixel.r = pixel.r * pixel.a
	pixel.g = pixel.g * pixel.a
	pixel.b = pixel.b * pixel.a
end

--- Modifies the Image in place. Will premultiply the color channels with alpha value.
--- @param leftColor ImagePixelArgument
--- @param rightColor ImagePixelArgument
function Image:horizontalGradient(leftColor, rightColor)
	leftColor.a = leftColor.a or 1
	rightColor.a = rightColor.a or 1
	premultiplyLuaPixel(leftColor)
	premultiplyLuaPixel(rightColor)
	--- @cast leftColor PremulImagePixelA
	--- @cast rightColor PremulImagePixelA

	for x = 1, self.width do
		local t = x / self.width
		local color = ffiPixel({
			math.lerp(leftColor.r, rightColor.r, t),
			math.lerp(leftColor.g, rightColor.g, t),
			math.lerp(leftColor.b, rightColor.b, t),
		})
		self:fillColumn(
			x, color,
			math.lerp(leftColor.a, rightColor.a, t)
		)
	end
end

--- Modifies the Image in place. Will premultiply the color channels with alpha value.
--- @param topColor ImagePixelArgument
--- @param bottomColor ImagePixelArgument
function Image:verticalGradient(topColor, bottomColor)
	topColor.a = topColor.a or 1
	bottomColor.a = bottomColor.a or 1
	premultiplyLuaPixel(topColor)
	premultiplyLuaPixel(bottomColor)
	--- @cast topColor PremulImagePixelA
	--- @cast bottomColor PremulImagePixelA

	-- Lower level fillRow will account for the 0-based indexing of the underlying data array.
	for y = 1, self.height do
		local t = y / self.height

		local color = ffiPixel({
			math.lerp(topColor.r, bottomColor.r, t),
			math.lerp(topColor.g, bottomColor.g, t),
			math.lerp(topColor.b, bottomColor.b, t),
		})
		self:fillRow(
			y, color,
			math.lerp(topColor.a, bottomColor.a, t)
		)
	end
end

--- Modifies the Image in place.
--- @param color ImagePixelArgument
function Image:horizontalColorGradient(color)
	--- @type ImagePixel
	local leftColor = { r = 1, g = 1, b = 1, a = 1 }
	self:horizontalGradient(leftColor, color)
end

--- Modifies the Image in place.
function Image:verticalGrayGradient()
	local topColor = { r = 0, g = 0, b = 0, a = 0 }
	local bottomColor = { r = 0, g = 0, b = 0, a = 1 }
	self:verticalGradient(topColor, bottomColor)
end

--- @param size integer? The size of single square in pixels.
--- @param lightGray ImagePixel?
--- @param darkGray ImagePixel?
function Image:toCheckerboard(size, lightGray, darkGray)
	size = size or 16
	local doubleSize = 2 * size
	local light = ffiPixel({ 0.7, 0.7, 0.7 })
	if lightGray then
		-- LuaJIT will do automatic type conversion for us.
		light = lightGray --[[@as ffiImagePixel]]
	end
	local dark = ffiPixel({ 0.5, 0.5, 0.5 })
	if darkGray then
		-- LuaJIT will do automatic type conversion for us.
		dark = darkGray --[[@as ffiImagePixel]]
	end

	for y = 0, self.height - 1 do
		local offset = self:getOffset(y)
		for x = 1, self.width do
			if ((y % doubleSize) < size) then
				-- -1 is compensation for indexing starting at 1.
				if (((x - 1) % doubleSize) < size) then
					self.data[offset + x] = light
				else
					self.data[offset + x] = dark
				end
			else
				if (((x - 1) % doubleSize) < size) then
					self.data[offset + x] = dark
				else
					self.data[offset + x] = light
				end
			end

		end
	end
end

function Image:copy()
	local size = self.height * self.width
	local data = ffiPixelArray(size + 1)
	ffi.copy(data, self.data, ffi.sizeof("RGB[?]", size))

	local alphas = table.new(size, 0)
	table.copy(self.alphas, alphas)


	local new = Image:new({
		height = self.height,
		width = self.width,
		data = data,
		alphas = alphas,
	})

	return new
end

-- https://en.wikipedia.org/wiki/Alpha_compositing#Description
local function colorBlend(cA, cB, alphaA, alphaB, alphaO)
	return (cA * alphaA + cB * alphaB * (1 - alphaA)) / alphaO
end

--- @alias ImageBlendType
---| "plus"
---| "dissolve"
---| "over"

--- @alias ImageBlendFunction fun(pixel1: PremulImagePixelA, pixel2: PremulImagePixelA, coeff: number): PremulImagePixelA

--- @type table<ImageBlendType, ImageBlendFunction>
local blend = {}

--- @deprecated This worked before when the color channels were in [0, 255] range.
--- No idea why this doesn't work correctly anymore
-- See 4.5 The PLUS operator in:
-- https://graphics.pixar.com/library/Compositing/paper.pdf
function blend.plus(pixel1, pixel2, coeff)
	return {
		r = pixel1.r + pixel2.r,
		g = pixel1.g + pixel2.g,
		b = pixel1.b + pixel2.b,
		a = pixel1.a * pixel2.a,
	}
end

--- @deprecated
-- See 4.5 The PLUS operator in:
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

--- https://en.wikipedia.org/wiki/Alpha_compositing#Straight_versus_premultiplied
function blend.over(pixel1, pixel2, coeff)
	local inverseA2 = 1 - pixel2.a
	-- TODO: see if modifying the pixel1 instead of creating a new table is faster
	return {
		r = pixel2.r + pixel1.r * inverseA2,
		g = pixel2.g + pixel1.g * inverseA2,
		b = pixel2.b + pixel1.b * inverseA2,
		a = pixel2.a + pixel1.a * inverseA2,
	}
end

--- Returns a copy with the result of blending between the two images
--- @param image Image
--- @param coeff number In range of [0, 1].
--- @param type ImageBlendType
--- @param copy boolean? If true, won't modify `self`, but will return the result of blend operation in a Image copy.
function Image:blend(image, coeff, type, copy)
	local sameWidth = self.width == image.width
	local sameHeight = self.height == image.height
	assert(sameWidth, "Images must be of same width.")
	assert(sameHeight, "Images must be of same height.")

	local data = self.data
	local alphas = self.alphas
	--- @type Image|nil
	local new
	if copy then
		new = self:copy()
		data = new.data
		alphas = new.alphas
	end
	local blend = blend[type]
	for y = 0, self.height - 1 do
		local offset = self:getOffset(y)
		for x = 1, self.width do
			-- We only do "over" blending in this version
			local alpha2 = image.alphas[offset + x]
			local inverseA2 = 1 - alpha2
			local pixel1 = data[offset + x]
			local pixel2 = image.data[offset + x]
			pixel1.r = pixel2.r + pixel1.r * inverseA2
			pixel1.g = pixel2.g + pixel1.g * inverseA2
			pixel1.b = pixel2.b + pixel1.b * inverseA2
			data[offset + x] = pixel1
			alphas[offset + x] = alpha2 + alphas[offset + x] * inverseA2
			-- TODO:
			-- data[offset + x] = blend(data[offset + x], image.data[offset + x], coeff)
		end
	end
	if copy then
		return new
	end
end


local test = Image:new({
	height = 3,
	width = 5,
	-- data = {
	-- 	{ r = 0, g = 0, b = 0, a = 1 }, { r = 0, g = 0, b = 0, a = 1 }, { r = 0, g = 0, b = 0, a = 1 }, { r = 0, g = 0, b = 0, a = 1 }, { r = 0, g = 0, b = 0, a = 1 },
	-- 	{ r = 0, g = 1, b = 0, a = 1 }, { r = 0, g = 1, b = 0, a = 1 }, { r = 0, g = 1, b = 0, a = 1 }, { r = 0, g = 1, b = 0, a = 1 }, { r = 0, g = 1, b = 0, a = 1 },
	-- 	{ r = 0, g = 0.3, b = 1, a = 1 }, { r = 0, g = 1, b = 1, a = 1 }, { r = 0, g = 1, b = 1, a = 1 }, { r = 0, g = 1, b = 1, a = 1 }, { r = 0, g = 1, b = 1, a = 1 },
	-- }
})
-- test:fillColor(ffiPixel({ 0.3, 0.3, 0.3 }), 0.5)
-- test:fillColumn(2, ffiPixel({ 1.0, 1.0, 1.0 }))
-- test:verticalHueBar()
-- test:mainPicker(60)
-- test:horizontalGradient({ r = 1, b = 1, g = 0, a = 0.5},{r = 0, b = 0.5, g = 1, a = 0.0})
-- test:verticalGradient({ r = 1, b = 1, g = 0, a = 0.5},{r = 0, b = 0.5, g = 1, a = 0.0})
-- test:horizontalColorGradient({ r = 1, b = 1, g = 0 })
-- test:verticalGrayGradient()
-- test:toCheckerboard(2, { r = 1.0, g = 0.0, b = 0.0 }, { r = 0.0, g = 0.0, b = 1.0 })
-- mwse.log("test.copy = %s", format.imageData(test))
-- mwse.log("test.alphas = %s", inspect(test.alphas))
-- test:saveBMP("imgTest.bmp")

local niPixelData_BYTES_PER_PIXEL = 4

--- For feeding data straight to `niPixelData:setPixelsFloat`.
function Image:toPixelBufferFloat()
	local size = self.width * self.height
	local buffer = table.new(size * niPixelData_BYTES_PER_PIXEL, 0)
	local stride = 0

	for y = 0, self.height - 1 do
		local offset = self:getOffset(y)
		for x = 1, self.width do
			local pixel = self.data[offset + x]
			buffer[stride + 1] = pixel.r
			buffer[stride + 2] = pixel.g
			buffer[stride + 3] = pixel.b
			-- buffer[stride + 4] = 1
			buffer[stride + 4] = self.alphas[offset + x]
			stride = stride + 4
		end
	end

	return buffer
end

--- For feeding data straight to `niPixelData:setPixelsByte`.
function Image:toPixelBufferByte()
	local size = self.width * self.height
	local buffer = table.new(size * niPixelData_BYTES_PER_PIXEL, 0)
	local stride = 0

	for y = 0, self.height - 1 do
		local offset = self:getOffset(y)
		for x = 1, self.width do
			local pixel = self.data[offset + x]
			buffer[stride + 1] = pixel.r * 255
			buffer[stride + 2] = pixel.g * 255
			buffer[stride + 3] = pixel.b * 255
			-- buffer[stride + 4] = 255
			buffer[stride + 4] = self.alphas[offset + x] * 255
			stride = stride + 4
		end
	end

	return buffer
end

--- @param file file*
--- @param ... integer
local function writeBytes(file, ...)
	file:write(string.char(...))
end

--- @param filename string
function Image:saveBMP(filename)
	if not EXPORT_IMAGES_BMP then
		error("Can't export images!")
	end
	local file = io.open(filename, "wb")
	if not file then
		error(string.format("Can't open %q. Traceback:%s", filename, debug.traceback()))
	end
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

	for y = self.height - 1, 0, -1 do
		local offset = self:getOffset(y)
		for x = 1, self.width do
			local pixel = self.data[offset + x]
			local alpha = self.alphas[offset + x]
			local b = math.round(255 * pixel.b)
			local g = math.round(255 * pixel.g)
			local r = math.round(255 * pixel.r)
			writeBytes(file, b, g, r)
		end
	end
	file:close()
end

return Image
