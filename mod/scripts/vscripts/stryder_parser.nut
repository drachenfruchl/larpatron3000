// Parser for the JSON-ish text returned by the vanilla Stryder backend.
//
// Supported differences from strict JSON:
//   - root braces are optional
//   - // and /* */ comments
//   - quoted or unquoted object keys
//   - ':' or '=' between a key and its value
//   - trailing commas
//   - newline-separated members without commas
//   - unquoted string values
//
// Keep this as a typed rSquirrel file. The parser state is a struct because
// Respawn's Squirrel compiler does not treat nested closures like JavaScript.

global function ParseStryderResponse
global function StryderGetString
global function StryderGetInt
global function StryderGetFloat
global function StryderGetBool

string function StryderGetString( table t, string key )
{
    var v = t[ key ]
    switch ( type( v ) )
    {
        case "string":  return expect string( v )
        case "int": 	return string( v )
        case "float":   return string( v )
        case "bool":    return v ? "true" : "false"
    }
    throw "StryderGetString: key '" + key + "' has unsupported type"
	return ""
}

int function StryderGetInt( table t, string key )
{
    var v = t[ key ]
    switch ( type( v ) )
    {
        case "int": 	return expect int( v )
        case "float":   return int( v )
        case "string":  return int( v )
        case "bool":    return v ? 1 : 0
    }
    throw "StryderGetInt: key '" + key + "' has unsupported type"
	return 0
}

float function StryderGetFloat( table t, string key )
{
    var v = t[ key ]
    switch ( type( v ) )
    {
        case "float":   return expect float( v )
        case "int": 	return float( v )
        case "string":  return float( v )
        case "bool":    return v ? 1.0 : 0.0
    }
    throw "StryderGetFloat: key '" + key + "' has unsupported type"
	return 0.0
}

bool function StryderGetBool( table t, string key )
{
    var v = t[ key ]
    switch ( type( v ) )
    {
        case "bool":    return expect bool( v )
        case "int": 	return v != 0
        case "float":   return v != 0.0
        case "string":  return v == "true" || v == "True" || v == "1"
    }
    throw "StryderGetBool: key '" + key + "' has unsupported type"
	return false
}

struct StryderParserState
{
	string text
	int pos
}

table function ParseStryderResponse( string raw )
{
	StryderParserState parser
	parser.text = raw

	StryderParser_SkipWhitespace( parser )

	if ( parser.pos >= parser.text.len() )
		StryderParser_Fail( parser, "empty input" )

	table result

	if ( StryderParser_CharAt( parser, parser.pos ) == "{" )
		result = StryderParser_ParseObject( parser, true )
	else
		result = StryderParser_ParseObject( parser, false )

	StryderParser_SkipWhitespace( parser )

	if ( parser.pos != parser.text.len() )
		StryderParser_Fail( parser, "unexpected trailing data" )

	return result
}

string function StryderParser_CharAt( StryderParserState parser, int index )
{
	return parser.text.slice( index, index + 1 )
}

bool function StryderParser_IsWhitespace( string character )
{
	return character == " " || character == "\t" || character == "\r" || character == "\n"
}

bool function StryderParser_IsDigit( string character )
{
	return character == "0" || character == "1" || character == "2" || character == "3" || character == "4" ||
		character == "5" || character == "6" || character == "7" || character == "8" || character == "9"
}

void function StryderParser_Fail( StryderParserState parser, string message )
{
	throw "ParseStryderResponse: " + message + " at offset " + parser.pos.tostring()
}

// Returns true when the skipped whitespace or comments contained a newline.
bool function StryderParser_SkipWhitespace( StryderParserState parser )
{
	bool hadNewline = false

	while ( parser.pos < parser.text.len() )
	{
		string character = StryderParser_CharAt( parser, parser.pos )

		if ( StryderParser_IsWhitespace( character ) )
		{
			if ( character == "\r" || character == "\n" )
				hadNewline = true

			parser.pos++
			continue
		}

		if ( character != "/" || parser.pos + 1 >= parser.text.len() )
			break

		string nextCharacter = StryderParser_CharAt( parser, parser.pos + 1 )

		if ( nextCharacter == "/" )
		{
			parser.pos += 2

			while ( parser.pos < parser.text.len() )
			{
				character = StryderParser_CharAt( parser, parser.pos )
				if ( character == "\r" || character == "\n" )
					break

				parser.pos++
			}

			continue
		}

		if ( nextCharacter != "*" )
			break

		parser.pos += 2
		bool closed = false

		while ( parser.pos < parser.text.len() )
		{
			character = StryderParser_CharAt( parser, parser.pos )

			if ( character == "\r" || character == "\n" )
				hadNewline = true

			if ( character == "*" && parser.pos + 1 < parser.text.len() && StryderParser_CharAt( parser, parser.pos + 1 ) == "/" )
			{
				parser.pos += 2
				closed = true
				break
			}

			parser.pos++
		}

		if ( !closed )
			StryderParser_Fail( parser, "unterminated block comment" )
	}

	return hadNewline
}

