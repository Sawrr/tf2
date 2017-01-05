#include <sourcemod>
#include <tf2_stocks>
#include <morecolors>

// ====[ CONSTANTS ]==========================================================

/** Time in seconds team has to cancel the gg call */
#define CONCEDE_TIME 10
/** g_iCountdown value when no countdown is happening */
#define NO_COUNTDOWN -1
/** Empty string used to clear center text */
#define CLEAR_TEXT " "
/** Maximum number of players, used for vote tracking */
#define MAX_PLAYERS 33

// ====[ ConVars ]==========================================================

/** mp_tournament */
ConVar g_cvTournament;

/** gg_enabled */
ConVar g_cvEnabled;
/** gg_vote */
ConVar g_cvVote;
/** gg_winnerconcede */
ConVar g_cvWinnerGG;
/** gg_winthreshold */
ConVar g_cvWinThreshold;
/** gg_windifference */
ConVar g_cvWinDifference;
/** gg_timeleft */
ConVar g_cvTimeLeft;

// ====[ GLOBAL VARIABLES ]==========================================================

/** Plugin enabled during tournament mode matches */
new bool:g_bPluginActive;

/** Number of seconds left in gg countdown */
new g_iCountdown;

/** Timer handle (aka pointer) */
new Handle:g_hCountdownTimer = INVALID_HANDLE;

/** Team that is calling gg */
new TFTeam:g_iGGTeam;
/** Buffer for RED or BLU */
char g_cTeamBuffer[ 4 ];

/** List of client indices that voted */
new g_iVotingPlayers[ MAX_PLAYERS ];
/** Number of votes */
new g_iVoteCount;
/** Number of votes needed for majority */
new g_iVoteMajority;

// ====[ PLUGIN SETUP ]==========================================================

public Plugin:myinfo =
{
	name = "GG Concede",
	author = "Sawr",
	description = "Allows teams to gg and concede a match. Type /gg or !gg in chat, or use console command \"gg\" ",
	version = "1.1.0",
	url = "https://github.com/Sawrr/tf2",
}

public OnPluginStart()
{
	// Start and end of game hooks
	HookEvent( "teamplay_restart_round", Enable );
	HookEvent( "tf_game_over", Disable );
	RegServerCmd( "mp_tournament_restart", Command_Disable );

	// ConVar for tournament mode
	g_cvTournament = FindConVar( "mp_tournament" );

	// GG ConVars
	g_cvEnabled = CreateConVar( "gg_enabled", "1", "Sets whether calling gg is enabled." );
	g_cvVote = CreateConVar( "gg_vote", "0", "Sets whether a team must vote on gg." );
	g_cvWinnerGG = CreateConVar( "gg_winnerconcede", "0", "Sets whether the winning team can call gg." );
	g_cvWinThreshold = CreateConVar( "gg_winthreshold", "0", "Sets the number of round wins a team must win before their opponents may call gg." );
	g_cvWinDifference = CreateConVar( "gg_windifference", "0", "Sets the difference in round wins required for the losing team to call gg." );
	g_cvTimeLeft = CreateConVar( "gg_timeleft", "0", "Sets the number of minutes left in the game before a team can call gg." );

	// Commands to call gg and cancel the countdown
	RegConsoleCmd( "gg", Command_Concede );
	RegConsoleCmd( "cancel", Command_Cancel );

	// Set all values to defaults
	OnMapStart();
}

// ====[ RESET PLUGIN ]==========================================================

public OnMapStart() {
	ResetCountdown();
	ResetVotes();

	// Not active until tournament match begins
	g_bPluginActive = false;
}

void ResetCountdown()
{
	if ( g_hCountdownTimer != INVALID_HANDLE ) {
		KillTimer( g_hCountdownTimer );
		g_hCountdownTimer = INVALID_HANDLE;
	}

	PrintCenterTextAll( CLEAR_TEXT );

	g_iGGTeam = TFTeam_Unassigned;
	g_iCountdown = NO_COUNTDOWN;
}

// ====[ COMMANDS ]==========================================================

/**
 * Starts gg countdown if ConVar conditions are met.
 *
 * @param client
 *				index of client who called the command
 */
