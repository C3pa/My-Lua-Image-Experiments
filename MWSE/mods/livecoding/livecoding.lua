--[[
	run code without restarting the game! hotkey alt+x
--]]

tes3.messageBox("Hello World")
mwse.log("Reset!")

local ffi = require("ffi")
local inspect = require("inspect")
local logger = require("logging.logger")

local Base = require("livecoding.Base")
local cursorHelper = require("livecoding.cursorHelper")
local headingMenu = require("livecoding.headingMenu")
local oklab = require("livecoding.oklab")

-- Will export the test images as BMP files for inspecting. This will force all the image
-- dimensions to 200x100.
local EXPORT_IMAGES_BMP = false




ffi.cdef[[
	typedef struct {
		float r;
		float g;
		float b;
	} RGB;

	typedef struct {
		float h;
		float s;
		float v;
	} HSV;
]]

--- @class ffiImagePixel : ffi.cdata*
--- @field r number Red in range [0, 1].
--- @field g number Green in range [0, 1].
--- @field b number Blue in range [0, 1].

--- @class ffiHSV : ffi.cdata*
--- @field h number Hue in range [0, 360)
--- @field s number Saturation in range [0, 1]
--- @field v number Value/brightness in range [0, 1]

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

--- @alias ImageData ffiImagePixel[]

--- An image helper class that stores RGBA color in premultiplied alpha format.
--- @class Image
--- @field width integer
--- @field height integer
--- @field data ImageData
--- @field alphas number[]
local Image = Base:new()

--- @class Image.new.data
--- @field width integer **Remember, to use it as an engine texture use power of 2 dimensions.**
--- @field height integer **Remember, to use it as an engine texture use power of 2 dimensions.**
--- @field data ImageData?
--- @field alphas number[]?

--- @alias ImagePixelArray number[] # A 1-indexed array of 3 rgb colors
--- @alias ffiImagePixelInit ImagePixelArray|ImagePixel

--- @alias hsvArray number[] # A 1-indexed array of 3 hsv values
--- @alias ffiHSVInit hsvArray|HSV

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
--- @param data ImageData
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
--- @param lightGray PremulImagePixelA?
--- @param darkGray PremulImagePixelA?
function Image:toCheckerboard(size, lightGray, darkGray)
	size = size or 16
	local doubleSize = 2 * size
	local light = ffiPixel({ 0.7, 0.7, 0.7 })
	if lightGray then
		-- TODO: check if we can assign to C struct this way
		light = lightGray
		-- light.r = lightGray.r
		-- light.g = lightGray.g
		-- light.b = lightGray.b
	end
	local dark = ffiPixel({ 0.5, 0.5, 0.5 })
	if darkGray then
		-- TODO: check if we can assign to C struct this way
		dark = darkGray
		-- dark.r = darkGray.r
		-- dark.g = darkGray.g
		-- dark.b = darkGray.b
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
	local size = self.height * self.width + 1
	local data = ffiPixelArray(size)
	-- TODO: why this for loop?
	for y = 0, self.height - 1 do
		local offset = self:getOffset(y)
		for x = 1, self.width do
			data[offset + x] = self.data[offset + x]
		end
	end
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


local PICKER_HEIGHT = 256
local PICKER_MAIN_WIDTH = 256
local PICKER_VERTICAL_COLUMN_WIDTH = 32
local PICKER_PREVIEW_WIDTH = 64
local PICKER_PREVIEW_HEIGHT = 32
local INDICATOR_TEXTURE = "textures\\menu_map_smark.dds"
local INDICATOR_COLOR = { 0.5, 0.5, 0.5 }

local mainImage = Image:new({
	width = PICKER_MAIN_WIDTH,
	height = PICKER_HEIGHT,
})

-- Base for the main color picker image.
-- mainImage:horizontalColorGradient({ r = 0, g = 1, b = 0 })
mainImage:mainPicker(60)

