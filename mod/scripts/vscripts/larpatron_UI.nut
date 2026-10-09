untyped
global function larpatron_UI_Init

global function inviteToCommunity

global function sendOpenInvite

global function getRoomForCommunity

global function sendNetworkMsg

global function spoofNetworkName
global function spoofNetworkName_inf
global function clearNetworkName

global function viewUser

global function scan4parties

global function bigScan4parties

global function viewCommunity

struct{
    string NUCLEUS_TOKEN 	= "<YOUR NUCLEUS TOKEN HERE>"
    string SECURITY_TOKEN 	= "<YOUR SECURITY TOKEN HERE>"
    string UID 				= "<YOUR UID HERE>"
}file

void function larpatron_UI_Init(){
    RegisterSignal( "larpatron3000_stopNameSpoof" )
}

void function debugPrint( var thing ){
    string prefix = "[larpatron3000] "

    printt( prefix + string( thing ) )
}

bool function checkUsage( array<string> args, int lbounds, int ubounds, string usage ){
    int argc = args.len()

    if( argc < lbounds || argc > ubounds){
        debugPrint( usage )
        return false
    }
    return true
}

// Does not exist on UI VM
function TableKeysToArray( tab )
{
    Assert( type( tab ) == "table", "Not a table" )

    local resultArray = []
    resultArray.resize( tab.len() )
    int currentArrayIndex = 0
    foreach ( key, val in tab )
    {
        resultArray[ currentArrayIndex ] = key
        ++currentArrayIndex
    }

    return resultArray
}

array function Larpatron_AsArray( var value )
{
    if ( value == null )
        return []
    if ( type( value ) == "array" )
        return expect array( value )
    return [ value ]
}

array function RemoveDuplicateRooms( array openInvites )
{
    array result 	= []
    table seenRooms = {}

    foreach( table invite in openInvites )
    {
        if( !( "room" in invite ) )
            continue

        var room = invite[ "room" ]
        if( !( room in seenRooms ) )
        {
            seenRooms[ room ] <- true
            result.append( invite )
        }
    }

    return result
}

void function inviteToCommunity( array<string> args = [] ){
    if( !checkUsage( args, 2, 2, "Usage: inviteToCommunity \"<community id>\" \"<uid>\" OR: \"true\"" ) )
        return

    int	communityID	= args[0].tointeger()
    var uidOrLobby	= ( args[1].tointeger() == 0 ? args[1] == "true" : args[1] )

    thread inviteToCommunity_Internal( communityID, uidOrLobby )
}

void function inviteToCommunity_Internal( int communityID, var uidOrLobby ){
    int oldCommunityID = GetCurrentCommunityId()

    if( communityID <= 1 ){
        debugPrint( "Not a valid community ID! (Also no invites to ADV)" )
        return
    }

    bool alreadyJoined = AreWeInCommunity( communityID )

    if( alreadyJoined ){
        SetActiveCommunity( communityID )
    } else {
        debugPrint( format( "Trying to temporarily join community %i!", communityID ) )

        if( !canInviteToCommunity( communityID ) ){
            debugPrint( "Community is private!" )
            return
        }

        JoinCommunity( communityID )
    }

    debugPrint( "Joined community!" )
    wait 0.1

    if( typeof( uidOrLobby ) == "bool" ){
        if( !uidOrLobby ){
            debugPrint( "Last parameter must be an UID or equal \"true\"")
            return
        }

        RunClientScript( "getAllPlayerUIDsInLobby" )
        debugPrint( "Getting all UIDs of players in same lobby. . ." )

        wait 0.2

        foreach( string uid in split( GetConVarString( "cv_larpatron3000_allLobbyUIDs" ), " " ) ){
            InviteUserToCommunity( uid, communityID )
            debugPrint( "Invite sent!" )

            wait 0.15
        }
    } else if( typeof( uidOrLobby ) == "string" ){
        if( int( uidOrLobby ) <= 0 ){
            debugPrint( "Not a valid UID!" )
            return
        }

        InviteUserToCommunity( uidOrLobby, communityID )
        debugPrint( "Invite sent!" )
    } else {
        SetActiveCommunity( oldCommunityID )
        debugPrint( "Unexpected error!" )
        return
    }

    if( oldCommunityID != communityID ){
        if( !alreadyJoined ){
            wait 0.1
            LeaveCommunity( communityID )
        }
        debugPrint( "Left temporary community!" )

        wait 0.1
        SetActiveCommunity( oldCommunityID )
        debugPrint( "Rejoined original community!" )
    }

    ClientCommand( "recheck" )
}