public Action:Command_Concede( int client, args )
{
	// Check for plugin enabled
	if ( !g_cvEnabled.BoolValue ||!g_cvTournament.BoolValue || !g_bPluginActive ) {
		return;
	}

	TFTeam team = TF2_GetClientTeam( client );

	// If countdown in progress
	if ( g_iCountdown != NO_COUNTDOWN ) {
		if ( g_cvVote.BoolValue ) {
			// Player is voting
			if ( team == g_iGGTeam ) {
				AddPlayerVote( client );
			}
		}
		return;
	}

	// Check for valid player
	if ( !IsClientInGame( client ) || !( team == TFTeam_Red || team == TFTeam_Blue ) ) {
		return;
	}

	int redScore = GetTeamScore( _:TFTeam_Red );
	int bluScore = GetTeamScore( _:TFTeam_Blue );

	// Check for winning team
	if ( !g_cvWinnerGG.BoolValue ) {
		if ( team == TFTeam_Red ) {
			if ( redScore >= bluScore ) {
				CPrintToChat( client, "{aliceblue}[GG] {default}You can only call GG when you are losing." );
				return;
			}
		} else {
			if ( bluScore >= redScore ) {
				CPrintToChat( client, "{aliceblue}[GG] {default}You can only call GG when you are losing." );
				return;
			}
		}
	}

	// Check for win threshold
	if ( g_cvWinThreshold.BoolValue ) {
		int score;
		if ( team == TFTeam_Red ) {
			score = bluScore;
		} else {
			score = redScore;
		}

		if ( score < g_cvWinThreshold.IntValue ) {
			CPrintToChat( client, "{aliceblue}[GG] {default}You can not call GG because the win threshold has not been met: %d rounds", g_cvWinThreshold.IntValue );
			return;
		}
	}

	// Check for win difference
	if ( g_cvWinDifference.BoolValue ) {
		int diff = absDiff( redScore, bluScore );
		if ( diff < g_cvWinDifference.IntValue ) {
			CPrintToChat( client, "{aliceblue}[GG] {default}You can not call GG because the win difference has not been met: %d rounds", g_cvWinDifference.IntValue );
			return;
		}
	}

	// Check for time left
	if ( g_cvTimeLeft.BoolValue ) {
		int timeInSeconds;
		GetMapTimeLeft( timeInSeconds );
		int mins = timeInSeconds / 60;
		if ( mins >= g_cvTimeLeft.IntValue ) {
			CPrintToChat( client, "{aliceblue}[GG] {default}You can not call GG because the time left requirement has not been met: %d minutes", g_cvTimeLeft.IntValue );
			return;
		}
	}

	// Initiate GG countdown
	g_iGGTeam = team;
	if ( g_iGGTeam == TFTeam_Red ) {
		g_cTeamBuffer = "RED";
	} else if ( g_iGGTeam == TFTeam_Blue ) {
		g_cTeamBuffer = "BLU";
	}

	if ( g_cvVote.BoolValue ) {
		// Compute majority of votes required
		for ( int i = 1; i < MaxClients; i++ ) {
			if ( IsClientInGame( i ) && TF2_GetClientTeam( i ) == g_iGGTeam ) {
				g_iVoteMajority++;
			}
		}
		g_iVoteMajority /= 2;
		g_iVoteMajority++;
	}

	g_iCountdown = CONCEDE_TIME;
	g_hCountdownTimer = CreateTimer( 1.0, Timer_Countdown, client, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT );
	Timer_Countdown( g_hCountdownTimer, client );
}

/**
 * Cancels gg countdown if called by member of team that is conceding.
 *
 * @param client
 *				index of client who called the command
 */
public Action:Command_Cancel( int client, args )
{
	// Cancel has no effect if gg_vote is enabled
	if ( g_cvVote.BoolValue ) {
		return;
	}

	// Check for plugin enabled
	if ( !g_cvEnabled.BoolValue || !g_cvTournament.BoolValue || !g_bPluginActive ) {
		return;
	}

	TFTeam team = TF2_GetClientTeam( client );

	// Check for valid player
	if ( !IsClientInGame( client ) || !( team == TFTeam_Red || team == TFTeam_Blue ) ) {
		return;
	}

	// Check for conceding team
	if ( team != g_iGGTeam ) {
		return;
	}

	PrintCenterTextAll( CLEAR_TEXT );
	CPrintToChatAllEx( client, "{aliceblue}[GG] {teamcolor}%N {default}cancelled the concession.", client );
	ResetCountdown();
}

// ====[ VOTE FUNCTIONS ]==========================================================

/**
 * Adds a players vote to the gg vote count.
 *
 * @param client
 *				index of client who voted
 */
