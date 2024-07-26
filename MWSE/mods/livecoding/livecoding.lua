--[[
	run code without restarting the game! hotkey alt+x
--]]

tes3.messageBox("Hello World")
mwse.log("Reset!")

local ffi = require("ffi")
local inspect = require("inspect")
local logger = require("logging.logger")

local Base = require("livecoding.Base")
local ColorPicker = require("livecoding.ColorPicker")
local cursorHelper = require("livecoding.cursorHelper")
local format = require("livecoding.formatHelpers")
local headingMenu = require("livecoding.headingMenu")
local Image = require("livecoding.Image")
local oklab = require("livecoding.oklab")
local premultiply = require("livecoding.premultiply")

-- Defined in oklab\init.lua
local ffiPixel = ffi.typeof("RGB") --[[@as fun(init: ffiImagePixelInit?): ffiImagePixel]]

local PICKER_HEIGHT = 256
local PICKER_MAIN_WIDTH = 256
local PICKER_VERTICAL_COLUMN_WIDTH = 32
local PICKER_PREVIEW_WIDTH = 64
local PICKER_PREVIEW_HEIGHT = 32
local INDICATOR_TEXTURE = "textures\\menu_map_smark.dds"
local INDICATOR_COLOR = { 0.5, 0.5, 0.5 }

