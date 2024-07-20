local cursorHelper = {}

---@return integer w2
---@return integer h2
function cursorHelper.getViewportHalfSize()
	local w, h = tes3ui.getViewportSize()
	return math.floor(w / 2), math.floor(h / 2)
end

--- Uses the same coordinate system as tes3uiElement.absolutePosAlignX, so upper left corner of
--- the screen has [0, 0] coordinates, while lower right corner of the screen is [1, 1].
---@return number x Horizontal
---@return number y Vertical
function cursorHelper.getCursorCoorsMenuRelative()
	local cursorPos = tes3.getCursorPosition()
	local cursorX, cursorY = cursorPos.x, cursorPos.y -- cursorHelper.getCursorScreenCoords()
	local w, h = cursorHelper.getViewportHalfSize()
	local screenX, screenY = tes3ui.getViewportSize()
	return (cursorX + w) / screenX, (h - cursorY) / screenY
end

return cursorHelper
