#include <sourcemod>
#include <tf2_stocks>
#include <morecolors>

// ====[ CONSTANTS ]==========================================================

/** Number of slots in player data array */
#define DATA_LIST_SIZE 12

/** Maximum number of players, used for condition tracking */
#define MAX_PLAYERS 33

/** Three-dimensional vectors */
#define VECTOR_DIM 3

/** Max weapon slots */
#define MAX_WEAPONS 4

/** 60 seconds per minute */
#define ONE_MINUTE 60.0
/** Minimum timer length in seconds */
#define TIMER_DUR 0.1

/** Accidental pause protection time in seconds */
#define PAUSE_UNPAUSE_TIME 2.0
/** Unpause countdown time in seconds */
#define UNPAUSE_WAIT_TIME 5
/** Default value of g_fLastPause */
#define DEFAULT_LASTPAUSE -10.0

/** Amount to move dead players upon rejoin */
#define VERTICAL_OFFSET 10000

/** Values for engineer metal property */
#define ENGIE_METAL_SIZE 4
#define ENGIE_METAL_ELEMENT 3

/** String buffer size, used by various */
#define BUFFER_SLOTX_SIZE 6
#define BUFFER_INFO_SIZE 5

/** Index of vector for z-axis */
#define Z_AXIS 2

/** Empty string for printing */
#define CLEAR_TEXT " "

/** Condition default durations */
#define JARATE_DURATION 10.0
#define MILK_DURATION 10.0
#define MARKED_DURATION 15.0

/** Condition constants */
#define NO_CONDITION 0
#define NO_CONDITION_TIME 0.0

/** Error codes */
#define NO_PLAYERDATA_FOUND -1
#define NO_STEAMID_FOUND -1
#define NO_CLIENT_FOUND -1
#define NO_SPACE_AVAILABLE -1
#define NO_WEAPON -1
#define NO_WEAPON_CLIP -1
#define NO_WEAPON_AMMO -1

// ====[ PAUSE ENUM ]==========================================================

/**
 * PauseState enum
 *
 *	The first four states are typical pause states:
 *		Unpaused - self explanatory
 *		Paused - self explanatory
 *		Countdown - countdown to unpause in progress, pause command will cancel
 *		Countdown_Complete - finished, next pause command will unpause (occurs automatically)
 *
 *	The DC_ states are used when a player disconnects during a match
 *		DC_Paused - game paused when player disconnects
 *		DC_Countdown - countdown to unpause BEFORE all players are back, pause command will cancel
 *		DC_PlayerRejoined - player is back, pause command will briefly unpause to let player load
 *		DC_PlayerLoading - game is unpaused briefly to let player load
 *
 */
enum PauseState {
	Unpaused,
	Paused,
	Countdown,
	Countdown_Complete,

	DC_Paused,
	DC_Countdown,
	DC_PlayerRejoined,
	DC_PlayerLoading
};

// ====[ ConVars ]==========================================================

/** sv_pausable */
ConVar g_cvPausable;
/** pause_enablechat */
ConVar g_cvPauseChat;
/** mp_tournament */
ConVar g_cvTournament;

// ====[ GLOBAL VARIABLES ]==========================================================

/** Plugin enabled during tournament mode matches */
new bool:g_bPluginActive;

/** Pause state */
new PauseState:g_iPauseState;

/** Time of last pause */
new Float:g_fLastPause;
/** Number of minutes game has been paused for */
new g_iPauseTimeMinutes;
/** Number of seconds left in pause countdown */
new g_iCountdown;

/** Timer handles (aka pointers) */
new Handle:g_hCountdownTimer = INVALID_HANDLE;
new Handle:g_hPauseTimeTimer = INVALID_HANDLE;
new Handle:g_hLoadWeaponsTimer = INVALID_HANDLE;
new Handle:g_hRepausePauseTimer = INVALID_HANDLE;

/** If player has just disconnected */
new bool:g_bPlayerJustDisconnected;
/** If player rejoined during countdown, cancel it */
new bool:g_bPlayerRejoinedDuringCountdown;
/** Game briefly unpaused, so repause it next tick */
new g_iRepauseNextTick;
/** Player rejoined, so load their data next tick  */
new g_iLoadPlayerNextTick;
/** Last player is disconnecting from server, so reset plugin */
new bool:g_bServerNowEmpty;

/** Condition time trackers */
new g_iJarated[ MAX_PLAYERS ];
new g_iMilked[ MAX_PLAYERS ];
new g_iMarkedForDeath[ MAX_PLAYERS ];

// ====[ PLUGIN SETUP ]==========================================================

public Plugin:myinfo =
{
	name = "AdvancedPause",
	author = "Sawr",
	description = "Pauses game when player disconnects and allows for reconnecting.",
	version = "1.0.0",
	url = "https://github.com/Sawrr/tf2/tree/master/AdvancedPause",
}