-- local gettime = require("socket").gettime
-- local t1 = gettime()
-- for i = 0, 255 do
-- 	mainImage:mainPicker(i)
-- end
-- local m = string.format("TEST DONE! Time elapsed: %ss", gettime() - t1)
-- mwse.log(m)
-- tes3.messageBox(m)



-- Black overlay for the main color picker image.
local blackGradient = Image:new({
	width = PICKER_MAIN_WIDTH,
	height = PICKER_HEIGHT,
})
blackGradient:verticalGrayGradient()

-- The main color picker image.
-- mainImage:blend(blackGradient, 0.5, "over")

local hueBar = Image:new({
	width = PICKER_VERTICAL_COLUMN_WIDTH,
	height = PICKER_HEIGHT,
})
hueBar:verticalHueBar()

local alphaChecker = Image:new({
	width = PICKER_VERTICAL_COLUMN_WIDTH,
	height = PICKER_HEIGHT,
})
alphaChecker:toCheckerboard()

local alphaBar = Image:new({
	width = PICKER_VERTICAL_COLUMN_WIDTH,
	height = PICKER_HEIGHT,
})
alphaBar:verticalGradient({ r = 0.25, g = 0.25, b = 0.25, a = 1.0 }, { r = 1, g = 1, b = 1, a = 0.0 })
alphaBar = alphaChecker:blend(alphaBar, 0.5, "over", true) --[[@as Image]]

local previewCheckers = Image:new({
	width = PICKER_PREVIEW_WIDTH / 2,
	height = PICKER_PREVIEW_HEIGHT
})
previewCheckers:toCheckerboard()
local previewForeground = Image:new({
	width = PICKER_PREVIEW_WIDTH / 2,
	height = PICKER_PREVIEW_HEIGHT
})

if EXPORT_IMAGES_BMP then
	blackGradient:saveBMP("imgBlackGradient.bmp")
	mainImage:saveBMP("imgMainImage+blackGradient.bmp")
	hueBar:saveBMP("imgHueBar.bmp")
	alphaBar:saveBMP("imgAlphaBar.bmp")
	tes3.messageBox("Images sucessfuly exported! Since these have wrong dimensions, color picker won't be opened. \z
		Disable `EXPORT_IMAGES_BMP` to open the color picker!"
	)
	return
end





local textures = {
	main = niPixelData.new(PICKER_MAIN_WIDTH, PICKER_HEIGHT):createSourceTexture(),
	hue = niPixelData.new(PICKER_VERTICAL_COLUMN_WIDTH, PICKER_HEIGHT):createSourceTexture(),
	alpha = niPixelData.new(PICKER_VERTICAL_COLUMN_WIDTH, PICKER_HEIGHT):createSourceTexture(),
	previewCurrent = niPixelData.new(PICKER_PREVIEW_WIDTH / 2, PICKER_PREVIEW_HEIGHT):createSourceTexture(),
	previewOriginal = niPixelData.new(PICKER_PREVIEW_WIDTH / 2, PICKER_PREVIEW_HEIGHT):createSourceTexture(),
}
for _, texture in pairs(textures) do
	texture.isStatic = false
end

--- @param color ffiImagePixel
local function updateMainPickerImage(color)
	local hsv = oklab.hsvlib_srgb_to_hsv(color)
	mainImage:mainPicker(hsv.h)
end

--- @param color ffiImagePixel
--- @param alpha number
local function updatePreviewImage(color, alpha)
	previewForeground:fillColor(color, alpha)
	previewForeground = previewCheckers:blend(previewForeground, 0.5, "over", true)
end

local UIID = {
	menu = tes3ui.registerID("testing:Menu"),
	pickerMenu = tes3ui.registerID("testing:pickerMenu"),
}


local close = {
	keyCode = tes3.scanCode.f
}

livecoding.registerEvent(tes3.event.keyDown, function(e)
	if not tes3.isKeyEqual({ actual = e, expected = close }) then return end
	if tes3ui.findMenu(UIID.pickerMenu) then return end
	local menu = tes3ui.findMenu(UIID.menu)
	if menu then
		menu:destroy()
		tes3ui.leaveMenuMode()
	end
end)

