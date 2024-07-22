--[[
	run code without restarting the game! hotkey alt+x
--]]

tes3.messageBox("Hello World")
mwse.log("Reset!")

local inspect = require("inspect")
local logger = require("logging.logger")

local Base = require("livecoding.Base")
local cursorHelper = require("livecoding.cursorHelper")
local headingMenu = require("livecoding.headingMenu")

-- Will export the test images as BMP files for inspecting. This will force all the image
-- dimensions to 200x100.
local EXPORT_IMAGES_BMP = false

--- @class ImagePixel
--- @field r number Red in range [0, 1].
--- @field g number Green in range [0, 1].
--- @field b number Blue in range [0, 1].

--- @class ImagePixelA : ImagePixel
--- @field a number Alpha in range [0, 1].

--- @alias ImagePixelArgument ImagePixel|ImagePixelA

--- Pixel storing the color in premultiplied format.
--- @class PremulImagePixelA : ImagePixelA

--- @alias ImageRow PremulImagePixelA[]
--- @alias ImageData ImageRow[]

--- An image helper class that stores RGBA color in premultiplied alpha format.
--- @class Image
--- @field width integer
--- @field height integer
--- @field data ImageData
local Image = Base:new()

--- @class Image.new.data
--- @field width integer **Remember, to use it as an engine texture use power of 2 dimensions.**
--- @field height integer **Remember, to use it as an engine texture use power of 2 dimensions.**
--- @field data ImageData?

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

--- Returns a copy of a pixel with given coordinates.
--- @param x integer Horizontal coordinate
--- @param y integer Vertical coordinate
--- @return PremulImagePixelA
function Image:getPixel(x, y)
	return table.copy(self.data[y][x])
end

--- @param x integer Horizontal coordinate
--- @param y integer Vertical coordinate
--- @param color PremulImagePixelA
function Image:setPixel(x, y, color)
	self.data[y][x] = color
end

--- Modifies the Image in place.
--- @param data ImageData
function Image:fill(data)
	for y = 1, self.height do
		for x = 1, self.width do
			table.copy(data[y][x], self.data[y][x])
		end
	end
end

--- Converts `ImagePixelA` to `PremulImagePixelA`.
--- @param pixel ImagePixelA
local function premultiply(pixel)
	pixel.r = pixel.r * pixel.a
	pixel.g = pixel.g * pixel.a
	pixel.b = pixel.b * pixel.a
end

--- Modifies the Image in place. Will premultiply the color channels with alpha value.
--- @param color ImagePixelArgument
function Image:fillColor(color)
	color.a = color.a or 1
	premultiply(color)
	--- @cast color PremulImagePixelA

	for y = 1, self.height do
		local row = self.data[y]
		for x = 1, self.width do
			table.copy(color, row[x])
		end
	end
end

--- Modifies the Image in place. Works with **premultiplied** color.
--- @param rowIndex integer
--- @param color PremulImagePixelA
function Image:fillRow(rowIndex, color)
	color.a = color.a or 1

	local row = self.data[rowIndex]
	for x = 1, self.width do
		table.copy(color, row[x])
	end
end

--- Modifies the Image in place. Works with **premultiplied** color.
--- @param columnIndex integer
--- @param color PremulImagePixelA
function Image:fillColumn(columnIndex, color)
	color.a = color.a or 1

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

--- Modifies the Image in place.
--- Fills the image into a vertical hue bar.
function Image:verticalHueBar()
	--- @type PremulImagePixelA
	local color = { r = 1, g = 0, b = 0, a = 1 }
	for y = 1, self.height do
		local t = y / self.height
		self:fillRow(y, color)

		if t < hueSection.first then
			color.g = math.lerp(0, 1, (t / hueSection.first))
		elseif t < hueSection.second then
			color.r = math.lerp(1, 0, ((t - hueSection.first) / hueSection.first))
		elseif t < hueSection.third then
			color.b = math.lerp(0, 1, ((t - hueSection.second) / hueSection.first))
		elseif t < hueSection.fourth then
			color.g = math.lerp(1, 0, ((t - hueSection.third) / hueSection.first))
		elseif t < hueSection.fifth then
			color.r = math.lerp(0, 1, ((t - hueSection.fourth) / hueSection.first))
		else
			color.b = math.lerp(1, 0, ((t - hueSection.fifth) / hueSection.first))
		end
	end
end

--- Modifies the Image in place. Will premultiply the color channels with alpha value.
--- @param leftColor ImagePixelArgument
--- @param rightColor ImagePixelArgument
function Image:horizontalGradient(leftColor, rightColor)
	leftColor.a = leftColor.a or 1
	rightColor.a = rightColor.a or 1
	premultiply(leftColor)
	premultiply(rightColor)
	--- @cast leftColor PremulImagePixelA
	--- @cast rightColor PremulImagePixelA

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

