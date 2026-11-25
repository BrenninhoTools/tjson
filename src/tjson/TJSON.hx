package tjson;

using StringTools;

class TJSON
{
	public static var OBJECT_REFERENCE_PREFIX:String = "@~obRef#";
	public static var VERSION(default, never):String = "2.0.0";

	public static function parse(json:String, ?fileName:String = "JSON Data", ?stringProcessor:String->Dynamic = null):Dynamic
	{
		return new TJSONParser(json, fileName, stringProcessor).doParse();
	}

	public static function tryParse(json:String, ?fallback:Dynamic = null, ?fileName:String = "JSON Data"):Dynamic
	{
		if (json == null) return fallback;
		try
		{
			return new TJSONParser(json, fileName).doParse();
		}
		catch (e:Dynamic)
		{
			return fallback;
		}
	}

	#if sys
	public static function parseFile(path:String, ?stringProcessor:String->Dynamic = null):Dynamic
	{
		return parse(sys.io.File.getContent(path), path, stringProcessor);
	}

	public static function saveFile(path:String, obj:Dynamic, ?style:Dynamic = null):Void
	{
		sys.io.File.saveContent(path, encode(obj, style));
	}
	#end

	public static function encode(obj:Dynamic, ?style:Dynamic = null, useCache:Bool = true):String
	{
		return new TJSONEncoder(useCache).doEncode(obj, style);
	}

	public static function stringify(obj:Dynamic, ?indent:String = null):String
	{
		var encoder:TJSONEncoder = new TJSONEncoder(false);
		encoder.writeClassNames = false;
		return encoder.doEncode(obj, indent != null && indent.length > 0 ? new PrettyStyle(indent) : null);
	}
}

class TJSONParser
{
	var pos:Int;
	var json:String;
	var length:Int;
	var lastSymbolQuoted:Bool;
	var fileName:String;
	var currentLine:Int;
	var lineStart:Int;
	var cache:Array<Dynamic>;
	var strProcessor:String->Dynamic;

	public function new(vjson:String, ?vfileName:String = "JSON Data", ?stringProcessor:String->Dynamic = null)
	{
		json = vjson != null ? vjson : "";
		length = json.length;
		fileName = vfileName != null ? vfileName : "JSON Data";
		currentLine = 1;
		lineStart = 0;
		lastSymbolQuoted = false;
		pos = length > 0 && StringTools.fastCodeAt(json, 0) == 0xFEFF ? 1 : 0;
		strProcessor = stringProcessor;
		cache = [];
	}

	public function doParse():Dynamic
	{
		try
		{
			var symbol:String = getNextSymbol();
			if (!lastSymbolQuoted && symbol == "{") return doObject();
			if (!lastSymbolQuoted && symbol == "[") return doArray();
			return convertSymbolToProperType(symbol);
		}
		catch (e:String)
		{
			throw fileName + " on line " + currentLine + ", column " + (pos - lineStart + 1) + ": " + e;
		}
	}

	function doObject():Dynamic
	{
		var o:Dynamic = {};
		var isClassOb:Bool = false;
		cache.push(o);
		while (pos < length)
		{
			var key:String = getNextSymbol();
			var keyQuoted:Bool = lastSymbolQuoted;
			if (!keyQuoted && key == ",") continue;
			if (!keyQuoted && key == "}")
			{
				if (isClassOb && hasMethod(o, "TJ_unserialize")) o.TJ_unserialize();
				return o;
			}
			if (!keyQuoted && key.length == 0) break;

			var separator:String = getNextSymbol();
			if (lastSymbolQuoted || separator != ":") throw "Expected ':' after key '" + key + "' but got '" + separator + "' instead.";

			var v:String = getNextSymbol();

			if (key == "_hxcls")
			{
				if (v.startsWith("Date@"))
				{
					o = Date.fromTime(Std.parseFloat(v.substr(5)));
				}
				else
				{
					var cls:Class<Dynamic> = Type.resolveClass(v);
					if (cls == null) throw "Invalid class name - " + v;
					o = Type.createEmptyInstance(cls);
				}
				cache[cache.length - 1] = o;
				isClassOb = true;
				continue;
			}

			var val:Dynamic = (!lastSymbolQuoted && v == "{") ? doObject() : ((!lastSymbolQuoted && v == "[") ? doArray() : convertSymbolToProperType(v));
			Reflect.setField(o, key, val);
		}
		throw "Unexpected end of data. Expected '}'";
	}

