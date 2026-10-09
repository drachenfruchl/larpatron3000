untyped
global function larpatron_CL_Init

global function impersonate

global function getAllPlayerUIDsInLobby

void function debugPrint( var thing ){
	string prefix = "[larpatron3000] "

	printt( prefix + string( thing ) )
}

void function getAllPlayerUIDsInLobby(){
	string result

	array<entity> allPlayers = GetPlayerArray()
	allPlayers.fastremovebyvalue( GetLocalClientPlayer() )

	foreach( entity player in allPlayers )
		result += GetUID( player ) + " "

	SetConVarString( "cv_larpatron3000_allLobbyUIDs", result.slice( 0, -1 ) )
}

bool function checkUsage( array<string> args, int lbounds, int ubounds, string usage ){
	int argc = args.len()

	if( argc < lbounds || argc > ubounds ){
		debugPrint( usage )
		return false
	}
	return true
}

void function larpatron_CL_Init(){
	RegisterSignal( "larpatron3000_stopNameSpoof" )
}

// [CONCOMMAND] Usage: impersonate "<player namepart>" "<message>"
void function impersonate( array<string> args = [] ){
	if( GetGameState() < 0 ){
		debugPrint( "Dont use this in the lobby..." )
		return
	}

	if( !checkUsage( args, 2, 2, "Usage: impersonate <player namepart> \"<message>\"" ) )
		return

	string 	namepart = args[0]
	entity 	player = dtool_getPlayerMatch_entity( namepart )
	if( !player ){
		debugPrint( format( "No player starting with \"%s\" found!", namepart ) )
		return
	}
	string 	playerNameWithClantag = player.GetPlayerNameWithClanTag()

	bool 	isEnemy = dtool_isEnemy( player )

	string 	message = args[1]

	// Enough newlines to hide message author on default height chat windows
	string newlinePrefix = "\\n\\n\\n\\n\\n\\n\\n\\n\\n\\n\\n"
	entity self = GetLocalClientPlayer()

	// Impersonated person is on opposite team?
	// Teamchat: Use enemy colors
	// Global: Use friendly colors

	// Impersonated person is on same team?
	// Teamchat: Use friendly colors
	// Global: Use enemy colors

	string formattedTeam = format(
		newlinePrefix + "\\%s%s: \\d%s",
		( isEnemy ? "e" : "t" ),
		playerNameWithClantag,
		message
	)

	string formattedGlobal = format(
		newlinePrefix + "\\%s%s: \\d%s",
		( isEnemy ? "t" : "e" ),
		playerNameWithClantag,
		message
	)

	// !! SEND GLOBAL FIRST !!
	self.ClientCommand( "say " 		+ formattedGlobal )
	self.ClientCommand( "say_team " + formattedTeam )
}