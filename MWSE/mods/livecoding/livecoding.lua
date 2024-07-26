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
local format = require("livecoding.formatHelpers")
local headingMenu = require("livecoding.headingMenu")
local Image = require("livecoding.Image")
local oklab = require("livecoding.oklab")
local premultiply = require("livecoding.premultiply")

-- Will export the test images as BMP files for inspecting. This will force all the image
-- dimensions to 200x100.
local EXPORT_IMAGES_BMP = false

if EXPORT_IMAGES_BMP then
	-- TODO
	-- Hack for `saveBMP`
	local parentConstructor = Image.new
	--- @diagnostic disable-next-line: duplicate-set-field
	Image.new = function(self, data)
		data.width = 200
		data.height = 100
		parentConstructor(self, data)
	end
end

-- Defined in oklab\init.lua
local ffiPixel = ffi.typeof("RGB") --[[@as fun(init: ffiImagePixelInit?): ffiImagePixel]]

local PICKER_HEIGHT = 256
local PICKER_MAIN_WIDTH = 256
local PICKER_VERTICAL_COLUMN_WIDTH = 32
local PICKER_PREVIEW_WIDTH = 64
local PICKER_PREVIEW_HEIGHT = 32
local INDICATOR_TEXTURE = "textures\\menu_map_smark.dds"
local INDICATOR_COLOR = { 0.5, 0.5, 0.5 }



--- @class ColorPicker
--- @field mainWidth integer Width of the main picker.
--- @field height integer Height of all the picker widgets.
--- @field hueWidth integer Width of hue and alpha pickers.
--- @field previewWidth integer Width of the preview widgets.
--- @field previewHeight integer Height of the preview widgets.
--- @field startHue number In range [0, 360].
--- @field mainImage Image
--- @field hueBar Image
--- @field alphaCheckerboard Image
--- @field alphaBar Image
--- @field previewCheckerboard Image
--- @field previewForeground Image
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
--- TODO: see if this is OK from API standpoint
--- @field startHue number In range [0, 360].
--- @field initialColor ImagePixel
--- @field initialAlpha number? *Default*: 1.0

--- @param data ColorPicker.new.data
--- @return ColorPicker
function ColorPicker:new(data)
	local t = Base:new(data)
	setmetatable(t, self)

	t.mainImage = Image:new({
		width = data.mainWidth,
		height = data.height,
	})
	t.mainImage:mainPicker(data.startHue)

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
	t.alphaBar = t.alphaCheckerboard:blend(t.alphaBar, 0.5, "over", true) --[[@as Image]]

	t.previewCheckerboard = Image:new({
		-- Only half of the preview is transparent.
		width = data.previewWidth / 2,
		height = data.previewHeight
	})
	t.previewCheckerboard:toCheckerboard()

	t.previewForeground = Image:new({
		-- Only half of the preview is transparent.
		width = data.previewWidth / 2,
		height = data.previewHeight
	})
	if not data.initialAlpha then
		t.initialAlpha = 1.0
	end

	t.currentColor = ffiPixel({ data.initialColor.r, data.initialColor.g, data.initialColor.b })
	t.currentAlpha = t.initialAlpha

	self.__index = self
	return t
end

--- @param color ffiImagePixel
--- @param alpha number
function ColorPicker:setColor(color, alpha)
	self.currentColor = color
	self.currentAlpha = alpha
end

-- local gettime = require("socket").gettime
-- local t1 = gettime()
-- for i = 0, 255 do
-- 	mainImage:mainPicker(i)
-- end
-- local m = string.format("TEST DONE! Time elapsed: %ss", gettime() - t1)
-- mwse.log(m)
-- tes3.messageBox(m)



local picker = ColorPicker:new({
	mainWidth = PICKER_MAIN_WIDTH,
	height = PICKER_HEIGHT,
	hueWidth = PICKER_VERTICAL_COLUMN_WIDTH,
	previewWidth = PICKER_PREVIEW_WIDTH,
	previewHeight = PICKER_PREVIEW_HEIGHT,
	startHue = 60,
	initialColor = { r = 0.5, g = 0.1, b = 0.3 },
	initialAlpha = 0.5,
})


if EXPORT_IMAGES_BMP then
	picker.mainImage:saveBMP("imgMainImage+blackGradient.bmp")
	picker.hueBar:saveBMP("imgHueBar.bmp")
	picker.alphaBar:saveBMP("imgAlphaBar.bmp")
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
	picker.mainImage:mainPicker(hsv.h)
end