bool function canJoinCommunity( int communityID ){
    CommunitySettings ornull settings = GetCommunitySettings( communityID )

    while ( settings == null ){
        wait 0
        settings = GetCommunitySettings( communityID )
    }
    expect CommunitySettings( settings )

    bool isJoinable = ( settings.membershipType != "invite" )

    debugPrint( format( "%s is %sjoinable!", settings.name, ( isJoinable ? "" : "NOT " ) ) )

    return isJoinable
}

bool function canInviteToCommunity( int communityID ){
    CommunitySettings ornull settings = GetCommunitySettings( communityID )

    while ( settings == null ){
        wait 0
        settings = GetCommunitySettings( communityID )
    }
    expect CommunitySettings( settings )

    bool isInviteable = ( settings.membershipType != "invite" && settings.invitesAllowed )

    debugPrint( format( "%s is %sinviteable!", settings.name, ( isInviteable ? "" : "NOT " ) ) )

    return isInviteable
}

void function sendOpenInvite( array<string> args = [] ){
    if( !checkUsage( args, 1, 5, "Usage: sendOpenInvite \"<communityID>\" optional: \"<name>\" \"<duration>\" \"<playlist>\" \"<numSlots>\"" ) )
        return

    int argc = args.len()

    int 	communityID = args[0].tointeger()
    string 	name 		= ( argc >= 2 ? args[1] : "\0" )
    int 	duration 	= ( argc >= 3 ? int( clamp( int( args[2] ), 0, 120 ) ) : 10 )
    string 	playlist 	= ( argc >= 4 ? args[3] : "" )
    int 	numSlots	= ( argc == 5 ? int( clamp( int( args[4] ), 2, 9999 ) ) : 5 )

    thread sendOpenInvite_Internal( communityID, name, duration, playlist, numSlots )
}

void function sendOpenInvite_Internal( int communityID, string name = "\0", int duration = 10, string playlist = "", int numSlots = 5 ){
    if( name == "\0" )
        name = GetPlayerName()

    string ornull room = getRoomForCommunity_Internal( communityID )
    if( !room )
        return
    expect string( room )

    // Build the query parameters
    table< string, array< string > > queryParameters = {
        [ "securityToken" ] = [ file.SECURITY_TOKEN ],
        [ "3pToken" ] 		= [ "PC_PLACEHOLDER_3P_TOKEN" ],
        [ "NucleusToken" ] 	= [ file.NUCLEUS_TOKEN ],
        [ "ver" ] 		 	= [ "51" ],
        [ "numSlots" ] 	 	= [ string( numSlots ) ],
        [ "name" ] 		 	= [ name ],
        [ "dc" ] 		 	= [ "" ],
        [ "language" ]		= [ "" ],
        [ "inviteType" ] 	= [ ( playlist == "private_match" ? "private_match" : "playlist" ) ],
        [ "playlist" ] 	 	= [ ( playlist == "private_match" ? "private_match" : ( playlist == "" ? "-" : playlist ) ) ],
        [ "inviteRoom" ] 	= [ room ],
        [ "duration" ] 	 	= [ string( duration ) ]
    }

    // Build the request struct
    HttpRequest request
    request.method          = HttpRequestMethod.POST
    request.url             = format( "https://R2-pc-sub.stryder.respawn.com/chat.php?qt=party-create&type=createParty&numSlots=6&hardware=PC&uid=%s&change=1&cprot=7", file.UID ) // Not file.UID because this is the uid we want to check
    request.queryParameters = queryParameters
    request.userAgent 		= "Respawn HTTPS/1.0"

    void functionref( HttpRequestResponse ) onSuccess = void function ( HttpRequestResponse response ) : (){
    }

    void functionref( HttpRequestFailure ) onFailure = void function ( HttpRequestFailure response ) : (){
    }

    NSHttpRequest( request, onSuccess, onFailure )
}

