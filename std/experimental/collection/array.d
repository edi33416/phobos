module std.experimental.collection.array;

import std.experimental.collection.common;
import std.experimental.allocator : IAllocator, theAllocator, make, dispose;
import std.experimental.allocator.building_blocks.affix_allocator;
import std.experimental.allocator.gc_allocator;

debug(CollectionArray) import std.stdio;

version(unittest)
{
    import std.experimental.allocator.mallocator;
    import std.experimental.allocator.building_blocks.stats_collector;

    private alias Alloc = StatsCollector!(
                        AffixAllocator!(Mallocator, uint),
                        Options.bytesUsed
    );
    Alloc _allocator;
}

struct Array(T)
{
    import std.traits : isImplicitlyConvertible, Unqual, isArray;
    import std.range.primitives : isInputRange, isForwardRange, isInfinite,
           ElementType, hasLength;
    import std.conv : emplace;
    import core.atomic : atomicOp;

    T[] _payload;
    Unqual!T[] _support;

    static enum double capacityFactor = 3.0 / 2;
    static enum initCapacity = 3;

    version(unittest) { } else
    {
        alias Alloc = AffixAllocator!(IAllocator, size_t);
        Alloc _allocator;
    }

    @trusted void addRef(SupportQual, this Qualified)(SupportQual support)
    {
        assert(support !is null);
        debug(CollectionArray)
        {
            writefln("Array.addRef: Array %s has refcount: %s; will be: %s",
                    support, *prefCount(support), *prefCount(support) + 1);
        }
        static if (is(Qualified == immutable) || is(Qualified == const))
        {
            atomicOp!"+="(*prefCount(support), 1);
        }
        else
        {
            ++*prefCount(support);
        }
    }

    @trusted void delRef(Unqual!T[] support)
    {
        assert(support !is null);
        uint *pref = prefCount(support);
        debug(CollectionArray) writefln("Array.delRef: Array %s has refcount: %s; will be: %s",
                support, *pref, *pref - 1);
        if (*pref == 0)
        {
            debug(CollectionArray) writefln("Array.delRef: Deleting array %s", support);
            _allocator.dispose(support);
        }
        else
        {
            --*pref;
        }
    }

    @trusted auto prefCount(SupportQual, this Qualified)(SupportQual support)
    {
        assert(support !is null);
        version(unittest)
        {
            alias _alloc = _allocator.parent;
        } else
        {
            alias _alloc = _allocator;
        }
        static if (is(Qualified == immutable) || is(Qualified == const))
        {
            return cast(shared uint*)(&_alloc.prefix(support));
        }
        else
        {
            return cast(uint*)(&_alloc.prefix(support));
        }
    }

    static string immutableInsert(StuffType)(string stuff)
    {
        static if (hasLength!StuffType)
        {
            auto stuffLengthStr = ""
                ~"{"
                    ~"stuffLength = " ~ stuff ~ ".length;"
                ~"}";
        }
        else
        {
            auto stuffLengthStr = ""
                ~"{"
                    ~"import std.range.primitives : walkLength;"
                    ~"stuffLength = walkLength(" ~ stuff ~ ");"
                ~"}";
        }

        return ""
        ~"size_t stuffLength = 0;"
        ~ stuffLengthStr
        ~"auto tmpSupport = cast(Unqual!T[])(_allocator.allocate(stuffLength * T.sizeof));"
        ~"size_t i = 0;"
        ~"foreach (item; " ~ stuff ~ ")"
        ~"{"
            ~"tmpSupport[i++] = item;"
        ~"}"
        ~"_support = cast(typeof(_support))(tmpSupport);"
        ~"_payload = cast(T[])(_support[0 .. stuffLength]);";
    }

    void destroyUnused()
    {
        debug(CollectionArray)
        {
            writefln("Array.destoryUnused: begin");
            scope(exit) writefln("Array.destoryUnused: end");
        }
        if (_support !is null)
        {
            delRef(_support);
        }
    }

public:
    this(U, this Qualified)(U[] values...)
    if (isImplicitlyConvertible!(U, T))
    {
        this(theAllocator, values);
    }

