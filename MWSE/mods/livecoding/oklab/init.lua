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
	RGB hsv_to_srgb(HSV c);
	HSV srgb_to_hsv(RGB rgb);
]]
local oklab = ffi.load(".\\Data Files\\MWSE\\mods\\livecoding\\oklab\\liboklab.dll")
local hsvlib = ffi.load(".\\Data Files\\MWSE\\mods\\livecoding\\oklab\\libhsv.dll")

--- @class liboklab
--- @field hsvtosrgb fun(hsv: HSV): ImagePixel
--- @field srgbtohsv fun(rgb: ImagePixelArgument|PremulImagePixelA): HSV
--- @field hsvlib_hsv_to_srgb fun(c: ffiHSV): ffiImagePixel
--- @field hsvlib_srgb_to_hsv fun(rgb: ffiImagePixel): ffiHSV
local this = {}

this.hsvlib_hsv_to_srgb = hsvlib.hsv_to_srgb
this.hsvlib_srgb_to_hsv = hsvlib.srgb_to_hsv

function this.hsvtosrgb(hsv)
	local arg = ffi.new("HSV")
	--- @diagnostic disable: inject-field
	arg.h = hsv.h
	arg.s = hsv.s
	arg.v = hsv.v
	--- @diagnostic enable: inject-field
	local ret = hsvlib.hsv_to_srgb(arg)
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
	local ret = hsvlib.srgb_to_hsv(arg)
	return {
		h = ret.h,
		s = ret.s,
		v = ret.v,
	}
end

--- @param hsv HSV
function this.oklab_hsvtosrgb(hsv)
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
function this.oklab_srgbtohsv(rgb)
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