public OnPluginStart()
{
	// Command listeners for pausing
	AddCommandListener( Command_Pause, "pause" );
	AddCommandListener( Command_Pause, "setpause" );
	AddCommandListener( Command_Pause, "unpause" );

	// Disconnect
	HookEvent( "player_disconnect", PlayerDisconnect, EventHookMode_Pre );

	// Start and end of game hooks
	HookEvent( "teamplay_restart_round", Enable );
	HookEvent( "tf_game_over", Disable );
	RegServerCmd( "mp_tournament_restart", Command_Disable );

	// ConVars for tournament mode, pausable
	g_cvTournament = FindConVar( "mp_tournament" );
	g_cvPausable = FindConVar( "sv_pausable" );

	// Pause chat ConVar
	g_cvPauseChat = CreateConVar("pause_enablechat", "1", "Enable people to chat as much as they want during a pause.", FCVAR_PLUGIN);
	
	// Unlimited pause chat
	AddCommandListener( Command_Say, "say" );

	// To hide MOTD on reconnect
	HookUserMessage( GetUserMessageId( "VGUIMenu" ), VGUIMenu, true );

	OnMapStart();
}

/**
 * Sets all settings to default values.
 */
public OnMapStart() {
	if ( g_hCountdownTimer != INVALID_HANDLE ) {
		KillTimer( g_hCountdownTimer );
	}

	if ( g_hPauseTimeTimer != INVALID_HANDLE ) {
		KillTimer( g_hPauseTimeTimer );
	}

	if ( g_hLoadWeaponsTimer != INVALID_HANDLE ) {
		KillTimer( g_hLoadWeaponsTimer );
	}

	if ( g_hRepausePauseTimer != INVALID_HANDLE ) {
		KillTimer( g_hRepausePauseTimer );
	}

	g_fLastPause = DEFAULT_LASTPAUSE;
	g_iPauseState = Unpaused; // The game is by default unpaused
	g_hCountdownTimer = INVALID_HANDLE;
	g_hPauseTimeTimer = INVALID_HANDLE;
	g_hLoadWeaponsTimer = INVALID_HANDLE;
	g_hRepausePauseTimer = INVALID_HANDLE;
	g_iPauseTimeMinutes = 0;
	g_bPlayerJustDisconnected = false;
	g_bPlayerRejoinedDuringCountdown = false;
	g_iRepauseNextTick = false;
	g_iLoadPlayerNextTick = false;
	g_bServerNowEmpty = false;

	// Not active until tournament match begins
	g_bPluginActive = false;

	FreeAllPlayerData();
}

// ====[ PLAYER DATA STRUCT ]==========================================================

/**
 * Player data "struct"
 *
 *	When a player disconnects, the first available index in the allocList is
 *	allocated for them, and the following fields are populated with the player's
 *	state at the allocated index. Sourcemod does not allow for structs or dynamic
 *	memory allocation, so parallel arrays are the best we can do, folks.
 */

/** Player steam ID */
steamId[ DATA_LIST_SIZE ];
/** Map time left when DC occurred */
DCTime[ DATA_LIST_SIZE ];

/** TF2 team, class */
TFTeam:tfteam[ DATA_LIST_SIZE ];
TFClassType:tfclass[ DATA_LIST_SIZE ];

/** If player was alive when they DC'd */
bool:alive[ DATA_LIST_SIZE ];
/** Player health */
health[ DATA_LIST_SIZE ];

/** Player position, velocity, view angle */
Float:vel_vec[ DATA_LIST_SIZE ][ VECTOR_DIM ];
Float:pos_vec[ DATA_LIST_SIZE ][ VECTOR_DIM ];
Float:ang_vec[ DATA_LIST_SIZE ][ VECTOR_DIM ];

/** Clip, energy, ammotype, ammo for each weapon */
weaponClip[ DATA_LIST_SIZE ][ MAX_WEAPONS ];
Float:weaponEnergy[ DATA_LIST_SIZE ][ MAX_WEAPONS ];
weaponAmmoType[ DATA_LIST_SIZE ][ MAX_WEAPONS ];
weaponAmmo[ DATA_LIST_SIZE ][ MAX_WEAPONS ];

/** Item id for each weapon to ensure no changing of loadout */
weaponItemId[ DATA_LIST_SIZE ][ MAX_WEAPONS ];
/** Weapon slot number of active weapon (1 = primary) */
activeWeaponSlot[ DATA_LIST_SIZE ];

/* Scout */
Float:hype[ DATA_LIST_SIZE ];
Float:energyDrink[ DATA_LIST_SIZE ];
airDash[ DATA_LIST_SIZE ]; // number of double jumps

/* Soldier */
Float:rage[ DATA_LIST_SIZE ];
bool:rageDraining[ DATA_LIST_SIZE ];

/* Demoman */
Float:charge[ DATA_LIST_SIZE ];

/* Engineer */
metal[ DATA_LIST_SIZE ];
revengeCrits[ DATA_LIST_SIZE ];

/* Medic */
bool:uberDeployed[ DATA_LIST_SIZE ];
Float:uberChargeLevel[ DATA_LIST_SIZE ];