local UIID = {
	menu = tes3ui.registerID("testing:Menu"),
	pickerMenu = tes3ui.registerID("testing:pickerMenu"),
	indicator = {
		main = tes3ui.registerID("ColorPicker_main_picker_indicator"),
		hue = tes3ui.registerID("ColorPicker_hue_picker_indicator"),
		alpha = tes3ui.registerID("ColorPicker_alpha_picker_indicator"),
		slider = tes3ui.registerID("ColorPicker_main_picker_slider"),
	}
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

--- @class openColorPickerMenu.new.params
--- @field initialColor ImagePixel
--- @field initialAlpha? number
--- @field alpha? boolean If true the picker will also allow picking an alpha value.
--- @field showOriginal? boolean If true the picker will show original color below the currently picked color.
--- @field showDataRow? boolean If true the picker will show RGB(A) values of currently picked color in a label below the picker.
--- @field closeCallback? fun(selectedColor: ImagePixel, selectedAlpha: number|nil) Called when the color picker has been closed.

-- TODO: these could use localization.
local strings = {
	["Color Picker Menu"] = "Color Picker Menu",
	["Current"] = "Current",
	["Original"] = "Original",
	["Copy"] = "Copy",
	["%q copied to clipboard."] = "%q copied to clipboard.",
	["RGB: #"] = "RGB: #",
	["ARGB: #"] = "ARGB: #",
}

--- @class ColorPickerPreviewsTable
--- @field standardPreview tes3uiElement
--- @field checkersPreview tes3uiElement


--- @param picker ColorPicker
--- @param previews ColorPickerPreviewsTable
--- @param newColor ffiImagePixel
--- @param alpha number
local function updatePreview(picker, previews, newColor, alpha)
	previews.standardPreview.color = { newColor.r, newColor.g, newColor.b }
	previews.standardPreview:updateLayout()
	picker:updatePreviewImage(newColor, alpha)
	previews.checkersPreview.texture.pixelData:setPixelsFloat(picker.previewImage:toPixelBufferFloat())
end

--- @alias IndicatorID
---| "main"
---| "hue"
---| "alpha"
---| "slider"

local function getIndicators()
	local menu = tes3ui.findMenu(UIID.menu)
	--- @cast menu -nil

	--- @type table<IndicatorID, tes3uiElement>
	local indicators = {}
	for _, UIID in pairs(UIID.indicator) do
		local indicator = menu:findChild(UIID)
		-- Not every Color Picker will have alpha indicator.
		if indicator then
			local id = indicator:getLuaData("indicatorID")
			indicators[id] = indicator
		end
	end
	return indicators
end

--- @param newColor ffiImagePixel
--- @param alpha number?
local function updateIndicatorPositions(newColor, alpha)
	local hsv = oklab.hsvlib_srgb_to_hsv(newColor)
	local indicators = getIndicators()
	indicators.main.absolutePosAlignX = hsv.s
	indicators.main.absolutePosAlignY = 1 - hsv.v
	indicators.hue.absolutePosAlignY = hsv.h / 360
	if indicators.alpha then
		indicators.alpha.absolutePosAlignY = 1 - alpha
	end
	-- Update main picker's slider
	indicators.slider.widget.current = hsv.s * 1000
	indicators.hue:getTopLevelMenu():updateLayout()
end

--- @param newColor ffiImagePixel|ImagePixel|ImagePixelA
--- @param alpha number
local function updateValueInput(newColor, alpha)
	local menu = tes3ui.findMenu(UIID.menu)
	--- @cast menu -nil
	local input = menu:findChild(tes3ui.registerID("ColorPicker_data_row_value_input"))
	if not input then return end

	-- Make sure we don't get NaNs in color text inputs. We clamp alpha here.
	if alpha then
		alpha = math.clamp(alpha, 0.0000001, 1.0)
	end

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

--- Used to update current preview color and the text shown in the value input.
--- Usually used when after a color was picked in the main or alpha pickers.
--- @param picker ColorPicker
--- @param newColor ffiImagePixel
--- @param alpha number
--- @param previews ColorPickerPreviewsTable
local function colorSelected(picker, newColor, alpha, previews)
	-- Make sure we don't create reference to the pixel picked from the mainImage.
	-- We construct a new ffiPixel.
	newColor = ffiPixel({ newColor.r, newColor.g, newColor.b })
	picker:setColor(newColor, alpha)
	updatePreview(picker, previews, newColor, alpha)
	updateValueInput(newColor, alpha)
end

--- Used when a color with different Hue was picked.
--- @param picker ColorPicker
--- @param newColor ffiImagePixel|ImagePixel
--- @param alpha number
--- @param previews ColorPickerPreviewsTable
--- @param mainPicker tes3uiElement
local function hueChanged(picker, newColor, alpha, previews, mainPicker)
	-- Make sure we don't create reference to the pixel picked from the mainImage.
	-- We construct a new ffiPixel.
	newColor = ffiPixel({ newColor.r, newColor.g, newColor.b })
	colorSelected(picker, newColor, alpha, previews)
	-- Now, also need to regenerate the image for the main picker since the Hue changed.
	picker:updateMainImage(newColor)
	mainPicker.texture.pixelData:setPixelsFloat(picker.mainImage:toPixelBufferFloat())
end

--- @param picker ColorPicker
--- @param parent tes3uiElement
--- @param color ffiImagePixel
--- @param alpha number
--- @param texture niSourceTexture
--- @return ColorPickerPreviewsTable
local function createPreviewElement(picker, parent, color, alpha, texture)
	local standardPreview = parent:createRect({
		id = tes3ui.registerID("ColorPicker_color_preview_left"),
		color = { color.r, color.g, color.b },
	})
	standardPreview.width = picker.previewWidth / 2
	standardPreview.height = picker.previewHeight
	standardPreview.borderLeft = 8

	local checkersPreview = parent:createRect({
		id = tes3ui.registerID("ColorPicker_color_preview_right"),
		color = { 1.0, 1.0, 1.0 },
	})
	checkersPreview.width = picker.previewWidth / 2
	checkersPreview.height = picker.previewHeight
	checkersPreview.texture = texture
	checkersPreview.imageFilter = false
	checkersPreview.borderRight = 8

	picker:updatePreviewImage(color, alpha)
	checkersPreview.texture.pixelData:setPixelsFloat(picker.previewImage:toPixelBufferFloat())

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

--- @param picker ColorPicker
--- @param parent tes3uiElement
--- @param color ffiImagePixel
--- @param alpha number
--- @param label string
--- @param labelOnTop boolean
--- @param onClickCallback? fun(e: tes3uiEventData)
--- @return ColorPickerPreviewsTable
local function createPreview(picker, parent, color, alpha, label, labelOnTop, onClickCallback)
	-- We don't want to create references to color.
	local color = ffiPixel({ color.r, color.g, color.b })
	local outerContainer = parent:createBlock({ id = tes3ui.registerID("ColorPicker_color_preview_outer_container") })
	outerContainer.flowDirection = tes3.flowDirection.topToBottom
	outerContainer.autoWidth = true
	outerContainer.autoHeight = true

	if labelOnTop then
		createPreviewLabel(outerContainer, label)
	end

	local innerContainer = outerContainer:createBlock({
		id = tes3ui.registerID("ColorPicker_color_preview_inner_container")
	})
	innerContainer.flowDirection = tes3.flowDirection.leftToRight
	innerContainer.autoWidth = true
	innerContainer.autoHeight = true

	local previewTexture = picker.textures["preview" .. label]
	local previews = createPreviewElement(picker, innerContainer, color, alpha, previewTexture)

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


--- @param parent tes3uiElement
--- @param id string
--- @param absolutePosAlignX number
--- @param absolutePosAlignY number
local function createIndicator(parent, id, absolutePosAlignX, absolutePosAlignY)
	local indicator = parent:createImage({
		id = UIID.indicator[id],
		path = INDICATOR_TEXTURE,
	})
	indicator.color = INDICATOR_COLOR
	indicator.absolutePosAlignX = absolutePosAlignX
	indicator.absolutePosAlignY = absolutePosAlignY
	indicator:setLuaData("indicatorID", id)
	return indicator
end

--- @param params openColorPickerMenu.new.params
--- @param picker ColorPicker
--- @param parent tes3uiElement
local function createPickerBlock(params, picker, parent)
	local initialColor = ffiPixel({ params.initialColor.r, params.initialColor.g, params.initialColor.b })

	local mainRow = parent:createBlock({ id = tes3ui.registerID("ColorPicker_picker_row_container") })
	mainRow.flowDirection = tes3.flowDirection.leftToRight
	mainRow.autoHeight = true
	mainRow.autoWidth = true
	mainRow.widthProportional = 1.0
	mainRow.paddingAllSides = 4

	local initialHSV = oklab.hsvlib_srgb_to_hsv(initialColor)
	local mainIndicatorInitialAbsolutePosAlignX = initialHSV.s
	local mainIndicatorInitialAbsolutePosAlignY = 1 - initialHSV.v
	local hueIndicatorInitialAbsolutePosAlignY = initialHSV.h / 360


	local pickerContainer = mainRow:createBlock({ id = tes3ui.registerID("ColorPicker_main_picker_container") })
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
	mainPicker.width = picker.mainWidth
	mainPicker.height = picker.height
	mainPicker.texture = picker.textures.main
	mainPicker.imageFilter = false
	mainPicker.texture.pixelData:setPixelsFloat(picker.mainImage:toPixelBufferFloat())
	mainPicker:register(tes3.uiEvent.mouseDown, function(e)
		tes3ui.captureMouseDrag(true)
	end)
	mainPicker:register(tes3.uiEvent.mouseRelease, function(e)
		tes3ui.captureMouseDrag(false)
	end)
	local mainIndicator = createIndicator(
		mainPicker,
		"main",
		mainIndicatorInitialAbsolutePosAlignX,
		mainIndicatorInitialAbsolutePosAlignY
	)
	local slider = pickerContainer:createSlider({
		id = UIID.indicator.slider,
		step = 1,
		jump = 1,
		current = mainIndicatorInitialAbsolutePosAlignX * 1000,
		max = 1000,
	})
	slider.width = picker.mainWidth
	slider.borderBottom = 8
	slider.borderLeft = 8
	slider.borderRight = 8
	slider:setLuaData("indicatorID", "slider")

	local huePicker = mainRow:createRect({
		id = tes3ui.registerID("ColorPicker_hue_picker"),
		color = { 1, 1, 1 },
	})
	huePicker.borderAllSides = 8
	huePicker.width = picker.hueWidth
	huePicker.height = picker.height
	huePicker.texture = picker.textures.hue
	huePicker.imageFilter = false
	huePicker.texture.pixelData:setPixelsFloat(picker.hueBar:toPixelBufferFloat())
	huePicker:register(tes3.uiEvent.mouseDown, function(e)
		tes3ui.captureMouseDrag(true)
	end)
	huePicker:register(tes3.uiEvent.mouseRelease, function(e)
		tes3ui.captureMouseDrag(false)
	end)
	local hueIndicator = createIndicator(
		huePicker,
		"hue",
		0.5,
		hueIndicatorInitialAbsolutePosAlignY
	)

	local alphaPicker
	local alphaIndicator
	if params.alpha then
		alphaPicker = mainRow:createRect({
			id = tes3ui.registerID("ColorPicker_alpha_picker"),
			color = { 1, 1, 1 },
		})
		alphaPicker.borderAllSides = 8
		alphaPicker.width = picker.hueWidth
		alphaPicker.height = picker.height
		alphaPicker.texture = picker.textures.alpha
		alphaPicker.imageFilter = false
		alphaPicker.texture.pixelData:setPixelsFloat(picker.alphaBar:toPixelBufferFloat())
		alphaPicker:register(tes3.uiEvent.mouseDown, function(e)
			tes3ui.captureMouseDrag(true)
		end)
		alphaPicker:register(tes3.uiEvent.mouseRelease, function(e)
			tes3ui.captureMouseDrag(false)
		end)

		alphaIndicator = createIndicator(
			alphaPicker,
			"alpha",
			0.5,
			1 - params.initialAlpha
		)
	end

	local previewContainer = mainRow:createBlock({ id = tes3ui.registerID("ColorPicker_color_preview_container") })
	previewContainer.flowDirection = tes3.flowDirection.topToBottom
	previewContainer.autoWidth = true
	previewContainer.autoHeight = true

	local currentPreview = createPreview(picker, previewContainer, initialColor, params.initialAlpha, "Current", true)

	-- Implement picking behavior
	mainPicker:register(tes3.uiEvent.mouseStillPressed, function(e)
		local x = math.clamp(e.relativeX, 1, mainPicker.width)
		local y = math.clamp(e.relativeY, 1, mainPicker.height)
		local pickedColor = picker.mainImage:getPixel(x, y)
		colorSelected(picker, pickedColor, picker.currentAlpha, currentPreview)

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
		colorSelected(picker, pickedColor, picker.currentAlpha, currentPreview)

		mainIndicator.absolutePosAlignX = x / mainPicker.width
		mainIndicator.absolutePosAlignY = y / mainPicker.height
		mainRow:getTopLevelMenu():updateLayout()
	end)

	huePicker:register(tes3.uiEvent.mouseStillPressed, function(e)
		local x = math.clamp(e.relativeX, 1, huePicker.width)
		local y = math.clamp(e.relativeY, 1, huePicker.height)
		local pickedColor = picker.hueBar:getPixel(x, y)
		hueChanged(picker, pickedColor, picker.currentAlpha, currentPreview, mainPicker)

		hueIndicator.absolutePosAlignY = y / huePicker.height
		mainRow:getTopLevelMenu():updateLayout()
	end)

	if params.alpha then
		alphaPicker:register(tes3.uiEvent.mouseStillPressed, function(e)
			local y = math.clamp(e.relativeY / alphaPicker.height, 0, 1)
			colorSelected(picker, picker.currentColor, 1 - y, currentPreview)
			alphaIndicator.absolutePosAlignY = y
			mainRow:getTopLevelMenu():updateLayout()
		end)
	end

	if params.showOriginal then
		--- @param e tes3uiEventData
		local function resetColor(e)
			hueChanged(picker, params.initialColor, params.initialAlpha, currentPreview, mainPicker)

			mainIndicator.absolutePosAlignX = mainIndicatorInitialAbsolutePosAlignX
			mainIndicator.absolutePosAlignY = mainIndicatorInitialAbsolutePosAlignY
			slider.widget.current = mainIndicatorInitialAbsolutePosAlignX * 1000
			hueIndicator.absolutePosAlignY = hueIndicatorInitialAbsolutePosAlignY
			if params.alpha then
				alphaIndicator.absolutePosAlignY = 1 - params.initialAlpha
			end
			mainRow:getTopLevelMenu():updateLayout()
		end
		createPreview(picker, previewContainer, initialColor, params.initialAlpha, "Original", false, resetColor)
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

--- @param params openColorPickerMenu.new.params
--- @param picker ColorPicker
--- @param parent tes3uiElement
--- @param onNewColorEntered fun(newColor: ffiImagePixel|ImagePixel, alpha: number)
local function createDataBlock(params, picker, parent, onNewColorEntered)
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

	local text = strings["RGB: #"]
	local inputText = format.pixelToHex(params.initialColor)
	if params.alpha then
		text = strings["ARGB: #"]
		local initialColor = table.copy(params.initialColor) --[[@as ImagePixelA]]
		initialColor.a = params.initialAlpha
		inputText = format.pixelToHex(initialColor)
	end
	local label = dataRow:createLabel({
		id = tes3ui.registerID("ColorPicker_data_row_label"),
		text = text
	})
	label.borderLeft = 4

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
		-- Update other parts of the Color Picker
		updateValueInput(color, color.a)
		onNewColorEntered(color, color.a)
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

--- @param params openColorPickerMenu.new.params
--- @param parent tes3uiElement
local function createColorPickerWidget(params, parent)
	if (not params.alpha) or (not params.initialAlpha) then
		params.initialAlpha = 1
	end
	-- The color picker stores color premultiplied by alpha
	premultiply.pixel(params.initialColor, params.initialAlpha)

	local picker = ColorPicker:new({
		mainWidth = PICKER_MAIN_WIDTH,
		height = PICKER_HEIGHT,
		hueWidth = PICKER_VERTICAL_COLUMN_WIDTH,
		previewWidth = PICKER_PREVIEW_WIDTH,
		previewHeight = PICKER_PREVIEW_HEIGHT,
		initialColor = params.initialColor,
		initialAlpha = params.initialAlpha,
	})

	picker:setColor(
		ffiPixel({ params.initialColor.r, params.initialColor.g, params.initialColor.b }),
		params.initialAlpha
	)

	local pickers = createPickerBlock(params, picker, parent)

	if params.showDataRow then
		--- @param newColor ffiImagePixel|ImagePixel
		--- @param alpha number
		local function onNewColorEntered(newColor, alpha)
			hueChanged(picker, newColor, alpha, pickers.currentPreview, pickers.mainPicker)
			-- TODO: looks like ffi can convert our ImagePixel table to ffiImagePixel when calling oklab.hsvlib_srgb_to_hsv
			updateIndicatorPositions(newColor, alpha)
		end

		createDataBlock(params, picker, parent, onNewColorEntered)
	end

	return picker
end

--- @param params openColorPickerMenu.new.params
local function openColorPickerMenu(params)
	local menu = tes3ui.findMenu(UIID.menu)
	if menu then
		return menu
	end
	local x, y = cursorHelper.getCursorCoorsMenuRelative()
	local context = headingMenu.create({
		id = UIID.menu,
		heading = strings["Color Picker Menu"],
		minWidth = 300,
		absolutePosAlignX = x,
		absolutePosAlignY = y
	})

	local bodyBlock = context.body:createBlock({ id = tes3ui.registerID("ColorPicker_main_body_container") })
	bodyBlock.autoHeight = true
	bodyBlock.autoWidth = true
	bodyBlock.widthProportional = 1.0
	bodyBlock.paddingLeft = 8
	bodyBlock.paddingRight = 8
	bodyBlock.paddingBottom = 8
	bodyBlock.flowDirection = tes3.flowDirection.topToBottom

	local picker = createColorPickerWidget(params, bodyBlock)
	context.menu:getTopLevelMenu():updateLayout()

	if params.closeCallback then
		context.menu:registerAfter(tes3.uiEvent.destroy, function()
			--- @type ImagePixel
			local color = {
				r = picker.currentColor.r,
				g = picker.currentColor.g,
				b = picker.currentColor.b,
			}
			params.closeCallback(color, picker.currentAlpha)
		end)
	end

	tes3ui.enterMenuMode(UIID.menu)
end

openColorPickerMenu({
	alpha = true,
	initialColor = { r = 0.75, g = 0.15, b = 0.45 },
	initialAlpha = 0.6,
	showOriginal = true,
	showDataRow = true,
	closeCallback = function (selectedColor, selectedAlpha)
		tes3.messageBox("Selected:\ncolor = %s,\nalpha = %s", format.pixel(selectedColor), selectedAlpha)
	end
})

-- TODO:
-- Expose as a widget: tes3uiElement:createColorPicker so modders can embed it into their menus.
-- Expose it as a global function. Something as tes3ui.openColorPickerMenu that opens color picker in a separate menu. I guess that would imply there is only one color picker menu active at a single time.
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