--- @class ColorPicker.new.params
--- @field initialColor ImagePixel
--- @field initialAlpha number?
--- @field alpha boolean? If true the picker will also allow picking an alpha value.
--- @field showOriginal boolean? If true the picker will show original color below the currently picked color.
--- @field showDataRow boolean? If true the picker will show RGB(A) values of currently picked color in a label below the picker.

-- TODO: these could use localization.
local strings = {
	["Current"] = "Current",
	["Original"] = "Original",
}

--- @class ColorPickerPreviewsTable
--- @field standardPreview tes3uiElement
--- @field checkersPreview tes3uiElement


--- @param previews ColorPickerPreviewsTable
--- @param newColor ffiImagePixel
--- @param alpha number
local function updatePreview(previews, newColor, alpha)
	previews.standardPreview.color = { newColor.r, newColor.g, newColor.b }
	previews.standardPreview:updateLayout()
	updatePreviewImage(newColor, alpha)
	previews.checkersPreview.texture.pixelData:setPixelsFloat(previewForeground:toPixelBufferFloat())
end

--- @param mainPicker tes3uiElement
--- @param newColor ffiImagePixel
local function updateMainPicker(mainPicker, newColor)
	newColor = ffiPixel({ newColor.r, newColor.g, newColor.b })
	updateMainPickerImage(newColor)
	-- mainPicker.imageFilter = false
	mainPicker.texture.pixelData:setPixelsFloat(mainImage:toPixelBufferFloat())
	-- mainPicker:getTopLevelMenu():updateLayout()
	-- mainPicker.imageFilter = false
end

--- @type ffiImagePixel, number
local currentColor, currentAlpha


--- @alias IndicatorID
---| "main"
---| "hue"
---| "alpha"

local function getIndicators()
	local menu = tes3ui.findMenu(UIID.menu)
	--- @cast menu -nil

	local pickerRow = menu:findChild(tes3ui.registerID("ColorPicker_picker_row_container"))

	--- @type table<IndicatorID, tes3uiElement>
	local indicators = {}
	for i = 1, 3 do
		local indicator = pickerRow.children[i].children[1]
		local id = indicator:getLuaData("indicatorID")
		if id then
			indicators[id] = indicator
		end
	end
	return indicators
end

--- @param mainIndicator tes3uiElement
--- @param hsv ffiHSV
local function updateMainIndicatorPosition(mainIndicator, hsv)
	mainIndicator.absolutePosAlignX = hsv.s
	mainIndicator.absolutePosAlignY = 1 - hsv.v
end

--- @param hueIndicator tes3uiElement
--- @param hsv ffiHSV
local function updateHueIndicatorPosition(hueIndicator, hsv)
	local y = hsv.h / 360
	hueIndicator.absolutePosAlignY = y
end

--- @param alphaIndicator tes3uiElement
--- @param alpha number
local function updateAlphaIndicatorPosition(alphaIndicator, alpha)
	alphaIndicator.absolutePosAlignY = 1 - alpha
end

--- @param newColor ffiImagePixel
--- @param alpha number?
local function updateIndicatorPositions(newColor, alpha)
	local hsv = oklab.hsvlib_srgb_to_hsv(newColor)
	local indicators = getIndicators()
	updateMainIndicatorPosition(indicators.main, hsv)
	updateHueIndicatorPosition(indicators.hue, hsv)
	if indicators.alpha then
		updateAlphaIndicatorPosition(indicators.alpha, alpha)
	end
	indicators.hue:getTopLevelMenu():updateLayout()
end

local function getValueInputs()
	local menu = tes3ui.findMenu(UIID.menu)
	--- @cast menu -nil
	local dataRow = menu:findChild(tes3ui.registerID("ColorPicker_data_row_container"))
	if not dataRow then return end
	--- @type table<channelType, tes3uiElement>
	local inputs = {}
	for _, child in ipairs(dataRow.children) do
		local input = child.children[2]
		local channel = input:getLuaData("channel")
		inputs[channel] = input
	end
	return inputs