void AddPlayerVote( int client )
{
	// Check for duplicate votes
	for ( int i = 0; i < MAX_PLAYERS; i++ ) {
		if ( g_iVotingPlayers[ i ] == client ) {
			return;
		}
	}

	// Add vote
	g_iVotingPlayers[ g_iVoteCount ] = client;
	g_iVoteCount++;
	if ( g_iVoteCount != 1 ) {
		int votesLeft = g_iVoteMajority - g_iVoteCount;
		CPrintToChatAllEx( client, "{aliceblue}[GG] {teamcolor}%N {default}voted to gg. %d more vote%s needed.", client, votesLeft, votesLeft == 1 ? "" : "s" );
	}

	// Check for majority
	if ( g_iVoteCount == g_iVoteMajority ) {
		CPrintToChatAllEx( client, "{aliceblue}[GG] {teamcolor}%s {default}voted to concede.", g_cTeamBuffer );
		EndGame();
	}
}

/**
 * Resets all voting counts.
 */
void ResetVotes()
{
	for ( int i = 0; i < MAX_PLAYERS; i++ ) {
		g_iVotingPlayers[ i ] = 0;
	}

	g_iVoteCount = 0;
	g_iVoteMajority = 0;
}

// ====[ HELPER FUNCTIONS ]==========================================================

/**
 * Takes absolute value of difference of two numbers.
 *
 * @param a
 * @param b
 *
 * @return |a - b|
 */
int absDiff( int a, int b )
{
	int c = a - b;
	if ( c < 0 ) {
		c = -c;
	}
	return c;
}

/**
 * Ends the match and resets the tournament mode to the ready up stage.
 */
void EndGame()
{
	Event gg = CreateEvent( "tf_game_over", true );
	FireEvent( gg );
	ServerCommand( "mp_tournament_restart" );
}

// ====[ GG COUNTDOWN ]==========================================================

/**
 * Called every second as countdown ticks down.
 *
 * @param timer
 *				timer handle
 * @param client
 *				index of client who called the command
 */
public Action:Timer_Countdown( Handle:timer, int client ) {
	if ( g_iCountdown == 0 ) {
		if ( g_cvVote.BoolValue ) {
			// Voting countdown finished, majority was not achieved
			CPrintToChatAllEx( client, "{aliceblue}[GG] {teamcolor}%s {default}voted not to concede.", g_cTeamBuffer );
			ResetCountdown();
			ResetVotes();
		} else {
			// Countdown finished, concede game
			ResetCountdown();
			PrintCenterTextAll( CLEAR_TEXT );
			CPrintToChatAllEx( client, "{aliceblue}[GG] {teamcolor}%s {default}conceded.", g_cTeamBuffer );
			EndGame();
		}
		return Plugin_Stop;
	} else {
		// Still counting down...
		for ( int i = 1; i < MaxClients; i++ ) {
			if ( IsClientInGame( i ) ) {
				if ( g_cvVote.BoolValue ) {
					// Voting to concede
					if ( g_iCountdown == CONCEDE_TIME ) {
						if ( TF2_GetClientTeam( i ) == g_iGGTeam ) {
							// Team that is conceding
							CPrintToChatEx( i, client, "{aliceblue}[GG] {teamcolor}%N {default}has started a vote to GG. Type !gg to vote to concede.", client );
						} else {
							// Everyone else
							CPrintToChatEx( i, client, "{aliceblue}[GG] {teamcolor}%N {default}has started a vote to GG.", client );
						}
						AddPlayerVote( client );
					}
				} else {
					// Normal concession
					if ( TF2_GetClientTeam( i ) == g_iGGTeam ) {
						// Team that is conceding
						if ( g_iCountdown == CONCEDE_TIME ) {
							CPrintToChatEx( i, client, "{aliceblue}[GG] {teamcolor}%N {default}wants to call GG. Type !cancel to stop.", client );
						}

						PrintCenterText( i, "Conceding in %i second%s. Type !cancel to stop.", g_iCountdown, g_iCountdown == 1 ? "" : "s" );
					} else {
						// Everyone else
						if ( g_iCountdown == CONCEDE_TIME ) {
							CPrintToChatEx( i, client, "{aliceblue}[GG] {teamcolor}%N {default}is calling GG. {teamcolor}%s {default}will concede in %d seconds.", client, g_cTeamBuffer, g_iCountdown );
						}
					}
				}
			}
		}

		g_iCountdown--;
		return Plugin_Continue;
	}
}

// ====[ SERVER TICK LISTENER ]==========================================================

/**
 * Called every server frame. Checks for end of map time
 * and resets plugin.
 */
public void OnGameFrame()
{
	// Disable plugin when map time runs out
	int time;
	GetMapTimeLeft( time );
	if ( time == 0 ) {
		// Disable
		OnMapStart();
	}
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