    this(U, this Qualified)(IAllocator allocator, U[] values...)
    if (isImplicitlyConvertible!(U, T))
    {
        debug(CollectionArray)
        {
            writefln("Array.ctor: begin");
            scope(exit) writefln("Array.ctor: end");
        }
        version(unittest) { } else
        {
            _allocator = AffixAllocator!(IAllocator, size_t)(allocator);
        }
        static if (is(Qualified == immutable) || is(Qualified == const))
        {
            mixin(immutableInsert!(typeof(values))("values"));
        }
        else
        {
            insert(0, values);
        }
    }

    this(Stuff, this Qualified)(Stuff stuff)
    if (isInputRange!Stuff && !isInfinite!Stuff
        && isImplicitlyConvertible!(ElementType!Stuff, T)
        && !is(Stuff == T[]))
    {
        this(theAllocator, stuff);
    }

    this(Stuff, this Qualified)(IAllocator allocator, Stuff stuff)
    if (isInputRange!Stuff && !isInfinite!Stuff
        && isImplicitlyConvertible!(ElementType!Stuff, T)
        && !is(Stuff == T[]))
    {
        debug(CollectionArray)
        {
            writefln("Array.ctor: begin");
            scope(exit) writefln("Array.ctor: end");
        }
        version(unittest) { } else
        {
            _allocator = AffixAllocator!(IAllocator, size_t)(allocator);
        }
        static if (is(Qualified == immutable) || is(Qualified == const))
        {
            mixin(immutableInsert!(typeof(stuff))("stuff"));
        }
        else
        {
            insert(0, stuff);
        }
    }

    this(this)
    {
        debug(CollectionArray)
        {
            writefln("Array.postblit: begin");
            scope(exit) writefln("Array.postblit: end");
        }
        if (_support !is null)
        {
            addRef(_support);
            debug(CollectionArray) writefln("Array.postblit: Array %s has refcount: %s",
                    _support, *prefCount)();
        }
    }

    @trusted ~this()
    {
        debug(CollectionArray)
        {
            writefln("Array.dtor: Begin for instance %s of type %s",
                cast(size_t)(&this), typeof(this).stringof);
            scope(exit) writefln("Array.dtor: End for instance %s of type %s",
                    cast(size_t)(&this), typeof(this).stringof);
        }
        destroyUnused();
    }

    private @trusted size_t slackFront() const
    {
        return _payload.ptr - _support.ptr;
    }

    private @trusted size_t slackBack() const
    {
        return _support.ptr + _support.length - _payload.ptr - _payload.length;
    }

    size_t length() const
    {
        return _payload.length;
    }

    alias opDollar = length;

    @trusted size_t capacity() const
    {
        return length + slackBack;
    }

    void reserve(size_t n)
    {
        debug(CollectionArray)
        {
            writefln("Array.reserve: begin");
            scope(exit) writefln("Array.reserve: end");
        }
        if (n <= capacity) { return; }

        if (_support && *prefCount(_support) == 0)
        {
            void[] buf = _support;
            if (_allocator.expand(buf, (n - capacity) * T.sizeof))
            {
                _support = cast(Unqual!T[])(buf);
                return;
            }
            else
            {
                //assert(0, "Array.reserve: Failed to expand array.");
            }
        }

        auto tmpSupport = cast(Unqual!T[])(_allocator.allocate(n * T.sizeof));
        assert(tmpSupport !is null);
        tmpSupport[0 .. _payload.length] = _payload[];
        __dtor();
        _support = tmpSupport;
        _payload = cast(T[])(_support[0 .. _payload.length]);
        assert(capacity >= n);
    }