	function doArray():Dynamic
	{
		var a:Array<Dynamic> = [];
		while (pos < length)
		{
			var val:String = getNextSymbol();
			if (!lastSymbolQuoted)
			{
				if (val == ",") continue;
				if (val == "]") return a;
				if (val.length == 0) break;
				if (val == "{")
				{
					a.push(doObject());
					continue;
				}
				if (val == "[")
				{
					a.push(doArray());
					continue;
				}
			}
			a.push(convertSymbolToProperType(val));
		}
		throw "Unexpected end of data. Expected ']'";
	}

	function convertSymbolToProperType(symbol:String):Dynamic
	{
		if (lastSymbolQuoted)
		{
			if (symbol.startsWith(TJSON.OBJECT_REFERENCE_PREFIX))
			{
				var idx:Null<Int> = Std.parseInt(symbol.substr(TJSON.OBJECT_REFERENCE_PREFIX.length));
				if (idx != null && idx >= 0 && idx < cache.length) return cache[idx];
			}
			return strProcessor != null ? strProcessor(symbol) : symbol;
		}

		var number:Dynamic = parseNumber(symbol);
		if (number != null) return number;

		switch (symbol.toLowerCase())
		{
			case "true":
				return true;
			case "false":
				return false;
			case "null" | "undefined":
				return null;
			case "nan":
				return Math.NaN;
			case "infinity" | "+infinity":
				return Math.POSITIVE_INFINITY;
			case "-infinity":
				return Math.NEGATIVE_INFINITY;
			default:
				return symbol;
		}
	}

	static function parseNumber(s:String):Dynamic
	{
		var len:Int = s.length;
		if (len == 0) return null;
		var i:Int = 0;
		var c:Int = StringTools.fastCodeAt(s, 0);
		var negative:Bool = false;
		if (c == "-".code || c == "+".code)
		{
			negative = c == "-".code;
			i++;
			if (i >= len) return null;
		}

		if (len - i > 2 && StringTools.fastCodeAt(s, i) == "0".code && (StringTools.fastCodeAt(s, i + 1) | 0x20) == "x".code)
		{
			var value:Float = 0;
			var j:Int = i + 2;
			while (j < len)
			{
				var h:Int = hexValue(StringTools.fastCodeAt(s, j));
				if (h < 0) return null;
				value = value * 16 + h;
				j++;
			}
			if (negative) value = -value;
			return fitsInt(value) ? Std.int(value) : value;
		}

		var digits:Int = 0;
		var isFloat:Bool = false;
		while (i < len)
		{
			c = StringTools.fastCodeAt(s, i);
			if (c >= "0".code && c <= "9".code) digits++;
			else break;
			i++;
		}
		if (i < len && StringTools.fastCodeAt(s, i) == ".".code)
		{
			isFloat = true;
			i++;
			while (i < len)
			{
				c = StringTools.fastCodeAt(s, i);
				if (c >= "0".code && c <= "9".code) digits++;
				else break;
				i++;
			}
		}
		if (digits == 0) return null;
		if (i < len && (StringTools.fastCodeAt(s, i) | 0x20) == "e".code)
		{
			isFloat = true;
			i++;
			if (i < len && (StringTools.fastCodeAt(s, i) == "+".code || StringTools.fastCodeAt(s, i) == "-".code)) i++;
			var expDigits:Int = 0;
			while (i < len)
			{
				c = StringTools.fastCodeAt(s, i);
				if (c >= "0".code && c <= "9".code) expDigits++;
				else break;
				i++;
			}
			if (expDigits == 0) return null;
		}
		if (i != len) return null;

		var text:String = StringTools.fastCodeAt(s, 0) == "+".code ? s.substr(1) : s;
		if (!isFloat)
		{
			var value:Float = Std.parseFloat(text);
			if (fitsInt(value)) return Std.parseInt(text);
			return value;
		}
		return Std.parseFloat(text);
	}