void function getRoomForCommunity( array<string> args = [] ){
    if( !checkUsage( args, 1, 1, "Usage: getRoomForCommunity \"<communityID>\"" ) )
        return

    int communityID = args[0].tointeger()

    thread getRoomForCommunity_Internal( communityID )
}

string ornull function getRoomForCommunity_Internal( int communityID ){
    table state = {
        finished 	= false,
        data 		= null
    }

    int oldCommunityID = GetCurrentCommunityId()
    bool alreadyJoined = AreWeInCommunity( communityID )

    if( communityID <= 0 ){
        debugPrint( "Not a valid community ID!" )
        return ""
    }

    if( alreadyJoined ){
        SetActiveCommunity( communityID )
        debugPrint( "Already in community" )
    } else {
        if( !canJoinCommunity( communityID ) ){
            debugPrint( "Community is private!" )
            return ""
        }
        JoinCommunity( communityID )
    }

    debugPrint( "Joined temporary community!" )

    // Build the query parameters
    table< string, array< string > > queryParameters = {
        [ "securityToken" ] = [ file.SECURITY_TOKEN ],
        [ "3pToken" ] 		= [ "PC_PLACEHOLDER_3P_TOKEN" ],
        [ "NucleusToken" ] 	= [ file.NUCLEUS_TOKEN ],
        [ "ver" ] 			= [ "51" ],
        [ "hardware" ] 		= [ "PC" ],
        [ "uid" ] 			= [ file.UID ],
        [ "dc" ] 			= [ "" ]
    }

    // Build the request struct
    HttpRequest request
    request.method          = HttpRequestMethod.POST
    request.url             = "https://R2-pc.stryder.respawn.com/me.php?qt=me&"
    request.queryParameters = queryParameters
    request.userAgent 		= "Respawn HTTPS/1.0"

    void functionref( HttpRequestResponse ) onSuccess = void function ( HttpRequestResponse response ) : ( state ){
        table json = ParseStryderResponse( response.body )
        array communityData = expect array( TableKeysToArray( json["communities"] ) )
        string currentCommunityName = expect string( communityData[0] )
        string room = expect string( json["communities"][ currentCommunityName ][ "room" ] )
        debugPrint( room )

        debugPrint( "Successfully sent request" )
        state.data = room
        state.finished = true
    }

    void functionref( HttpRequestFailure ) onFailure = void function ( HttpRequestFailure response ) : ( state ){
        debugPrint( "Failed sending request!" )
        state.finished = true
    }

    NSHttpRequest( request, onSuccess, onFailure )

    while( !state.finished )
        wait 0

    if( oldCommunityID != communityID ){
        if( !alreadyJoined && communityID != 1 ){
            wait 0.1
            LeaveCommunity( communityID )
        }
        debugPrint( "Left temporary community!" )

        wait 0.2
        SetActiveCommunity( oldCommunityID )
        debugPrint( "Rejoined original community!" )
    }

    ClientCommand( "recheck" )

    return expect string ornull( state.data )
}

void function sendNetworkMsg( array<string> args = [] ){
    if( !checkUsage( args, 1, 3, "Usage: sendNetworkMsg \"<message>\" optional: \"<name>\" \"<communityID>\"" ) )
        return

    int argc = args.len()

    string message 		= args[0]
    string name 		= ( argc >= 2 ? args[1] : "\0" )
    int    communityID 	= ( argc == 3 ? int( args[2] ) : 0 )

    thread sendNetworkMsg_Internal( message, name, communityID )
}

