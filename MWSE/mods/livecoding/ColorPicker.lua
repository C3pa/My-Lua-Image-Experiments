local ffi = require("ffi")

local Base = require("livecoding.Base")
local Image = require("livecoding.Image")
local oklab = require("livecoding.oklab")


-- Defined in oklab\init.lua
local ffiPixel = ffi.typeof("RGB") --[[@as fun(init: ffiImagePixelInit?): ffiImagePixel]]


--- @class ColorPickerTextureTable
---	@field main niSourceTexture
---	@field hue niSourceTexture
---	@field alpha niSourceTexture
---	@field previewCurrent niSourceTexture
---	@field previewOriginal niSourceTexture

--- @class ColorPicker
--- @field mainWidth integer Width of the main picker.
--- @field height integer Height of all the picker widgets.
--- @field hueWidth integer Width of hue and alpha pickers.
--- @field previewWidth integer Width of the preview widgets.
--- @field previewHeight integer Height of the preview widgets.
--- @field mainImage Image
--- @field hueBar Image
--- @field alphaCheckerboard Image
--- @field alphaBar Image
--- @field previewCheckerboard Image
--- @field previewImage Image
--- @field textures ColorPickerTextureTable
--- @field currentColor ffiImagePixel
--- @field currentAlpha number
--- @field initialColor ImagePixel
--- @field initialAlpha number
local ColorPicker = Base:new()

--- @class ColorPicker.new.data
--- @field mainWidth integer Width of the main picker. **Remember, to use it as an engine texture use power of 2 dimensions.**
--- @field height integer Height of all the picker widgets. **Remember, to use it as an engine texture use power of 2 dimensions.**
--- @field hueWidth integer Width of hue and alpha pickers. **Remember, to use it as an engine texture use power of 2 dimensions.**
--- @field previewWidth integer Width of the preview widgets. **Remember, to use it as an engine texture use power of 2 dimensions.**
--- @field previewHeight integer Height of the preview widgets. **Remember, to use it as an engine texture use power of 2 dimensions.**
--- @field initialColor ImagePixel
--- @field initialAlpha number? *Default*: 1.0

--- @param data ColorPicker.new.data
--- @return ColorPicker
function ColorPicker:new(data)
	local t = Base:new(data)
	setmetatable(t, self)

	if not data.initialAlpha then
		t.initialAlpha = 1.0
	end

	t.currentColor = ffiPixel({ data.initialColor.r, data.initialColor.g, data.initialColor.b })
	t.currentAlpha = t.initialAlpha

	t.mainImage = Image:new({
		width = data.mainWidth,
		height = data.height,
	})
	local startHSV = oklab.hsvlib_srgb_to_hsv(t.currentColor)
	t.mainImage:mainPicker(startHSV.h)

	t.hueBar = Image:new({
		width = data.hueWidth,
		height = data.height,
	})
	t.hueBar:verticalHueBar()

	t.alphaCheckerboard = Image:new({
		width = data.hueWidth,
		height = data.height,
	})
	t.alphaCheckerboard:toCheckerboard()

	t.alphaBar = Image:new({
		width = data.hueWidth,
		height = data.height,
	})
	t.alphaBar:verticalGradient(
		{ r = 0.25, g = 0.25, b = 0.25, a = 1.0 },
		{ r = 1.0,  g = 1.0,  b = 1.0,  a = 0.0 }
	)
	t.alphaBar = t.alphaBar:blend(t.alphaCheckerboard, true) --[[@as Image]]

	t.previewCheckerboard = Image:new({
		-- Only half of the preview is transparent.
		width = data.previewWidth / 2,
		height = data.previewHeight
	})
	t.previewCheckerboard:toCheckerboard()

	t.previewImage = Image:new({
		-- Only half of the preview is transparent.
		width = data.previewWidth / 2,
		height = data.previewHeight
	})

	-- Create textures for this Color Picker
	t.textures = {
		main = niPixelData.new(data.mainWidth, data.height):createSourceTexture(),
		hue = niPixelData.new(data.hueWidth, data.height):createSourceTexture(),
		alpha = niPixelData.new(data.hueWidth, data.height):createSourceTexture(),
		previewCurrent = niPixelData.new(data.previewWidth / 2, data.previewHeight):createSourceTexture(),
		previewOriginal = niPixelData.new(data.previewWidth / 2, data.previewHeight):createSourceTexture(),
	}
	for _, texture in pairs(t.textures) do
		texture.isStatic = false
	end

	self.__index = self
	return t
end

--- @param color ffiImagePixel
--- @param alpha number
function ColorPicker:setColor(color, alpha)
	self.currentColor = color
	self.currentAlpha = alpha
end

--- @param color ffiImagePixel
function ColorPicker:updateMainImage(color)
	local hsv = oklab.hsvlib_srgb_to_hsv(color)
	self.mainImage:mainPicker(hsv.h)
end

--- @param color ffiImagePixel
--- @param alpha number
function ColorPicker:updatePreviewImage(color, alpha)
	self.previewImage:fillColor(color, alpha)
	self.previewImage = self.previewImage:blend(self.previewCheckerboard, true) --[[@as Image]]
end

return ColorPicker
