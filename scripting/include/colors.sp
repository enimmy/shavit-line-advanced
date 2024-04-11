#define COLORS_NUMBER 9

enum //enum for colors same indexes as colors below
{
	Red, //for all colors structs, first 5 idxs are default, dont reorder them
	Orange,
	Green,
	Cyan,
	White,
	Yellow,
	Blue,
	Purple,
	Pink
};

char g_sBstatColorStrs[][] = { //strings for colors at same indexes as colors below
	"Red",
	"Orange",
	"Green",
	"Cyan",
	"White",
	"Yellow",
	"Blue",
	"Purple",
	"Pink"
};

char g_sBstatColorsHex[][] = {
	"\x07ff0000",
	"\x07ffa500",
	"\x0700ff00",
	"\x0700ffff",
	"\x07ffffff",
	"\x07ffff00",
	"\x070000ff",
	"\x07800080",
	"\x07ee00ff"
};

int g_iBstatColors[][] = { //general colors
	{255, 0, 0},
	{255, 165, 0},
	{0, 255, 0},
	{0, 255, 255},
	{255, 255, 255},
	{255, 255, 0},
	{0, 0, 255},
	{128, 0, 128},
	{238, 0, 255}
};