--- Modifies the Image in place. Will premultiply the color channels with alpha value.
--- @param topColor ImagePixelArgument
--- @param bottomColor ImagePixelArgument
function Image:verticalGradient(topColor, bottomColor)
	topColor.a = topColor.a or 1
	bottomColor.a = bottomColor.a or 1
	premultiply(topColor)
	premultiply(bottomColor)
	--- @cast topColor PremulImagePixelA
	--- @cast bottomColor PremulImagePixelA

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
	--- @type PremulImagePixelA
	local lightGray = lightGray or { r = 0.7, g = 0.7, b = 0.7, a = 1 }
	--- @type PremulImagePixelA
	local darkGray = darkGray or { r = 0.5, g = 0.5, b = 0.5, a = 1 }
	local doubleSize = 2 * size

	for y = 1, self.height do
		local row = self.data[y]
		for x = 1, self.width do
			-- -1 is compensation for indexing starting at 1.
			if (((y - 1) % doubleSize) < size) then
				if (((x - 1) % doubleSize) < size) then
					table.copy(lightGray, row[x])
				else
					table.copy(darkGray, row[x])
				end
			else
				if (((x - 1) % doubleSize) < size) then
					table.copy(darkGray, row[x])
				else
					table.copy(lightGray, row[x])
				end
			end

		end
	end
end

