package;

class TestAll
{
	static function main():Void
	{
		var test:TestParser = new TestParser();
		var failed:Int = 0;
		for (field in Type.getInstanceFields(TestParser))
		{
			if (!StringTools.startsWith(field, "test")) continue;
			var before:Int = test.failures.length;
			try
			{
				Reflect.callMethod(test, Reflect.field(test, field), []);
			}
			catch (e:Dynamic)
			{
				test.failures.push('$field threw ${Std.string(e)}');
			}
			if (test.failures.length > before) failed++;
		}
		for (failure in test.failures)
			Sys.println(failure);
		Sys.println('${test.assertions} assertions, ${test.failures.length} failures');
		Sys.exit(test.failures.length == 0 ? 0 : 1);
	}
}