end

--- @param color number
local function channelToString(color)
	return string.format("%.3f", color * 255)
end

--- @param newColor ffiImagePixel
--- @param alpha number
local function updateValueInputs(newColor, alpha)
	-- Make sure we don't get NaNs in color text inputs. We clamp alpha here.
	alpha = math.clamp(alpha, 0.0000001, 1.0)
	-- We store color premultiplied by alpha. Let's undo it to not expose this to the user via the UI.
	newColor.r = newColor.r / alpha
	newColor.g = newColor.g / alpha
	newColor.b = newColor.b / alpha
	local inputs = getValueInputs()
	if not inputs then return end
	for channel, input in pairs(inputs) do
		if channel == 'a' then
			input.text = channelToString(alpha)
		else
			input.text = channelToString(newColor[channel])
		end
	end
end

--- @param newColor ffiImagePixel
--- @param alpha number
--- @param previews ColorPickerPreviewsTable
local function colorSelected(newColor, alpha, previews)
	newColor = ffiPixel({ newColor.r, newColor.g, newColor.b })
	updatePreview(previews, newColor, alpha)
	updateValueInputs(newColor, alpha)
end

--- @param newColor ffiImagePixel
--- @param alpha number
--- @param previews ColorPickerPreviewsTable
--- @param mainPicker tes3uiElement
local function hueChanged(newColor, alpha, previews, mainPicker)
	newColor = ffiPixel({ newColor.r, newColor.g, newColor.b })
	updatePreview(previews, newColor, alpha)
	updateMainPicker(mainPicker, newColor)
	updateValueInputs(newColor, alpha)
end

--- @param parent tes3uiElement
--- @param color ffiImagePixel
--- @param alpha number
--- @param texture niSourceTexture
--- @return ColorPickerPreviewsTable
local function createPreviewElement(parent, color, alpha, texture)
	local standardPreview = parent:createRect({
		id = tes3ui.registerID("ColorPicker_color_preview_left"),
		color = { color.r, color.g, color.b },
	})
	standardPreview.width = PICKER_PREVIEW_WIDTH / 2
	standardPreview.height = PICKER_PREVIEW_HEIGHT
	standardPreview.borderTop = 8
	standardPreview.borderLeft = 8
	standardPreview.borderBottom = 8

	local checkersPreview = parent:createRect({
		id = tes3ui.registerID("ColorPicker_color_preview_right"),
		color = { 1.0, 1.0, 1.0 },
	})
	checkersPreview.width = PICKER_PREVIEW_WIDTH / 2
	checkersPreview.height = PICKER_PREVIEW_HEIGHT
	checkersPreview.texture = texture
	checkersPreview.imageFilter = false
	checkersPreview.borderTop = 8
	checkersPreview.borderRight = 8
	checkersPreview.borderBottom = 8

	updatePreviewImage(color, alpha)
	checkersPreview.texture.pixelData:setPixelsFloat(previewForeground:toPixelBufferFloat())

	return {
		standardPreview = standardPreview,
		checkersPreview = checkersPreview,
	}
end

--- @param parent tes3uiElement
--- @param color ffiImagePixel
--- @param alpha number
--- @param label string
--- @param onClickCallback? fun(e: tes3uiEventData)
--- @return ColorPickerPreviewsTable
local function createPreview(parent, color, alpha, label, onClickCallback)
	-- We don't want to create references to color.
	local color = ffiPixel({ color.r, color.g, color.b })
	local outerContainer = parent:createBlock({ id = tes3ui.registerID("ColorPicker_color_preview_outer_container") })
	outerContainer.flowDirection = tes3.flowDirection.topToBottom
	outerContainer.autoWidth = true
	outerContainer.autoHeight = true
	outerContainer.paddingTop = 8

	outerContainer:createLabel({
		id = tes3ui.registerID("ColorPicker_color_preview_" .. label ),
		text = strings[label]
	})

	local innerContainer = outerContainer:createBlock({ id = tes3ui.registerID("ColorPicker_color_preview_inner_container") })
	innerContainer.flowDirection = tes3.flowDirection.leftToRight
	innerContainer.autoWidth = true
	innerContainer.autoHeight = true

	local previewTexture = textures["preview" .. label]
	local previews = createPreviewElement(innerContainer, color, alpha, previewTexture)

	if onClickCallback then
		innerContainer:register(tes3.uiEvent.mouseDown, function(e)
			onClickCallback(e)
		end)
	end
	return previews