	static inline function fitsInt(value:Float):Bool
	{
		return value <= 2147483647.0 && value >= -2147483648.0;
	}

	static function hexValue(c:Int):Int
	{
		if (c >= "0".code && c <= "9".code) return c - "0".code;
		if (c >= "a".code && c <= "f".code) return c - "a".code + 10;
		if (c >= "A".code && c <= "F".code) return c - "A".code + 10;
		return -1;
	}

	static function hasMethod(o:Dynamic, name:String):Bool
	{
		try
		{
			return Reflect.isFunction(Reflect.getProperty(o, name));
		}
		catch (e:Dynamic)
		{
			return false;
		}
	}

	inline function newLine(at:Int):Void
	{
		currentLine++;
		lineStart = at + 1;
	}

	function skipIgnored():Void
	{
		while (pos < length)
		{
			var c:Int = StringTools.fastCodeAt(json, pos);
			switch (c)
			{
				case " ".code, "\t".code, "\r".code, 0xFEFF, 0xA0:
					pos++;
				case "\n".code:
					newLine(pos);
					pos++;
				case "/".code if (pos + 1 < length && StringTools.fastCodeAt(json, pos + 1) == "/".code):
					pos += 2;
					while (pos < length)
					{
						var l:Int = StringTools.fastCodeAt(json, pos);
						if (l == "\n".code || l == "\r".code) break;
						pos++;
					}
				case "/".code if (pos + 1 < length && StringTools.fastCodeAt(json, pos + 1) == "*".code):
					pos += 2;
					var closed:Bool = false;
					while (pos < length)
					{
						var b:Int = StringTools.fastCodeAt(json, pos);
						if (b == "*".code && pos + 1 < length && StringTools.fastCodeAt(json, pos + 1) == "/".code)
						{
							pos += 2;
							closed = true;
							break;
						}
						if (b == "\n".code) newLine(pos);
						pos++;
					}
					if (!closed) throw "Unterminated block comment";
				default:
					return;
			}
		}
	}

	function getNextSymbol():String
	{
		lastSymbolQuoted = false;
		skipIgnored();
		if (pos >= length) return "";

		var c:Int = StringTools.fastCodeAt(json, pos);
		switch (c)
		{
			case "{".code:
				pos++;
				return "{";
			case "}".code:
				pos++;
				return "}";
			case "[".code:
				pos++;
				return "[";
			case "]".code:
				pos++;
				return "]";
			case ",".code:
				pos++;
				return ",";
			case ":".code:
				pos++;
				return ":";
			case '"'.code, "'".code:
				pos++;
				lastSymbolQuoted = true;
				return readString(c);
			default:
				return readSymbol();
		}
	}

	function readSymbol():String
	{
		var start:Int = pos;
		while (pos < length)
		{
			var c:Int = StringTools.fastCodeAt(json, pos);
			if (c == " ".code || c == "\n".code || c == "\r".code || c == "\t".code || c == ",".code || c == ":".code || c == "}".code
				|| c == "]".code || c == "{".code || c == "[".code)
				break;
			if (c == "/".code && pos + 1 < length)
			{
				var n:Int = StringTools.fastCodeAt(json, pos + 1);
				if (n == "/".code || n == "*".code) break;
			}
			pos++;
		}
		return json.substring(start, pos);
	}