/* Spy */
Float:cloak[ DATA_LIST_SIZE ];

/* Conditions */
Float:jarated[ DATA_LIST_SIZE ];
Float:milked[ DATA_LIST_SIZE ];
Float:markedForDeath[ DATA_LIST_SIZE ];

// ====[ PLAYER DATA FUNCTIONS ]==========================================================

/** List of player data slots. True indicates that slot is occupied */
new bool:allocList[ DATA_LIST_SIZE ];

/**
 * Allocates the first available slot in the list
 *
 * @return index of allocated slot
 */
int AllocPlayerData()
{
	for ( int i = 0; i < DATA_LIST_SIZE; i++ ) {
		if ( !allocList[ i ] ) {
			allocList[ i ] = true;
			return i;
		}
	}

	return NO_SPACE_AVAILABLE;
}

/**
 * Frees the given slot in list
 *
 * @param index
 *				index of slot
 */
void FreePlayerData( int index )
{
	allocList[ index ] = false;
	steamId[ index ] = 0;
	
	/* Conditions */
	jarated[ index ] = NO_CONDITION_TIME;
	milked[ index ] = NO_CONDITION_TIME;
	markedForDeath[ index ] = NO_CONDITION_TIME;
}

/**
 * Frees all slots in player data list
 */
void FreeAllPlayerData()
{
	for ( int i = 0; i < DATA_LIST_SIZE; i++ ) {
		FreePlayerData( i );
	}
}

/**
 * Returns slot index with given steam id
 *
 * @param client
 *				client id
 * @return index, or -1 if not found
 */
int GetIndexOfClient( int client )
{
	for ( int i = 0; i < DATA_LIST_SIZE; i++ ) {
		if ( steamId[ i ] == GetSteamAccountID( client ) && allocList[ i ] ) {
			return i;
		}
	}
	return NO_CLIENT_FOUND;
}

/**
 * Returns client of given slot index
 *
 * @param idx
 *			index
 * @return client index, or -1 if not found
 */
int GetClientOfIndex( int idx )
{
	if ( !allocList[ idx ] ) {
		return NO_CLIENT_FOUND;
	}

	for ( int i = 1; i < GetMaxClients(); i++ ) {
		if ( IsClientConnected( i ) && !IsFakeClient( i ) && IsClientInGame( i ) ) {
			int steam = GetSteamAccountID( i );
			if ( steam == steamId[ idx ] ) {
				return i;
			}
		}
	}
	return NO_CLIENT_FOUND;
}

/**
 * Returns the number of players who DC'd and haven't been loaded.
 */
int NumOfPlayersDisconnected()
{
	int num = 0;
	for ( int i = 0; i < DATA_LIST_SIZE; i++ ) {
		if ( allocList[ i ] ) {
			num++;
		}
	}
	return num;
}

// ====[ PAUSE LISTENER ]==========================================================

/**
 * Handles all logic for when pause command occurs.
 */
