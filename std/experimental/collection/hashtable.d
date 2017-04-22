module std.experimental.collection.hashtable;

import std.experimental.collection.common;
import std.experimental.allocator : IAllocator, theAllocator, make, dispose;
import std.experimental.allocator.building_blocks.affix_allocator;
import std.experimental.allocator.gc_allocator;
//import std.experimental.collection.pair : Pair;
import std.experimental.collection.slist : SList;
import std.experimental.collection.array : Array;

debug(CollectionHashtable) import std.stdio;

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

struct Hashtable(K, V)
{
    import std.traits : isImplicitlyConvertible, Unqual, isArray;
    import std.range.primitives : isInputRange, isForwardRange, isInfinite,
           ElementType, hasLength;
    import std.conv : emplace;
    import std.typecons : Tuple;
    import core.atomic : atomicOp;

private:
    Array!(SList!(Tuple!(K, V))) _buckets;
    Array!size_t _numElems; // This needs to be ref counted
    static enum double loadFactor = 0.75;

    static string immutableInsert(string stuff)
    {
        return "";
    }

public:
    this(U, this Qualified)(U assocArr)
    if (is(U == Value[Key], Value : V, Key : K))
    {
        this(theAllocator, assocArr);
    }

    this(U, this Qualified)(IAllocator allocator, U assocArr)
    if (is(U == Value[Key], Value : V, Key : K))
    {
        debug(CollectionHashtable)
        {
            writefln("Hashtable.ctor: begin");
            scope(exit) writefln("Hashtable.ctor: end");
        }
        version(unittest) { } else
        {
            _allocator = AffixAllocator!(IAllocator, size_t)(allocator);
            _buckets = Array!(SList!(Tuple!(K, V)))(_allocator);
            // Treat immutable
            //auto tmpNumElems = Array!size_t(_allocator);
            //tmpNumElems.reserve(1);
            //tmpNumElems[0] = assocArr.length;
            //_numElems = cast(typeof(_numElems))(tmpNumElems);
            _numElems = Array!size_t(_allocator);
        }
        static if (is(Qualified == immutable) || is(Qualified == const))
        {
            mixin(immutableInsert("assocArr"));
        }
        else
        {
            auto reqCap = requiredCapacity(assocArr.length);
            _buckets.reserve(reqCap);
            _buckets.forceLength(reqCap);
            _numElems.reserve(1);
            _numElems.forceLength(1);
            insert(assocArr);
        }
    }

    size_t insert(U)(U assocArr)
    if (is(U == Value[Key], Value : V, Key : K))
    {
        debug(CollectionHashtable)
        {
            writefln("Hashtable.insert: begin");
            scope(exit) writefln("Hashtable.insert: end");
        }
        version(unittest) { } else
        {
            if (() @trusted { return _allocator.parent is null; }())
            {
                _allocator = AffixAllocator!(IAllocator, size_t)(theAllocator);
                _buckets = Array!(SList!(Tuple!(K, V)))(_allocator);
                _numElems = Array!size_t(_allocator);
            }
        }
        if (_buckets.empty)
        {
            auto reqCap = requiredCapacity(assocArr.length);
            _buckets.reserve(reqCap);
            _buckets.forceLength(reqCap);
            _numElems.reserve(1);
            _numElems.forceLength(1);
        }
        foreach(k, v; assocArr)
        {
            size_t pos = k.hashOf & (length - 1);
            if (_buckets[pos].empty)
            {
                version(unittest)
                {
                    _buckets[pos] = SList!(Tuple!(K, V))(Tuple!(K, V)(k, v));
                }
                else
                {
                    _buckets[pos] = SList(_allocator, Tuple!(K, V)(k, v));
                }
            }
            else
            {
                _buckets[pos].insert(Tuple!(K, V)(k, v));
            }
        }
        _numElems[0] += assocArr.length;
        return assocArr.length;
    }

    private size_t requiredCapacity(size_t numElems)
    {
        static enum size_t maxPow2 = cast(size_t)(1) << (size_t.sizeof * 8 - 1);
        while (numElems & (numElems - 1))
        {
            numElems &= (numElems - 1);
        }
        return numElems < maxPow2 ? 2 * numElems : maxPow2;
    }

