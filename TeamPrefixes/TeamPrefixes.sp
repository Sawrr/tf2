#include <sourcemod>
#include <sdktools>
#include <colors>

public Plugin myinfo =
{
	name = "TeamPrefixes",
	description = "Use /prefix <tag> to add your team's tag to the names of all players on your team.",
	author = "Sawr",
	version = "1.0",
	url = ""
};

/* ================================================================================== */

// Array of player names when they connect. Names may be up to 32 characters
new String:nameArray[MAXPLAYERS + 1][32];

// Arrays for RED and BLU prefixes. 7 character maximum
new String:bluPrefix[7];
new String:redPrefix[7];

// Convars for mp_tournament and enable command
ConVar g_hTournament = null;
ConVar g_hPluginEnabled;

// Prefix changing is allowed before and after games
new bool:roundEnabled = true;

// User message for text; required to check for name changes
new UserMsg:g_umSayText2;

// When true, the next name change will be hidden from chat
new bool:hideNextNameChange = false;
new bool:manualNameChange = true;

/* ================================================================================== */

// Create /prefix <tag> or !prefix <tag> command
// Disable command when game starts, enable when game ends
public void OnPluginStart()
{
	RegConsoleCmd("prefix", Command_Prefix);
	g_hPluginEnabled = CreateConVar("sm_teamprefixes_enabled", "0", "Enables/disables team prefixes.", FCVAR_NONE, true, 0.0, true, 1.0);
	g_hPluginEnabled.AddChangeHook(OnConvarChange);
	
	g_hTournament = FindConVar("mp_tournament");
	g_hTournament.AddChangeHook(OnConvarChange);
	
	HookEvent("teamplay_round_start", Disable);
	HookEvent("tf_game_over", Enable);
	
	AddCommandListener(Command_JoinTeam, "jointeam")
	
	g_umSayText2 = GetUserMessageId("SayText2");
	HookUserMessage(g_umSayText2, UserMessageHook, true);
	
	HookEvent("player_changename", OnNameChange);
}

// Get connected player's names and store them in an array
public void OnClientConnected(client)
{
	new String:clientName[32];
	GetClientName(client, clientName, 32);
	nameArray[client] = clientName;
}

// Prefix changing is enabled before the round starts
public void OnMapStart()
{
	g_hPluginEnabled.IntValue = 0;
	roundEnabled = true;
	bluPrefix = "";
	redPrefix = "";
}

/* ================================================================================== */

public void OnConvarChange(ConVar convar, char[] oldValue, char[] newValue)
{
	if(StringToInt(newValue) == 0 && StringToInt(oldValue) == 1)
	{
		bluPrefix = "";
		redPrefix = "";
		for( int i = 1; i < MaxClients + 1; i = i + 1 )
		{
			UpdateName(i);
		}
	}
	if(StringToInt(newValue) == 1 && StringToInt(oldValue) == 0)
	{
		bluPrefix = "";
		redPrefix = "";
		for( int i = 1; i < MaxClients + 1; i = i + 1 )
		{
			if(IsClientInGame(i))
			{
				new String:clientName[32];
				GetClientName(i, clientName, 32);
				nameArray[i] = clientName;
			}
		}
	}
}

public Action:Command_JoinTeam(client, const String:command[], args)
{
	g_hTournament = FindConVar("mp_tournament");
	if(g_hTournament.BoolValue && g_hPluginEnabled.BoolValue && roundEnabled && IsClientInGame(client))
	{
		if(IsClientInGame(client))
		{
			CreateTimer(0.1, ChangeTeamTimer, client);
		}
		PrintToChat(client, "\x03 Type /prefix <tag> to set your team's prefix.")
	}
	return Plugin_Continue;
}

public Action:ChangeTeamTimer(Handle timer, client)
{
	UpdateName(client);
}

/* ================================================================================== */

public Action:UserMessageHook(UserMsg:msg_hd, Handle:bf, const players[], playersNum, bool:reliable, bool:init)
{
	decl String:_sMessage[96];
	BfReadString(bf, _sMessage, sizeof(_sMessage));
	BfReadString(bf, _sMessage, sizeof(_sMessage));
	
	if(StrContains(_sMessage, "Name_Change") != -1  && hideNextNameChange)
	{	
		hideNextNameChange = false;
		for(new i = 1; i <= MaxClients; i++)
		{
			if(IsClientInGame(i))
			{
				return Plugin_Handled;
			}
		}
	}
	return Plugin_Continue;
}