public Action:Command_Pause( client, const String:command[], args ) {
	// Let the game handle the "off" situations
	if ( !g_cvPausable.BoolValue )
		return Plugin_Continue;
	if ( client == 0 )
		return Plugin_Continue;

		// If all players disconnect, all hope is lost
	if ( g_bServerNowEmpty ) {
		g_bServerNowEmpty = false;

		new PauseState:oldState = g_iPauseState;

		// Full reset of plugin
		OnMapStart();

		if ( oldState == Unpaused || oldState == DC_PlayerLoading ) {
			// If game is currently unpaused, keep it that way
			return Plugin_Handled;
		} else {
			// Otherwise unpause it
			return Plugin_Continue;
		}
	}

	if ( g_bPlayerJustDisconnected ) {
		// Pause command due to disconnect

		g_bPlayerJustDisconnected = false;

		// State is now paused due to disconnect
		new PauseState:oldState = g_iPauseState;
		g_iPauseState = DC_Paused;
		CPrintToChatAllEx( client, "{lightgreen}[AdvPause] {default}Player {teamcolor}%N {default}disconnected! Game paused.", client );

		if (  oldState == Unpaused || oldState == DC_PlayerLoading ) {
			// Set last pause time
			g_fLastPause = GetTickedTime();

			// Set number of minutes paused timer
			g_hPauseTimeTimer = CreateTimer( ONE_MINUTE, Timer_PauseTime, _, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT );
			g_iPauseTimeMinutes = 0;

			// Game currently unpaused, so let the pause command occur
			return Plugin_Continue;

		} else {
			// Clear countdown timer and screen text
			if ( g_hCountdownTimer != INVALID_HANDLE ) {
				KillTimer( g_hCountdownTimer );
				g_hCountdownTimer = INVALID_HANDLE;
				PrintCenterTextAll( CLEAR_TEXT );
			}

			// Game currently paused, so block the command
			return Plugin_Handled;
		}
	} else {
		// Pause command NOT due to disconnect

		if ( g_iPauseState == Countdown_Complete ) {
			g_iPauseState = Unpaused;
			return Plugin_Continue;
		} else if ( g_iPauseState == Unpaused || g_iPauseState == Countdown || g_iPauseState == DC_Countdown ) {
			// Set last pause time
			g_fLastPause = GetTickedTime();

			// Clear countdown timer and screen text
			if ( g_hCountdownTimer != INVALID_HANDLE ) {
				KillTimer( g_hCountdownTimer );
				g_hCountdownTimer = INVALID_HANDLE;
				PrintCenterTextAll( CLEAR_TEXT );
			}

			// Game is now paused
			new PauseState:oldState = g_iPauseState;
			if ( g_iPauseState == DC_Countdown ) {
				if ( g_bPlayerRejoinedDuringCountdown == true ) {
					g_bPlayerRejoinedDuringCountdown = false;
					g_iPauseState = DC_PlayerRejoined;
				} else {
					g_iPauseState = DC_Paused;
				}
			} else {
				g_iPauseState = Paused;
			}
			CPrintToChatAllEx( client, "{lightgreen}[AdvPause] {default}Game was paused by {teamcolor}%N", client );

			if ( oldState == Unpaused ) {
				// Set number of minutes paused timer
				g_hPauseTimeTimer = CreateTimer( ONE_MINUTE, Timer_PauseTime, _, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT );
				g_iPauseTimeMinutes = 0;

				// Allow pause to occur
				return Plugin_Continue;
			} else {
				// Countdown cancelled
				return Plugin_Handled;
			}
		} else if ( g_iPauseState == Paused || g_iPauseState == DC_Paused ) {
			// Check for accidental unpauses
			new Float:timeSinceLastPause = GetTickedTime() - g_fLastPause;
			if ( timeSinceLastPause < PAUSE_UNPAUSE_TIME ) {
				new Float:waitTime = PAUSE_UNPAUSE_TIME - timeSinceLastPause;
				CPrintToChat( client, "{lightgreen}[AdvPause] {default}To prevent accidental unpauses, you have to wait %.1f second%s before unpausing.", waitTime, (waitTime >= 0.95 && waitTime < 1.05) ? "" : "s" );
				return Plugin_Handled;
			}

			// Start countdown
			CPrintToChatAllEx( client, "{lightgreen}[AdvPause] {default}Game is being unpaused in %i seconds by {teamcolor}%N{default}...", UNPAUSE_WAIT_TIME, client );
			if ( g_iPauseState == Paused ) {
				g_iPauseState = Countdown;
			} else {
				CPrintToChatAllEx( client, "{red}WARNING: {default}Disconnected players will have to rejoin from spawn!" );
				g_iPauseState = DC_Countdown;
			}

			g_iCountdown = UNPAUSE_WAIT_TIME;
			g_hCountdownTimer = CreateTimer( 1.0, Timer_Countdown, client, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT );
			Timer_Countdown( g_hCountdownTimer, client );

			return Plugin_Handled;
		} else if ( g_iPauseState == DC_PlayerRejoined ) {
			// Blip
			g_iPauseState = DC_PlayerLoading;
			g_iRepauseNextTick = client;
			return Plugin_Continue;
		} else if ( g_iPauseState == DC_PlayerLoading ) {
			if ( NumOfPlayersDisconnected() == 1 ) {
				// If last player is being loaded in
				CPrintToChatAllEx( client, "{lightgreen}[AdvPause] {default}Disconnected players are loaded in!" );
				g_iPauseState = Paused;
			} else {
				// Otherwise
				CPrintToChatAllEx( client, "{lightgreen}[AdvPause] {default}Still waiting on all players." );
				g_iPauseState = DC_Paused;
			}
			return Plugin_Continue;
		}
	}

	return Plugin_Handled;
}

/**
 * Called every second when unpause countdown is happening.
 */
public Action:Timer_Countdown( Handle:timer, int client ) {
	if ( g_iCountdown == 0 ) {
		// Countdown finished
		g_hCountdownTimer = INVALID_HANDLE;
		PrintCenterTextAll( CLEAR_TEXT );

		KillTimer( g_hPauseTimeTimer );
		g_hPauseTimeTimer = INVALID_HANDLE;

		if ( g_iPauseState == DC_Countdown ) {
			// If unpausing before players have reconnected, they can no longer rejoin
			FreeAllPlayerData();
		}

		g_iPauseState = Countdown_Complete;
		CPrintToChatAllEx( client, "{lightgreen}[AdvPause] {default}Game is unpaused!" );
		FakeClientCommandEx( client, "pause" );

		return Plugin_Stop;
	} else {
		// Still counting down...
		PrintCenterTextAll( "Unpausing in %is...", g_iCountdown );
		if ( g_iCountdown < UNPAUSE_WAIT_TIME )
			CPrintToChatAllEx( client, "{lightgreen}[AdvPause] {default}Game is being unpaused in %i second%s...", g_iCountdown, g_iCountdown == 1 ? "" : "s" );
		g_iCountdown--;
		return Plugin_Continue;
	}
}

/**
 * Called every minute when game is paused to alert players of
 * the amount of time the game has been paused for.
 */
