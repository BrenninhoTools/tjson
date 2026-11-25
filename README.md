TJSON
=====

The tolerant JSON parser and encoder for Haxe, maintained by BrenninhoTools.

TJSON reads everything standard JSON accepts plus:

1. Single quoted strings
2. Unquoted keys and values
3. `/* block */` and `// line` comments
4. Trailing and missing commas
5. Hex numbers (`0x1F`), exponents (`1e3`), leading `+`, `NaN` and `Infinity`
6. Escapes `\b`, `\f`, `\v`, `\0`, `\xHH`, `\uHHHH` with surrogate pairs, and line continuations
7. A UTF-8 byte order mark at the start

Errors report the file name, line and column.

Install
-------

```
haxelib git tjson https://github.com/BrenninhoTools/tjson
```

Add `-lib tjson` to your hxml or `<haxelib name="tjson"/>` to your Lime project.

Parsing
-------

```haxe
import tjson.TJSON;

var object = TJSON.parse("{key:'value', list:[1, 2, 3,], // comment\n}");
var maybe = TJSON.tryParse(text, {});
var config = TJSON.parseFile("config.json");
```

`tryParse` returns the fallback instead of throwing. `parseFile` and `saveFile` are available on sys targets.

Encoding
--------

```haxe
TJSON.encode({myKey: 'myValue'});
TJSON.encode(data, 'fancy');
TJSON.encode(data, 'pretty');
TJSON.stringify(data);
TJSON.stringify(data, '\t');
```

`encode` keeps class instances (`_hxcls`), `Date` values and shared references, so `parse` can rebuild them. Classes can implement `TJ_noEncode():Array<String>` to skip fields and `TJ_unserialize()` to run after loading.

`stringify` writes plain standard JSON: no class names, dates as text and an error on circular references. Pass an indent to pretty print it.

Maps of any key type, `List`, `Bytes` (as Base64) and enum values are supported. `NaN` and infinite numbers are written as `null`, and strings are fully escaped, including control characters.

Custom styles implement `tjson.EncodeStyle`. `SimpleStyle`, `FancyStyle` and `PrettyStyle` are included.

Tests
-----

```
haxe test.hxml --interp
```

License
-------

BSD, see the original project by martamius.