	function readString(quote:Int):String
	{
		var start:Int = pos;
		var buffer:StringBuf = null;
		while (pos < length)
		{
			var c:Int = StringTools.fastCodeAt(json, pos);
			if (c == quote)
			{
				var result:String = json.substring(start, pos);
				if (buffer != null)
				{
					buffer.add(result);
					result = buffer.toString();
				}
				pos++;
				return result;
			}
			if (c == "\n".code) newLine(pos);
			if (c != "\\".code)
			{
				pos++;
				continue;
			}

			if (buffer == null) buffer = new StringBuf();
			buffer.addSub(json, start, pos - start);
			pos++;
			if (pos >= length) break;
			var e:Int = StringTools.fastCodeAt(json, pos++);
			switch (e)
			{
				case '"'.code, "'".code, "\\".code, "/".code, "`".code:
					buffer.addChar(e);
				case "n".code:
					buffer.addChar("\n".code);
				case "r".code:
					buffer.addChar("\r".code);
				case "t".code:
					buffer.addChar("\t".code);
				case "b".code:
					buffer.addChar(8);
				case "f".code:
					buffer.addChar(12);
				case "v".code:
					buffer.addChar(11);
				case "0".code:
					buffer.addChar(0);
				case "\n".code:
					newLine(pos - 1);
				case "\r".code:
					if (pos < length && StringTools.fastCodeAt(json, pos) == "\n".code)
					{
						newLine(pos);
						pos++;
					}
				case "x".code:
					buffer.addChar(readHex(2));
				case "u".code:
					var code:Int = readHex(4);
					if (code >= 0xD800 && code <= 0xDBFF && pos + 1 < length && StringTools.fastCodeAt(json, pos) == "\\".code
						&& StringTools.fastCodeAt(json, pos + 1) == "u".code)
					{
						var save:Int = pos;
						pos += 2;
						var low:Int = readHex(4);
						if (low >= 0xDC00 && low <= 0xDFFF) code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00);
						else
						{
							pos = save;
							code = 0xFFFD;
						}
					}
					else if (code >= 0xD800 && code <= 0xDFFF)
					{
						code = 0xFFFD;
					}
					buffer.addChar(code);
				default:
					throw "Invalid escape sequence '\\" + String.fromCharCode(e) + "'";
			}
			start = pos;
		}
		throw "Unexpected end of data. Expected ( " + String.fromCharCode(quote) + " )";
	}

	function readHex(count:Int):Int
	{
		var value:Int = 0;
		for (i in 0...count)
		{
			if (pos >= length) throw "Unfinished escape sequence";
			var h:Int = hexValue(StringTools.fastCodeAt(json, pos++));
			if (h < 0) throw "Not a hex digit";
			value = (value << 4) | h;
		}
		return value;
	}
}

class TJSONEncoder
{
	public var writeClassNames:Bool = true;

	var cache:Array<Dynamic>;
	var stack:Array<Dynamic>;
	var uCache:Bool;

	public function new(useCache:Bool = true)
	{
		uCache = useCache;
		cache = [];
		stack = [];
	}

	public function doEncode(obj:Dynamic, ?style:Dynamic = null):String
	{
		var st:EncodeStyle = Std.isOfType(style, EncodeStyle) ? style : (style == "fancy" ? new FancyStyle() : (style == "pretty" ? new PrettyStyle() : new SimpleStyle()));
		if (Std.isOfType(obj, Array) || Std.isOfType(obj, List)) return encodeIterable(obj, st, 0);
		if (Std.isOfType(obj, haxe.Constraints.IMap)) return encodeMap(obj, st, 0);
		if (isPlainValue(obj))
		{
			var value:String = encodeValue(obj, st, 0);
			return value != null ? value : "null";
		}
		cacheEncode(obj);
		return encodeObject(obj, st, 0);
	}

	static function isPlainValue(value:Dynamic):Bool
	{
		return value == null || Std.isOfType(value, String) || Std.isOfType(value, Bool) || Std.isOfType(value, Int) || Std.isOfType(value, Float)
			|| Reflect.isFunction(value) || !Reflect.isObject(value) || Reflect.isEnumValue(value);
	}

	function enter(obj:Dynamic):Void
	{
		if (!uCache)
		{
			for (item in stack)
				if (item == obj) throw "Circular reference found while encoding. Enable the reference cache to keep it.";
			stack.push(obj);
		}
	}

	inline function leave():Void
	{
		if (!uCache) stack.pop();
	}