public Action:Timer_PauseTime(Handle:timer) {
	g_iPauseTimeMinutes++;
	if ( !( g_iPauseState == Countdown || g_iPauseState == DC_Countdown ) )
		CPrintToChatAll( "{lightgreen}[AdvPause] {default}Game has been paused for %i minute%s", g_iPauseTimeMinutes, g_iPauseTimeMinutes == 1 ? "" : "s" );
	return Plugin_Continue;
}

// ====[ CONNECT/DISCONNECT LISTENERS ]==========================================================

/**
 * When client reconnects after disconnect, place them
 * on the appropriate team and class and set a short timer
 * to load their data.
 *
 * @param client
 *				index of client that joined
 */
public void OnClientPutInServer( int client )
{
	if ( !g_cvTournament.BoolValue || !g_bPluginActive ) {
		return;
	}

	int idx = GetIndexOfClient( client );
	if ( idx == NO_PLAYERDATA_FOUND || !allocList[ idx ] ) {
		return;
	}
	TF2_ChangeClientTeam( client, tfteam[ idx ] );
	TF2_SetPlayerClass( client, tfclass[ idx ] );
	g_iLoadPlayerNextTick = client;
	if ( g_iPauseState == DC_Countdown ) {
		g_bPlayerRejoinedDuringCountdown = true;
		FakeClientCommandEx( client, "pause" );
	} else {
		g_iPauseState = DC_PlayerRejoined;
	}
	CPrintToChatAllEx( client, "{lightgreen}[AdvPause] {teamcolor}%N {default}has rejoined.", client );
	g_hRepausePauseTimer = CreateTimer( TIMER_DUR, Timer_RepausePause, client )
}

/**
 * Called after player has rejoined. Unpauses briefly to
 * allow client to load in, and repauses one tick later.
 * (see Command_Pause and OnGameFrame functions)
 */
public Action:Timer_RepausePause( Handle timer, int client )
{
	g_hRepausePauseTimer = INVALID_HANDLE;
	FakeClientCommandEx( client, "pause" );
}

/**
 * When client disconnects, store their data if a tournament
 * match is being played and the player is valid, then pause.
 *
 * @param client
 *				index of client that disconnected
 */
public Action:PlayerDisconnect( Event event, const char[] name, bool dontBroadcast )
{
	if ( !g_cvTournament.BoolValue || !g_bPluginActive ) {
		return;
	}

	int userid = event.GetInt( "userid" );
	int client = GetClientOfUserId( userid );

	if ( client == 0 ) {
		return;
	}

	// Check for all players disconnecting
	int numPlayers = 0;
	for ( int i = 1; i < MaxClients; i++ ) {
		if ( IsClientInGame( i ) && !IsFakeClient( i ) ) {
			numPlayers++;
		}
	}

	// Last player is DCing, server about to be empty
	if ( numPlayers == 1 ) {
		g_bServerNowEmpty = true;
	}

	// Ensure player is real and on a team
	if ( !IsClientInGame( client ) || IsFakeClient( client )
		|| TF2_GetClientTeam( client ) == TFTeam_Spectator
		|| TF2_GetClientTeam( client ) == TFTeam_Unassigned ) {
		return;
	}

	// Save player data only if they aren't already
	int idx = GetIndexOfClient( client );
	if ( idx == NO_CLIENT_FOUND ) {
		SaveClient( client );
	}

	// Pause game
	g_bPlayerJustDisconnected = true;
	FakeClientCommand( client, "pause" );
}

// ====[ SERVER TICK LISTENER ]==========================================================

/**
 * Called every server frame. Checks for the need to
 * repause after game was unpaused due to player loading.
 * Also checks for a player that needs to be loaded.
 */
public void OnGameFrame()
{
	// If game was just unpaused due to client rejoining, repause it
	if ( g_iRepauseNextTick ) {
		int client = g_iRepauseNextTick;
		g_iRepauseNextTick = 0;
		
		FakeClientCommandEx( client, "pause" );
		g_hLoadWeaponsTimer = CreateTimer( TIMER_DUR, Timer_LoadWeapons, 0 );
	}

	// If player rejoined, load their saved data
	if ( g_iLoadPlayerNextTick ) {
		int client = g_iLoadPlayerNextTick;
		g_iLoadPlayerNextTick = 0;
		LoadClient( client );
	}
}

/**
 * Finishes loading rejoined players by setting
 * their active weapon. Then frees up their data.
 */
public Action:Timer_LoadWeapons( Handle timer, args )
{
	g_hLoadWeaponsTimer = INVALID_HANDLE;
	for ( int idx = 0; idx < DATA_LIST_SIZE; idx++ ) {
		if ( allocList[ idx ] ) {
			int client = GetClientOfIndex( idx );
			if ( client != NO_CLIENT_FOUND) {
				// Set weapon to active weapon
				char cmdBuffer[ BUFFER_SLOTX_SIZE ];
				cmdBuffer[ BUFFER_SLOTX_SIZE - 1 ] = '\0';
				Format( cmdBuffer, sizeof(cmdBuffer), "slot%d", activeWeaponSlot[ idx ] );
				ClientCommand( client, cmdBuffer );
				
				// Player is fully loaded, free slot in list
				FreePlayerData( idx );
			}
		}
	}
}