string function StryderParser_ParseString( StryderParserState parser )
{
	string quote = StryderParser_CharAt( parser, parser.pos )
	parser.pos++

	string result = ""

	while ( parser.pos < parser.text.len() )
	{
		string character = StryderParser_CharAt( parser, parser.pos )
		parser.pos++

		if ( character == quote )
			return result

		if ( character != "\\" )
		{
			result += character
			continue
		}

		if ( parser.pos >= parser.text.len() )
			StryderParser_Fail( parser, "unterminated escape sequence" )

		string escaped = StryderParser_CharAt( parser, parser.pos )
		parser.pos++

		switch ( escaped )
		{
			case "\"":
				result += "\""
				break
			case "'":
				result += "'"
				break
			case "\\":
				result += "\\"
				break
			case "/":
				result += "/"
				break
			case "b":
				result += "\b"
				break
			case "f":
				result += "\f"
				break
			case "n":
				result += "\n"
				break
			case "r":
				result += "\r"
				break
			case "t":
				result += "\t"
				break
			case "u":
				// rSquirrel strings are byte strings. Preserve the escape rather
				// than corrupting non-ASCII code points during conversion.
				if ( parser.pos + 4 > parser.text.len() )
					StryderParser_Fail( parser, "short Unicode escape" )

				result += "\\u" + parser.text.slice( parser.pos, parser.pos + 4 )
				parser.pos += 4
				break
			default:
				result += escaped
				break
		}
	}

	StryderParser_Fail( parser, "unterminated string" )
	return ""
}

string function StryderParser_ParseKey( StryderParserState parser )
{
	StryderParser_SkipWhitespace( parser )

	if ( parser.pos >= parser.text.len() )
		StryderParser_Fail( parser, "expected object key" )

	string character = StryderParser_CharAt( parser, parser.pos )

	if ( character == "\"" || character == "'" )
		return StryderParser_ParseString( parser )

	int start = parser.pos

	while ( parser.pos < parser.text.len() )
	{
		character = StryderParser_CharAt( parser, parser.pos )

		if ( StryderParser_IsWhitespace( character ) || character == ":" || character == "=" || character == "," ||
			character == "{" || character == "}" || character == "[" || character == "]" )
			break

		parser.pos++
	}

	if ( start == parser.pos )
		StryderParser_Fail( parser, "expected object key" )

	return parser.text.slice( start, parser.pos )
}

bool function StryderParser_LooksLikeNumber( string token )
{
	if ( token.len() == 0 )
		return false

	int pos = 0
	string character = token.slice( pos, pos + 1 )

	if ( character == "+" || character == "-" )
	{
		pos++
		if ( pos >= token.len() )
			return false
	}

	int digitsBeforeDot = 0
	while ( pos < token.len() && StryderParser_IsDigit( token.slice( pos, pos + 1 ) ) )
	{
		pos++
		digitsBeforeDot++
	}

	int digitsAfterDot = 0
	if ( pos < token.len() && token.slice( pos, pos + 1 ) == "." )
	{
		pos++
		while ( pos < token.len() && StryderParser_IsDigit( token.slice( pos, pos + 1 ) ) )
		{
			pos++
			digitsAfterDot++
		}
	}

	if ( digitsBeforeDot == 0 && digitsAfterDot == 0 )
		return false

	if ( pos < token.len() && ( token.slice( pos, pos + 1 ) == "e" || token.slice( pos, pos + 1 ) == "E" ) )
	{
		pos++

		if ( pos < token.len() && ( token.slice( pos, pos + 1 ) == "+" || token.slice( pos, pos + 1 ) == "-" ) )
			pos++

		int exponentDigits = 0
		while ( pos < token.len() && StryderParser_IsDigit( token.slice( pos, pos + 1 ) ) )
		{
			pos++
			exponentDigits++
		}

		if ( exponentDigits == 0 )
			return false
	}

	return pos == token.len()
}

var function StryderParser_ParseBareValue( StryderParserState parser )
{
	int start = parser.pos

	while ( parser.pos < parser.text.len() )
	{
		string character = StryderParser_CharAt( parser, parser.pos )

		if ( character == "," || character == "}" || character == "]" || character == "\r" || character == "\n" )
			break

		if ( character == "/" && parser.pos + 1 < parser.text.len() )
		{
			string nextCharacter = StryderParser_CharAt( parser, parser.pos + 1 )
			if ( nextCharacter == "/" || nextCharacter == "*" )
				break
		}

		parser.pos++
	}

	int end = parser.pos
	while ( end > start && StryderParser_IsWhitespace( StryderParser_CharAt( parser, end - 1 ) ) )
		end--

	if ( start == end )
		StryderParser_Fail( parser, "expected value" )

	string token = parser.text.slice( start, end )

	if ( token == "null" )
		return null
	if ( token == "true" )
		return true
	if ( token == "false" )
		return false

	if ( StryderParser_LooksLikeNumber( token ) )
	{
		if ( token.find( "." ) != null || token.find( "e" ) != null || token.find( "E" ) != null )
			return token.tofloat()


		if ( token.len() > 9 )
			return token

		return token.tointeger()
	}

	return token
}