end

--- @param params ColorPicker.new.params
--- @param parent tes3uiElement
local function createPickerBlock(params, parent)
	local initialColor = ffiPixel({
		params.initialColor.r,
		params.initialColor.g,
		params.initialColor.b,
	})

	local mainRow = parent:createBlock({
		id = tes3ui.registerID("ColorPicker_picker_row_container")
	})
	mainRow.flowDirection = tes3.flowDirection.leftToRight
	mainRow.autoHeight = true
	mainRow.autoWidth = true
	mainRow.widthProportional = 1.0
	mainRow.paddingAllSides = 4

	local initialHSV = oklab.hsvlib_srgb_to_hsv(initialColor)
	local mainIndicatorInitialAbsolutePosAlignX = initialHSV.s
	local mainIndicatorInitialAbsolutePosAlignY = 1 - initialHSV.v
	local hueIndicatorInitialAbsolutePosAlignY = initialHSV.h / 360

	local mainPicker = mainRow:createRect({
		id = tes3ui.registerID("ColorPicker_main_picker"),
		color = { 1, 1, 1 },
	})
	mainPicker.borderAllSides = 8
	mainPicker.width = PICKER_MAIN_WIDTH
	mainPicker.height = PICKER_HEIGHT
	mainPicker.texture = textures.main
	mainPicker.imageFilter = false

	updateMainPickerImage(initialColor)

	mainPicker.texture.pixelData:setPixelsFloat(mainImage:toPixelBufferFloat())
	mainPicker:register(tes3.uiEvent.mouseDown, function(e)
		tes3ui.captureMouseDrag(true)
	end)
	mainPicker:register(tes3.uiEvent.mouseRelease, function(e)
		tes3ui.captureMouseDrag(false)
	end)
	local mainIndicator = mainPicker:createImage({
		id = tes3ui.registerID("ColorPicker_main_picker_indicator"),
		path = INDICATOR_TEXTURE,
	})
	mainIndicator.color = INDICATOR_COLOR
	mainIndicator.absolutePosAlignX = mainIndicatorInitialAbsolutePosAlignX
	mainIndicator.absolutePosAlignY = mainIndicatorInitialAbsolutePosAlignY
	mainIndicator:setLuaData("indicatorID", "main")

	local huePicker = mainRow:createRect({
		id = tes3ui.registerID("ColorPicker_hue_picker"),
		color = { 1, 1, 1 },
	})
	huePicker.borderAllSides = 8
	huePicker.width = PICKER_VERTICAL_COLUMN_WIDTH
	huePicker.height = PICKER_HEIGHT
	huePicker.texture = textures.hue
	huePicker.imageFilter = false
	huePicker.texture.pixelData:setPixelsFloat(hueBar:toPixelBufferFloat())
	huePicker:register(tes3.uiEvent.mouseDown, function(e)
		tes3ui.captureMouseDrag(true)
	end)
	huePicker:register(tes3.uiEvent.mouseRelease, function(e)
		tes3ui.captureMouseDrag(false)
	end)
	local hueIndicator = huePicker:createImage({
		id = tes3ui.registerID("ColorPicker_hue_picker_indicator"),
		path = INDICATOR_TEXTURE,
	})
	hueIndicator.color = INDICATOR_COLOR
	hueIndicator.absolutePosAlignX = 0.5
	hueIndicator.absolutePosAlignY = hueIndicatorInitialAbsolutePosAlignY
	hueIndicator:setLuaData("indicatorID", "hue")


	local alphaPicker
	local alphaIndicator
	if params.alpha then
		alphaPicker = mainRow:createRect({
			id = tes3ui.registerID("ColorPicker_alpha_picker"),
			color = { 1, 1, 1 },
		})
		alphaPicker.borderAllSides = 8
		alphaPicker.width = PICKER_VERTICAL_COLUMN_WIDTH
		alphaPicker.height = PICKER_HEIGHT
		alphaPicker.texture = textures.alpha
		alphaPicker.imageFilter = false
		alphaPicker.texture.pixelData:setPixelsFloat(alphaBar:toPixelBufferFloat())
		alphaPicker:register(tes3.uiEvent.mouseDown, function(e)
			tes3ui.captureMouseDrag(true)
		end)
		alphaPicker:register(tes3.uiEvent.mouseRelease, function(e)
			tes3ui.captureMouseDrag(false)
		end)

		alphaIndicator = alphaPicker:createImage({
			id = tes3ui.registerID("ColorPicker_alpha_picker_indicator"),
			path = INDICATOR_TEXTURE,
		})
		alphaIndicator.color = INDICATOR_COLOR
		alphaIndicator.absolutePosAlignX = 0.5
		alphaIndicator.absolutePosAlignY = 1 - params.initialAlpha
		alphaIndicator:setLuaData("indicatorID", "alpha")
	end

	local previewContainer = mainRow:createBlock({ id = tes3ui.registerID("ColorPicker_color_preview_container") })
	previewContainer.flowDirection = tes3.flowDirection.topToBottom
	previewContainer.autoWidth = true
	previewContainer.autoHeight = true

	local currentPreview = createPreview(previewContainer, initialColor, params.initialAlpha, "Current")

	-- Implement picking behavior
	mainPicker:register(tes3.uiEvent.mouseStillPressed, function(e)
		local x = math.clamp(e.relativeX, 1, mainPicker.width)
		local y = math.clamp(e.relativeY, 1, mainPicker.height)
		local pickedColor = mainImage:getPixel(x, y)
		-- Make sure we don't create reference to the pixel from the mainImage.
		currentColor = ffiPixel({ pickedColor.r, pickedColor.g, pickedColor.b })
		colorSelected(currentColor, currentAlpha, currentPreview)

		mainIndicator.absolutePosAlignX = x / mainPicker.width
		mainIndicator.absolutePosAlignY = y / mainPicker.height
		mainRow:getTopLevelMenu():updateLayout()
	end)

	huePicker:register(tes3.uiEvent.mouseStillPressed, function(e)
		local x = math.clamp(e.relativeX, 1, huePicker.width)
		local y = math.clamp(e.relativeY, 1, huePicker.height)
		local pickedColor = hueBar:getPixel(x, y)
		-- Make sure we don't create reference to the pixel from the hueBar.
		currentColor = ffiPixel({ pickedColor.r, pickedColor.g, pickedColor.b })
		hueChanged(currentColor, currentAlpha, currentPreview, mainPicker)

		hueIndicator.absolutePosAlignY = y / huePicker.height
		mainRow:getTopLevelMenu():updateLayout()
	end)

	if params.alpha then
		alphaPicker:register(tes3.uiEvent.mouseStillPressed, function(e)
			local y = math.clamp(e.relativeY / alphaPicker.height, 0, 1)
			currentAlpha = 1 - y

			colorSelected(currentColor, currentAlpha, currentPreview)
			alphaIndicator.absolutePosAlignY = y
			mainRow:getTopLevelMenu():updateLayout()
		end)
	end

	if params.showOriginal then
		--- @param e tes3uiEventData
		local function resetColor(e)
			currentColor = ffiPixel({ params.initialColor.r, params.initialColor.g, params.initialColor.b })
			hueChanged(currentColor, params.initialAlpha, currentPreview, mainPicker)

			mainIndicator.absolutePosAlignX = mainIndicatorInitialAbsolutePosAlignX
			mainIndicator.absolutePosAlignY = mainIndicatorInitialAbsolutePosAlignY
			hueIndicator.absolutePosAlignY = hueIndicatorInitialAbsolutePosAlignY
			if params.alpha then
				alphaIndicator.absolutePosAlignY = 1 - params.initialAlpha
				currentAlpha = params.initialAlpha
			end
			mainRow:getTopLevelMenu():updateLayout()
		end
		createPreview(previewContainer, initialColor, params.initialAlpha, "Original", false, resetColor)
	end

	colorSelected(initialColor, params.initialAlpha, currentPreview)
	mainRow:getTopLevelMenu():updateLayout()
	mainPicker.imageFilter = false
	huePicker.imageFilter = false
	if alphaPicker then
		alphaPicker.imageFilter = false
	end
	return {
		mainPicker = mainPicker,
		huePicker = huePicker,
		alphaPicker = alphaPicker,
		currentPreview = currentPreview,
	}