// This needs to have an _Internal because getCurrentRoom() is async
void function sendNetworkMsg_Internal( string message, string name = "\0", int communityID = 0 ){
    // Use provided room if possible
    string ornull room = getRoomForCommunity_Internal( communityID == 0 ? GetCurrentCommunityId() : communityID )
    if( !room )
        return
    expect string( room )

    // This way we can still use empty names or escaped backslashes as names
    if( name == "\0" ){
        name = GetPlayerName()
    } else {
        if( !applyNetworkMessageNameChange() ){
            debugPrint( "Failed to apply name change!" )
            return
        }
    }

    // Build the query parameters
    table< string, array< string > > queryParameters = {
        [ "name" ] 			= [ name ],
        [ "room" ]			= [ room ],
        [ "text" ] 			= [ message ],
        [ "securityToken" ] = [ file.SECURITY_TOKEN ],
        [ "3pToken" ] 		= [ "PC_PLACEHOLDER_3P_TOKEN" ],
        [ "NucleusToken" ] 	= [ file.NUCLEUS_TOKEN ]
    }

    // Build the request struct
    HttpRequest request
    request.method          = HttpRequestMethod.POST
    request.url             = format( "https://R2-pc-sub.stryder.respawn.com/chat.php?qt=chat-send&type=chat&post=1&hardware=PC&uid=%s", file.UID )
    request.queryParameters = queryParameters
    request.userAgent 		= "Respawn HTTPS/1.0"

    void functionref( HttpRequestResponse ) onSuccess = void function ( HttpRequestResponse response ) : (){
        debugPrint( "Successfully sent message! " + strip( response.body )  )
    }

    void functionref( HttpRequestFailure ) onFailure = void function ( HttpRequestFailure response ) : (){
        debugPrint( "Failed to send message: " + response.errorMessage )
    }

    NSHttpRequest( request, onSuccess, onFailure )
}

// This does "nothing" in itself but we need to do it so that custom names get applied when sending names to other rooms
// I dont like that i have to do this
bool function applyNetworkMessageNameChange(){
    table state = {
        finished 	= false,
        success 	= false
    }

    // Build the query parameters
    table< string, array< string > > queryParameters = {
        [ "ver" ] 			= [ "51" ],
        [ "hardware" ] 		= [ "PC" ],
        [ "uid" ] 			= [ file.UID ],
        [ "dc" ] 			= [ "" ],
        [ "securityToken" ] = [ file.SECURITY_TOKEN ],
        [ "3pToken" ] 		= [ "PC_PLACEHOLDER_3P_TOKEN" ],
        [ "NucleusToken" ] 	= [ file.NUCLEUS_TOKEN ]
    }

    // Build the request struct
    HttpRequest request
    request.method          = HttpRequestMethod.POST
    request.url             = "https://R2-pc.stryder.respawn.com/me.php?qt=me&"
    request.queryParameters = queryParameters
    request.userAgent 		= "Respawn HTTPS/1.0"

    void functionref( HttpRequestResponse ) onSuccess = void function ( HttpRequestResponse response ) : ( state ){
        state.success  = true
        state.finished = true

        debugPrint( "Applied network message name change" )
    }

    void functionref( HttpRequestFailure ) onFailure = void function ( HttpRequestFailure response ) : ( state ){
        state.success  = false
        state.finished = true
    }

    NSHttpRequest( request, onSuccess, onFailure )

    while( !state.finished )
        wait 0

    return expect bool( state.success )
}

// [CONCOMMAND] Usage: spoofNetworkName "<name>"
void function spoofNetworkName( array<string> args = [] ){
    if( !checkUsage( args, 1, 1, "spoofNetworkName \"<name>\" (\\\\n for newlines)" ) )
        return

    string name = args[0]

    thread spoofNetworkName_Internal( name )
}

void function spoofNetworkName_Internal( string name ){
    table state = {
        finished = false
    }

    if( name == "" )
        name = "\x1b"

    if( name.find( "\\n" ) != null ){
        while( name.find( "\\n" ) != null )
            name = StringReplace( name, "\\n", "\n" )
        name = "\x1b" + name + "\x1b"
    }

    // Build the query parameters
    table< string, array< string > > queryParameters = {
        [ "hardware" ]      = [ "PC" ],
        [ "uid" ]           = [ file.UID ],
        [ "name" ]          = [ name ],
        [ "securityToken" ] = [ file.SECURITY_TOKEN ],
        [ "3pToken" ] 		= [ "PC_PLACEHOLDER_3P_TOKEN" ],
        [ "NucleusToken" ] 	= [ file.NUCLEUS_TOKEN ]
    }

    // Build the request struct
    HttpRequest request
    request.method          = HttpRequestMethod.POST
    request.url             = "https://R2-pc.stryder.respawn.com/me.php?qt=me&"
    request.queryParameters = queryParameters
    request.userAgent 		= "Respawn HTTPS/1.0"

    void functionref( HttpRequestResponse ) onSuccess = void function ( HttpRequestResponse response ) : ( state ){
        debugPrint( "Successfully spoofed network chat name for a short time!" )
        state.finished = true
    }

    void functionref( HttpRequestFailure ) onFailure = void function ( HttpRequestFailure response ) : ( state ){
        debugPrint( "Failed to spoof network name!" )
        state.finished = true
    }

    NSHttpRequest( request, onSuccess, onFailure )

    while( !state.finished )
        wait 0
}

