package;

import haxe.PosInfos;

class TestCase
{
	public var failures:Array<String> = [];
	public var assertions:Int = 0;

	public function new() {}

	function assertEquals(expected:Dynamic, actual:Dynamic, ?pos:PosInfos):Void
	{
		assertions++;
		if (expected != actual) failures.push('${pos.methodName}:${pos.lineNumber} expected ${Std.string(expected)} but was ${Std.string(actual)}');
	}

	function assertTrue(value:Bool, ?pos:PosInfos):Void
	{
		assertions++;
		if (!value) failures.push('${pos.methodName}:${pos.lineNumber} expected true');
	}

	function assertFalse(value:Bool, ?pos:PosInfos):Void
	{
		assertions++;
		if (value) failures.push('${pos.methodName}:${pos.lineNumber} expected false');
	}
}