array function StryderParser_ParseArray( StryderParserState parser )
{
	array result = []

	if ( StryderParser_CharAt( parser, parser.pos ) != "[" )
		StryderParser_Fail( parser, "expected '['" )

	parser.pos++
	StryderParser_SkipWhitespace( parser )

	if ( parser.pos < parser.text.len() && StryderParser_CharAt( parser, parser.pos ) == "]" )
	{
		parser.pos++
		return result
	}

	while ( parser.pos < parser.text.len() )
	{
		result.append( StryderParser_ParseValue( parser ) )

		bool hadNewline = StryderParser_SkipWhitespace( parser )
		if ( parser.pos >= parser.text.len() )
			StryderParser_Fail( parser, "unterminated array" )

		string character = StryderParser_CharAt( parser, parser.pos )

		if ( character == "]" )
		{
			parser.pos++
			return result
		}

		if ( character == "," )
		{
			parser.pos++
			StryderParser_SkipWhitespace( parser )

			if ( parser.pos < parser.text.len() && StryderParser_CharAt( parser, parser.pos ) == "]" )
			{
				parser.pos++
				return result
			}

			continue
		}

		if ( hadNewline )
			continue

		StryderParser_Fail( parser, "expected ',' or ']' after array value" )
	}

	StryderParser_Fail( parser, "unterminated array" )
	return result
}

table function StryderParser_ParseObject( StryderParserState parser, bool hasOpeningBrace )
{
	table result = {}

	if ( hasOpeningBrace )
	{
		if ( parser.pos >= parser.text.len() || StryderParser_CharAt( parser, parser.pos ) != "{" )
			StryderParser_Fail( parser, "expected '{'" )

		parser.pos++
	}

	StryderParser_SkipWhitespace( parser )

	while ( parser.pos < parser.text.len() )
	{
		if ( hasOpeningBrace && StryderParser_CharAt( parser, parser.pos ) == "}" )
		{
			parser.pos++
			return result
		}

		string key = StryderParser_ParseKey( parser )
		StryderParser_SkipWhitespace( parser )

		if ( parser.pos >= parser.text.len() )
			StryderParser_Fail( parser, "expected ':' or '=' after object key" )

		string separator = StryderParser_CharAt( parser, parser.pos )
		if ( separator != ":" && separator != "=" )
			StryderParser_Fail( parser, "expected ':' or '=' after object key" )

		parser.pos++
		var value = StryderParser_ParseValue( parser )

		// === NEU: Behandlung doppelter Schlüssel ===
		if ( key in result )
		{
			var existing = result[key]
			if ( type( existing ) == "array" )
			{
				expect array( existing )
				existing.append( value )          // weiteres Element anhängen
			}
			else
			{
				array items = [ existing, value ] // erstes Duplikat -> Array erzeugen
				result[key] = items
			}
		}
		else
		{
			result[key] <- value                 // erster Wert für diesen Schlüssel
		}
		// =========================================

		bool hadNewline = StryderParser_SkipWhitespace( parser )

		if ( parser.pos >= parser.text.len() )
		{
			if ( hasOpeningBrace )
				StryderParser_Fail( parser, "unterminated object" )

			return result
		}

		string character = StryderParser_CharAt( parser, parser.pos )

		if ( character == "," )
		{
			parser.pos++
			StryderParser_SkipWhitespace( parser )

			if ( hasOpeningBrace && parser.pos < parser.text.len() && StryderParser_CharAt( parser, parser.pos ) == "}" )
			{
				parser.pos++
				return result
			}

			continue
		}

		if ( hasOpeningBrace && character == "}" )
		{
			parser.pos++
			return result
		}

		if ( hadNewline )
			continue

		StryderParser_Fail( parser, "expected ',' or '}' after object member" )
	}

	if ( hasOpeningBrace )
		StryderParser_Fail( parser, "unterminated object" )

	return result
}

var function StryderParser_ParseValue( StryderParserState parser )
{
	StryderParser_SkipWhitespace( parser )

	if ( parser.pos >= parser.text.len() )
		StryderParser_Fail( parser, "expected value" )

	string character = StryderParser_CharAt( parser, parser.pos )

	if ( character == "{" )
		return StryderParser_ParseObject( parser, true )
	if ( character == "[" )
		return StryderParser_ParseArray( parser )
	if ( character == "\"" || character == "'" )
		return StryderParser_ParseString( parser )

	return StryderParser_ParseBareValue( parser )
}