// [CONCOMMAND] Usage: spoofNetworkName "<name>"
void function spoofNetworkName_inf( array<string> args = [] ){
    if( !checkUsage( args, 1, 2, "spoofNetworkName_inf \"<name>\"" ) )
        return

    int argc = args.len()

    string name = args[0]

    thread spoofNetworkName_inf_Internal( name )
}

void function spoofNetworkName_inf_Internal( string name ){
    EndSignal( uiGlobal.signalDummy, "larpatron3000_stopNameSpoof" )

    for(;;){
        spoofNetworkName( [ name ] )
        wait 5
    }
}

// [CONCOMMAND] Usage: clearNetworkName
void function clearNetworkName(){
    Signal( uiGlobal.signalDummy, "larpatron3000_stopNameSpoof" )

    string name = GetPlayerName()

    // Build the query parameters
    table< string, array< string > > queryParameters = {
        [ "hardware" ]      = [ "PC" ],
        [ "uid" ]           = [ file.UID ],
        [ "name" ]          = [ name ],
        [ "securityToken" ] = [ file.SECURITY_TOKEN ],
        [ "3pToken" ] 		= [ "PC_PLACEHOLDER_3P_TOKEN" ],
        [ "NucleusToken" ] 	= [ file.NUCLEUS_TOKEN ]
    }

    // Build the request struct
    HttpRequest request
    request.method          = HttpRequestMethod.POST
    request.url             = "https://R2-pc.stryder.respawn.com/me.php?qt=me&"
    request.queryParameters = queryParameters
    request.userAgent 		= "Respawn HTTPS/1.0"

    void functionref( HttpRequestResponse ) onSuccess = void function ( HttpRequestResponse response ) : (){
        debugPrint( "Successfully restored default network chat name!" )
    }

    void functionref( HttpRequestFailure ) onFailure = void function ( HttpRequestFailure response ) : (){
        debugPrint( "Failed to restore network chat name!" )
    }

    NSHttpRequest( request, onSuccess, onFailure )
}

void function viewUser( array<string> args = [] ){
    if( !checkUsage( args, 1, 1, "Usage: viewUser \"<uid>\"" ) )
        return

    string uid = args[0]

    // Build the request struct
    HttpRequest request
    request.method          = HttpRequestMethod.POST
    request.url             = "https://R2-pc.stryder.respawn.com/user.php?qt=user-getinfo&hardware=PC&uid=" + uid
    request.userAgent 		= "Respawn HTTPS/1.0"

    void functionref( HttpRequestResponse ) onSuccess = void function ( HttpRequestResponse response ) : (){
        table userData = ParseStryderResponse( response.body )
        printUserData( userData )
    }

    void functionref( HttpRequestFailure ) onFailure = void function ( HttpRequestFailure response ) : (){
        debugPrint( response.errorMessage )
    }

    NSHttpRequest( request, onSuccess, onFailure )
}