// ====[ PLAYER LOAD/SAVE FUNCTIONS ]==========================================================

/**
 * Saves a clients data who just disconnected.
 *
 * @param client
 *				index of client
 */
void SaveClient( int client )
{
	int idx = AllocPlayerData();
	if ( idx == NO_SPACE_AVAILABLE ) {
		return;
	}

	steamId[ idx ] = GetSteamAccountID( client, true );

	GetMapTimeLeft( DCTime[ idx ] );

	/* ALL CLASS */

	// Player team and class
	tfteam[ idx ] = TF2_GetClientTeam( client );
	tfclass[ idx ] = TF2_GetPlayerClass( client );

	// Player health
	health[ idx ] = GetClientHealth( client );

	// Player position, facing angle, velocity
	GetEntPropVector( client, Prop_Data, "m_vecVelocity", vel_vec[ idx ] );
	GetClientEyeAngles( client, ang_vec[ idx ] );
	GetClientAbsOrigin( client, pos_vec[ idx ] );

	// Player alive status
	alive[ idx ] = IsPlayerAlive( client );

	// Get player weapons info
	for ( int i = 0; i < MAX_WEAPONS; i++ ) {
		int weapon = GetPlayerWeaponSlot( client, i );

		// Default to no ID
		weaponItemId[ idx ][ i ] = NO_WEAPON;

		// If weapon exists
		if ( weapon != NO_WEAPON ) {
			// Store weapon item id
			weaponItemId[ idx ][ i ] = GetEntProp( weapon, Prop_Send, "m_iItemDefinitionIndex" );

			// Set index in weaponItemId of active weapon
			if ( GetEntPropEnt( client, Prop_Send, "m_hActiveWeapon" ) == weapon ) {
				activeWeaponSlot[ idx ] = i + 1;
			}

			// Get weapon clip
			weaponClip[ idx ][ i ] = GetEntProp( weapon, Prop_Data, "m_iClip1" );

			// Energy weapons
			weaponEnergy[ idx ][ i ] = GetEntPropFloat( weapon, Prop_Send, "m_flEnergy" );

			// Get weapon ammo
			weaponAmmoType[ idx ][ i ] = GetEntProp( weapon, Prop_Send, "m_iPrimaryAmmoType" );
			if (weaponAmmoType[ idx ][ i ] != NO_WEAPON_AMMO) {
				weaponAmmo[ idx ][ i ] = GetEntProp( client, Prop_Data, "m_iAmmo", _, weaponAmmoType[ idx ][ i ] );
			}
		}
	}

	/* SCOUT - HYPE, DRINK */
	if ( TF2_GetPlayerClass( client ) == TFClass_Scout ) {
		hype[ idx ] = GetEntPropFloat( client, Prop_Send, "m_flHypeMeter" );
		energyDrink[ idx ] = GetEntPropFloat( client, Prop_Send, "m_flEnergyDrinkMeter" );
		airDash[ idx ] = GetEntProp( client, Prop_Send, "m_iAirDash" );
	}

	/* SOLDIER - RAGE */
	if ( TF2_GetPlayerClass( client ) == TFClass_Soldier ) {
		 rage[ idx ] = GetEntPropFloat( client, Prop_Send, "m_flRageMeter" );
		 rageDraining[ idx ] = bool:GetEntProp( client, Prop_Send, "m_bRageDraining" );
	}

	/* DEMO - CHARGE */
	if ( TF2_GetPlayerClass( client ) == TFClass_DemoMan ) {
		charge[ idx ] = GetEntPropFloat( client, Prop_Send, "m_flChargeMeter" );
	}

	/* ENGINEER - METAL, REVENGE CRITS */
	if ( TF2_GetPlayerClass( client ) == TFClass_Engineer ) {
		metal[ idx ] = GetEntProp( client, Prop_Data, "m_iAmmo", ENGIE_METAL_SIZE, ENGIE_METAL_ELEMENT );
		revengeCrits[ idx ] = GetEntProp( client, Prop_Send, "m_iRevengeCrits" );
	}

	/* MEDIC - UBERCHARGE */
	if ( TF2_GetPlayerClass( client ) == TFClass_Medic ) {
		int medigun = GetPlayerWeaponSlot( client, 1 );
		uberDeployed[ idx ] = bool:GetEntProp( medigun, Prop_Send, "m_bChargeRelease", 1 );
		uberChargeLevel[ idx ] = GetEntPropFloat( medigun, Prop_Send, "m_flChargeLevel" );
	}

	/* SPY - CLOAK */
	if ( TF2_GetPlayerClass( client ) == TFClass_Spy ) {
		cloak[ idx ] = GetEntPropFloat( client, Prop_Send, "m_flCloakMeter" );
	}
	
	/* CONDITIONS */
	if ( TF2_IsPlayerInCondition( client, TFCond_Jarated ) ) {
		jarated[ idx ] = JARATE_DURATION - ( g_iJarated[ client ] - DCTime[ idx ] );
	}
	if ( TF2_IsPlayerInCondition( client, TFCond_Milked ) ) {
		milked[ idx ] = MILK_DURATION - ( g_iMilked[ client ] - DCTime[ idx ] );
	}
	if ( TF2_IsPlayerInCondition( client, TFCond_MarkedForDeath ) ) {
		markedForDeath[ idx ] = MARKED_DURATION - ( g_iMarkedForDeath[ client ] - DCTime[ idx ] );
	}
}