end

--- @alias channelType
---| 'r'
---| 'g'
---| 'b'
---| 'a'

--- Returns the channel value by reading `text` property of given TextInput. Returned value is in range of [0, 1].
--- @param input tes3uiElement
local function getInputValue(input)
	-- Clearing the text input will set the color to 0.
	local text = input.text
	if text == "" then
		text = '0'
	end

	-- Make sure the entered color will be clamped to [0, 255].
	return math.clamp(tonumber(text), 0, 255) / 255
end

--- It will return given color in range of [0, 1] in non-premultiplied format.
--- @param inputs table<channelType, tes3uiElement>
local function getColorFromInputs(inputs)
	--- @type ImagePixelA
	local color = { r = 0.0, g = 0.0, b = 0.0, a = 1.0 }
	for channel, input in pairs(inputs) do
		color[channel] = getInputValue(input)
	end
	return color
end

--- @param parent tes3uiElement
--- @param channel channelType
--- @param initialValue number
--- @param onNewValueEntered function
local function createValueLabel(parent, channel, initialValue, onNewValueEntered)
	local container = parent:createBlock({
		id = tes3ui.registerID("ColorPicker_data_row_value_container")
	})
	container.autoHeight = true
	container.autoWidth = true
	container.paddingAllSides = 8

	local nameLabel = container:createLabel({
		id = tes3ui.registerID("ColorPicker_data_row_value_nameLabel_" .. channel),
		text = string.format("%s:", string.upper(channel)),
	})
	nameLabel.paddingRight = 8
	nameLabel.color = tes3ui.getPalette(tes3.palette.headerColor)


	local input = container:createTextInput({
		id = tes3ui.registerID("ColorPicker_data_row_value_input_" .. channel),
		numeric = true,
		text = channelToString(initialValue),
	})
	input.borderLeft = 4
	input.color = tes3ui.getPalette(tes3.palette.activeColor)
	input:setLuaData("channel", channel)

	-- Make it clear that the value fields accept text input.
	input:registerAfter(tes3.uiEvent.mouseOver, function(e)
		input.color = tes3ui.getPalette(tes3.palette.activeOverColor)
		input:updateLayout()
	end)
	input:registerAfter(tes3.uiEvent.mouseLeave, function(e)
		input.color = tes3ui.getPalette(tes3.palette.activeColor)
		input:updateLayout()
	end)

	-- Update color after new value was entered.
	input:registerAfter(tes3.uiEvent.keyEnter, function(e)
		local color = getInputValue(input)
		input.text = channelToString(color)
		input.color = tes3ui.getPalette(tes3.palette.activeColor)
		input:updateLayout()

		-- Update other parts of the Color Picker
		onNewValueEntered()
	end)
	return input