    size_t insert(Stuff)(size_t pos, Stuff stuff)
    if (!isArray!(typeof(stuff)) && isInputRange!Stuff && !isInfinite!Stuff
        && isImplicitlyConvertible!(ElementType!Stuff, T))
    {
        debug(CollectionArray)
        {
            writefln("Array.insert: begin");
            scope(exit) writefln("Array.insert: end");
        }
        version(unittest) { } else
        {
            if (() @trusted { return _allocator.parent is null; }())
            {
                _allocator = AffixAllocator!(IAllocator, size_t)(theAllocator);
            }
        }

        size_t stuffLength = 0;
        static if (hasLength!Stuff)
        {
            stuffLength = stuff.length;
        }
        else
        {
            import std.range.primitives : walkLength;
            stuffLength = walkLength(stuff);
        }

        auto tmpSupport = cast(Unqual!T[])(_allocator.allocate(stuffLength * T.sizeof));
        size_t i = 0;
        foreach (item; stuff)
        {
            tmpSupport[i++] = item;
        }
        size_t result = insert(pos, tmpSupport);
        _allocator.dispose(tmpSupport);
        return result;
    }

    size_t insert(Stuff)(size_t pos, Stuff[] stuff...)
    if (isImplicitlyConvertible!(Stuff, T))
    {
        debug(CollectionArray)
        {
            writefln("Array.insert: begin");
            scope(exit) writefln("Array.insert: end");
        }
        assert(pos <= _payload.length);
        version(unittest) { } else
        {
            if (() @trusted { return _allocator.parent is null; }())
            {
                _allocator = AffixAllocator!(IAllocator, size_t)(theAllocator);
            }
        }

        if (stuff.length > slackBack)
        {
            double newCapacity = capacity ? capacity * capacityFactor : stuff.length;
            while (newCapacity < capacity + stuff.length)
            {
                newCapacity = newCapacity * capacityFactor;
            }
            reserve(cast(size_t)(newCapacity));
        }
        _support[pos + stuff.length .. _payload.length + stuff.length] =
            _support[pos .. _payload.length];
        _support[pos .. pos + stuff.length] = stuff[];
        _payload = cast(Unqual!T[])(_support[0 .. _payload.length + stuff.length]);
        return stuff.length;
    }

    bool empty(this _)()
    {
        assert(_payload !is null);
        return length == 0;
    }

    ref auto front(this _)()
    {
        assert(!empty, "Array.front: Array is empty");
        return _payload[0];
    }

    void popFront()
    {
        debug(CollectionArray)
        {
            writefln("Array.popFront: begin");
            scope(exit) writefln("Array.popFront: end");
        }
        assert(!empty, "Array.popFront: Array is empty");
        _payload = _payload[1 .. $];
    }

    Qualified tail(this Qualified)()
    {
        debug(CollectionArray)
        {
            writefln("Array.tail: begin");
            scope(exit) writefln("Array.tail: end");
        }
        assert(!empty, "Array.tail: Array is empty");

        static if (is(Qualified == immutable) || is(Qualified == const))
        {
            return this[1 .. $];
        }
        else
        {
            return .tail(this);
        }
    }

    ref auto save(this _)()
    {
        debug(CollectionSList)
        {
            writefln("Array.save: begin");
            scope(exit) writefln("Array.save: end");
        }
        return this;
    }

    typeof(this) dup()
    {
        debug(CollectionSList)
        {
            writefln("Array.dup: begin");
            scope(exit) writefln("Array.dup: end");
        }
        return typeof(this)(this);
    }

    Qualified opSlice(this Qualified)()
    {
        debug(CollectionArray)
        {
            writefln("Array.opSlice(): begin");
            scope(exit) writefln("Array.opSlice(): end");
        }
        return this.save;
    }

    Qualified opSlice(this Qualified)(size_t start, size_t end)
    in
    {
        assert(start <= end && end <= length,
               "Array.opSlice(s, e): Invalid bounds: Ensure start <= end <= length");
    }
    body
    {
        debug(CollectionArray)
        {
            writefln("Array.opSlice(s, e): begin");
            scope(exit) writefln("Array.opSlice(s, e): end");
        }
        Unqual!(typeof(this)) result;
        result._support = cast(typeof(result._support))(_support);
        result._payload = cast(typeof(result._payload))(_payload[start .. end]);
        addRef(_support);
        return cast(typeof(this))(result);
    }

