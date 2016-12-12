#include <sourcemod>
#include <sdktools>
#include <colors>

// ====[ PLUGIN ]====================================================================

public Plugin myinfo = {
	name = "TeamPrefixes",
	description = "Use /prefix <tag> to add your team's tag to the names of all players on your team.",
	author = "Sawr",
	version = "1.1",
	url = "https://github.com/Sawrr/tf2/tree/master/TeamPrefixes"
};

// ====[ CONSTANTS ]=================================================================

const int NAME_MAX_LENGTH = 32;
const int PREFIX_MAX_LENGTH = 7;

const int BLU_ID = 3;
const int RED_ID = 2;

// ====[ VARIABLES ]=================================================================

// Array of player names when they connect. Names may be up to NAME_MAX_LENGTH characters
new String:nameArray[MAXPLAYERS][NAME_MAX_LENGTH];

// Arrays for RED and BLU prefixes. PREFIX_MAX_LENGTH character maximum
new String:bluPrefix[PREFIX_MAX_LENGTH];
new String:redPrefix[PREFIX_MAX_LENGTH];

// Convars for mp_tournament, plugin enabled, disable on map change
ConVar g_Tournament = null;
ConVar g_PluginEnabled;
ConVar g_DisableOnMapChange;

// Prefix changing is allowed before and after games
new bool:roundEnabled = true;

// User message for text; required to check for name changes
new UserMsg:g_umSayText2;

// When true, the next name change will be hidden from chat
new bool:hideNextNameChange = false;

// Name changes are considered manual until told otherwise by prefix change
new bool:manualNameChange = true;

// ====[ PLUGIN FUNCTIONS ]==========================================================

/* OnPluginStart()
 *
 * Called when plugin is loaded
 * ------------------------------------------------------------------------- */
public void OnPluginStart() {
	RegConsoleCmd("prefix", Command_Prefix);
    
	g_PluginEnabled = CreateConVar("sm_teamprefixes_enabled", "0", "Enables/disables team prefixes.", FCVAR_NONE, true, 0.0, true, 1.0);
	g_PluginEnabled.AddChangeHook(OnConvarChange);

	g_DisableOnMapChange = CreateConVar("sm_teamprefixes_mapchange_disabled", "0", "Disables the plugin on map change", FCVAR_NONE, true, 0.0, true, 1.0);
	
	g_Tournament = FindConVar("mp_tournament");
	g_Tournament.AddChangeHook(OnConvarChange);

	HookEvent("teamplay_round_start", Disable);
	HookEvent("tf_game_over", Enable);
	HookEvent("teamplay_game_over", Enable);
	RegServerCmd("mp_tournament_restart", Command_Restart);

	AddCommandListener(Command_JoinTeam, "jointeam")

	g_umSayText2 = GetUserMessageId("SayText2");
	HookUserMessage(g_umSayText2, UserMessageHook, true);

	HookEvent("player_changename", OnNameChange);

	// Load names of all current players into nameArray
	GetAllPlayerNames();
}

/* OnPluginEnd()
 *
 * Called when plugin is unloaded
 * ------------------------------------------------------------------------- */
public void OnPluginEnd() {
	ClearAllPlayerNames();
}

/* OnClientConnected(client)
 *
 * Called when client connects. Adds client's name to nameArray
 * @param client client who connected
 * ------------------------------------------------------------------------- */
public void OnClientConnected(client) {
	new String:clientName[NAME_MAX_LENGTH];
	GetClientName(client, clientName, NAME_MAX_LENGTH);
	nameArray[client] = clientName;
}

/* OnMapStart()
 *
 * Called when map starts. Resets prefixes
 * ------------------------------------------------------------------------- */
public void OnMapStart() {
	if (g_DisableOnMapChange.IntValue == 1) {
		g_PluginEnabled.IntValue = 0;
	}
	roundEnabled = true;
	bluPrefix = "";
	redPrefix = "";
}

// ====[ NAME UPDATING ]=============================================================

/* GetAllPlayerNames()
 *
 * Add all currently connected player names to nameArray
 * ------------------------------------------------------------------------- */
public void GetAllPlayerNames() {
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i)) {
			new String:clientName[NAME_MAX_LENGTH];
			GetClientName(i, clientName, NAME_MAX_LENGTH);
			nameArray[i] = clientName;
		}
	}
}

/* ClearAllPlayerNames()
 *
 * Removes prefixes from all names
 * ------------------------------------------------------------------------- */
public void ClearAllPlayerNames() {
	bluPrefix = "";
	redPrefix = "";
	for (int i = 1; i <= MaxClients; i++) {
		UpdateName(i);
	}
}

