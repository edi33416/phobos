import std.experimental.allocator : IAllocator, theAllocator, make, dispose;
import std.experimental.allocator.building_blocks.affix_allocator;
import std.experimental.allocator.gc_allocator;
import std.range: isInputRange;

debug(CollectionSList) import std.stdio;


auto tail(Collection)(Collection collection)
    if (isInputRange!Collection)
{
    collection.popFront();
    return collection;
}

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

struct SList(T, Allocator = IAllocator)
{
    import std.traits : isImplicitlyConvertible;
    import std.range.primitives : isInputRange, isForwardRange, ElementType;
    import std.conv : emplace;

private:
    struct Node
    {
        T _payload;
        Node *_next;

        this(T v, Node *n)
        {
            debug(CollectionSList) writefln("SList.Node.ctor: Constructing node" ~
                    " with payload: %s", v);
            _payload = v;
            _next = n;
        }

        ~this()
        {
            debug(CollectionSList) writefln("SList.Node.dtor: Destroying node" ~
                    " with payload: %s", _payload);
        }
    }

    Node *_head;

    version (unittest) { } else
    {
        alias Alloc = AffixAllocator!(GCAllocator, uint);
        alias _allocator = Alloc.instance;
        //Alloc _allocator;
    }

    @trusted void addRef(Node *node)
    {
        assert(node !is null);
        debug(CollectionSList)
        {
            uint *pref = prefCount(node);
            writefln("SList.addRef: Node %s has refcount: %s; will be: %s",
                    node._payload, *pref, *pref + 1);
        }
        ++*prefCount(node);
    }

    @trusted void addRef(immutable Node *node) immutable
    {
        assert(node !is null);
        debug(CollectionSList)
        {
            uint *pref = prefCount(node);
            writefln("SList.addRef: Node %s has refcount: %s; will be: %s",
                    node._payload, *pref, *pref + 1);
        }
        ++*prefCount(node);
    }

    @trusted void addRef(const Node *node) const
    {
        assert(node !is null);
        debug(CollectionSList)
        {
            uint *pref = prefCount(node);
            writefln("SList.addRef: Node %s has refcount: %s; will be: %s",
                    node._payload, *pref, *pref + 1);
        }
        ++*prefCount(node);
    }

    @trusted void delRef(Node *node)
    {
        assert(node !is null);
        uint *pref = prefCount(node);
        debug(CollectionSList) writefln("SList.delRef: Node %s has refcount: %s; will be: %s",
                node._payload, *pref, *pref - 1);
        if (*pref == 0)
        {
            debug(CollectionSList) writefln("SList.delRef: Deleting node %s", node._payload);
            _allocator.dispose(node);
        }
        else
        {
            --*pref;
        }
    }

    @trusted uint* prefCount(const Node *node) const
    {
        assert(node !is null);
        return cast(uint*)(&_allocator.parent.prefix(cast(void[Node.sizeof])(*node)));
    }

    //@trusted uint* prefCount(immutable Node *node) immutable
    //{
        //assert(node !is null);
        //return cast(uint*)(&_allocator.parent.prefix(cast(void[Node.sizeof])(*node)));
    //}

public:
    this(U, this Qualified)(U[] values...)
    if (isImplicitlyConvertible!(U, T))
    {
        this(theAllocator, values);
    }