	function encodeObject(obj:Dynamic, style:EncodeStyle, depth:Int):String
	{
		enter(obj);
		var buffer:StringBuf = new StringBuf();
		var fieldCount:Int = 0;
		var dontEncodeFields:Array<String> = null;
		var cls:Class<Dynamic> = Type.getClass(obj);
		var fields:Array<String> = cls != null ? Type.getInstanceFields(cls) : Reflect.fields(obj);

		if (cls != null)
		{
			if (writeClassNames)
			{
				var className:String = Type.getClassName(cls);
				if (className == "Date") className += "@" + Std.string((cast obj : Date).getTime());
				buffer.add(style.firstEntry(depth));
				fieldCount++;
				buffer.add('"_hxcls"' + style.keyValueSeperator(depth));
				buffer.add(quote(className));
			}
			else if (Std.isOfType(obj, Date))
			{
				leave();
				return quote((cast obj : Date).toString());
			}

			var noEncode:Dynamic = Reflect.field(obj, "TJ_noEncode");
			if (Reflect.isFunction(noEncode)) dontEncodeFields = Reflect.callMethod(obj, noEncode, []);
		}

		for (field in fields)
		{
			if (dontEncodeFields != null && dontEncodeFields.indexOf(field) >= 0) continue;
			var value:Dynamic = cls != null ? Reflect.getProperty(obj, field) : Reflect.field(obj, field);
			if (Reflect.isFunction(value)) continue;
			var vStr:String = encodeValue(value, style, depth);
			if (vStr == null) continue;
			if (fieldCount++ > 0) buffer.add(style.entrySeperator(depth));
			else buffer.add(style.firstEntry(depth));
			buffer.add(quote(field));
			buffer.add(style.keyValueSeperator(depth));
			buffer.add(vStr);
		}

		leave();
		return fieldCount > 0 ? style.beginObject(depth) + buffer.toString() + style.endObject(depth) : "{}";
	}

	function encodeMap(obj:haxe.Constraints.IMap<Dynamic, Dynamic>, style:EncodeStyle, depth:Int):String
	{
		enter(obj);
		var buffer:StringBuf = new StringBuf();
		var fieldCount:Int = 0;
		for (key in obj.keys())
		{
			var vStr:String = encodeValue(obj.get(key), style, depth);
			if (vStr == null) continue;
			if (fieldCount++ > 0) buffer.add(style.entrySeperator(depth));
			else buffer.add(style.firstEntry(depth));
			buffer.add(quote(Std.string(key)));
			buffer.add(style.keyValueSeperator(depth));
			buffer.add(vStr);
		}
		leave();
		return fieldCount > 0 ? style.beginObject(depth) + buffer.toString() + style.endObject(depth) : "{}";
	}

	function encodeIterable(obj:Dynamic, style:EncodeStyle, depth:Int):String
	{
		enter(obj);
		var buffer:StringBuf = new StringBuf();
		var fieldCount:Int = 0;
		var values:Array<Dynamic> = Std.isOfType(obj, Array) ? obj : Lambda.array((obj : List<Dynamic>));
		for (value in values)
		{
			var vStr:String = encodeValue(value, style, depth);
			if (fieldCount++ > 0) buffer.add(style.entrySeperator(depth));
			else buffer.add(style.firstEntry(depth));
			buffer.add(vStr != null ? vStr : "null");
		}
		leave();
		return fieldCount > 0 ? style.beginArray(depth) + buffer.toString() + style.endArray(depth) : "[]";
	}

	function cacheEncode(value:Dynamic):String
	{
		if (!uCache) return null;
		for (c in 0...cache.length)
			if (cache[c] == value) return '"' + TJSON.OBJECT_REFERENCE_PREFIX + c + '"';
		cache.push(value);
		return null;
	}

	function encodeValue(value:Dynamic, style:EncodeStyle, depth:Int):String
	{
		if (value == null) return "null";
		if (Std.isOfType(value, Bool)) return value ? "true" : "false";
		if (Std.isOfType(value, Int)) return Std.string(value);
		if (Std.isOfType(value, Float))
		{
			var f:Float = value;
			return Math.isFinite(f) ? Std.string(f) : "null";
		}
		if (Std.isOfType(value, String)) return quote(value);
		if (Reflect.isFunction(value)) return null;
		if (Std.isOfType(value, Array) || Std.isOfType(value, List)) return encodeIterable(value, style, depth + 1);
		if (Std.isOfType(value, haxe.Constraints.IMap)) return encodeMap(value, style, depth + 1);
		if (Std.isOfType(value, haxe.io.Bytes)) return quote(haxe.crypto.Base64.encode(value));
		if (Reflect.isEnumValue(value)) return quote(Std.string(value));
		if (Reflect.isObject(value))
		{
			var ret:String = cacheEncode(value);
			if (ret != null) return ret;
			return encodeObject(value, style, depth + 1);
		}
		return null;
	}

