Changelog
=========

2.0.0
-----

- Rewrote the scanner on char codes with substring copies, about twice as fast and far fewer allocations.
- Fixed `\u` escapes with lowercase hex digits, the character after a line comment being skipped and wrong line numbers.
- Added `\b`, `\f`, `\v`, `\0`, `\x` escapes, surrogate pairs, exponents, hex numbers, `NaN`, `Infinity` and BOM handling.
- Errors include the column.
- Dates keep millisecond timestamps that do not fit an `Int`.
- The string processor passed to `parse` is now applied to quoted values.
- The encoder escapes keys and control characters, writes `NaN` as `null`, encodes every map type, `Bytes` and enums, and writes empty containers as `{}` and `[]`.
- Added `TJSON.stringify`, `TJSON.tryParse`, `TJSON.parseFile`, `TJSON.saveFile` and `PrettyStyle`.
- The haxelib now lives at the repository root, so `haxelib git` works directly.