function Image:copy()
	-- Don't use table.deepCopy here, it causes lag when dragging the hue picker.
	-- Manually copying row by row helps.
	local data = table.new(self.height, 0)
	for y = 1, self.height do
		data[y] = table.new(self.width, 0)
		table.copy(self.data[y], data[y])
	end

	local new = Image:new({
		height = self.height,
		width = self.width,
		data = data,
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
	--- @type Image|nil
	local new
	if copy then
		new = self:copy()
		data = new.data
	end
	local blend = blend[type]
	for y = 1, self.height do
		local rowA = data[y]
		local rowB = image.data[y]
		for x = 1, self.width do
			rowA[x] = blend(rowA[x], rowB[x], coeff)
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
	local offset = 0

	for y = 1, self.height do
		local row = self.data[y]
		for x = 1, self.width do
			local pixel = row[x]
			buffer[offset + 1] = pixel.r
			buffer[offset + 2] = pixel.g
			buffer[offset + 3] = pixel.b
			-- buffer[offset + 4] = 1
			buffer[offset + 4] = pixel.a
			offset = offset + 4
		end
	end

	return buffer
end

--- For feeding data straight to `niPixelData:setPixelsByte`.
function Image:toPixelBufferByte()
	local size = self.width * self.height
	local buffer = table.new(size * niPixelData_BYTES_PER_PIXEL, 0)
	local offset = 0

	for y = 1, self.height do
		local row = self.data[y]
		for x = 1, self.width do
			local pixel = row[x]

			buffer[offset + 1] = pixel.r * 255
			buffer[offset + 2] = pixel.g * 255
			buffer[offset + 3] = pixel.b * 255
			-- buffer[offset + 4] = 255
			buffer[offset + 4] = pixel.a * 255
			offset = offset + 4
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

	for y = self.height, 1, -1 do
		local row = self.data[y]
		for x = 1, self.width do
			local pixel = row[x]
			local alpha = pixel.a
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
mainImage:horizontalColorGradient({ r = 0, g = 1, b = 0 })

-- Black overlay for the main color picker image.
local blackGradient = Image:new({
	width = PICKER_MAIN_WIDTH,
	height = PICKER_HEIGHT,
})
blackGradient:verticalGrayGradient()

-- The main color picker image.
mainImage:blend(blackGradient, 0.5, "over")

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
alphaBar:verticalGradient({ r = 0.35, g = 0.35, b = 0.35, a = 1.0 }, { r = 1, g = 1, b = 1, a = 0.0 })
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
	blackGradient:saveBMP("blackGradient.bmp")
	mainImage:saveBMP("mainImage+blackGradient.bmp")
	hueBar:saveBMP("imgHueBar.bmp")
	alphaBar:saveBMP("imgAlphaBar.bmp")
end


--------------------------------------
--- Color space conversion helpers ---
--------------------------------------

--- Returned values are: H in range [0, 360], s [0, 1], v [0, 1]
--- @param rgb ImagePixel
function RGBtoHSV(rgb)
	local Cmax = math.max(rgb.r, rgb.g, rgb.b)
	local Cmin = math.min(rgb.r, rgb.g, rgb.b)
	local delta = Cmax - Cmin
	local h
	if rgb.r > rgb.g and rgb.r > rgb.b then
		h = 60 * (((rgb.g - rgb.b) / delta) % 6)
	elseif rgb.g > rgb.r and rgb.g > rgb.b then
		h = 60 * (((rgb.b - rgb.r) / delta) + 2)
	else
		h = 60 * (((rgb.r - rgb.g) / delta) + 4)
	end
	local s
	if Cmax == 0 then
		s = 0
	else
		s = delta / Cmax
	end

	return {
		h = h,
		s = s,
		v = Cmax,
	}
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

--- @param color ImagePixelArgument
local function updateMainPickerImage(color)
	color = table.copy(color)
	-- Main picker shouldn't be transparent
	color.a = 1.0
	mainImage:horizontalColorGradient(color)
	mainImage:blend(blackGradient, 0.5, "over")
end

--- @param color ImagePixelArgument
local function updatePreviewImage(color)
	previewForeground:fillColor(color)
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
--- @field alpha boolean? If true the picker will also allow picking an alpha value.
--- @field showOriginal boolean? If true the picker will show original color below the currently picked color.
--- @field showDataRow boolean? If true the picker will show RGB(A) values of currently picked color in a label below the picker.
--- @field initialColor PremulImagePixelA


--- @param pixel PremulImagePixelA
local function formatPixelA(pixel)
	return string.format(
		"R: %.0f %%, G: %.0f %%, B: %.0f %%, A: %.0f %%",
		pixel.r * 100, pixel.g * 100, pixel.b * 100, pixel.a * 100
	)
end
--- @param pixel PremulImagePixelA
local function formatPixel(pixel)
	return string.format(
		"R: %.0f %%, G: %.0f %%, B: %.0f %%",
		pixel.r * 100, pixel.g * 100, pixel.b * 100
	)
end

-- TODO: these could use localization.
local strings = {
	["Current"] = "Current",
	["Original"] = "Original",
}

--- @class ColorPickerPreviewsTable
--- @field standardPreview tes3uiElement
--- @field checkersPreview tes3uiElement


--- @param previews ColorPickerPreviewsTable
--- @param newColor ImagePixelA
local function updatePreview(previews, newColor)
	newColor = table.copy(newColor) --[[@as ImagePixelA]]
	previews.standardPreview.color = { newColor.r, newColor.g, newColor.b }
	previews.standardPreview:updateLayout()
	updatePreviewImage(newColor)
	previews.checkersPreview.texture.pixelData:setPixelsFloat(previewForeground:toPixelBufferFloat())
end

--- @param mainPicker tes3uiElement
--- @param newColor ImagePixelA
local function updateMainPicker(mainPicker, newColor)
	newColor = table.copy(newColor) --[[@as ImagePixelA]]
	updateMainPickerImage(newColor)
	-- mainPicker.imageFilter = false
	mainPicker.texture.pixelData:setPixelsFloat(mainImage:toPixelBufferFloat())
	-- mainPicker:getTopLevelMenu():updateLayout()
	-- mainPicker.imageFilter = false
end

--- @type PremulImagePixelA
local currentColor

--- @param newColor ImagePixelA
--- @param previews ColorPickerPreviewsTable
local function colorSelected(newColor, previews)
	currentColor = table.copy(newColor) --[[@as PremulImagePixelA]]
	updatePreview(previews, newColor)
end

--- @param newColor ImagePixelA
--- @param previews ColorPickerPreviewsTable
--- @param mainPicker tes3uiElement
local function hueChanged(newColor, previews, mainPicker)
	currentColor = table.copy(newColor) --[[@as PremulImagePixelA]]
	updatePreview(previews, newColor)
	updateMainPicker(mainPicker, newColor)
end

--- @param parent tes3uiElement
--- @param color PremulImagePixelA
--- @param texture niSourceTexture
--- @return ColorPickerPreviewsTable
local function createPreviewElement(parent, color, texture)
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

	updatePreviewImage(color)
	checkersPreview.texture.pixelData:setPixelsFloat(previewForeground:toPixelBufferFloat())

	return {
		standardPreview = standardPreview,
		checkersPreview = checkersPreview,
	}
end

--- @param parent tes3uiElement
--- @param color PremulImagePixelA
--- @param label string
--- @param onClickCallback? fun(e: tes3uiEventData)
--- @return ColorPickerPreviewsTable
local function createPreview(parent, color, label, onClickCallback)
	color = table.copy(color)

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
	local previews = createPreviewElement(innerContainer, color, previewTexture)

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
	local mainRow = parent:createBlock({
		id = tes3ui.registerID("ColorPicker_picker_row_container")
	})
	mainRow.flowDirection = tes3.flowDirection.leftToRight
	mainRow.autoHeight = true
	mainRow.autoWidth = true
	mainRow.widthProportional = 1.0
	mainRow.paddingAllSides = 4

	local initialHSV = RGBtoHSV(params.initialColor)
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

	updateMainPickerImage(params.initialColor)

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
		alphaIndicator.absolutePosAlignY = 1 - params.initialColor.a
	end

	local previewContainer = mainRow:createBlock({ id = tes3ui.registerID("ColorPicker_color_preview_container") })
	previewContainer.flowDirection = tes3.flowDirection.topToBottom
	previewContainer.autoWidth = true
	previewContainer.autoHeight = true

	local currentPreview = createPreview(previewContainer, params.initialColor, "Current")

	-- Implement picking behavior
	mainPicker:register(tes3.uiEvent.mouseStillPressed, function(e)
		local x = math.clamp(e.relativeX, 1, mainPicker.width)
		local y = math.clamp(e.relativeY, 1, mainPicker.height)
		local color = mainImage:getPixel(x, y)
		-- Make sure we don't change current alpha value in this picker.
		color.a = currentColor.a
		colorSelected(color, currentPreview)

		mainIndicator.absolutePosAlignX = x / mainPicker.width
		mainIndicator.absolutePosAlignY = y / mainPicker.height
		mainRow:getTopLevelMenu():updateLayout()
	end)

	huePicker:register(tes3.uiEvent.mouseStillPressed, function(e)
		local x = math.clamp(e.relativeX, 1, mainPicker.width)
		local y = math.clamp(e.relativeY, 1, mainPicker.height)
		local color = hueBar:getPixel(x, y)
		-- Make sure we don't change current alpha value in this picker.
		color.a = currentColor.a
		hueChanged(color, currentPreview, mainPicker)

		hueIndicator.absolutePosAlignY = y / huePicker.height
		mainRow:getTopLevelMenu():updateLayout()
	end)

	if params.alpha then
		alphaPicker:register(tes3.uiEvent.mouseStillPressed, function(e)
			local y = math.clamp(e.relativeY / alphaPicker.height, 0, 1)
			local newColor = table.copy(currentColor)
			newColor.a = 1 - y
			colorSelected(newColor, currentPreview)

			alphaIndicator.absolutePosAlignY = y
			mainRow:getTopLevelMenu():updateLayout()
		end)
	end

	if params.showOriginal then
		--- @param e tes3uiEventData
		local function resetColor(e)
			hueChanged(params.initialColor, currentPreview, mainPicker)

			mainIndicator.absolutePosAlignX = mainIndicatorInitialAbsolutePosAlignX
			mainIndicator.absolutePosAlignY = mainIndicatorInitialAbsolutePosAlignY
			hueIndicator.absolutePosAlignY = hueIndicatorInitialAbsolutePosAlignY
			alphaIndicator.absolutePosAlignY = 1 - params.initialColor.a
			mainRow:getTopLevelMenu():updateLayout()
		end
		createPreview(previewContainer, params.initialColor, "Original", resetColor)
	end

	colorSelected(params.initialColor, currentPreview)
	mainRow:getTopLevelMenu():updateLayout()
	mainPicker.imageFilter = false
	huePicker.imageFilter = false
	if alphaPicker then
		alphaPicker.imageFilter = false
	end
	return {
		mainPicker = mainPicker,
		huePicker = huePicker,
		alphaPicker = alphaPicker
	}
end

--- @param params ColorPicker.new.params
--- @param parent tes3uiElement
local function createDataBlock(params, parent)
	local initialColor = params.initialColor
	local pixelToString = formatPixelA
	if not params.alpha then
		pixelToString = formatPixel
	end

	local dataRow = parent:createBlock({
		id = tes3ui.registerID("ColorPicker_data_row_container")
	})
	dataRow.flowDirection = tes3.flowDirection.leftToRight
	dataRow.autoHeight = true
	dataRow.autoWidth = true
	dataRow.widthProportional = 1.0
	dataRow.paddingAllSides = 4

	local valueLabel = dataRow:createLabel({
		id = tes3ui.registerID("ColorPicker_ValueLabel"),
		text = pixelToString(initialColor)
	})
	valueLabel.autoHeight = true
	valueLabel.autoWidth = true

	return {
		valueLabel = valueLabel,
	}
end

--- @param params ColorPicker.new.params
local function openMenu(params)
	local initialColor = params.initialColor
	local menu = tes3ui.findMenu(UIID.menu)
	if menu then
		return menu
	end
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
	if params.showDataRow then
		local dataBlock = createDataBlock(params, bodyBlock)
	end

	context.menu:registerAfter(tes3.uiEvent.mouseStillPressedOutside, function (e)
		context.menu:destroy()
		tes3ui.leaveMenuMode()
	end)
	tes3ui.enterMenuMode(UIID.menu)
	context.menu:getTopLevelMenu():updateLayout()
	return context.menu
end

-- TODO: main points left:
-- Improve data row

openMenu({
	alpha = true,
	initialColor = { r = 0.5, g = 0.1, b = 0.3, a = 0.4 },
	showOriginal = true,
	showDataRow = true,

})