end

--- @param params ColorPicker.new.params
--- @param parent tes3uiElement
--- @param onNewColorEntered fun(newColor: ffiImagePixel, alpha: number)
--- @param onNewAlphaEntered? fun(newColor: ffiImagePixel, alpha: number)
local function createDataBlock(params, parent, onNewColorEntered, onNewAlphaEntered)
	local dataRow = parent:createBlock({
		id = tes3ui.registerID("ColorPicker_data_row_container")
	})
	dataRow.flowDirection = tes3.flowDirection.leftToRight
	dataRow.autoHeight = true
	dataRow.autoWidth = true
	dataRow.widthProportional = 1.0
	dataRow.paddingAllSides = 4

	--- @type channelType[]
	local channels = { 'r', 'g', 'b' }

	--- @type table<channelType, tes3uiElement>
	local inputs = {}

	local function updateColors()
		local color = getColorFromInputs(inputs)
		local pixel = ffiPixel({ color.r, color.g, color.b })
		currentColor = pixel
		currentAlpha = color.a
		onNewColorEntered(pixel, color.a)
	end

	for _, channel in ipairs(channels) do
		-- We store color premultiplied by alpha. Don't expose this to the user, undo it in the UI.
		local initialColor = params.initialColor[channel] / params.initialAlpha
		inputs[channel] = createValueLabel(dataRow, channel, initialColor, updateColors)
	end
	if params.alpha then
		assert(onNewAlphaEntered ~= nil, "Need to provide a onNewAlphaEntered.")
		assert(type(onNewAlphaEntered) == "function", "onNewAlphaEntered needs to be a function.")

		local function updateAlpha()
			local color = getColorFromInputs(inputs)
			local pixel = ffiPixel({ color.r, color.g, color.b })
			currentColor = pixel
			currentAlpha = color.a
			onNewAlphaEntered(pixel, color.a)
		end
		inputs['a'] = createValueLabel(dataRow, 'a', params.initialAlpha, updateAlpha)
	end

	return {
		inputs = inputs,
	}