    ref auto opIndex(this _)(size_t idx)
    in
    {
        assert(idx <= length, "Array.opIndex: Index out of bounds");
    }
    body
    {
        return _payload[idx];
    }

    ref auto opIndexUnary(string op)(size_t idx)
    in
    {
        assert(idx <= length, "Array.opIndexUnary!" ~ op ~ ": Index out of bounds");
    }
    body
    {
        mixin("return " ~ op ~ "_payload[idx];");
    }

    ref auto opIndexAssign(U)(U elem, size_t idx)
    if (isImplicitlyConvertible!(U, T))
    in
    {
        assert(idx <= length, "Array.opIndexAssign: Index out of bounds");
    }
    body
    {
        _payload[idx] = elem;
    }

    ref auto opIndexOpAssign(string op, U)(U elem, size_t idx)
    if (isImplicitlyConvertible!(U, T))
    in
    {
        assert(idx <= length, "Array.opIndexOpAssign!" ~ op ~ ": Index out of bounds");
    }
    body
    {
        mixin("return _payload[idx]" ~ op ~ "= elem;");
    }

    auto ref opAssign()(auto ref typeof(this) rhs)
    {
        debug(CollectionArray)
        {
            writefln("Array.opAssign: begin");
            scope(exit) writefln("Array.opAssign: end");
        }

        if (rhs._support !is null && _support is rhs._support)
        {
            return this;
        }

        if (rhs._support !is null)
        {
            addRef(rhs._support);
            debug(CollectionArray) writefln("Array.opAssign: Array %s has refcount: %s",
                    rhs._payload, *prefCount(rhs._support));
        }
        __dtor();
        _support = rhs._support;
        _payload = rhs._payload;

        return this;
    }

    auto ref opOpAssign(string op, U)(auto ref U rhs)
        if (op == "~" &&
            (is (U == typeof(this))
             || is (U : T)
             || (isInputRange!U && isImplicitlyConvertible!(ElementType!U, T))
            ))
    {
        debug(CollectionArray)
        {
            writefln("Array.opOpAssign!~: %s begin", typeof(this).stringof);
            scope(exit) writefln("Array.opOpAssign!~: %s end", typeof(this).stringof);
        }
        insert(length, rhs);
        return this;
    }

}

version(unittest) private @trusted void testInit()
{
    import std.stdio;
    auto v = Array!int([10, 20, 30]);
    writefln("Array %s cap %s", v, v.capacity);
    v.insert(1, 1, 2);
    writefln("Array %s cap %s", v, v.capacity);
    auto t = v.dup();
}

@safe unittest
{
    import std.conv;
    testInit();
    auto bytesUsed = _allocator.bytesUsed;
    assert(bytesUsed == 0, "Array ref count leaks memory; leaked "
                           ~ to!string(bytesUsed) ~ " bytes");
}

version(unittest) private @trusted void testImmutability()
{
    auto a = immutable Array!(int)(1, 2, 3);
    auto a2 = a;
    auto a3 = a2.save();

    assert(a2.front == 1);
    static assert(!__traits(compiles, a2.front = 4));
    static assert(!__traits(compiles, a2.popFront()));

    auto a4 = a2.tail;
    assert(a4.front == 2);
    static assert(!__traits(compiles, a4 = a4.tail));
}

version(unittest) private @trusted void testConstness()
{
    auto a = const Array!(int)(1, 2, 3);
    auto a2 = a;
    auto a3 = a2.save();

    assert(a2.front == 1);
    static assert(!__traits(compiles, a2.front = 4));
    static assert(!__traits(compiles, a2.popFront()));

    auto a4 = a2.tail;
    assert(a4.front == 2);
    static assert(!__traits(compiles, a4 = a4.tail));
}

@safe unittest
{
    import std.conv;
    testImmutability();
    testConstness();
    auto bytesUsed = _allocator.bytesUsed;
    assert(bytesUsed == 0, "SList ref count leaks memory; leaked "
                           ~ to!string(bytesUsed) ~ " bytes");
}


void main(string[] args)
{
}
