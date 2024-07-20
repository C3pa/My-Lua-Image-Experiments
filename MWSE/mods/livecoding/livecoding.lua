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
local Image = Base:new()

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

--- Modifies the Image in place.
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

--- Modifies the Image in place.
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

--- Modifies the Image in place.
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

--- Modifies the Image in place.
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

--- Modifies the Image in place.
--- Fills the image into a vertical hue bar.
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

--- Modifies the Image in place.
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

--- Modifies the Image in place.
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

--- Modifies the Image in place.
--- @param color ImagePixel|ImagePixelA
function Image:horizontalColorGradient(color)
	local leftColor = { r = 255, g = 255, b = 255 }
	self:horizontalGradient(leftColor, color)
end

--- Modifies the Image in place.
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

-- https://en.wikipedia.org/wiki/Alpha_compositing#Description
local function colorBlend(cA, cB, alphaA, alphaB, alphaO)
	return (cA * alphaA + cB * alphaB * (1 - alphaA)) / alphaO
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

--- Returns a copy with the result of blending between the two images
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

function Image:toPixelBufferFloat()
	local size = self.width * self.height
	-- local buffer = table.new(size * 4, 0)
	local buffer = {}
	local offset = 0

	for y = 1, self.height do
		local row = self.data[y]
		for x = 1, self.width do
			local pixel = row[x]
			buffer[offset + 1] = pixel.r / 255
			buffer[offset + 2] = pixel.g / 255
			buffer[offset + 3] = pixel.b / 255
			buffer[offset + 4] = pixel.a
			offset = offset + 4
		end
	end

	return buffer
end

function Image:toPixelBufferByte()
	local size = self.width * self.height
	-- local buffer = table.new(size * 4, 0)
	local buffer = {}
	local offset = 0

	for y = 1, self.height do
		local row = self.data[y]
		for x = 1, self.width do
			local pixel = row[x]

			buffer[offset + 1] = pixel.r
			buffer[offset + 2] = pixel.g
			buffer[offset + 3] = pixel.b
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
			local b = math.round(pixel.b * alpha)
			local g = math.round(pixel.g * alpha)
			local r = math.round(pixel.r * alpha)
			-- mwse.log("(%s, %s, %s)", r, g, b)
			writeBytes(file, b, g, r)
		end
	end
	file:close()
end


local PICKER_HEIGHT = 150
local PICKER_MAIN_WIDTH = 256
local PICKER_VERTICAL_COLUMN_WIDTH = 15

local img1 = Image:new({
	width = PICKER_MAIN_WIDTH,
	height = PICKER_HEIGHT,
})

-- Base for the main color picker image.
img1:horizontalColorGradient({ r = 255, g = 0, b = 0 })

local img2 = Image:new({
	width = PICKER_MAIN_WIDTH,
	height = PICKER_HEIGHT,
})

-- Black overlay for the main color picker image.
img2:verticalGrayGradient()

-- The main color picker image.
local blended = img2:blend(img1, 0.5, "plus")

local hueBar = Image:new({
	width = PICKER_VERTICAL_COLUMN_WIDTH,
	height = PICKER_HEIGHT,
})
hueBar:verticalHueBar()

local alphaBar = Image:new({
	width = PICKER_VERTICAL_COLUMN_WIDTH,
	height = PICKER_HEIGHT,
})
alphaBar:verticalGradient({ r = 0, g = 0, b = 0 }, { r = 255, g = 255, b = 255 })

if EXPORT_IMAGES_BMP then
	img2:saveBMP("img2.bmp")
	img1:saveBMP("img1.bmp")
	blended:saveBMP("img1+img2.bmp")
	hueBar:saveBMP("imgHueBar.bmp")
	alphaBar:saveBMP("imgAlphaBar.bmp")
end


local textures = {
	main = niPixelData.new(PICKER_MAIN_WIDTH, PICKER_HEIGHT):createSourceTexture(),
	hue = niPixelData.new(PICKER_VERTICAL_COLUMN_WIDTH, PICKER_HEIGHT):createSourceTexture(),
	alpha = niPixelData.new(PICKER_VERTICAL_COLUMN_WIDTH, PICKER_HEIGHT):createSourceTexture(),
}
for _, texture in pairs(textures) do
	texture.isStatic = false
end

--- @param color ImagePixel
local function updateMainPickerImage(color)
	img1:horizontalColorGradient(color)
	blended = img2:blend(img1, 0.5, "plus")
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

local function openMenu()
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

	-- Main body
	local bodyBlock = context.body:createBlock()
	bodyBlock.autoHeight = true
	bodyBlock.autoWidth = true
	bodyBlock.widthProportional = 1.0
	bodyBlock.paddingLeft = 8
	bodyBlock.paddingRight = 8
	bodyBlock.paddingBottom = 8
	bodyBlock.flowDirection = tes3.flowDirection.topToBottom

	local mainRrow = bodyBlock:createBlock()
	mainRrow.flowDirection = tes3.flowDirection.leftToRight
	mainRrow.autoHeight = true
	mainRrow.autoWidth = true
	mainRrow.widthProportional = 1.0
	mainRrow.paddingAllSides = 4

	local mainPicker = mainRrow:createRect({ color = { 1, 1, 1 } })
	mainPicker.width = PICKER_MAIN_WIDTH
	mainPicker.height = PICKER_HEIGHT
	mainPicker.texture = textures.main
	mainPicker.texture.pixelData:setPixelsByte(blended:toPixelBufferByte())
	-- local buffer = blended:toPixelBufferFloat()
	-- mainPicker.texture.pixelData:setPixelsFloat(buffer)

	context.menu:registerAfter(tes3.uiEvent.mouseStillPressedOutside, function (e)
		context.menu:destroy()
		tes3ui.leaveMenuMode()
	end)
	tes3ui.enterMenuMode(UIID.menu)
	context.menu:getTopLevelMenu():updateLayout()
	return context.menu
end

openMenu()
