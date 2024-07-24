// https://stackoverflow.com/a/36209005

#include <algorithm>
#include <cmath>

struct RGB {
	float r;
	float g;
	float b;
};

struct HSV {
	float h;
	float s;
	float v;
};

extern "C" HSV srgb_to_hsv(RGB c)
{
	float Cmax = std::max(std::max(c.r, c.g), c.b);
	float Cmin = std::min(std::min(c.r, c.g), c.b);
	float delta = Cmax - Cmin;
	HSV out;
	out.v = Cmax;
	if (delta < 0.00001f)
	{
		out.s = 0;
		out.h = 0;
		return out;
	}

	if (Cmax > 0.0)
	{
		out.s = delta / Cmax;
	}
	else
	{
		out.s = 0;
		out.h = NAN;
		return out;
	}

	if (c.r >= Cmax)
	{
		out.h = (c.g - c.b) / delta;
	}
	else if (c.g >= Cmax)
	{
		out.h = 2.0f + (c.b - c.r) / delta;
	}
	else
	{
		out.h = 4.0f + (c.r - c.g) / delta;
	}
	out.h *= 60.0f;

	if (out.h < 0.0f)
	{
		out.h += 360.0;
	}
	return out;
}

extern "C" RGB hsv_to_srgb(HSV c)
{
	float H = c.h;
	float S = c.s;
	float V = c.v;
	RGB out;
	if (std::abs(H - 360) < 0.0001)
	{
		H = 0;
	}
	else
	{
		H /= 60.0f;
	}
	float fract = H - std::floor(H);

	float P = V * (1.0f - S);
	float Q = V * (1.0f - S * fract);
	float T = V * (1.0f - S * (1.0f - fract));

	if (0.0f <= H && H < 1.0f)
	{
		out.r = V;
		out.g = T;
		out.b = P;
	}
	else if (1.0f <= H && H < 2.0f)
	{
		out.r = Q;
		out.g = V;
		out.b = P;
	}
	else if (2.0f <= H && H < 3.0f)
	{
		out.r = P;
		out.g = V;
		out.b = T;
	}
	else if (3.0f <= H && H < 4.0f)
	{
		out.r = P;
		out.g = Q;
		out.b = V;
	}
	else if (4.0f <= H && H < 5.0f)
	{
		out.r = T;
		out.g = P;
		out.b = V;
	}
	else if (5.0f <= H && H < 6.0f)
	{
		out.r = V;
		out.g = P;
		out.b = Q;
	}
	else
	{
		out.r = 0.0f;
		out.g = 0.0f;
		out.b = 0.0f;
	}
	return out;
}
