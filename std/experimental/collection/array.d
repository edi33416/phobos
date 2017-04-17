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
    import std.traits : isImplicitlyConvertible, Unqual;
    import std.range.primitives : isInputRange, isForwardRange, ElementType;
    import std.conv : emplace;
    import core.atomic : atomicOp;

    T[] _payload;
    Unqual!T[] _support;

    static enum double capacityFactor = 3.0 / 2;

    version(unittest) { } else
    {
        alias Alloc = AffixAllocator!(IAllocator, size_t);
        Alloc _allocator;
    }

    @trusted void addRef(this Qualified)(Unqual!T[] support)
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

    @trusted auto prefCount(this Qualified)(Unqual!T[] support)
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

    static string immutableInsert(string stuff)
    {
        return ""
            ~"if (stuff.length > slackBack)"
            ~"{"
                ~"reserve(capacity + stuff.length);"
            ~"}"
            ~"_support[_payload.length .. _payload.length + stuff.length] = stuff[];"
            ~"_payload = cast(Unqual!T[])(_support[0 .. _payload.length + stuff.length]);";
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
            mixin(immutableInsert("values"));
        }
        else
        {
            insert(0, values);
        }
    }

    this(Stuff, this Qualified)(Stuff stuff)
    if (isInputRange!Stuff
        && isImplicitlyConvertible!(ElementType!Stuff, T)
        && !is(Stuff == T[]))
    {
        this(theAllocator, stuff);
    }

    this(Stuff, this Qualified)(IAllocator allocator, Stuff stuff)
    if (isInputRange!Stuff
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
            mixin(immutableInsert("stuff"));
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

    // Immutable ctors
    //private this(NodeQual, this Qualified)(NodeQual _newHead)
        //if (is(typeof(_head) : typeof(_newHead))
            //&& (is(Qualified == immutable) || is(Qualified == const)))
    //{
        //_head = _newHead;
        //if (_head !is null)
        //{
            //shared uint *pref = prefCount(_head);
            //addRef(_head);
            //debug(CollectionArray) writefln("Array.ctor immutable: Node %s has "
                    //~ "refcount: %s", _head._payload, *pref);
        //}
    //}

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

    //size_t insert(Stuff)(size_t pos, Stuff stuff)
    //if (isInputRange!Stuff && isImplicitlyConvertible!(ElementType!Stuff, T))
    //{
        //debug(CollectionArray)
        //{
            //writefln("Array.insert: begin");
            //scope(exit) writefln("Array.insert: end");
        //}
        //version(unittest) { } else
        //{
            //if (() @trusted { return _allocator.parent is null; }())
            //{
                //_allocator = AffixAllocator!(IAllocator, size_t)(theAllocator);
            //}
        //}

        //size_t result;
        //foreach (item; stuff)
        //{
            //++result;
        //}
        //return result;
    //}

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
}

version(unittest) private @trusted void testInit()
{
    import std.stdio;
    auto v = Array!int([10, 20, 30]);
    writefln("Array %s cap %s", v, v.capacity);
    v.insert(1, 1, 2);
    writefln("Array %s cap %s", v, v.capacity);
}

@safe unittest
{
    import std.conv;
    testInit();
    auto bytesUsed = _allocator.bytesUsed;
    assert(bytesUsed == 0, "Array ref count leaks memory; leaked "
                           ~ to!string(bytesUsed) ~ " bytes");
}


void main(string[] args)
{
}
