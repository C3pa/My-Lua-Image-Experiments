local this = {}

--- @class ImagePixel
--- @field r number Red in range [0, 1].
--- @field g number Green in range [0, 1].
--- @field b number Blue in range [0, 1].

--- @class HSV
--- @field h number Hue in range [0, 360)
--- @field s number Saturation in range [0, 1]
--- @field v number Value/brightness in range [0, 1]

--- Returned values are: H in range [0, 360), s [0, 1], v [0, 1]
--- @param rgb ImagePixel
--- @return HSV
function this.RGBtoHSV(rgb)
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

--- @param hsv HSV
--- @return ImagePixel
function this.HSVtoRGB(hsv)
	local H = hsv.h / 60
	if math.isclose(H, 360) then
		H = 0
	end
	local fract = H - math.floor(H)

	local P = hsv.v * (1 - hsv.s)
	local Q = hsv.v * (1 - hsv.s * fract)
	local T = hsv.v * (1 - hsv.s * (1 - fract))
	local rgb
	if 0 <= H and H < 1 then
		rgb = { r = hsv.v, g = T, b = P }
	elseif 1 <= H and H < 2 then
		rgb = { r = Q, g = hsv.v, b = P }
	elseif 2 <= H and H < 3 then
		rgb = { r = P, g = hsv.v, b = T }
	elseif 3 <= H and H < 4 then
		rgb = { r = P, g = Q, b = hsv.v }
	elseif 4 <= H and H < 5 then
		rgb = { r = T, g = P, b = hsv.v }
	elseif 5 <= H and H < 6 then
		rgb = { r = hsv.v, g = P, b = Q }
	else
		rgb = { r = 0, g = 0, b = 0 }
	end

	return rgb
end

return this
