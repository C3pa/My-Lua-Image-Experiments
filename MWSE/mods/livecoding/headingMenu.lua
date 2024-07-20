local this = {}

---@class TEST.GUI.headingMenu.create.params
---@field id string|number
---@field minWidth integer?
---@field heading string
---@field absolutePosAlignX number?
---@field absolutePosAlignY number?

---@param params TEST.GUI.headingMenu.create.params
function this.create(params)
	local menu = tes3ui.createMenu({ id = params.id, fixedFrame = true })

	menu.absolutePosAlignX = params.absolutePosAlignX or 0.1
	menu.absolutePosAlignY = params.absolutePosAlignY or 0.2
	menu.childAlignX = 0.5
	menu.childAlignY = 0.5
	menu.autoWidth = true
	menu.autoHeight = true
	menu.minWidth = params.minWidth or 500
	menu.alpha = tes3.worldController.menuAlpha

	-- Heading
	local headingBlock = menu:createBlock()
	headingBlock.childAlignX = 0.5
	headingBlock.autoHeight = true
	headingBlock.autoWidth = true
	headingBlock.widthProportional = 1.0
	headingBlock.paddingAllSides = 8
	headingBlock.flowDirection = tes3.flowDirection.topToBottom

	headingBlock:createLabel({ text = params.heading })
	headingBlock:createDivider()

	-- Main body
	local bodyBlock = menu:createBlock()
	bodyBlock.autoHeight = true
	bodyBlock.autoWidth = true
	bodyBlock.widthProportional = 1.0
	bodyBlock.paddingLeft = 8
	bodyBlock.paddingRight = 8
	bodyBlock.flowDirection = tes3.flowDirection.topToBottom
	menu:getTopLevelMenu():updateLayout()


	return {
		menu = menu,
		body = bodyBlock
	}
end

return this
