local premultiply = {}

--- Premultiplies colors in given pixel by alpha value.
--- @param pixel ffiImagePixel
--- @param alpha number
function premultiply.pixel(pixel, alpha)
	pixel.r = pixel.r * alpha
	pixel.g = pixel.g * alpha
	pixel.b = pixel.b * alpha
end

--- Premultiplies colors in given pixel by alpha value.
--- @param pixel ImagePixelA
function premultiply.pixelLua(pixel)
	pixel.r = pixel.r * pixel.a
	pixel.g = pixel.g * pixel.a
	pixel.b = pixel.b * pixel.a
end

--- Undoes premultiplication of colors chanells in given pixel by alpha value.
--- @param pixel ffiImagePixel
--- @param alpha number
function premultiply.undo(pixel, alpha)
	pixel.r = pixel.r / alpha
	pixel.g = pixel.g / alpha
	pixel.b = pixel.b / alpha
end

--- Undoes premultiplication of colors chanells in given pixel by alpha value.
--- @param pixel ImagePixelA
function premultiply.undoLua(pixel)
	pixel.r = pixel.r / pixel.a
	pixel.g = pixel.g / pixel.a
	pixel.b = pixel.b / pixel.a
end


return premultiply