--- @param color ffiImagePixel
--- @param alpha number
local function updatePreviewImage(color, alpha)
	picker.previewForeground:fillColor(color, alpha)
	picker.previewForeground = picker.previewCheckerboard:blend(picker.previewForeground, 0.5, "over", true) --[[@as Image]]
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
--- @field initialAlpha? number
--- @field alpha? boolean If true the picker will also allow picking an alpha value.
--- @field showOriginal? boolean If true the picker will show original color below the currently picked color.
--- @field showDataRow? boolean If true the picker will show RGB(A) values of currently picked color in a label below the picker.
--- @field closeCallback? fun(selectedColor: ImagePixel, selectedAlpha: number|nil) Called when the color picker has been closed.

-- TODO: these could use localization.
local strings = {
	["Current"] = "Current",
	["Original"] = "Original",
	["Copy"] = "Copy",
	["%q copied to clipboard."] = "%q copied to clipboard.",
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
	previews.checkersPreview.texture.pixelData:setPixelsFloat(picker.previewForeground:toPixelBufferFloat())
end

--- @param mainPicker tes3uiElement
--- @param newColor ffiImagePixel
local function updateMainPicker(mainPicker, newColor)
	newColor = ffiPixel({ newColor.r, newColor.g, newColor.b })
	updateMainPickerImage(newColor)
	-- mainPicker.imageFilter = false
	mainPicker.texture.pixelData:setPixelsFloat(picker.mainImage:toPixelBufferFloat())
	-- mainPicker:getTopLevelMenu():updateLayout()
	-- mainPicker.imageFilter = false
end

--- @alias IndicatorID
---| "main"
---| "hue"
---| "alpha"
---| "slider"

local function getIndicators()
	local menu = tes3ui.findMenu(UIID.menu)
	--- @cast menu -nil
	local indicatorsUIIDs = {
		"ColorPicker_main_picker_indicator",
		"ColorPicker_hue_picker_indicator",
		"ColorPicker_alpha_picker_indicator",
		"ColorPicker_main_picker_slider",
	}

	--- @type table<IndicatorID, tes3uiElement>
	local indicators = {}
	for _, UIID in ipairs(indicatorsUIIDs) do
		local indicator = menu:findChild(UIID)
		-- Not every Color Picker will have alpha indicator.
		if indicator then
			local id = indicator:getLuaData("indicatorID")
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
	-- Update main picker's slider
	indicators.slider.widget.current = hsv.s * 1000
	indicators.hue:getTopLevelMenu():updateLayout()
end

--- @param newColor ffiImagePixel
--- @param alpha number
local function updateValueInput(newColor, alpha)
	local menu = tes3ui.findMenu(UIID.menu)
	--- @cast menu -nil
	local input = menu:findChild(tes3ui.registerID("ColorPicker_data_row_value_input"))
	if not input then return end

	-- Make sure we don't get NaNs in color text inputs. We clamp alpha here.
	alpha = 1.0 or math.clamp(alpha, 0.0000001, 1.0)

	-- We store color premultiplied by alpha. Let's undo it to not expose this to the user via the UI.
	premultiply.undo(newColor, alpha)

	local newText = ""
	if input:getLuaData("hasAlpha") then
		newText = format.pixelToHex({
			r = newColor.r,
			g = newColor.g,
			b = newColor.b,
			a = alpha,
		})
	else
		newText = format.pixelToHex({
			r = newColor.r,
			g = newColor.g,
			b = newColor.b,
		})
	end
	input.text = newText
end

--- @param newColor ffiImagePixel
--- @param alpha number
--- @param previews ColorPickerPreviewsTable
local function colorSelected(newColor, alpha, previews)
	newColor = ffiPixel({ newColor.r, newColor.g, newColor.b })
	updatePreview(previews, newColor, alpha)
	updateValueInput(newColor, alpha)
end

--- @param newColor ffiImagePixel
--- @param alpha number
--- @param previews ColorPickerPreviewsTable
--- @param mainPicker tes3uiElement
local function hueChanged(newColor, alpha, previews, mainPicker)
	newColor = ffiPixel({ newColor.r, newColor.g, newColor.b })
	updatePreview(previews, newColor, alpha)
	updateMainPicker(mainPicker, newColor)
	updateValueInput(newColor, alpha)
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
	standardPreview.borderLeft = 8

	local checkersPreview = parent:createRect({
		id = tes3ui.registerID("ColorPicker_color_preview_right"),
		color = { 1.0, 1.0, 1.0 },
	})
	checkersPreview.width = PICKER_PREVIEW_WIDTH / 2
	checkersPreview.height = PICKER_PREVIEW_HEIGHT
	checkersPreview.texture = texture
	checkersPreview.imageFilter = false
	checkersPreview.borderRight = 8

	updatePreviewImage(color, alpha)
	checkersPreview.texture.pixelData:setPixelsFloat(picker.previewForeground:toPixelBufferFloat())

	return {
		standardPreview = standardPreview,
		checkersPreview = checkersPreview,
	}
end

--- @param outerContainer tes3uiElement
--- @param label string
local function createPreviewLabel(outerContainer, label)
	local labelContainer = outerContainer:createBlock({
		id = tes3ui.registerID("ColorPicker_color_preview_label_container")
	})
	labelContainer.flowDirection = tes3.flowDirection.topToBottom
	labelContainer.autoWidth = true
	labelContainer.autoHeight = true
	labelContainer.paddingAllSides = 8
	labelContainer:createLabel({
		id = tes3ui.registerID("ColorPicker_color_preview_" .. label ),
		text = strings[label]
	})
end

--- @param parent tes3uiElement
--- @param color ffiImagePixel
--- @param alpha number
--- @param label string
--- @param labelOnTop boolean
--- @param onClickCallback? fun(e: tes3uiEventData)
--- @return ColorPickerPreviewsTable
local function createPreview(parent, color, alpha, label, labelOnTop, onClickCallback)
	-- We don't want to create references to color.
	local color = ffiPixel({ color.r, color.g, color.b })
	local outerContainer = parent:createBlock({ id = tes3ui.registerID("ColorPicker_color_preview_outer_container") })
	outerContainer.flowDirection = tes3.flowDirection.topToBottom
	outerContainer.autoWidth = true
	outerContainer.autoHeight = true

	if labelOnTop then
		createPreviewLabel(outerContainer, label)
	end

	local innerContainer = outerContainer:createBlock({ id = tes3ui.registerID("ColorPicker_color_preview_inner_container") })
	innerContainer.flowDirection = tes3.flowDirection.leftToRight
	innerContainer.autoWidth = true
	innerContainer.autoHeight = true

	local previewTexture = textures["preview" .. label]
	local previews = createPreviewElement(innerContainer, color, alpha, previewTexture)

	if not labelOnTop then
		createPreviewLabel(outerContainer, label)
	end

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


	local pickerContainer = mainRow:createBlock({
		id = tes3ui.registerID("ColorPicker_main_picker_container")
	})
	pickerContainer.autoHeight = true
	pickerContainer.autoWidth = true
	pickerContainer.flowDirection = tes3.flowDirection.topToBottom

	local mainPicker = pickerContainer:createRect({
		id = tes3ui.registerID("ColorPicker_main_picker"),
		color = { 1, 1, 1 },
	})
	mainPicker.borderTop = 8
	mainPicker.borderLeft = 8
	mainPicker.borderRight = 8
	mainPicker.width = PICKER_MAIN_WIDTH
	mainPicker.height = PICKER_HEIGHT
	mainPicker.texture = textures.main
	mainPicker.imageFilter = false

	updateMainPickerImage(initialColor)

	mainPicker.texture.pixelData:setPixelsFloat(picker.mainImage:toPixelBufferFloat())
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

	local slider = pickerContainer:createSlider({
		id = tes3ui.registerID("ColorPicker_main_picker_slider"),
		step = 1,
		jump = 1,
		current = mainIndicatorInitialAbsolutePosAlignX * 1000,
		max = 1000,
	})
	slider.width = PICKER_MAIN_WIDTH
	slider.borderBottom = 8
	slider.borderLeft = 8
	slider.borderRight = 8
	slider:setLuaData("indicatorID", "slider")

	local huePicker = mainRow:createRect({
		id = tes3ui.registerID("ColorPicker_hue_picker"),
		color = { 1, 1, 1 },
	})
	huePicker.borderAllSides = 8
	huePicker.width = PICKER_VERTICAL_COLUMN_WIDTH
	huePicker.height = PICKER_HEIGHT
	huePicker.texture = textures.hue
	huePicker.imageFilter = false
	huePicker.texture.pixelData:setPixelsFloat(picker.hueBar:toPixelBufferFloat())
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
		alphaPicker.texture.pixelData:setPixelsFloat(picker.alphaBar:toPixelBufferFloat())
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

	local currentPreview = createPreview(previewContainer, initialColor, params.initialAlpha, "Current", true)

	-- Implement picking behavior
	mainPicker:register(tes3.uiEvent.mouseStillPressed, function(e)
		local x = math.clamp(e.relativeX, 1, mainPicker.width)
		local y = math.clamp(e.relativeY, 1, mainPicker.height)
		local pickedColor = picker.mainImage:getPixel(x, y)
		picker:setColor(
			-- Make sure we don't create reference to the pixel from the mainImage.
			ffiPixel({ pickedColor.r, pickedColor.g, pickedColor.b }),
			picker.currentAlpha
		)
		colorSelected(picker.currentColor, picker.currentAlpha, currentPreview)

		x = x / mainPicker.width
		y = y / mainPicker.height
		mainIndicator.absolutePosAlignX = x
		mainIndicator.absolutePosAlignY = y
		slider.widget.current = x * 1000
		mainRow:getTopLevelMenu():updateLayout()
	end)
	slider:register(tes3.uiEvent.partScrollBarChanged, function(e)
		local x = math.clamp((slider.widget.current / 1000) * mainPicker.width, 1, mainPicker.width)
		local y = mainIndicator.absolutePosAlignY * mainPicker.height
		local pickedColor = picker.mainImage:getPixel(x, y)
		picker:setColor(
			-- Make sure we don't create reference to the pixel from the mainImage.
			ffiPixel({ pickedColor.r, pickedColor.g, pickedColor.b }),
			picker.currentAlpha
		)
		colorSelected(picker.currentColor, picker.currentAlpha, currentPreview)

		mainIndicator.absolutePosAlignX = x / mainPicker.width
		mainIndicator.absolutePosAlignY = y / mainPicker.height
		mainRow:getTopLevelMenu():updateLayout()
	end)

	huePicker:register(tes3.uiEvent.mouseStillPressed, function(e)
		local x = math.clamp(e.relativeX, 1, huePicker.width)
		local y = math.clamp(e.relativeY, 1, huePicker.height)
		local pickedColor = picker.hueBar:getPixel(x, y)
		picker:setColor(
			-- Make sure we don't create reference to the pixel from the mainImage.
			ffiPixel({ pickedColor.r, pickedColor.g, pickedColor.b }),
			picker.currentAlpha
		)
		colorSelected(picker.currentColor, picker.currentAlpha, currentPreview)
		hueChanged(picker.currentColor, picker.currentAlpha, currentPreview, mainPicker)

		hueIndicator.absolutePosAlignY = y / huePicker.height
		mainRow:getTopLevelMenu():updateLayout()
	end)

	if params.alpha then
		alphaPicker:register(tes3.uiEvent.mouseStillPressed, function(e)
			local y = math.clamp(e.relativeY / alphaPicker.height, 0, 1)
			picker:setColor(picker.currentColor, 1 - y)

			colorSelected(picker.currentColor, picker.currentAlpha, currentPreview)
			alphaIndicator.absolutePosAlignY = y
			mainRow:getTopLevelMenu():updateLayout()
		end)
	end

	if params.showOriginal then
		--- @param e tes3uiEventData
		local function resetColor(e)
			picker:setColor(
				-- Make sure we don't create reference to the pixel from the mainImage.
				ffiPixel({ params.initialColor.r, params.initialColor.g, params.initialColor.b }),
				params.initialAlpha
			)
			hueChanged(picker.currentColor, picker.currentAlpha, currentPreview, mainPicker)

			mainIndicator.absolutePosAlignX = mainIndicatorInitialAbsolutePosAlignX
			mainIndicator.absolutePosAlignY = mainIndicatorInitialAbsolutePosAlignY
			slider.widget.current = mainIndicatorInitialAbsolutePosAlignX * 1000
			hueIndicator.absolutePosAlignY = hueIndicatorInitialAbsolutePosAlignY
			if params.alpha then
				alphaIndicator.absolutePosAlignY = 1 - params.initialAlpha
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

--- Returns the channel value by reading `text` property of given TextInput. Returned value is in range of [0, 1].
--- @param input tes3uiElement
local function getInputValue(input)
	local text = input.text
	local hasAlpha = input:getLuaData("hasAlpha")

	-- Clearing the text input will set the color to 0.
	if text == "" then
		text = hasAlpha and "00000000" or "000000"
	end

	-- Clamp the text length to the correct value.
	local expectedLength = hasAlpha and 8 or 6
	local actualLength = string.len(text)
	local delta = actualLength - expectedLength

	if delta > 0 then
		text = string.sub(text, 1, expectedLength)
	elseif delta < 0 then
		-- If user cleared some characters, fill with 0.
		text = text .. string.rep('0', math.abs(delta))
	end

	return text
end

--- @param params ColorPicker.new.params
--- @param parent tes3uiElement
--- @param onNewColorEntered fun(newColor: ffiImagePixel, alpha: number)
local function createDataBlock(params, parent, onNewColorEntered)
	-- local dataRow = parent:createBlock({
	local dataRow = parent:createThinBorder({
		id = tes3ui.registerID("ColorPicker_data_row_container")
	})
	dataRow.flowDirection = tes3.flowDirection.leftToRight
	dataRow.autoHeight = true
	dataRow.autoWidth = true
	dataRow.widthProportional = 1.0
	dataRow.borderLeft = 12
	dataRow.paddingAllSides = 4
	dataRow.childAlignY = 0.5

	local initialColor = table.copy(params.initialColor) --[[@as ImagePixelA]]
	initialColor.a = params.initialAlpha
	-- We store color premultiplied by alpha. Don't expose this to the user, undo it in the UI.
	premultiply.undoLua(initialColor)

	local text = "RGB: #"
	local inputText = format.pixelToHex(params.initialColor)
	if params.alpha then
		text = "ARGB: #"
		inputText = format.pixelToHex(initialColor)
	end
	dataRow:createLabel({
		id = tes3ui.registerID("ColorPicker_data_row_label"),
		text = text
	})

	local input = dataRow:createTextInput({
		id = tes3ui.registerID("ColorPicker_data_row_value_input"),
		text = inputText,
	})
	input:setLuaData("hasAlpha", params.alpha or false)
	input.autoWidth = true
	input.widthProportional = 1.0

	-- Update color after new value was entered.
	input:registerAfter(tes3.uiEvent.keyEnter, function(e)
		local color = format.hexToPixel(getInputValue(input))
		-- The user might have entered invalid hex code.
		-- Let's reset that channel to the currently selected color.
		color.r = color.r or picker.currentColor.r
		color.g = color.g or picker.currentColor.g
		color.b = color.b or picker.currentColor.b
		color.a = color.a or 1.0
		local pixel = ffiPixel({ color.r, color.g, color.b })
		picker:setColor(pixel, color.a)
		-- Update other parts of the Color Picker
		updateValueInput(pixel, color.a)
		onNewColorEntered(pixel, color.a)
	end)

	local copyButton = dataRow:createButton({
		id = tes3ui.registerID("ColorPicker_data_row_copy_button"),
		text = strings["Copy"],
	})
	copyButton:register(tes3.uiEvent.mouseClick, function(e)
		local text = getInputValue(input)
		os.setClipboardText(text)
		tes3.messageBox(strings["%q copied to clipboard."], text)
	end)

	return {
		input = input,
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

	picker:setColor(
		ffiPixel({ params.initialColor.r, params.initialColor.g, params.initialColor.b }),
		params.initialAlpha
	)
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

	if params.showDataRow then
		createDataBlock(params, bodyBlock, onNewColorEntered)
	end

	context.menu:registerAfter(tes3.uiEvent.destroy, function()
		if params.closeCallback then
			--- @type ImagePixel
			local color = {
				r = picker.currentColor.r,
				g = picker.currentColor.g,
				b = picker.currentColor.b,
			}
			params.closeCallback(color, picker.currentAlpha)
		end
	end)

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
	closeCallback = function (selectedColor, selectedAlpha)
		tes3.messageBox("Selected:\ncolor = %s,\nalpha = %s", format.pixel(selectedColor), selectedAlpha)
	end
})

-- TODO:
-- Expose it as a global function. Something as tes3ui.openColorPickerMenu that opens color picker in a separate menu. I guess that would imply there is only one color picker menu active at a single time.
-- Expose as a widget: tes3uiElement:createColorPicker so modders can embed it into their menus.
-- Add a mwseMCMColorPicker setting

--[[
TODO: Perceptual color spaces. Hrnchamd proposed using Oklab. Some notes he left:

Hrnchamd — Today at 9:03 PM
For any perceptual colour space, there also the issue of out of gamut colours
they should be clamped correctly to sRGB 0-255 output in the code somewhere
e.g. pure blue can't reach high luminance, so there will be a big patch of solid blue or "wrong-looking" colours in the lighter part of the picker

Hrnchamd — Today at 9:05 PM
make sure it 's obvious what's happening because it's not labelled as Oklab and people won't expect it

well, it's easy to not clamp and produce garbage output in C
it will only write the lower bits when casting
--]]