/* OnConvarChange(ConVar convar, char[] oldValue, char[] newValue)
 *
 * Add all currently connected player names to nameArray
 *
 * @param convar convar that changed (sm_teamprefixes_enabled)
 * @param oldValue previous value of convar
 * @param newValue new value of convar
 * ------------------------------------------------------------------------- */
public void OnConvarChange(ConVar convar, char[] oldValue, char[] newValue) {
	if (StringToInt(newValue) == 0 && StringToInt(oldValue) == 1) {
		ClearAllPlayerNames();
	}
	if (StringToInt(newValue) == 1 && StringToInt(oldValue) == 0) {
		GetAllPlayerNames();
	}
}

/* Command_JoinTeam(client, const String:command[], args)
 *
 * Called when a player tries to change team. If the plugin is active,
 * create short timer that will update player's prefix. The timer is
 * necessary because the game needs to process the team change first
 *
 * @param client client that changed team
 * @param command[]
 * @param args
 * ------------------------------------------------------------------------- */
public Action:Command_JoinTeam(client, const String:command[], args) {
	g_Tournament = FindConVar("mp_tournament");
	if (g_Tournament.BoolValue && g_PluginEnabled.BoolValue && roundEnabled && IsClientInGame(client)) {
		if (IsClientInGame(client)) {
			CreateTimer(0.1, ChangeTeamTimer, client);
		}
		PrintToChat(client, "\x03 Type /prefix <tag> to set your team's prefix.")
	}
	return Plugin_Continue;
}

/* ChangeTeamTimer(Handle timer, client)
 *
 * Called after client has changed teams
 *
 * @param timer
 * @param client client who changed teams
 * ------------------------------------------------------------------------- */
public Action:ChangeTeamTimer(Handle timer, client) {
	UpdateName(client);
}

// ====[ USER NAME CHANGE ]==========================================================

/* UserMessageHook(UserMsg:msg_hd, Handle:bf, const players[], playersNum, bool:reliable, bool:init)
 *
 * Called when player's name changes, either manually or via the plugin.
 * If the name change was manual, display it. Otherwise, do not
 *
 * @param msg_hd
 * @param bf
 * @param players[]
 * @param playersNum
 * @param reliable
 * @param init
 * ------------------------------------------------------------------------- */
public Action:UserMessageHook(UserMsg:msg_hd, Handle:bf, const players[], playersNum, bool:reliable, bool:init) {
	decl String:_sMessage[96];
	BfReadString(bf, _sMessage, sizeof(_sMessage));
	BfReadString(bf, _sMessage, sizeof(_sMessage));

	if (StrContains(_sMessage, "Name_Change") != -1	 && hideNextNameChange) {
		hideNextNameChange = false;
		for (int i = 1; i <= MaxClients; i++) {
			if (IsClientInGame(i)) {
				return Plugin_Handled;
			}
		}
	}
	return Plugin_Continue;
}

/* OnNameChange(Handle:event, const String:name[], bool:dontBroadcast)
 *
 * Called when player changes name. If change was manual, create timer
 * to update name in nameArray
 *
 * @param event name change event
 * @param name[]
 * @param dontBroadcast
 * ------------------------------------------------------------------------- */
public Action:OnNameChange(Handle:event, const String:name[], bool:dontBroadcast) {
	if (manualNameChange == true) {
		new client = GetClientOfUserId(GetEventInt(event, "userid"));
		CreateTimer(0.1, ChangeNameTimer, client);
	} else {
		manualNameChange = true;
	}
}

/* ChangeNameTimer(Handle timer, client)
 *
 * Called after client has manually changed names.
 * Updates their name in nameArray and then applies prefix
 *
 * @param timer
 * @param client client who changed teams
 * ------------------------------------------------------------------------- */
public Action:ChangeNameTimer(Handle timer, client) {
	new String:clientName[NAME_MAX_LENGTH];
	GetClientName(client, clientName, NAME_MAX_LENGTH);
	nameArray[client] = clientName;
	UpdateName(client);
}

// ====[ ROUND ENABLE/DISABLE ]======================================================

/* Disable(Handle: event, const String: name[], bool: dontBroadcast)
 *
 * Called when a round starts. If both teams are ready,
 * disables prefix changing during the match
 *
 * @param event round start event
 * @param name[]
 * @param dontBroadcast
 * ------------------------------------------------------------------------- */
public Action:Disable(Handle: event, const String: name[], bool: dontBroadcast) {
	new redReady = GameRules_GetProp("m_bTeamReady", 1, RED_ID);
	new bluReady = GameRules_GetProp("m_bTeamReady", 1, BLU_ID);

	if (bluReady && redReady) {
		roundEnabled = false;
	}
}