/**
 * Loads a clients data who rejoined.
 *
 * @param client
 *				index of client
 */
void LoadClient( int client )
{
	int idx = GetIndexOfClient( client );

	if ( idx == NO_PLAYERDATA_FOUND ) {
		return;
	}

	TF2_RespawnPlayer( client );

	// If player was dead, kill them again MAYBE
	if ( !alive[ idx ] ) {
		KillPlayer( client );
		return;
	}

	/* ALL CLASS BASICS */

	// Set health
	SetEntityHealth( client, health[ idx ] );

	// Move to position, set facing angle, set velocity
	TeleportEntity( client, pos_vec[ idx ], ang_vec[ idx ], vel_vec[ idx ] );

	// Fix weapons
	for ( int i = 0; i < MAX_WEAPONS; i++ ) {
		int weapon = GetPlayerWeaponSlot( client, i );
		if ( weapon != NO_WEAPON ) {
			// No changing weapons is allowed! Kill player on detected weapon change
			if ( GetEntProp( weapon, Prop_Send, "m_iItemDefinitionIndex" ) != weaponItemId[ idx ][ i ] ) {
				KillPlayer( client );
			}

			// If weapon has a clip, set it
			if ( weaponClip[ idx ][ i ] != NO_WEAPON_CLIP ) {
				SetEntProp( weapon, Prop_Data, "m_iClip1", weaponClip[ idx ][ i ] );
			}

			// Energy weapons
			SetEntPropFloat( weapon, Prop_Send, "m_flEnergy", weaponEnergy[ idx ][ i ] );

			// Set weapon ammo
			if ( weaponAmmoType[ idx ][ i ] != NO_WEAPON_AMMO ) {
				SetEntProp( client, Prop_Data, "m_iAmmo", weaponAmmo[ idx ][ i ], _, weaponAmmoType[ idx ][ i ] );
			}
		}
	}

	/* SCOUT - HYPE, DRINK, DOUBLE JUMP */
	if ( TF2_GetPlayerClass( client ) == TFClass_Scout ) {
		SetEntPropFloat( client, Prop_Send, "m_flHypeMeter", hype[ idx ] );
		SetEntPropFloat( client, Prop_Send, "m_flEnergyDrinkMeter", energyDrink[ idx ] );
		SetEntProp( client, Prop_Send, "m_iAirDash", airDash[ idx ] );
	}

	/* SOLDIER - RAGE */
	if ( TF2_GetPlayerClass( client ) == TFClass_Soldier ) {
		SetEntPropFloat( client, Prop_Send, "m_flRageMeter", rage[ idx ] );
		SetEntProp( client, Prop_Send, "m_bRageDraining", rageDraining[ idx ] );
	}

	/* DEMO - CHARGE */
	if ( TF2_GetPlayerClass( client ) == TFClass_DemoMan ) {
		SetEntPropFloat( client, Prop_Send, "m_flChargeMeter", charge[ idx ] );
	}

	/* ENGINEER - METAL, REVENGE CRITS */
	if ( TF2_GetPlayerClass( client ) == TFClass_Engineer ) {
		SetEntProp( client, Prop_Data, "m_iAmmo", metal[ idx ], ENGIE_METAL_SIZE, ENGIE_METAL_ELEMENT );
		SetEntProp( client, Prop_Send, "m_iRevengeCrits", revengeCrits[ idx ] );
	}

	/* MEDIC - UBERCHARGE */
	if ( TF2_GetPlayerClass( client ) == TFClass_Medic ) {
		// Set ubercharge percent
		int medigun = GetPlayerWeaponSlot( client, TFWeaponSlot_Secondary );
		SetEntPropFloat( medigun, Prop_Send, "m_flChargeLevel", uberChargeLevel[ idx ] );

		// Deploy uber
		if ( uberDeployed[ idx ] ) {
			SetEntProp( medigun, Prop_Send, "m_bChargeRelease", 1, 1 );
		}
	}

	/* SPY - CLOAK */
	if ( TF2_GetPlayerClass( client ) == TFClass_Spy ) {
		SetEntPropFloat( client, Prop_Send, "m_flCloakMeter", cloak[ idx ] );
	}
	
	/* CONDITIONS */	
	if ( jarated[ idx ] ) {
		TF2_AddCondition( client, TFCond_Jarated, jarated[ idx ] );
		jarated[ idx ] = NO_CONDITION_TIME;
	}
	if ( milked[ idx ] ) {
		TF2_AddCondition( client, TFCond_Milked, milked[ idx ] );
		milked[ idx ] = NO_CONDITION_TIME;
	}
	if ( markedForDeath[ idx ] ) {
		TF2_AddCondition( client, TFCond_MarkedForDeath, markedForDeath[ idx ] );
		markedForDeath[ idx ] = NO_CONDITION_TIME;
	}
}

