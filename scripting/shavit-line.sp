#pragma semicolon 1
#pragma newdecls required

#include <clientprefs>
#include <closestpos>
#include <sdktools>
#include <sdkhooks>
#include <dhooks>
#include <shavit/core>
#include <shavit/replay-playback>
#include <sourcemod>

#define NON_GHOST_UPDATE_TICKS 50
#define GHOST_UPDATE_TICKS     10

#define COLORS_NUMBER 9

enum { //enum for colors same indexes as colors below
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

char g_sColorStrs[][] = { //strings for colors at same indexes as colors below
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

int g_iColorInts[][] = { //general colors
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

#define SKIPFRAMES 5
#define SEC_AHEAD 7
#define SEC_UPDATE_DELAY 1.5 // If you have gammacase's showplayerclips installed you should divide this by 2 so 0.75

#define DUCKCOLOR 0
#define NODUCKCOLOR 1
#define LINECOLOR 2
#define ENABLED 3
#define FLATMODE 4
#define GHOSTMODE 5
#define LINE_WIDTH 6
#define TRACK_IDX 7
#define STYLE_IDX 8
#define CMD_NUM 9
#define EDIT_ELEMENT 10
#define EDIT_COLOR 11

#define SETTINGS_NUMBER 7

#define TE_TIME 1.0
#define TE_MIN 0.5
#define TE_MAX 0.5

#define ELEMENT_NUMBER 3

char g_sElementStrings[][] = {
	"Duck Box",
	"No Duck Box",
	"Line"
};

enum {
	DuckBox,
	NoDuckBox,
	Line
}

enum OSType
{
	OSUnknown = 0,
	OSWindows = 1,
	OSLinux   = 2
};

enum {
	GS_RACE  = 0,
	GS_ROUTE = 1,
	GS_GUIDE = 2
}

OSType gOSType;
EngineVersion gEngineVer;

int sprite;
ArrayList g_hReplayFrames[STYLE_LIMIT][TRACKS_SIZE];
ArrayList g_hReplayFrames_Guide[STYLE_LIMIT][TRACKS_SIZE];
int g_iReplayPreFrames[STYLE_LIMIT][TRACKS_SIZE];
ClosestPos g_hClosestPos[STYLE_LIMIT][TRACKS_SIZE];
ClosestPos g_hClosestPos_Guide[STYLE_LIMIT][TRACKS_SIZE];

int g_iIntCache[MAXPLAYERS + 1][12];
float g_fLineWidth[MAXPLAYERS + 1];
Cookie g_hSettings[SETTINGS_NUMBER];

int gTELimitData;
Address gTELimitAddress;

int gI_GuideFramesAhead;
int gI_Tickrate;

public Plugin myinfo = {
	name = "shavit-line-advanced",
	author = "enimmy",
	description = "Shows the WR route with a path on the ground. Use the command sm_line to toggle.",
	version = "0.4",
	url = "https://github.com/enimmy/shavit-line-advanced"
};

public void OnPluginStart() {
	gI_Tickrate = RoundToNearest(1.0 / GetTickInterval());

	g_hSettings[DUCKCOLOR] = new Cookie("shavit_line_duckcolor", "", CookieAccess_Private);
	g_hSettings[NODUCKCOLOR] = new Cookie("shavit_line_noduckcolor", "", CookieAccess_Private);
	g_hSettings[LINECOLOR] = new Cookie("shavit_line_linecolor", "", CookieAccess_Private);
	g_hSettings[ENABLED] = new Cookie("shavit_line_enabled", "", CookieAccess_Private);
	g_hSettings[FLATMODE] = new Cookie("shavit_line_flatmode", "", CookieAccess_Private);
	g_hSettings[GHOSTMODE] = new Cookie("shavit_line_ghostmode", "", CookieAccess_Private);
	g_hSettings[LINE_WIDTH] = new Cookie("shavit_line_width", "1", CookieAccess_Private);

	RegConsoleCmd("sm_line", LineCmd);

	GameData gconf = new GameData("shavit-line.games");
	gOSType = view_as<OSType>(GameConfGetOffset(gconf, "OSType"));
	if(gOSType == OSUnknown){
		SetFailState("Failed to get OS type. Make sure gamedata file is in gamedata folder, and you are using windows or linux. Your Current OS Type is %d", gOSType);
	}

	gEngineVer = GetEngineVersion();
	if(gEngineVer == Engine_CSS)
		BytePatchTELimit(gconf);

	bool shavitLoaded = LibraryExists("shavit-replay-playback");

	if(shavitLoaded) {
		Shavit_OnReplaysLoaded();
	}

	for(int i = 1; i <= MaxClients; i++) {
		if (!IsClientConnected(i) || !IsClientInGame(i) || IsFakeClient(i)) {
			continue;
		}

		if(shavitLoaded) {
			UpdateTrackStyle(i);
		}

		if (AreClientCookiesCached(i)) {
			OnClientCookiesCached(i);
		}
	}
}

public void OnPluginEnd()
{
	if(gTELimitAddress == Address_Null)
		return;
	
	StoreToAddress(gTELimitAddress, gTELimitData, NumberType_Int8);
}

stock void BytePatchTELimit(Handle gconf)
{
	//TELimit
	gTELimitAddress = GameConfGetAddress(gconf, "TELimit");
	if(gTELimitAddress == Address_Null){
		SetFailState("Failed to get addres of \"TELimit\".");
	}
	
	gTELimitData = LoadFromAddress(gTELimitAddress, NumberType_Int8);
	
	if(gOSType == OSWindows)
		StoreToAddress(gTELimitAddress, 0xFF, NumberType_Int8);
	else if(gOSType == OSLinux)
		StoreToAddress(gTELimitAddress, 0x02, NumberType_Int8);
	else
		SetFailState("Failed to store addres of \"TELimit\".");
}

public void OnClientCookiesCached(int client) {
    char strCookie[256];
    bool defaultsPushed = false;

    for(int i = 0; i < SETTINGS_NUMBER; i++) {
        GetClientCookie(client, g_hSettings[i], strCookie, sizeof(strCookie));
        if(strCookie[0] == '\0') {
            if (!defaultsPushed) {
                PushDefaultSettings(client);
                defaultsPushed = true;
            }
            break;
        }

        if (i == LINE_WIDTH) {
             g_fLineWidth[client] = StringToFloat(strCookie);
        } else {
             g_iIntCache[client][i] = StringToInt(strCookie);
        }
    }

    if (!defaultsPushed) {
         GetClientCookie(client, g_hSettings[LINE_WIDTH], strCookie, sizeof(strCookie));
         if (strCookie[0] != '\0') {
              g_fLineWidth[client] = StringToFloat(strCookie);
         } else {
              g_fLineWidth[client] = 1.0;
         }
    }


    UpdateTrackStyle(client);
}

public void Shavit_OnReplaysLoaded() {
	for(int style = 0; style < STYLE_LIMIT; style++) {
		for(int track = 0; track < TRACKS_SIZE; track++) {
			LoadReplay(style, track);
		}
	}
}

public void LoadReplay(int style, int track) {
	delete g_hClosestPos[style][track];
	delete g_hClosestPos_Guide[style][track];
	delete g_hReplayFrames[style][track];
	delete g_hReplayFrames_Guide[style][track];
	g_iReplayPreFrames[style][track] = 0;

	ArrayList list = Shavit_GetReplayFrames(style, track, true);
	g_hReplayFrames[style][track] = new ArrayList(sizeof(frame_t));
	g_hReplayFrames_Guide[style][track] = new ArrayList(sizeof(frame_t));
	g_iReplayPreFrames[style][track] = Shavit_GetReplayPreFrames(style, track);

	if(!list) {
		return;
	}

	frame_t aFrame;
	bool hitGround = false;

	for(int i = 0; i < list.Length; i++) {
		list.GetArray(i, aFrame, sizeof(frame_t));
		if(aFrame.flags & FL_ONGROUND && !hitGround) {
			hitGround = true;
		}
		else {
			hitGround = false;
		}

		g_hReplayFrames_Guide[style][track].PushArray(aFrame);

		if (hitGround || i % SKIPFRAMES == 0) {
			g_hReplayFrames[style][track].PushArray(aFrame);
		}
	}

	g_hClosestPos[style][track] = new ClosestPos(g_hReplayFrames[style][track], 0, 0, Shavit_GetReplayFrameCount(style, track));
	g_hClosestPos_Guide[style][track] = new ClosestPos(g_hReplayFrames_Guide[style][track], 0, 0, Shavit_GetReplayFrames(style, track).Length - Shavit_GetReplayPostFrames(style, track));
	delete list;
}

public void Shavit_OnStyleChanged(int client, int oldstyle, int newstyle, int track, bool manual) {
	g_iIntCache[client][TRACK_IDX] = track;
	g_iIntCache[client][STYLE_IDX] = newstyle;
}

public void Shavit_OnReplaySaved(int client, int style, float time, int jumps, int strafes, float sync, int track) {
    LoadReplay(style, track);
}

public void OnConfigsExecuted() {
	sprite = PrecacheModel("sprites/laserbeam.vmt");

	gI_GuideFramesAhead = RoundToNearest(gI_Tickrate * SEC_UPDATE_DELAY);
}

Action LineCmd(int client, int args) {
	if (!IsValidClient(client)) {
		return Plugin_Handled;
	}
	ShowToggleMenu(client);
	return Plugin_Handled;
}

void ShowToggleMenu(int client) {
	Menu menu = CreateMenu(LinesMenu_Callback);
	SetMenuTitle(menu, "｢ Shavit Line Advanced ｣");
	AddMenuItem(menu, "linetoggle", (g_iIntCache[client][ENABLED]) ? "[x] Enabled":"[ ] Enabled");
	AddMenuItem(menu, "flatmode", (g_iIntCache[client][FLATMODE]) ? "[x] Flat Mode":"[ ] Flat Mode");
	AddMenuItem(menu, "ghosttoggle", (g_iIntCache[client][GHOSTMODE]) ? "[x] Guide Mode":"[ ] Guide Mode");

	char sMessage[256];
	Shavit_GetStyleStrings(g_iIntCache[client][STYLE_IDX], sStyleName, sMessage, sizeof(sMessage));
	Format(sMessage, sizeof(sMessage), "Style: %s", sMessage);

	AddMenuItem(menu, "style", sMessage);
	AddMenuItem(menu, "colors", "Colors");
	AddMenuItem(menu, "widths", "Line Width");
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}


public int LinesMenu_Callback (Menu menu, MenuAction action, int client, int option) {
	if (action == MenuAction_Select) {
		char info[32];
		GetMenuItem(menu, option, info, sizeof(info));

		if (StrEqual(info, "linetoggle")) {
			g_iIntCache[client][ENABLED] = !g_iIntCache[client][ENABLED];

			if(g_iIntCache[client][ENABLED]) {
				Shavit_PrintToChat(client, "Explanation in Console");
				PrintToConsole(client, "The boxes on the ground show the jump locations of the WR route on this servers replay for the style you are on.");
				PrintToConsole(client, "By default White Box = Uncrouched Jump | Pink Box = Crouched Jump");
				PrintToConsole(client, "You can change the colors under settings.");
			}

			PushCookies(client);
		}
		else if(StrEqual(info, "flatmode")) {
			if(g_iIntCache[client][GHOSTMODE]){
				Shavit_PrintToChat(client, "FlatMode disabled by GuideMode, please turn off GuideMode first!");
			}else{
				g_iIntCache[client][FLATMODE] = !g_iIntCache[client][FLATMODE];
			}
			PushCookies(client);
		}
		else if(StrEqual(info, "style")) {
			int style = g_iIntCache[client][STYLE_IDX] + 1;
			for(int i = style; i < STYLE_LIMIT; i++) {
				if(g_hReplayFrames[i][g_iIntCache[client][TRACK_IDX]].Length > 0) {
					style = i;
					break;
				} else if(i == STYLE_LIMIT - 1) {
					style = 0;
				}
			}
			g_iIntCache[client][STYLE_IDX] = style;
		}
		else if (StrEqual(info, "colors")) {
			ShowColorOptionsMenu(client);
			return 0;
		}else if (StrEqual(info, "widths")) {
			ShowWidthOptionsMenu(client);
			return 0;
		}else if (StrEqual(info, "ghosttoggle")) {
			g_iIntCache[client][GHOSTMODE] = !g_iIntCache[client][GHOSTMODE];
			
			if(g_iIntCache[client][GHOSTMODE]){
				Shavit_PrintToChat(client, "Guide mode can display the best recorded route in server.");
				if(g_iIntCache[client][FLATMODE]){
					Shavit_PrintToChat(client, "FlatMode automatic disabled by GuideMode");
					g_iIntCache[client][FLATMODE] = 0;
				}
			}
			PushCookies(client);
		}
		ShowToggleMenu(client);
	}
	else if (action == MenuAction_End) {
		delete menu;
	}
	return 0;
}

void ShowColorOptionsMenu(int client) {
	Menu menu = CreateMenu(LinesColors_Callback);
	SetMenuTitle(menu, "Colors\n\n");

	char sMessage[256];
	Format(sMessage, sizeof(sMessage), "< Editing: %s >", g_sElementStrings[g_iIntCache[client][EDIT_ELEMENT]]);
	AddMenuItem(menu, "editbox", sMessage);

	Format(sMessage, sizeof(sMessage), "Color: %s", g_sColorStrs[g_iIntCache[client][g_iIntCache[client][EDIT_ELEMENT]]]);
	AddMenuItem(menu, "editcolor", sMessage);
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

void ShowWidthOptionsMenu(int client) {
    Menu menu = CreateMenu(LinesWidth_Callback);
    SetMenuTitle(menu, "Widths\n\n");
    char sMessage[256];

    Format(sMessage, sizeof(sMessage), " + 0.1");
    AddMenuItem(menu, "add", sMessage);

    Format(sMessage, sizeof(sMessage), "< Width: %.1f >", g_fLineWidth[client] > 0.0 ? g_fLineWidth[client] : 1.0);
    AddMenuItem(menu, "show_width", sMessage, 1);
    Format(sMessage, sizeof(sMessage), " - 0.1");
    AddMenuItem(menu, "del", sMessage);

    DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public int LinesWidth_Callback(Menu menu, MenuAction action, int client, int option) {
    if (action == MenuAction_Select) {
        char info[32];
        GetMenuItem(menu, option, info, sizeof(info));

        float currentWidth = g_fLineWidth[client];

        if(currentWidth <= 0.0){
            currentWidth = 1.0;
        }
        if(StrEqual(info, "add")){
            if(10.0 > currentWidth){
                currentWidth += 0.1;
            }
        }else
        if(StrEqual(info, "del")){
            if(currentWidth > 0.1){
                currentWidth -= 0.1;
            } else {
                // Optional: Snap to a minimum positive value or 0 if needed
                // currentWidth = 0.1;
            }
        }
        g_fLineWidth[client] = currentWidth;
        PushCookies(client);
        ShowWidthOptionsMenu(client);

    } else if (action == MenuAction_End) {
        delete menu;
    }
    return 0;
}

public int LinesColors_Callback(Menu menu, MenuAction action, int client, int option) {
	if (action == MenuAction_Select) {
		char info[32];
		GetMenuItem(menu, option, info, sizeof(info));

		if(StrEqual(info, "editbox")) {
			g_iIntCache[client][EDIT_ELEMENT]++;

			if(g_iIntCache[client][EDIT_ELEMENT] >= ELEMENT_NUMBER)
			{
				g_iIntCache[client][EDIT_ELEMENT] = 0;
			}
		}
		else if (StrEqual(info, "editcolor")) {
			g_iIntCache[client][EDIT_COLOR]++;

			if(g_iIntCache[client][EDIT_COLOR] >= COLORS_NUMBER)
			{
				g_iIntCache[client][EDIT_COLOR] = 0;
			}

			g_iIntCache[client][g_iIntCache[client][EDIT_ELEMENT]] = g_iIntCache[client][EDIT_COLOR];
			PushCookies(client);
		}
		ShowColorOptionsMenu(client);
	}
	else if (action == MenuAction_End) {
		delete menu;
	}
	return 0;
}

void PushDefaultSettings(int client) {
    g_iIntCache[client][ENABLED] = 1;
    g_iIntCache[client][FLATMODE] = 0;
    g_iIntCache[client][DUCKCOLOR] = Red;
    g_iIntCache[client][NODUCKCOLOR] = Pink;
    g_iIntCache[client][LINECOLOR] = White;
    g_iIntCache[client][GHOSTMODE] = 0;
    g_iIntCache[client][TRACK_IDX] = 0;
    g_iIntCache[client][STYLE_IDX] = 0;
    g_iIntCache[client][CMD_NUM] = 0;
    g_iIntCache[client][EDIT_ELEMENT] = 0;
    g_iIntCache[client][EDIT_COLOR] = 0;

    g_fLineWidth[client] = 1.0;

    PushCookies(client);
    UpdateTrackStyle(client);
}

void PushCookies(int client) {
    char strCookie[64];

    for(int i = 0; i < SETTINGS_NUMBER; i++) {
        if (i == LINE_WIDTH) {
            FloatToString(g_fLineWidth[client], strCookie, sizeof(strCookie));
            SetClientCookie(client, g_hSettings[i], strCookie);
        } else {
            IntToString(g_iIntCache[client][i], strCookie, sizeof(strCookie));
            SetClientCookie(client, g_hSettings[i], strCookie);
        }
    }
}

public void OnPlayerRunCmdPost(int client) {
	if (!IsValidClient(client) || !g_iIntCache[client][ENABLED]) {
		return;
	}

	g_iIntCache[client][CMD_NUM]++;

	int updateInterval = g_iIntCache[client][GHOSTMODE] ? GHOST_UPDATE_TICKS : NON_GHOST_UPDATE_TICKS;

	if (g_iIntCache[client][CMD_NUM] % updateInterval != 0) {
		return;
	}

	g_iIntCache[client][CMD_NUM] %= updateInterval;

	ArrayList list;
	ClosestPos cp_handle;
	int framesToDraw;

	if(!g_iIntCache[client][GHOSTMODE]){
		list = g_hReplayFrames[g_iIntCache[client][STYLE_IDX]][g_iIntCache[client][TRACK_IDX]];
		cp_handle = g_hClosestPos[g_iIntCache[client][STYLE_IDX]][g_iIntCache[client][TRACK_IDX]];
		framesToDraw = 125;
	} else {
		list = g_hReplayFrames_Guide[g_iIntCache[client][STYLE_IDX]][g_iIntCache[client][TRACK_IDX]];
		cp_handle = g_hClosestPos_Guide[g_iIntCache[client][STYLE_IDX]][g_iIntCache[client][TRACK_IDX]];
        framesToDraw = gI_GuideFramesAhead;
	}

	if(!cp_handle || list.Length == 0){
		return;
	}

	float pos[3];
	GetClientAbsOrigin(client, pos);
	int closeframe = cp_handle.Find(pos);

	if(closeframe < 0){
		 return;
	}

	int startFrame = closeframe;
	int endFrame = min(list.Length - 1, startFrame + framesToDraw);

	if(startFrame < 0 || startFrame >= list.Length || endFrame < startFrame) {
		 return;
	}

	frame_t currentFrameData;
	list.GetArray(startFrame, currentFrameData, sizeof(frame_t));
	float currentPos[3];
	currentPos = currentFrameData.pos;

	if(!g_iIntCache[client][GHOSTMODE] && !g_iIntCache[client][FLATMODE]) {
		currentPos[2] += 2.5;
	}

	int prevFlags = currentFrameData.flags;

	for(int i = startFrame + 1; i <= endFrame; i++) {
		frame_t nextFrameData;
		list.GetArray(i, nextFrameData, sizeof(frame_t));
		float nextPos[3];
		nextPos = nextFrameData.pos;

		if(!g_iIntCache[client][GHOSTMODE] && !g_iIntCache[client][FLATMODE]) {
			nextPos[2] += 2.5;
		}

		DrawBeam(client, currentPos, nextPos, TE_TIME, g_fLineWidth[client], g_fLineWidth[client], g_iColorInts[g_iIntCache[client][LINECOLOR]], 0.0, 0);

		if(!g_iIntCache[client][GHOSTMODE]) {
			if((nextFrameData.flags & FL_ONGROUND) && !(prevFlags & FL_ONGROUND)) {
				DrawBox(client, currentPos, g_iColorInts[g_iIntCache[client][(prevFlags & FL_DUCKING) ? DUCKCOLOR:NODUCKCOLOR]]);
			}
		}

		currentPos = nextPos;
		prevFlags = nextFrameData.flags;
	}

}

float box_offset[4][2] = {
	{-10.0, 10.0},
	{10.0, 10.0},
	{-10.0, -10.0},
	{10.0, -10.0},
};

void DrawBox(int client, float pos[3], int color[3]) {
	float square[4][3];
	for (int z = 0; z < 4; z++) {
		square[z][0] = pos[0] + (box_offset[z][0]);
		square[z][1] = pos[1] + (box_offset[z][1]);
		square[z][2] = pos[2];
	}

	DrawBeam(client, square[0], square[1], TE_TIME, TE_MIN, TE_MAX, color, 0.0, 0);
	DrawBeam(client, square[0], square[2], TE_TIME, TE_MIN, TE_MAX, color, 0.0, 0);
	DrawBeam(client, square[2], square[3], TE_TIME, TE_MIN, TE_MAX, color, 0.0, 0);
	DrawBeam(client, square[1], square[3], TE_TIME, TE_MIN, TE_MAX, color, 0.0, 0);
}

void DrawBeam(int client, float startvec[3], float endvec[3], float life, float width, float endwidth, int color[3], float amplitude, int speed) {

	int sendColor[4];
	for(int i = 0; i < 3; i++) {
		sendColor[i] = color[i];
	}
	sendColor[3] = 255;

	TE_SetupBeamPoints(startvec, endvec, sprite, 0, 0, 66, life, width, endwidth, 0, amplitude, sendColor, speed);
	TE_SendToClient(client);
}

int min(int a, int b) {
	return a < b ? a : b;
}

void UpdateTrackStyle(int client) {
	g_iIntCache[client][TRACK_IDX] = Shavit_GetClientTrack(client);
	g_iIntCache[client][STYLE_IDX] = Shavit_GetBhopStyle(client);
}