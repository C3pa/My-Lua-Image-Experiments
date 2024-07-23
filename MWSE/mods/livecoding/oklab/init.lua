local ffi = require("ffi")

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
	RGB okhsv_to_srgb(HSV hsv);
	HSV srgb_to_okhsv(RGB rgb);
]]
local oklab = ffi.load(".\\Data Files\\MWSE\\mods\\livecoding\\oklab\\liboklab.dll")

--- @class liboklab
--- @field hsvtosrgb fun(hsv: HSV): ImagePixel
--- @field srgbtohsv fun(rgb: ImagePixelArgument|PremulImagePixelA): HSV
local this = {}

--- @param hsv HSV
function this.hsvtosrgb(hsv)
	local arg = ffi.new("HSV")
	--- @diagnostic disable: inject-field
	-- okhsv_to_srgb h is in [0, 1] range.
	arg.h = hsv.h / 360
	arg.s = hsv.s
	arg.v = hsv.v
	--- @diagnostic enable: inject-field
	local ret = oklab.okhsv_to_srgb(arg)
	return {
		r = ret.r,
		g = ret.g,
		b = ret.b,
	}
end

--- @param rgb ImagePixelArgument|PremulImagePixelA
function this.srgbtohsv(rgb)
	local arg = ffi.new("RGB")
	--- @diagnostic disable: inject-field
	arg.r = rgb.r
	arg.g = rgb.g
	arg.b = rgb.b
	--- @diagnostic enable: inject-field
	local ret = oklab.srgb_to_okhsv(arg)
	return {
		-- srgb_to_okhsv returns h in [0, 1] range.
		h = ret.h * 360,
		s = ret.s,
		v = ret.v,
	}
end

return this
