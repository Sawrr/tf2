#include <sourcemod>
#include <sdktools>
#include <sdktools_entinput>

// ====[ PLUGIN ]====================================================================

public Plugin myinfo = {
	name = "JohnCena",
	description = "And his name is sm_jc",
	author = "Sawr",
	version = "1.0",
	url = "https://github.com/Sawrr/tf2/tree/master/JohnCena"
};

// ====[ FUNCTIONS ]==========================================================

public void OnPluginStart() {
	PrecacheSound("custom/jc.mp3");
    RegServerCmd("sm_jc", Command_JC);
}

public Action Command_JC(args) {
	EmitSoundToAll("custom/jc.mp3")
	CreateTimer(0.9, OverlayStart);
	CreateTimer(4.4, OverlayEnd);
}

public Action OverlayStart(Handle timer) {
	for (int i = 1; i < MaxClients + 1; i++) {
		if (IsClientInGame(i)) {
            ClientCommand(i, "r_screenoverlay custom/jcm.vmt")
		}
	}
}

public Action OverlayEnd(Handle timer) {
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i)) {
            ClientCommand(i, "r_screenoverlay 0")
		}
	}
}