void function printUserData( table userData ){
    userData = expect table( userData[ "userInfo" ] )

    debugPrint(
        "\n" +
        "\n" + "Name    : " + userData[ "name" ] 	+
        "\n" + "Kills   : " + userData[ "kills" ] 	+
        "\n" + "Wins    : " + userData[ "wins" ] 	+
        "\n" + "Credits : " + ( "credits" in userData ? userData[ "credits" ] : "None" ) +
        "\n" + "Level   : " + ( userData[ "gen" ].tointeger() == 100 && userData[ "lvl" ].tointeger() == 50 ? "MAX" : format( "%s%i", ( userData[ "gen" ].tointeger() == 1 ? "" : format( "G%i.", userData[ "gen" ] ) ) , userData[ "lvl" ] ) ) +
        "\n"
    )

    foreach( table communityData in userData[ "communities" ] ){
        // string clantag = expect string( communityData[ "clantag" ] )
        // string clantagBytes
        // for( int i = 0; i < clantag.len(); i++ )
        // 	clantagBytes += "[" + clantag[i].tointeger() + "] "

        // string name = expect string( communityData[ "name" ] )
        // string nameBytes
        // for( int i = 0; i < name.len(); i++ )
        // 	nameBytes += "[" + name[i].tointeger() + "] "

        debugPrint(
            "\n" +
            "\n" + "Clantag : " + communityData[ "clantag" ] + //" / " + clantagBytes +
            "\n" + "Name    : " + communityData[ "name" ] 	 + //" / " + nameBytes +
            "\n" + "Level   : " + communityData[ "level" ] 	 +
            "\n" + "ID      : " + communityData[ "id" ] 	 +
            "\n"
        )
    }
}

void function scan4parties( array<string> args = [] ){
    if( !checkUsage( args, 1, 1, "Usage: scan4parties \"<communityID>\"" ) )
        return

    int communityID = int( args[0] )

    thread scan4parties_Internal( communityID, true )
}

array ornull function scan4parties_Internal( int communityID, bool print = false ) {
    table state = {
        data = null,
        gotResponse = false
    }

    void functionref( HttpRequestResponse ) onSuccess = void function ( HttpRequestResponse response ) : ( state, print, communityID ) {
        table json = ParseStryderResponse( response.body )

        array openInvites = Larpatron_AsArray( "openInvite" in json ? json[ "openInvite" ] : null )
        if( openInvites.len() == 0 )
            return

        openInvites = RemoveDuplicateRooms( openInvites )
        if( openInvites.len() == 0 )
            return

        state.data = getOpenInviteData( openInvites )

        if( print )
            printOpenInviteDataArray( communityID, expect array( state.data ) )

        state.gotResponse = true
    }

    void functionref( HttpRequestFailure ) onFailure = void function ( HttpRequestFailure response ) : ( state ) {
        debugPrint( response.errorMessage )
    }

    int requestTimeout = 2

    HttpRequest request
    request.method          = HttpRequestMethod.GET
    request.userAgent       = "Respawn HTTPS/1.0"
    request.timeout         = requestTimeout

    foreach( int sub in [ 3, 5 ] ) {
        request.url = format( "https://r2-pc-sub%i.stryder.respawn.com/sub/%i?qt=sub&", sub, communityID )
        NSHttpRequest( request, onSuccess, onFailure )

        float t_start = Time()
        while( Time() < t_start + requestTimeout && !state.gotResponse )
            wait 0

        if( state.gotResponse )
            break
    }

    return expect array ornull( state.data )
}

array function getOpenInviteData( array scanResults ) {
    array result = []

    foreach( table openInviteData in scanResults ) {
        array entry

        entry.append(
            "\n" +
            "\n" + "Room         : " + openInviteData[ "room" ] +
            "\n" + "Creator      : " + format( "%s (%s)", string( openInviteData[ "creatorName" ] ), string( openInviteData[ "uid" ] ) ) +
            "\n" + "Playlist     : " + openInviteData[ "playlist" ] +
            "\n" + "Localization : " + format( "%s (%s)", string( openInviteData[ "region" ] ), string( openInviteData[ "language" ] ) ) +
            "\n" + "Slots        : " + format( "%s / %s", string( openInviteData[ "slotsUsed" ] ), string( openInviteData[ "numSlots" ] ) ) +
            "\n"
        )

        // player0 is always originator
        for( int i = 1; i < 32; i++ ) {
            try {
                entry.append(
                    "\n" + "Name : " + openInviteData[ format( "player%iname", i ) ] +
                    "\n" + "UID  : " + openInviteData[ format( "player%iuid",  i ) ] +
                    "\n"
                )
            } catch(e) { break }
        }

        result.append( entry )
    }

    return result
}