    this(U, this Qualified)(Allocator allocator, U[] values...)
    if (isImplicitlyConvertible!(U, T))
    {
        debug(CollectionSList)
        {
            writefln("SList.ctor: begin");
            scope(exit) writefln("SList.ctor: end");
        }
        //_allocator = allocator;
        static if (is(Qualified == immutable) || is(Qualified == const))
        {
            Node *tmpNode;
            Node *tmpHead;
            foreach (item; values)
            {
                Node *newNode = _allocator.make!(Node)(item, null);
                (tmpHead ? tmpNode._next : tmpHead) = newNode;
                tmpNode = newNode;
            }
            _head = cast(immutable Node*)(tmpHead);
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

    this(Stuff, this Qualified)(Allocator allocator, Stuff stuff)
    if (isInputRange!Stuff
        && isImplicitlyConvertible!(ElementType!Stuff, T)
        && !is(Stuff == T[]))
    {
        debug(CollectionSList)
        {
            writefln("SList.ctor: begin");
            scope(exit) writefln("SList.ctor: end");
        }
        //_allocator = allocator;

        static if (is(Qualified == immutable) || is(Qualified == const))
        {
            Node *tmpNode;
            Node *tmpHead;
            foreach (item; stuff)
            {
                Node *newNode = _allocator.make!(Node)(item, null);
                (tmpHead ? tmpNode._next : tmpHead) = newNode;
                tmpNode = newNode;
            }
            _head = cast(immutable Node*)(tmpHead);
        }
        else
        {
            insert(stuff);
        }
    }

    this(this)
    {
        debug(CollectionSList)
        {
            writefln("SList.postblit: begin");
            scope(exit) writefln("SList.postblit: end");
        }
        if (_head !is null)
        {
            uint *pref = prefCount(_head);
            addRef(_head);
            debug(CollectionSList) writefln("SList.postblit: Node %s has refcount: %s",
                    _head._payload, *pref);
        }
    }

    // Immutable ctors
    private this(immutable Node *_newHead) immutable
    {
        _head = _newHead;
        if (_head !is null)
        {
            uint *pref = prefCount(_head);
            addRef(_head);
            debug(CollectionSList) writefln("SList.ctor immutable: Node %s has "
                    ~ "refcount: %s", _head._payload, *pref);
        }
    }

    private this(const Node *_newHead) const
    {
        _head = _newHead;
        if (_head !is null)
        {
            uint *pref = prefCount(_head);
            addRef(_head);
            debug(CollectionSList) writefln("SList.ctor immutable: Node %s has "
                    ~ "refcount: %s", _head._payload, *pref);
        }
    }

    ~this()
    {
        debug(CollectionSList)
        {
            writefln("SList.dtor: Begin for instance %s of type %s",
                cast(size_t)(&this), typeof(this).stringof);
            scope(exit) writefln("SList.dtor: End for instance %s of type %s",
                    cast(size_t)(&this), typeof(this).stringof);
        }
        destroyUnused();
    }

    void destroyUnused()
    {
        debug(CollectionSList)
        {
            writefln("SList.destoryUnused: begin");
            scope(exit) writefln("SList.destoryUnused: end");
        }
        while (_head !is null && *prefCount(_head) == 0)
        {
            debug(CollectionSList) writefln("SList.destoryUnused: One ref with head at %s",
                    _head._payload);
            Node *tmpNode = _head;
            _head = _head._next;
            delRef(tmpNode);
        }

        if (_head !is null && *prefCount(_head) > 0)
        {
            // We reached a copy, so just remove the head ref, thus deleting
            // the copy in constant time (we are undoing the postblit)
            debug(CollectionSList) writefln("SList.destoryUnused: Multiple refs with head at %s",
                    _head._payload);
            delRef(_head);
        }
    }

    bool empty(this _)()
    {
        return _head is null;
    }

    ref auto front(this _)()
    {
        assert(!empty, "SList.front: List is empty");
        return _head._payload;
    }

    void popFront()
    {
        debug(CollectionSList)
        {
            writefln("SList.popFront: begin");
            scope(exit) writefln("SList.popFront: end");
        }
        assert(!empty, "SList.popFront: List is empty");

        Node *tmpNode = _head;
        _head = _head._next;
        if (*prefCount(tmpNode) > 0 &&  _head !is null)
        {
            // If we have another copy of the list then the refcount
            // must increase, otherwise it will remain the same
            // This condition is needed because the recounting is zero based
            addRef(_head);
        }
        delRef(tmpNode);
    }

    Qualified tail(this Qualified)()
    {
        debug(CollectionSList)
        {
            writefln("SList.popFront: begin");
            scope(exit) writefln("SList.popFront: end");
        }
        assert(!empty, "SList.popFront: List is empty");

        static if (is(Qualified == immutable) || is(Qualified == const))
        {
            return typeof(this)(_head._next);
        }
        else
        {
            return .tail(this);
        }
    }

    ref Qualified save(this Qualified)()
    {
        debug(CollectionSList)
        {
            writefln("SList.save: begin");
            scope(exit) writefln("SList.save: end");
        }
        return this;
    }

    typeof(this) dup()
    {
        debug(CollectionSList)
        {
            writefln("SList.dup: begin");
            scope(exit) writefln("SList.dup: end");
        }
        return typeof(this)(this);
    }

    size_t insert(Stuff)(Stuff stuff)
    if (isInputRange!Stuff && isImplicitlyConvertible!(ElementType!Stuff, T))
    {
        debug(CollectionSList)
        {
            writefln("SList.insert: begin");
            scope(exit) writefln("SList.insert: end");
        }
        //if (_allocator is null) _allocator = theAllocator;

        size_t result;
        Node *tmpNode;
        Node *tmpHead;
        foreach (item; stuff)
        {
            Node *newNode = _allocator.make!(Node)(item, null);
            (tmpHead ? tmpNode._next : tmpHead) = newNode;
            tmpNode = newNode;
            ++result;
        }

        if (!tmpNode)
        {
            return 0;
        }

        tmpNode._next = _head;
        _head = tmpHead;
        return result;
    }

    size_t insert(Stuff)(Stuff[] stuff...)
    if (isImplicitlyConvertible!(Stuff, T))
    {
        return insert(stuff);
    }

    size_t insertBack(Stuff)(Stuff stuff)
    if (isInputRange!Stuff && isImplicitlyConvertible!(ElementType!Stuff, T))
    {
        debug(CollectionSList)
        {
            writefln("SList.insertBack: begin");
            scope(exit) writefln("SList.insertBack: end");
        }

        size_t result;
        Node *tmpNode;
        Node *tmpHead;
        foreach (item; stuff)
        {
            Node *newNode = _allocator.make!(Node)(item, null);
            (tmpHead ? tmpNode._next : tmpHead) = newNode;
            tmpNode = newNode;
            ++result;
        }

        if (!tmpNode)
        {
            return 0;
        }

        if (_head is null)
        {
            _head = tmpHead;
        }
        else
        {
            Node *endNode;
            for (endNode = _head; endNode._next !is null; endNode = endNode._next) { }
            endNode._next = tmpHead;
        }

        return result;
    }

    size_t insertBack(Stuff)(Stuff[] stuff...)
    if (isImplicitlyConvertible!(Stuff, T))
    {
        return insertBack(stuff);
    }

    auto ref opBinary(string op, U)(auto ref U rhs)
        if (op == "~" && (is (U == typeof(this)) || is (U : T)))
    {
        debug(CollectionSList)
        {
            writefln("SList.opBinary!~: begin");
            scope(exit) writefln("SList.opBinary!~: end");
        }

        typeof(this) newList = typeof(this)(rhs);
        newList.insert(this);
        return newList;
    }

    auto ref opAssign()(auto ref typeof(this) rhs)
    {
        debug(CollectionSList)
        {
            writefln("SList.opAssign: begin");
            scope(exit) writefln("SList.opAssign: end");
        }

        if (rhs._head !is null && _head is rhs._head)
        {
            return this;
        }

        if (rhs._head !is null)
        {
            addRef(rhs._head);
            uint *pref = prefCount(rhs._head);
            debug(CollectionSList) writefln("SList.opAssign: Node %s has refcount: %s",
                    rhs._head._payload, *pref);
        }
        destroyUnused();
        _head = rhs._head;

        return this;
    }

    auto ref opOpAssign(string op, U)(auto ref U rhs)
        if (op == "~" && (is (U == typeof(this)) || is (U : T)))
    {
        debug(CollectionSList)
        {
            writefln("SList.opOpAssign!~: %s begin", typeof(this).stringof);
            scope(exit) writefln("SList.opOpAssign!~: %s end", typeof(this).stringof);
        }

        insertBack(rhs);
        return this;
    }

    void remove()
    {
        assert(!empty, "SList.remove: List is empty");
        popFront();
    }

    debug(CollectionSList) void printRefCount()
    {
        writefln("SList.printRefCount: begin");
        scope(exit) writefln("SList.printRefCount: end");

        Node *tmpNode = _head;
        while (tmpNode !is null)
        {
            writefln("SList.printRefCount: Node %s has ref count %s",
                    tmpNode._payload, *prefCount(tmpNode));
            tmpNode = tmpNode._next;
        }
    }
}

version (unittest) private @trusted void testImmutability()
{
    auto s = immutable SList!(int)(1, 2, 3);
    auto s2 = s;
    auto s3 = s2.save();

    assert(s2.front == 1);
    static assert(!__traits(compiles, s2.front = 4));
    static assert(!__traits(compiles, s2.popFront()));

    auto s4 = s2.tail;
    assert(s4.front == 2);
    static assert(!__traits(compiles, s4 = s4.tail));
}

version (unittest) private @trusted void testConstness()
{
    auto s = const SList!(int)(1, 2, 3);
    auto s2 = s;
    auto s3 = s2.save();

    assert(s2.front == 1);
    static assert(!__traits(compiles, s2.front = 4));
    static assert(!__traits(compiles, s2.popFront()));

    auto s4 = s2.tail;
    assert(s4.front == 2);
    static assert(!__traits(compiles, s4 = s4.tail));
}

@trusted unittest
{
    testImmutability();
    testConstness();
    assert(_allocator.bytesUsed == 0, "SList ref count leaks memory");
}

version (unittest) private @trusted void testConcatAndAppend()
{
    import std.algorithm.comparison : equal;

    auto sl = SList!(int)(1, 2, 3);
    SList!(int) sl2;

    auto sl3 = sl ~ sl2;
    assert(equal(sl3, [1, 2, 3]));

    auto sl4 = sl3;
    sl3 = sl3 ~ 4;
    assert(equal(sl3, [1, 2, 3, 4]));
    assert(equal(sl4, [1, 2, 3]));

    sl4 = sl3;
    sl3 ~= 10;
    assert(equal(sl3, [1, 2, 3, 4, 10]));
    assert(equal(sl4, [1, 2, 3, 4, 10]));

    sl3 ~= sl3;
    assert(equal(sl3, [1, 2, 3, 4, 10, 1, 2, 3, 4, 10]));
    assert(equal(sl4, [1, 2, 3, 4, 10, 1, 2, 3, 4, 10]));
}

@trusted unittest
{
    testConcatAndAppend();
    assert(_allocator.bytesUsed == 0, "SList ref count leaks memory");
}

version (unittest) private @trusted void testSimple()
{
    import std.algorithm.comparison : equal;
    import std.algorithm.searching : canFind;

    auto sl = SList!int();
    assert(sl.empty);

    sl.insert(1, 2, 3);
    assert(sl.front == 1);
    assert(equal(sl, sl));
    assert(equal(sl, [1, 2, 3]));

    sl.popFront();
    assert(sl.front == 2);
    assert(equal(sl, [2, 3]));

    sl.insert([4, 5, 6]);
    sl.insert(7);
    sl.insert([8]);
    assert(equal(sl, [8, 7, 4, 5, 6, 2, 3]));

    sl.insertBack(0, 1);
    sl.insertBack([-1, -2]);
    assert(equal(sl, [8, 7, 4, 5, 6, 2, 3, 0, 1, -1, -2]));

    sl.front = 9;
    assert(equal(sl, [9, 7, 4, 5, 6, 2, 3, 0, 1, -1, -2]));

    auto slTail = sl.tail;
    assert(slTail.front == 7);
    slTail.front = 8;
    assert(slTail.front == 8);
    assert(sl.tail.front == 8);

    assert(canFind(sl, 2));
    assert(!canFind(sl, -10));
}

@trusted unittest
{
    testSimple();
    assert(_allocator.bytesUsed == 0, "SList ref count leaks memory");
}

version (unittest) private @trusted void testSimpleImmutable()
{
    import std.algorithm.comparison : equal;
    import std.algorithm.searching : canFind;

    auto sl = SList!(immutable int)();
    assert(sl.empty);

    sl.insert(1, 2, 3);
    assert(sl.front == 1);
    assert(equal(sl, sl));
    assert(equal(sl, [1, 2, 3]));

    sl.popFront();
    assert(sl.front == 2);
    assert(equal(sl, [2, 3]));
    assert(sl.tail.front == 3);

    sl.insert([4, 5, 6]);
    sl.insert(7);
    sl.insert([8]);
    assert(equal(sl, [8, 7, 4, 5, 6, 2, 3]));

    sl.insertBack(0, 1);
    sl.insertBack([-1, -2]);
    assert(equal(sl, [8, 7, 4, 5, 6, 2, 3, 0, 1, -1, -2]));

    // Cannot modify immutable values
    static assert(!__traits(compiles, sl.front = 9));

    assert(canFind(sl, 2));
    assert(!canFind(sl, -10));
}

@trusted unittest
{
    testSimpleImmutable();
    assert(_allocator.bytesUsed == 0, "SList ref count leaks memory");
}

version (unittest) private @trusted void testCopyAndRef()
{
    import std.algorithm.comparison : equal;

    auto slFromList = SList!int(1, 2, 3);
    auto slFromRange = SList!int(slFromList);
    assert(equal(slFromList, slFromRange));

    slFromList.popFront();
    assert(equal(slFromList, [2, 3]));
    assert(equal(slFromRange, [1, 2, 3]));

    SList!int slInsFromRange;
    slInsFromRange.insert(slFromList);
    slFromList.popFront();
    assert(equal(slFromList, [3]));
    assert(equal(slInsFromRange, [2, 3]));

    SList!int slInsBackFromRange;
    slInsBackFromRange.insert(slFromList);
    slFromList.popFront();
    assert(slFromList.empty);
    assert(equal(slInsBackFromRange, [3]));

    auto slFromRef = slInsFromRange;
    auto slFromDup = slInsFromRange.dup;
    assert(slInsFromRange.front == 2);
    slFromRef.front = 5;
    assert(slInsFromRange.front == 5);
    assert(slFromDup.front == 2);
}

@trusted unittest
{
    testCopyAndRef();
    assert(_allocator.bytesUsed == 0, "SList ref count leaks memory");
}

void main(string[] args)
{
}
