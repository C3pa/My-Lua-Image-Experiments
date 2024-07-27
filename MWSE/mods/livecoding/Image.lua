local ffi = require("ffi")

local Base = require("livecoding.Base")
local oklab = require("livecoding.oklab")
local premultiply = require("livecoding.premultiply")

local niPixelData_BYTES_PER_PIXEL = 4

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

--- @private
--- @param y integer
function Image:getOffset(y)
	return y * self.width
end

--- Returns a copy of a pixel with given coordinates.
--- @param x number Horizontal coordinate
--- @param y number Vertical coordinate
function Image:getPixel(x, y)
	-- Slider at the bottom of main picker has higher precision than color picker width.
	-- So, we could feed in non integer coordinates. Let's make sure these are integers.
	x = math.floor(x)
	y = math.floor(y)
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
--- @param color ffiImagePixel
--- @param alpha number?
function Image:fillColor(color, alpha)
	alpha = alpha or 1

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

--- Generates main picker image for given Hue.
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

--- Modifies the Image in place.
--- @param leftColor PremulImagePixelA
--- @param rightColor PremulImagePixelA
function Image:horizontalGradient(leftColor, rightColor)
	leftColor.a = leftColor.a or 1
	rightColor.a = rightColor.a or 1

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

--- Modifies the Image in place.
--- @param topColor PremulImagePixelA
--- @param bottomColor PremulImagePixelA
function Image:verticalGradient(topColor, bottomColor)
	topColor.a = topColor.a or 1
	bottomColor.a = bottomColor.a or 1

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

--- Creates a checkered pattern.
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
local function colorBlend(cA, cB, alphaA, alphaB, inverse)
	local alphaO = alphaA + alphaB * inverse
	return (cA * alphaA + cB * alphaB * inverse) / alphaO
end

--- Returns a copy with the result of blending between `self` and given `image`.
--- @param background Image
--- @param copy boolean? If true, won't modify `self`, but will return the result of blend operation in a Image copy.
function Image:blend(background, copy)
	local sameWidth = self.width == background.width
	local sameHeight = self.height == background.height
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

	for y = 0, self.height - 1 do
		local offset = self:getOffset(y)
		for x = 1, self.width do
			local i = offset + x
			local pixel1 = data[i]
			local pixel2 = background.data[i]
			local alpha1 = alphas[i]
			local alpha2 = background.alphas[i]

			local inverse = 1 - alpha1
			pixel1.r = colorBlend(pixel1.r, pixel2.r, alpha1, alpha2, inverse)
			pixel1.g = colorBlend(pixel1.g, pixel2.g, alpha1, alpha2, inverse)
			pixel1.b = colorBlend(pixel1.b, pixel2.b, alpha1, alpha2, inverse)
			alpha1 = alpha1 + alpha2 * inverse
			data[i], alphas[i] = pixel1, alpha1
		end
	end
	if copy then
		return new
	end
end


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