void function printOpenInviteDataArray( int communityID, array openInviteDataArray ) {
    debugPrint( format( "\n\nDisplaying open invites for community %i\n", communityID ) )

    foreach( array openInviteData in openInviteDataArray ) {
        string result = ""
        foreach( string data in openInviteData )
            result += data

        debugPrint( result )
    }
}

void function bigScan4parties( array<string> args = [] ){
    if( !checkUsage( args, 2, 2, "Usage: bigScan4parties \"<max communities>\" \"<min members>\"" ) )
        return

    int argc = args.len()

    int maxCommunities 	= int( args[0] )//( argc >= 1 ? int( args[0] ) : 50 )
    int minMembers 		= int( args[1] )//( argc == 2 ? int( args[1] ) : 0 )

    thread bigScan4parties_Internal( maxCommunities, minMembers )
}

void function bigScan4parties_Internal( int maxCommunities = 50, int minMembers = 0 ){
    table state = {
        finished   = false,
        pending    = 0,
        results    = []
    }

    // Build the query parameters
    table< string, array< string > > queryParameters = {
        [ "securityToken" ] = [ file.SECURITY_TOKEN ],
        [ "3pToken" ] 		= [ "PC_PLACEHOLDER_3P_TOKEN" ],
        [ "NucleusToken" ] 	= [ file.NUCLEUS_TOKEN ],

        [ "language" ] 		= [ "english" ],
        [ "dc" ] 			= [ "" ],
        [ "category" ] 		= [ "" ],
        [ "competitive" ] 	= [ "" ],
        [ "open" ] 			= [ "open" ],
        [ "playtime" ] 		= [ "" ],
        [ "micPref" ] 		= [ "" ],
        [ "name" ] 			= [ "" ],
        [ "clantag" ] 		= [ "" ]
    }

    HttpRequest request
    request.method          = HttpRequestMethod.POST
    request.url             = format(
        "https://R2-pc.stryder.respawn.com/communities.php?qt=communities-browse&browseall=1&start=0&max=%i&hardware=PC&uid=%s&notmine=0&minMembers=%i",
        maxCommunities,
        file.UID,
        minMembers
    )
    request.queryParameters = queryParameters
    request.userAgent 		= "Respawn HTTPS/1.0"

    void functionref( HttpRequestResponse ) onSuccess = void function ( HttpRequestResponse response ) : ( state ){
        thread function():( response, state ){
            table json = ParseStryderResponse( response.body )
            table browseall = expect table( json[ "browseall" ] )
            array communities = Larpatron_AsArray( browseall[ "community" ] )

            state.pending = communities.len()

            foreach( table communityData in communities ){
                int communityID = StryderGetInt( communityData, "id" )

                thread function():( communityID, state ){
                    array ornull scanResult = scan4parties_Internal( communityID )
                    if( scanResult != null ){
                        state.results.append( { id = communityID, data = expect array( scanResult ) } )
                    }
                    state.pending--
                }()
            }

            while( state.pending > 0 )
                wait 0

            wait 1

            foreach( table resultEntry in state.results ){
                printOpenInviteDataArray( expect int( resultEntry.id ), expect array( resultEntry.data ) )
            }

            state.finished = true
        }()
    }

    void functionref( HttpRequestFailure ) onFailure = void function ( HttpRequestFailure response ) : ( state ){
        state.finished = true
    }

    NSHttpRequest( request, onSuccess, onFailure )

    while( !state.finished )
        wait 0
}

// void function printNetworkData( table scanResults ){
//     table browseall = expect table( scanResults[ "browseall" ] )
//     array communities = Larpatron_AsArray( browseall[ "community" ] )

//     foreach( table communityData in communities ){
//         debugPrint(
//             "\n"													+
//             "\n" + "ID         : " + communityData[ "id" ] 			+
//             "\n" + "Clantag    : " + communityData[ "clantag" ] 	+
//             "\n" + "Name       : " + communityData[ "name" ] 		+
//             "\n" + "Members    : " + communityData[ "users" ]		+
//             "\n" + "CreatorUID : " + communityData[ "creatorUID" ]	+
//             "\n" + "Membership : " + communityData[ "membership" ]	+
//             "\n"
//         )
//     }
// }