    size_t length() const
    {
        return _buckets.length;
    }

    bool empty(this _)()
    {
        return _buckets.empty || _numElems.empty || _numElems[0] == 0;
    }

    ref auto front(this _)()
    {
        debug(CollectionHashtable)
        {
            writefln("Hashtable.front: begin");
            scope(exit) writefln("Hashtable.front: end");
        }
        //import std.stdio;
        //writefln("front: %s", _buckets);
        auto tmpBuckets = _buckets;
        while ((!tmpBuckets.empty) && tmpBuckets.front.empty)
        {
            tmpBuckets.popFront;
        }
        assert(!tmpBuckets.empty, "Hashtable.front: Hashtable is empty");
        return tmpBuckets.front.front;
    }

    void popFront()
    {
        debug(CollectionHashtable)
        {
            writefln("Hashtable.popFront: begin");
            scope(exit) writefln("Hashtable.popFront: end");
        }
        while ((!_buckets.empty) && _buckets.front.empty)
        {
            _buckets.popFront;
        }
        assert(!_buckets.empty, "Hashtable.front: Hashtable is empty");
        _buckets.front.popFront;
        if (_buckets.front.empty)
        {
            while ((!_buckets.empty) && _buckets.front.empty)
            {
                _buckets.popFront;
            }
        }
    }

    auto get(this _)(K key)
    {
        size_t pos = key.hashOf & (length - 1);
        return _buckets[pos];
    }

    Array!K getKeys(this _)()
    {
        Array!K keys;
        foreach(bucketList; _buckets)
        {
            auto tmpBL = bucketList.save;
            pragma(msg, typeof(tmpBL));
            import std.stdio;
            tmpBL.empty || writefln("rc %s", *tmpBL.prefCount(tmpBL._head));
            foreach(pair; tmpBL)
            {
                keys ~= pair[0];
            }
        }
        return keys;
    }

    Array!K getValues(this _)()
    {
        Array!K values;
        foreach(bucketList; _buckets)
        {
            auto tmpBL = bucketList;
            foreach(pair; tmpBL)
            {
                values ~= pair[1];
            }
        }
        return values;
    }
}

@trusted unittest // SList Refcount BUG
{
    import std.stdio;
    auto h = Hashtable!(int, int)([1 : 10]);
    auto h2 = h;
    //writeln(h.get(1));
    writeln(*h2._buckets.prefCount(h2._buckets._support));
    writeln(*h2._buckets[0].prefCount(h2._buckets[0]._head));
    writeln(h2);
    //auto i = 0;
    //foreach(bucketList; h._buckets)
    //{
        //auto j = 0;
        //foreach(pair; bucketList)
        //{
            //writefln("Pair[%s, %s]: %s", i, j++, pair);
        //}
        //++i;
    //}
    writefln("Empty? %s", h.empty);
    writefln("Empty? %s", h._buckets.empty);
    writeln(h._buckets);

    //writefln("Pair %s", h.front);
    //h.popFront;
    //writefln("Empty? %s", h.empty);

    auto a = Array!(SList!int)(SList!int(10));
    writefln("Array %s", *a.prefCount(a._support));
    writefln("SList %s", *a[0].prefCount(a[0]._head));

    auto a2 = a;
    writefln("Array %s", *a.prefCount(a._support));
    writefln("SList %s", *a[0].prefCount(a[0]._head));
}

@trusted unittest
{
    import std.stdio;
    auto h = Hashtable!(int, int)([1 : 10]);

    writeln(*h._buckets.prefCount(h._buckets._support));
    h._buckets[0].empty || writeln(*h._buckets[0].prefCount(h._buckets[0]._head));
    writefln("h keys %s", h.getKeys());
    writefln("h values %s", h.getValues());
    writeln(*h._buckets.prefCount(h._buckets._support));
    h._buckets[0].empty || writeln(*h._buckets[0].prefCount(h._buckets[0]._head));
    writeln(h);
    writeln(*h._buckets.prefCount(h._buckets._support));
    h._buckets[0].empty || writeln(*h._buckets[0].prefCount(h._buckets[0]._head));
}

void main(string[] args)
{
}