/* Enable(Handle: event, const String: name[], bool: dontBroadcast)
 *
 * Called when a round ends. Enables prefix changing
 *
 * @param event round end event
 * @param name[]
 * @param dontBroadcast
 * ------------------------------------------------------------------------- */
public Action:Enable(Handle: event, const String: name[], bool: dontBroadcast) {
	roundEnabled = true;
}

/* Command_Restart(args)
 *
 * Called when a tournament mode is restarted. Enables prefix changing
 *
 * @param args
 * ------------------------------------------------------------------------- */
public Action:Command_Restart(args) {
	roundEnabled = true;
}

// ====[ PREFIX ]====================================================================

/* Command_Prefix(int client, int args)
 *
 * Called when a user types /prefix <tag> or !prefix <tag>
 * If plugin is active, set the prefix. Otherwise explain
 * why the plugin is not active
 *
 * @param client user who typed the command
 * @param args desired prefix
 * ------------------------------------------------------------------------- */
public Action:Command_Prefix(int client, int args) {
	g_Tournament = FindConVar("mp_tournament");
	if (g_Tournament != null) {
		if (IsClientInGame(client)) {
			if (g_PluginEnabled.BoolValue) {
				if (g_Tournament.BoolValue) {
					if (roundEnabled) {
						SetPrefix(client, args);
					} else {
						PrintToChat(client, "TeamPrefixes is disabled during the match.");
					}
				} else {
					PrintToChat(client, "TeamPrefixes is only enabled in tournament mode.");
				}
			} else {
				PrintToChat(client, "TeamPrefixes is currently disabled. Use sm_teamprefixes_enabled 1 to enable the plugin.");
			}
		}
	}
}

/* SetPrefix(int client, int args)
 *
 * Sets prefix for team of client who changed
 * and updates ALL users prefixes
 *
 * @param client user who set the prefix
 * @param args desired prefix
 * ------------------------------------------------------------------------- */
public Action:SetPrefix(int client, int args) {
	new String:name[PREFIX_MAX_LENGTH];
	GetCmdArgString(name, sizeof(name));

	if (GetClientTeam(client) == BLU_ID) {
		bluPrefix = name;
	} else if (GetClientTeam(client) == RED_ID) {
		redPrefix = name;
	} else {
		return Plugin_Continue;
	}

	new String:clientName[62];
	GetClientName(client, clientName, sizeof(clientName));

	new String:changeString[25];

	if (StrEqual(name,""))
	{
		if (GetClientTeam(client) == BLU_ID) {
			changeString = " cleared BLU's prefix";
		} else if (GetClientTeam(client) == RED_ID) {
			changeString = " cleared RED's prefix";
		}
		StrCat(clientName, sizeof(clientName), changeString);
	} else {
		if (GetClientTeam(client) == BLU_ID) {
			changeString = " changed BLU's prefix to ";
			StrCat(clientName, sizeof(clientName), changeString);
			StrCat(clientName, sizeof(clientName), bluPrefix)
		} else if (GetClientTeam(client) == RED_ID) {
			changeString = " changed RED's prefix to ";
			StrCat(clientName, sizeof(clientName), changeString);
			StrCat(clientName, sizeof(clientName), redPrefix)
		}
	}

	CPrintToChatAllEx(client, "{teamcolor}%s", clientName);

	for (int i = 1; i <= MaxClients; i++) {
		UpdateName(i);
	}
	return Plugin_Continue;
}

/* UpdateName(client)
 *
 * Called when a user types /prefix <tag> or !prefix <tag>
 * If plugin is active, set the prefix. Otherwise explain
 * why the plugin is not active
 *
 * @param client user whose name will be updated
 * ------------------------------------------------------------------------- */
public void UpdateName(client) {
	if (IsClientInGame(client)) {
		new String:prefix[NAME_MAX_LENGTH];
		new String:playerName[NAME_MAX_LENGTH];

		if (GetClientTeam(client) == BLU_ID) {
			prefix = bluPrefix;
		} else if (GetClientTeam(client) == RED_ID) {
			prefix = redPrefix;
		} else {
			prefix = ""
		}

		// Reset player name first...
		hideNextNameChange = true;
		manualNameChange = false;
		SetClientName(client, nameArray[client]);

		g_Tournament = FindConVar("mp_tournament");
		if (g_Tournament.BoolValue && g_PluginEnabled.BoolValue) {
			// ... now set new player name
			GetClientName(client, playerName, sizeof(playerName));
			StrCat(prefix, sizeof(prefix), " ");
			StrCat(prefix, sizeof(prefix), playerName);
			hideNextNameChange = true;
			manualNameChange = false;
			SetClientName(client, prefix);
		}
	}
}