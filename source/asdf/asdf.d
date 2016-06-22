/++
ASDF Representation

Copyright: Tamedia Digital, 2016

Authors: Ilya Yaroshenko

License: MIT

Macros:
SUBMODULE = $(LINK2 asdf_$1.html, asdf.$1)
SUBREF = $(LINK2 asdf_$1.html#.$2, $(TT $2))$(NBSP)
T2=$(TR $(TDNW $(LREF $1)) $(TD $+))
T4=$(TR $(TDNW $(LREF $1)) $(TD $2) $(TD $3) $(TD $4))
+/
module asdf.asdf;

import std.exception;
import std.range.primitives;
import std.typecons;

import asdf.jsonbuffer;

///
class AsdfException: Exception
{
	///
	this(
		string msg,
		string file = __FILE__,
		size_t line = __LINE__,
		Throwable next = null) pure nothrow @nogc @safe 
	{
		super(msg, file, line, next);
	}
}

///
class InvalidAsdfException: AsdfException
{
	///
	this(
		uint kind,
		string file = __FILE__,
		size_t line = __LINE__,
		Throwable next = null) pure nothrow @safe 
	{
		import std.conv: text;
		super(text("ASDF values is invalid for kind = ", kind), file, line, next);
	}
}

private void enforceValidAsdf(
		bool condition,
		uint kind,
		string file = __FILE__,
		size_t line = __LINE__)
{
	if(!condition)
		throw new InvalidAsdfException(kind, file, line);
}

///
class EmptyAsdfException: AsdfException
{
	///
	this(
		string msg = "ASDF values is empty",
		string file = __FILE__,
		size_t line = __LINE__,
		Throwable next = null) pure nothrow @nogc @safe 
	{
		super(msg, file, line, next);
	}
}

/++
The structure for ASDF manipulation.
+/
struct Asdf
{
	enum Kind : ubyte
	{
		null_  = 0x00,
		true_  = 0x01,
		false_ = 0x02,
		number = 0x03,
		string = 0x05,
		array  = 0x09,
		object = 0x0A,
	}

	/// Returns ASDF Kind
	ubyte kind() const
	{
		enforce!EmptyAsdfException(data.length);
		return data[0];
	}

	/++
	Plain ASDF data.
	+/
	ubyte[] data;

	/// Creates ASDF using already allocated data
	this(ubyte[] data)
	{
		this.data = data;
	}

	/// Creates ASDF from a string
	this(in char[] str)
	{
		data = new ubyte[str.length + 5];
		data[0] = Kind.string;
		length4 = str.length;
		data[5 .. $] = cast(const(ubyte)[])str;
	}

	///
	unittest
	{
		assert(Asdf("string") == "string");
		assert(Asdf("string") != "String");
	}

	/// Sets deleted bit on
	void remove()
	{
		if(data.length)
			data[0] |= 0x80;
	}

	///
	unittest
	{
		import std.conv: to;
		import asdf.jsonparser;
		auto asdfData = `{"foo":"bar","inner":{"a":true,"b":false,"c":"32323","d":null,"e":{}}}`.parseJson;
		asdfData["inner", "d"].remove;
		assert(asdfData.to!string == `{"foo":"bar","inner":{"a":true,"b":false,"c":"32323","e":{}}}`);
	}

	///
	void toString(scope void delegate(const(char)[]) sink)
	{
		scope buffer = JsonBuffer(sink);
		toStringImpl(buffer);
		buffer.flush;
	}

	/+
	Internal recursive toString implementation.
	Params:
		sink = output range that accepts `char`, `in char[]` and compile time string `(string str)()`
	+/
	private void toStringImpl(ref JsonBuffer sink)
	{
		enforce!EmptyAsdfException(data.length, "data buffer is empty");
		auto t = data[0];
		switch(t)
		{
			case Kind.null_:
				enforceValidAsdf(data.length == 1, t);
				sink.put!"null";
				break;
			case Kind.true_:
				enforceValidAsdf(data.length == 1, t);
				sink.put!"true";
				break;
			case Kind.false_:
				enforceValidAsdf(data.length == 1, t);
				sink.put!"false";
				break;
			case Kind.number:
				enforceValidAsdf(data.length > 1, t);
				size_t length = data[1];
				enforceValidAsdf(data.length == length + 2, t);
				sink.putSmallEscaped(cast(const(char)[]) data[2 .. $]);
				break;
			case Kind.string:
				enforceValidAsdf(data.length >= 5, Kind.object);
				enforceValidAsdf(data.length == length4 + 5, t);
				sink.put('"');
				sink.put(cast(const(char)[]) data[5 .. $]);
				sink.put('"');
				break;
			case Kind.array:
				auto elems = byElement;
				if(byElement.empty)
				{
					sink.put!"[]";
					break;
				}
				sink.put('[');
				elems.front.toStringImpl(sink);
				elems.popFront;
				foreach(e; elems)
				{
					sink.put(',');
					e.toStringImpl(sink);
				}
				sink.put(']');
				break;
			case Kind.object:
				auto pairs = byKeyValue;
				if(byKeyValue.empty)
				{
					sink.put!"{}";
					break;
				}
				sink.put!"{\"";
				sink.put(pairs.front.key);
				sink.put!"\":";
				pairs.front.value.toStringImpl(sink);
				pairs.popFront;
				foreach(e; pairs)
				{
					sink.put!",\"";
					sink.put(e.key);
					sink.put!"\":";
					e.value.toStringImpl(sink);
				}
				sink.put('}');
				break;
			default:
				enforceValidAsdf(0, t);
		}
	}

	///
	unittest
	{
		import std.conv: to;
		import asdf.jsonparser;
		auto text = `{"foo":"bar","inner":{"a":true,"b":false,"c":"32323","d":null,"e":{}}}`;
		auto asdfData = text.parseJson;
		assert(asdfData.to!string == text);
	}

	/++
	`==` operator overloads for `null`
	+/
	bool opEquals(in Asdf rhs) const
	{
		return data == rhs.data;
	}

	///
	unittest
	{
		import asdf.jsonparser;
		auto asdfData = `null`.parseJson;
		assert(asdfData == asdfData);
	}

	/++
	`==` operator overloads for `null`
	+/
	bool opEquals(typeof(null)) const
	{
		return data.length == 1 && data[0] == 0;
	}

	///
	unittest
	{
		import asdf.jsonparser;
		auto asdfData = `null`.parseJson;
		assert(asdfData == null);
	}

	/++
	`==` operator overloads for `bool`
	+/
	bool opEquals(bool boolean) const
	{
		return data.length == 1 && (data[0] == Kind.true_ && boolean || data[0] == Kind.false_ && !boolean);
	}

	///
	unittest
	{
		import asdf.jsonparser;
		auto asdfData = `true`.parseJson;
		assert(asdfData == true);
		assert(asdfData != false);
	}

	/++
	`==` operator overloads for `string`
	+/
	bool opEquals(in char[] str) const
	{
		return data.length >= 5 && data[0] == Kind.string && data[5 .. 5 + length4] == cast(const(ubyte)[]) str;
	}

	///
	unittest
	{
		import asdf.jsonparser;
		auto asdfData = `"str"`.parseJson;
		assert(asdfData == "str");
		assert(asdfData != "stR");
	}

	/++
	Returns:
		input range composed of elements of an array.
	+/
	auto byElement()
	{
		static struct Range
		{
			private ubyte[] _data;
			private Asdf _front;

			auto save() @property
			{
				return this;
			}

			void popFront()
			{
				while(!_data.empty)
				{
					uint t = cast(ubyte) _data.front;
					switch(t)
					{
						case Kind.null_:
						case Kind.true_:
						case Kind.false_:
							_front = Asdf(_data[0 .. 1]);
							_data.popFront;
							return;
						case Kind.number:
							enforceValidAsdf(_data.length >= 2, t);
							size_t len = _data[1] + 2;
							enforceValidAsdf(_data.length >= len, t);
							_front = Asdf(_data[0 .. len]);
							_data = _data[len .. $];
							return;
						case Kind.string:
						case Kind.array:
						case Kind.object:
							enforceValidAsdf(_data.length >= 5, t);
							size_t len = Asdf(_data).length4 + 5;
							enforceValidAsdf(_data.length >= len, t);
							_front = Asdf(_data[0 .. len]);
							_data = _data[len .. $];
							return;
						case 0x80 | Kind.null_:
						case 0x80 | Kind.true_:
						case 0x80 | Kind.false_:
							_data.popFront;
							continue;
						case 0x80 | Kind.number:
							enforceValidAsdf(_data.length >= 2, t);
							_data.popFrontExactly(_data[1] + 2);
							continue;
						case 0x80 | Kind.string:
						case 0x80 | Kind.array:
						case 0x80 | Kind.object:
							enforceValidAsdf(_data.length >= 5, t);
							size_t len = Asdf(_data).length4 + 5;
							_data.popFrontExactly(len);
							continue;
						default:
							enforceValidAsdf(0, t);
					}
				}
				_front = Asdf.init;
			}

			auto front() @property
			{
				assert(!empty);
				return _front;
			}

			bool empty() @property
			{
				return _front.data.length == 0;
			}
		}
		if(data.empty || data[0] != Kind.array)
			return Range.init;
		enforceValidAsdf(data.length >= 5, Kind.array);
		enforceValidAsdf(length4 == data.length - 5, Kind.array);
		auto ret = Range(data[5 .. $]);
		if(ret._data.length)
			ret.popFront;
		return ret;
	}

	/++
	Returns:
		Input range composed of key-value pairs of an object.
		Elements are type of `Tuple!(const(char)[], "key", Asdf, "value")`.
	+/
	auto byKeyValue()
	{
		static struct Range
		{
			private ubyte[] _data;
			private Tuple!(const(char)[], "key", Asdf, "value") _front;

			auto save() @property
			{
				return this;
			}

			void popFront()
			{
				while(!_data.empty)
				{
					enforceValidAsdf(_data.length > 1, Kind.object);
					size_t l = cast(ubyte) _data[0];
					_data.popFront;
					enforceValidAsdf(_data.length >= l, Kind.object);
					_front.key = cast(const(char)[])_data[0 .. l];
					_data.popFrontExactly(l);
					uint t = cast(ubyte) _data.front;
					switch(t)
					{
						case Kind.null_:
						case Kind.true_:
						case Kind.false_:
							_front.value = Asdf(_data[0 .. 1]);
							_data.popFront;
							return;
						case Kind.number:
							enforceValidAsdf(_data.length >= 2, t);
							size_t len = _data[1] + 2;
							enforceValidAsdf(_data.length >= len, t);
							_front.value = Asdf(_data[0 .. len]);
							_data = _data[len .. $];
							return;
						case Kind.string:
						case Kind.array:
						case Kind.object:
							enforceValidAsdf(_data.length >= 5, t);
							size_t len = Asdf(_data).length4 + 5;
							enforceValidAsdf(_data.length >= len, t);
							_front.value = Asdf(_data[0 .. len]);
							_data = _data[len .. $];
							return;
						case 0x80 | Kind.null_:
						case 0x80 | Kind.true_:
						case 0x80 | Kind.false_:
							_data.popFront;
							continue;
						case 0x80 | Kind.number:
							enforceValidAsdf(_data.length >= 2, t);
							_data.popFrontExactly(_data[1] + 2);
							continue;
						case 0x80 | Kind.string:
						case 0x80 | Kind.array:
						case 0x80 | Kind.object:
							enforceValidAsdf(_data.length >= 5, t);
							size_t len = Asdf(_data).length4 + 5;
							_data.popFrontExactly(len);
							continue;
						default:
							enforceValidAsdf(0, t);
					}
				}
				_front = _front.init;
			}

			auto front() @property
			{
				assert(!empty);
				return _front;
			}

			bool empty() @property
			{
				return _front.value.data.length == 0;
			}
		}
		if(data.empty || data[0] != Kind.object)
			return Range.init;
		enforceValidAsdf(data.length >= 5, Kind.object);
		enforceValidAsdf(length4 == data.length - 5, Kind.object);
		auto ret = Range(data[5 .. $]);
		if(ret._data.length)
			ret.popFront;
		return ret;
	}

	/// returns 4-byte length
	private size_t length4() const @property
	{
		assert(data.length >= 5);
		return (cast(uint[1])cast(ubyte[4])data[1 .. 5])[0];
	}

	/// ditto
	void length4(size_t len) const @property
	{
		assert(data.length >= 5);
		assert(len <= uint.max);
		(cast(uint[1])cast(ubyte[4])data[1 .. 5])[0] = cast(uint) len;
	}


	/++
	Searches a value recursively in an ASDF object.

	Params:
		keys = list of keys keys
	Returns
		ASDF value if it was found (first win) or ASDF with empty plain data.
	+/
	Asdf opIndex(in char[][] keys...)
	{
		auto asdf = this;
		if(asdf.data.empty)
			return Asdf.init;
		L: foreach(key; keys)
		{
			if(asdf.data[0] != Asdf.Kind.object)
				return Asdf.init;
			foreach(e; asdf.byKeyValue)
			{
				if(e.key == key)
				{
					asdf = e.value;
					continue L;
				}
			}
			return Asdf.init;
		}
		return asdf;
	}

	///
	unittest
	{
		import asdf.jsonparser;
		auto asdfData = `{"foo":"bar","inner":{"a":true,"b":false,"c":"32323","d":null,"e":{}}}`.parseJson;
		assert(asdfData["inner", "a"] == true);
		assert(asdfData["inner", "b"] == false);
		assert(asdfData["inner", "c"] == "32323");
		assert(asdfData["inner", "d"] == null);
		assert(asdfData["no", "such", "keys"] == Asdf.init);
	}

	/++
	Params:
		def = default value. It is used when ASDF value equals to `Asdf.init`.
	Returns:
		`cast(T) this` if `this != Asdf.init` and `def` otherwise.
	+/
	T get(T)(T def)
	{
		if(data.length)
		{
			return cast(T) this;
		}
		return def;
	}

	///
	unittest
	{
		import asdf.jsonparser;
		auto asdfData = `{"foo":"bar","inner":{"a":true,"b":false,"c":"32323","d":null,"e":{}}}`.parseJson;
		assert(asdfData["inner", "a"].get(false) == true);
		assert(asdfData["inner", "b"].get(true) == false);
		assert(asdfData["inner", "c"].get(100) == 32323);
		assert(asdfData["no", "such", "keys"].get(100) == 100);
	}

	/++
	`cast` operator overloading.
	+/
	T opCast(T)()
	{
		import std.datetime: SysTime, DateTime, usecs, UTC;
		import std.traits: isNumeric;
		import std.conv: to, ConvException;
		import std.format: format;
		import std.math: isNumeric, lround, trunc;
		import asdf.serialization;
		auto k = kind;
		with(Kind) switch(kind)
		{
			case null_ :
				static if (isNumeric!T
						|| is(T == interface)
						|| is(T == class)
						|| is(T == E[], E)
						|| is(T == E[K], E, K)
						|| is(T == bool))
					return T.init;
				else goto default;
			case true_ :
				static if(__traits(compiles, true.to!T))
					return true.to!T;
				else goto default;
			case false_:
				static if(__traits(compiles, false.to!T))
					return false.to!T;
				else goto default;
			case number:
				scope str = cast(const(char)[]) data[2 .. $];
				static if(is(T == bool))
					return str.to!real != 0;
				else
				static if(is(T == SysTime) || is(T == DateTime))
				{
					auto unixTime = str.to!real;
					auto secsR = unixTime.trunc;
					auto rem = unixTime - secsR;
					auto st = SysTime.fromUnixTime(lround(secsR), UTC());
					st.fracSecs = usecs(lround(rem * 1_000_000));
					return st.to!T;
				}
				else
				static if(__traits(compiles, str.to!T))
					return str.to!T;
				else goto default;
			case string:
				scope str = cast(const(char)[]) data[5 .. $];
				static if(is(T == bool))
					return str != "0" && str != "false" && str != "";
				else
				static if(__traits(compiles, str.to!T))
					return str.to!T;
				else goto default;
			case array :
			case object:
				static if(__traits(compiles, {T t = deserialize!T(this);}))
					return deserialize!T(this);
				else goto default;
			default:
				throw new ConvException(format("Cannot convert kind \\x%02X to %s", k, T.stringof));
		}
	}

	/// null
	unittest
	{
		import std.math;
		import asdf.serialization;
		auto null_ = serializeToAsdf(null);
		interface I {}
		class C {}
		assert(cast(uint[]) null_ is null);
		assert(cast(uint[uint]) null_ is null);
		assert(cast(I) null_ is null);
		assert(cast(C) null_ is null);
		assert(isNaN(cast(double) null_));
		assert(! cast(bool) null_);
	}

	/// boolean
	unittest
	{
		import std.math;
		import asdf.serialization;
		auto true_ = serializeToAsdf(true);
		auto false_ = serializeToAsdf(false);
		static struct C {
			this(bool){}
		}
		auto a = cast(C) true_;
		auto b = cast(C) false_;
		assert(cast(bool) true_ == true);
		assert(cast(bool) false_ == false);
		assert(cast(uint) true_ == 1);
		assert(cast(uint) false_ == 0);
		assert(cast(double) true_ == 1);
		assert(cast(double) false_ == 0);
	}

	/// numbers
	unittest
	{
		import std.bigint;
		import asdf.serialization;
		auto number = serializeToAsdf(1234);
		auto zero = serializeToAsdf(0);
		static struct C
		{
			this(in char[] numberString)
			{
				assert(numberString == "1234");
			}
		}
		auto a = cast(C) number;
		assert(cast(bool) number == true);
		assert(cast(bool) zero == false);
		assert(cast(uint) number == 1234);
		assert(cast(double) number == 1234);
		assert(cast(BigInt) number == 1234);
		assert(cast(uint) zero == 0);
		assert(cast(double) zero == 0);
		assert(cast(BigInt) zero == 0);
	}

	/// string
	unittest
	{
		import std.bigint;
		import asdf.serialization;
		auto number = serializeToAsdf("1234");
		auto false_ = serializeToAsdf("false");
		auto bar = serializeToAsdf("bar");
		auto zero = serializeToAsdf("0");
		static struct C
		{
			this(in char[] str)
			{
				assert(str == "1234");
			}
		}
		auto a = cast(C) number;
		assert(cast(string) number == "1234");
		assert(cast(bool) number == true);
		assert(cast(bool) bar == true);
		assert(cast(bool) zero == false);
		assert(cast(bool) false_ == false);
		assert(cast(uint) number == 1234);
		assert(cast(double) number == 1234);
		assert(cast(BigInt) number == 1234);
		assert(cast(uint) zero == 0);
		assert(cast(double) zero == 0);
		assert(cast(BigInt) zero == 0);
	}

	/++
	For ASDF arrays and objects `cast(T)` just returns `this.deserialize!T`.
	+/
	unittest
	{
		import std.bigint;
		import asdf.serialization;
		assert(cast(int[]) serializeToAsdf([100, 20]) == [100, 20]);
	}

	/// UNIX Time
	unittest
	{
		import std.datetime;
		import asdf.serialization;

		auto num =  serializeToAsdf(0.123456789); // rounding up to usecs
		assert(cast(DateTime) num == DateTime(1970, 1, 1));
		assert(cast(SysTime) num == SysTime(DateTime(1970, 1, 1), usecs(123457), UTC())); // UTC time zone is used.
	}
}