/**
 * Helper function kills a player who should be dead upon rejoining.
 * Places player far below the map so they cannot switch class and
 * respawn. Also prevents players from gaining information about the map.
 *
 * @param client
 *				index of client
 */
void KillPlayer( int client )
{
	new Float:outOfSpawn[ VECTOR_DIM ];
	new Float:zeros[ VECTOR_DIM ];
	GetClientAbsOrigin( client, outOfSpawn );
	outOfSpawn[ Z_AXIS ] -= VERTICAL_OFFSET;
	TeleportEntity( client, outOfSpawn, zeros, zeros );
	ForcePlayerSuicide( client );
}

// ====[ CONDITION LISTENER ]==========================================================

public void TF2_OnConditionAdded( int client, TFCond:condition )
{
	int time;
	GetMapTimeLeft( time );
	if ( condition == TFCond_Jarated ) {
		g_iJarated[ client ] = time;
	}
	if ( condition == TFCond_Milked ) {
		g_iMilked[ client ] = time;
	}
	if ( condition == TFCond_MarkedForDeath ) {
		g_iMarkedForDeath[ client ] = time;
	}
}

public void TF2_OnConditionRemoved( int client, TFCond:condition )
{
	if ( condition == TFCond_Jarated ) {
		g_iJarated[ client ] = NO_CONDITION;
	}
	if ( condition == TFCond_Milked ) {
		g_iMilked[ client ] = NO_CONDITION;
	}
	if ( condition == TFCond_MarkedForDeath ) {
		g_iMarkedForDeath[ client ] = NO_CONDITION;
	}
}

// ====[ MOTD ]==========================================================

/**
 * Called when usermessage is sent to open MOTD.
 * If player is reconnecting after disconnect,
 * prevent MOTD from opening.
 *
 * Credit to Bacardi: https://forums.alliedmods.net/showthread.php?t=213807
 */
public Action:VGUIMenu(UserMsg:msg_id, Handle:bf, const players[], playersNum, bool:reliable, bool:init)
{
	// If player connecting for first time, show MOTD
	int idx = GetIndexOfClient( players[ 0 ] );
	if ( idx == NO_STEAMID_FOUND || !allocList[ idx ] ) {
		return Plugin_Continue;
	}

	// Otherwise do not to avoid HUD bugging out
	new String:buffer[ BUFFER_INFO_SIZE ];
	BfReadString( bf, buffer, sizeof( buffer ) );
	if ( StrEqual( buffer, "info" ) ) {
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

// ====[ UNLIMITED PAUSE CHAT ]==========================================================

/**
 * Allows for sending of unlimited messages while game is paused.
 *
 * Taken from original Pause plugin. Credit to F2.
 */
public Action:Command_Say( client, const String:command[], args ) {
	if ( client == 0 )
		return Plugin_Continue;
	
	if ( g_iPauseState != Unpaused ) {
		if ( !g_cvPauseChat.BoolValue )
			return Plugin_Continue;
		
		decl String:buffer[ 256 ];
		GetCmdArgString( buffer, sizeof( buffer ) );
		if ( buffer[ 0 ] != '\0' ) {
			if ( buffer[ strlen( buffer )-1 ] == '"' )
				buffer[ strlen( buffer )-1 ] = '\0';
			if ( buffer[ 0 ] == '"' )
				strcopy( buffer, sizeof( buffer ), buffer[ 1 ] );
			
			decl String:dead[ 16 ] = "";
			if ( GetClientTeam( client ) == _:TFTeam_Spectator )
				dead = "*SPEC* ";
			else if ( ( GetClientTeam( client ) == _:TFTeam_Red || GetClientTeam( client ) == _:TFTeam_Blue ) && !IsPlayerAlive( client ) )
				dead = "*DEAD* ";
			
			CPrintToChatAllEx( client, "%s{teamcolor}%N{default} :  %s", dead, client, buffer );
		}
		
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

// ====[ ENABLE / DISABLE PLUGIN ]==========================================================

/**
 * Enables the plugin. Called when a tournament match begins.
 */
public Action:Enable( Handle:event, const String: name[], bool: dontBroadcast )
{
	g_bPluginActive = true;
}

/**
 * Disables the plugin. Called when a tournament match ends.
 */
public Action:Disable( Handle:event, const String: name[], bool: dontBroadcast )
{
	OnMapStart();
}

/**
 * Disables the plugin. Called when mp_tournament_restart is called.
 */
public Action:Command_Disable( args )
{
	OnMapStart();
}
