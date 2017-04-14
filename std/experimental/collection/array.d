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
    import std.traits : isImplicitlyConvertible;
    import std.range.primitives : isInputRange, isForwardRange, ElementType;
    import std.conv : emplace;
    import core.atomic : atomicOp;

    T[] _payload;

    version(unittest) { } else
    {
        alias Alloc = AffixAllocator!(IAllocator, size_t);
        Alloc _allocator;
    }

    @trusted void addRef(this Qualified)()
    {
        assert(_payload !is null);
        debug(CollectionArray)
        {
            writefln("Array.addRef: Array %s has refcount: %s; will be: %s",
                    _payload, *prefCount(), *prefCount() + 1);
        }
        static if (is(Qualified == immutable) || is(Qualified == const))
        {
            atomicOp!"+="(*prefCount(), 1);
        }
        else
        {
            ++*prefCount();
        }
    }

    @trusted void delRef()
    {
        assert(_payload !is null);
        uint *pref = prefCount();
        debug(CollectionArray) writefln("Array.delRef: Array %s has refcount: %s; will be: %s",
                _payload, *pref, *pref - 1);
        if (*pref == 0)
        {
            debug(CollectionArray) writefln("Array.delRef: Deleting array %s", _payload);
            _allocator.dispose(_payload);
        }
        else
        {
            --*pref;
        }
    }

    @trusted auto prefCount(this Qualified)()
    {
        assert(_payload !is null);
        version(unittest)
        {
            alias _alloc = _allocator.parent;
        } else
        {
            alias _alloc = _allocator;
        }
        static if (is(Qualified == immutable) || is(Qualified == const))
        {
            return cast(shared uint*)(&_alloc.prefix(_payload));
        }
        else
        {
            return cast(uint*)(&_alloc.prefix(_payload));
        }
    }

    static string immutableInsert(string stuff)
    {
        return ""
            ~"Node *tmpNode;"
            ~"Node *tmpHead;"
            ~"foreach (item; " ~ stuff ~ ")"
            ~"{"
                ~"Node *newNode;"
                ~"() @trusted { newNode = _allocator.make!(Node)(item, null); }();"
                ~"(tmpHead ? tmpNode._next : tmpHead) = newNode;"
                ~"tmpNode = newNode;"
            ~"}"
            ~"_head = () @trusted { return cast(immutable Node*)(tmpHead); }();";
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
            insert(values);
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
            insert(stuff);
        }
    }

    this(this)
    {
        debug(CollectionArray)
        {
            writefln("Array.postblit: begin");
            scope(exit) writefln("Array.postblit: end");
        }
        if (_head !is null)
        {
            uint *pref = prefCount(_head);
            addRef(_head);
            debug(CollectionArray) writefln("Array.postblit: Node %s has refcount: %s",
                    _head._payload, *pref);
        }
    }

    // Immutable ctors
    private this(NodeQual, this Qualified)(NodeQual _newHead)
        if (is(typeof(_head) : typeof(_newHead))
            && (is(Qualified == immutable) || is(Qualified == const)))
    {
        _head = _newHead;
        if (_head !is null)
        {
            shared uint *pref = prefCount(_head);
            addRef(_head);
            debug(CollectionArray) writefln("Array.ctor immutable: Node %s has "
                    ~ "refcount: %s", _head._payload, *pref);
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

    void destroyUnused()
    {
        debug(CollectionArray)
        {
            writefln("Array.destoryUnused: begin");
            scope(exit) writefln("Array.destoryUnused: end");
        }
        while (_head !is null && *prefCount(_head) == 0)
        {
            debug(CollectionArray) writefln("Array.destoryUnused: One ref with head at %s",
                    _head._payload);
            Node *tmpNode = _head;
            _head = _head._next;
            delRef(tmpNode);
        }

        if (_head !is null && *prefCount(_head) > 0)
        {
            // We reached a copy, so just remove the head ref, thus deleting
            // the copy in constant time (we are undoing the postblit)
            debug(CollectionArray) writefln("Array.destoryUnused: Multiple refs with head at %s",
                    _head._payload);
            delRef(_head);
        }
    }
}