end

--- @param params ColorPicker.new.params
local function openMenu(params)
	local menu = tes3ui.findMenu(UIID.menu)
	if menu then
		return menu
	end

	if (not params.alpha) or (not params.initialAlpha) then
		params.initialAlpha = 1
	end

	currentColor = ffiPixel({ params.initialColor.r, params.initialColor.g, params.initialColor.b })
	currentAlpha = params.initialAlpha
	local x, y = cursorHelper.getCursorCoorsMenuRelative()

	local context = headingMenu.create({
		id = UIID.menu,
		heading = "Color Picker Menu",
		minWidth = 300,
		absolutePosAlignX = x,
		absolutePosAlignY = y
	})

	local bodyBlock = context.body:createBlock({
		id = tes3ui.registerID("ColorPicker_main_body_container"),
	})
	bodyBlock.autoHeight = true
	bodyBlock.autoWidth = true
	bodyBlock.widthProportional = 1.0
	bodyBlock.paddingLeft = 8
	bodyBlock.paddingRight = 8
	bodyBlock.paddingBottom = 8
	bodyBlock.flowDirection = tes3.flowDirection.topToBottom

	local pickers = createPickerBlock(params, bodyBlock)

	--- @param newColor ffiImagePixel
	--- @param alpha number
	local function onNewColorEntered(newColor, alpha)
		hueChanged(newColor, alpha, pickers.currentPreview, pickers.mainPicker)
		updateIndicatorPositions(newColor, alpha)
	end

	local onNewAlphaEntered
	if params.alpha then
		--- @param newColor ffiImagePixel
		--- @param alpha number
		onNewAlphaEntered = function(newColor, alpha)
			colorSelected(newColor, alpha, pickers.currentPreview)
			updateIndicatorPositions(newColor, alpha)
		end
	end

	if params.showDataRow then
		createDataBlock(params, bodyBlock, onNewColorEntered, onNewAlphaEntered)
	end

	tes3ui.enterMenuMode(UIID.menu)
	context.menu:getTopLevelMenu():updateLayout()
	return context.menu
end

openMenu({
	alpha = true,
	initialColor = { r = 0.5, g = 0.1, b = 0.3 },
	initialAlpha = 0.5,
	showOriginal = true,
	showDataRow = true,

})

-- TODO:
-- Try out oklab conversion functions once again.