	public static function quote(s:String):String
	{
		var buffer:StringBuf = null;
		var start:Int = 0;
		var len:Int = s.length;
		for (i in 0...len)
		{
			var c:Int = StringTools.fastCodeAt(s, i);
			var escape:String = switch (c)
			{
				case '"'.code: '\\"';
				case "\\".code: "\\\\";
				case "\n".code: "\\n";
				case "\r".code: "\\r";
				case "\t".code: "\\t";
				case 8: "\\b";
				case 12: "\\f";
				case 0x2028: "\\u2028";
				case 0x2029: "\\u2029";
				default: c < 0x20 ? "\\u" + StringTools.hex(c, 4) : null;
			}
			if (escape == null) continue;
			if (buffer == null)
			{
				buffer = new StringBuf();
				buffer.addChar('"'.code);
			}
			buffer.addSub(s, start, i - start);
			buffer.add(escape);
			start = i + 1;
		}
		if (buffer == null) return '"' + s + '"';
		buffer.addSub(s, start, len - start);
		buffer.addChar('"'.code);
		return buffer.toString();
	}
}

interface EncodeStyle
{
	public function beginObject(depth:Int):String;
	public function endObject(depth:Int):String;
	public function beginArray(depth:Int):String;
	public function endArray(depth:Int):String;
	public function firstEntry(depth:Int):String;
	public function entrySeperator(depth:Int):String;
	public function keyValueSeperator(depth:Int):String;
}

class SimpleStyle implements EncodeStyle
{
	public function new() {}

	public function beginObject(depth:Int):String
	{
		return "{";
	}

	public function endObject(depth:Int):String
	{
		return "}";
	}

	public function beginArray(depth:Int):String
	{
		return "[";
	}

	public function endArray(depth:Int):String
	{
		return "]";
	}

	public function firstEntry(depth:Int):String
	{
		return "";
	}

	public function entrySeperator(depth:Int):String
	{
		return ",";
	}

	public function keyValueSeperator(depth:Int):String
	{
		return ":";
	}
}

class IndentedStyle
{
	public var tab(default, null):String;

	var charTimesNCache:Array<String>;

	public function new(tab:String)
	{
		this.tab = tab;
		charTimesNCache = [""];
	}

	function charTimesN(n:Int):String
	{
		while (charTimesNCache.length <= n)
			charTimesNCache.push(charTimesNCache[charTimesNCache.length - 1] + tab);
		return charTimesNCache[n];
	}
}

class FancyStyle extends IndentedStyle implements EncodeStyle
{
	public function new(tab:String = "    ")
	{
		super(tab);
	}

	public function beginObject(depth:Int):String
	{
		return "{\n";
	}

	public function endObject(depth:Int):String
	{
		return "\n" + charTimesN(depth) + "}";
	}

	public function beginArray(depth:Int):String
	{
		return "[\n";
	}

	public function endArray(depth:Int):String
	{
		return "\n" + charTimesN(depth) + "]";
	}

	public function firstEntry(depth:Int):String
	{
		return charTimesN(depth + 1) + " ";
	}

	public function entrySeperator(depth:Int):String
	{
		return "\n" + charTimesN(depth + 1) + ",";
	}

	public function keyValueSeperator(depth:Int):String
	{
		return " : ";
	}
}

class PrettyStyle extends IndentedStyle implements EncodeStyle
{
	public function new(tab:String = "\t")
	{
		super(tab);
	}

	public function beginObject(depth:Int):String
	{
		return "{";
	}

	public function endObject(depth:Int):String
	{
		return "\n" + charTimesN(depth) + "}";
	}

	public function beginArray(depth:Int):String
	{
		return "[";
	}

	public function endArray(depth:Int):String
	{
		return "\n" + charTimesN(depth) + "]";
	}

	public function firstEntry(depth:Int):String
	{
		return "\n" + charTimesN(depth + 1);
	}

	public function entrySeperator(depth:Int):String
	{
		return ",\n" + charTimesN(depth + 1);
	}

	public function keyValueSeperator(depth:Int):String
	{
		return ": ";
	}
}