public Action:OnNameChange(Handle:event, const String:name[], bool:dontBroadcast)
{
	if(manualNameChange == true)
	{
		new client = GetClientOfUserId(GetEventInt(event, "userid"));
		CreateTimer(0.1, ChangeNameTimer, client);
	}
	else
	{
		manualNameChange = true;
	}
}

public Action:ChangeNameTimer(Handle timer, client)
{
	new String:clientName[32];
	GetClientName(client, clientName, 32);
	nameArray[client] = clientName;
}

/* ================================================================================== */

// Check if both teams are readied up to disable prefix changing
public Action:Disable(Handle: event, const String: name[], bool: dontBroadcast)
{
	new redReady = GameRules_GetProp("m_bTeamReady",1,2);
	new bluReady = GameRules_GetProp("m_bTeamReady",1,3);

	if(bluReady && redReady)
	{
		roundEnabled = false;
	}

}

// Enable prefix changing
public Action:Enable(Handle: event, const String: name[], bool: dontBroadcast)
{
	roundEnabled = true;
}

/* ================================================================================== */

// Command for /prefix <tag> or !prefix <tag>
// makes sure tournament mode is roundEnabled and checks player's team
public Action:Command_Prefix(int client, int args)
{
	g_hTournament = FindConVar("mp_tournament");
	if(g_hTournament != null)
	{
		if(IsClientInGame(client))
		{
			if(g_hPluginEnabled.BoolValue)
			{
				if(g_hTournament.BoolValue)
				{
					if(roundEnabled)
					{
						SetPrefix(client, args);
					}
					else
					{						
						PrintToChat(client, "TeamPrefixes is disabled during the match.");
					}
				}
				else
				{
					PrintToChat(client, "TeamPrefixes is only enabled in tournament mode.");
				}
			}
			else
			{
				PrintToChat(client, "TeamPrefixes is currently disabled. Use sm_teamprefixes_enabled 1 to enable the plugin.");
			}
		}
	}
}

/* ================================================================================== */

// Get prefix from the command
public Action:SetPrefix(int client, int args)
{
	new String:name[7];
	GetCmdArgString(name, sizeof(name));
	
	if(GetClientTeam(client) == 3)
	{
		bluPrefix = name;
	}
	else if(GetClientTeam(client) == 2)
	{
		redPrefix = name;
	}
	else
	{
		return Plugin_Continue;
	}
	
	new String:clientName[62];
	GetClientName(client, clientName, sizeof(clientName));
	
	new String:changeString[25];
	
	if(StrEqual(name,""))
	{
		if(GetClientTeam(client) == 3)
		{
			changeString = " cleared BLU's prefix";
		}
		else if(GetClientTeam(client) == 2)
		{
			changeString = " cleared RED's prefix";
		}
		StrCat(clientName, sizeof(clientName), changeString);
	}
	else
	{
		if(GetClientTeam(client) == 3)
		{
			changeString = " changed BLU's prefix to ";
			StrCat(clientName, sizeof(clientName), changeString);
			StrCat(clientName, sizeof(clientName), bluPrefix)
		}
		else if(GetClientTeam(client) == 2)
		{
			changeString = " changed RED's prefix to ";
			StrCat(clientName, sizeof(clientName), changeString);
			StrCat(clientName, sizeof(clientName), redPrefix)
		}
	}	
	
	CPrintToChatAllEx(client, "{teamcolor}%s", clientName);
	
	for( int i = 1; i < MaxClients + 1; i = i + 1 )
	{
		if(GetClientTeam(i) == GetClientTeam(client))
		{
			UpdateName(i);
		}
	}
	return Plugin_Continue;
}

// Update player's name
public void UpdateName(client)
{
	if(IsClientInGame(client))
	{
		new String:prefix[32];
		new String:playerName[32];
		
		if(GetClientTeam(client) == 3)
		{
			prefix = bluPrefix;
		}
		else if(GetClientTeam(client) == 2)
		{
			prefix = redPrefix;
		}
		else
		{
			prefix = ""
		}
		
		// Reset player name
		hideNextNameChange = true;
		manualNameChange = false;
		SetClientName(client, nameArray[client]);
		
		g_hTournament = FindConVar("mp_tournament");
		if(g_hTournament.BoolValue && g_hPluginEnabled.BoolValue)
		{
			// Set new player name
			GetClientName(client, playerName, sizeof(playerName));
			StrCat(prefix, sizeof(prefix), " ");
			StrCat(prefix, sizeof(prefix), playerName);
			hideNextNameChange = true;
			manualNameChange = false;
			SetClientName(client, prefix);
		}
	}
}