void function viewCommunity( array<string> args = [] ){
    if( !checkUsage( args, 1, 1, "Usage: viewCommunity \"<community id>\"" ) )
        return

    int communityID = int( args[0] )

    // Build the query parameters
    table< string, array< string > > queryParameters = {
        [ "securityToken" ] = [ file.SECURITY_TOKEN ],
        [ "3pToken" ] 		= [ "PC_PLACEHOLDER_3P_TOKEN" ],
        [ "NucleusToken" ] 	= [ file.NUCLEUS_TOKEN ]
    }

    HttpRequest request
    request.method          = HttpRequestMethod.POST
    request.url             = format(
        "https://R2-pc.stryder.respawn.com/communities.php?qt=communities-getsettings&hardware=PC&uid=%s&getsettings=1&id=%i",
        file.UID,
        communityID
    )
    request.queryParameters = queryParameters
    request.userAgent 		= "Respawn HTTPS/1.0"

    void functionref( HttpRequestResponse ) onSuccess = void function ( HttpRequestResponse response ) : (){
        table json = ParseStryderResponse( response.body )

        table communitySettings = expect table( json[ "communitySettings" ] )

        string creatorUID   = StryderGetString( communitySettings, "creatorUID" )
        string creatorName  = StryderGetString( communitySettings, "creatorName" )
        string creator      = format( "%s (%s)", creatorName, creatorUID )

        string name         = StryderGetString( communitySettings, "name" )
        while( name.find( "\n" ) != null )
            name = StringReplace( name, "\n", "/n" )

        int     nameLen     = name.len()
        if( nameLen >= 50 )
            name = format( "%s... (%i remaining)", name.slice( 0, 50 ), nameLen - 50 )

        string clanTag      = StryderGetString( communitySettings, "clantag" )
        while( clanTag.find( "\n" ) != null )
            clanTag = StringReplace( clanTag, "\n", "/n" )

        string motd         = StryderGetString( communitySettings, "motd" )
        while( motd.find( "\n" ) != null )
            motd = StringReplace( motd, "\n", "/n" )

        int   kills         = StryderGetInt( communitySettings, "kills" )
        int   deaths        = StryderGetInt( communitySettings, "deaths" )
        float KD            = float( kills ) / max( float( deaths ), 1.0 )

        int   matches       = StryderGetInt( communitySettings, "matches" )
        int   wins          = StryderGetInt( communitySettings, "wins" )
        int   losses        = StryderGetInt( communitySettings, "losses" )
        float winratio      = float( wins ) / max( float( matches ), 1.0 )

        string  stats       = ( creatorUID == file.UID ) ? (
            "\n" + "Matches         : " + matches								                            +
            "\n" + "Wins            : " + wins									                            +
            "\n" + "Losses          : " + losses								                            +
            "\n" + "Win %           : " + format( "%.1f%%", winratio * 100.0 )                              +

            "\n" + "Kills           : " + kills									                            +
            "\n" + "Deaths          : " + deaths								                            +
            "\n" + "KD              : " + format( "%.2f", KD )
        ) : (
            "\n" + "Wins            : " + wins									                            +
            "\n" + "Kills           : " + kills
        )

        debugPrint(
            "\n"																                            +
            "\n" + "ID              : " + StryderGetString( communitySettings, "id" ) 			            +
            "\n" + "Creator         : " + creator                                                           +
            "\n" + "Clantag         : " + clanTag 		                                                    +
            "\n" + "Name            : " + name 			                                                    +
            "\n" + "MOTD            : " + motd                      			                            +

            "\n" + "Members         : " + StryderGetInt( communitySettings, "memberCount" )		            +
            "\n" + "Membership      : " + StryderGetString( communitySettings, "open" )			            +
            "\n" + "Invites allowed : " + string( StryderGetBool( communitySettings, "invitesAllowed" ) )   +

            "\n" + stats                                                                                    +
            "\n"
        )
    }

    void functionref( HttpRequestFailure ) onFailure = void function ( HttpRequestFailure response ) : (){
    }

    NSHttpRequest( request, onSuccess, onFailure )
}