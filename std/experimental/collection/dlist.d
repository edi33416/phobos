import std.experimental.allocator : IAllocator, theAllocator, make, dispose;
import std.experimental.allocator.building_blocks.affix_allocator;
import std.experimental.allocator.gc_allocator;

debug(CollectionDList) import std.stdio;

version(unittest)
{
    import std.experimental.allocator.mallocator;
    import std.experimental.allocator.building_blocks.stats_collector,
        std.stdio;

    private alias Alloc = StatsCollector!(
                        AffixAllocator!(Mallocator, uint),
                        Options.bytesUsed
    );
    Alloc _allocator;
}

struct DList(T)
    //if (is(typeof(allocatorObject(Allocator.instance))))
{
    import std.traits : isImplicitlyConvertible;
    import std.range.primitives : isInputRange, isForwardRange, ElementType;
    import std.conv : emplace;

private:
    struct Node
    {
        T _payload;
        Node *_next;
        Node *_prev;

        this(T v, Node *n, Node *p)
        {
            debug(CollectionDList) writefln("DList.Node.ctor: Constructing node" ~
                    " with payload: %s", v);
            _payload = v;
            _next = n;
            _prev = p;
        }

        ~this()
        {
            debug(CollectionDList) writefln("DList.Node.dtor: Destroying node" ~
                    " with payload: %s", _payload);
        }
    }

    Node *_head;

    version (unittest) { } else
    {
        alias Alloc = AffixAllocator!(IAllocator, size_t);
        Alloc _allocator;
        //Alloc _allocator;
    }

    @trusted void addRef(QualNode, this Qualified)(QualNode node)
    {
        assert(node !is null);
        debug(CollectionDList)
        {
            writefln("DList.addRef: Node %s has refcount: %s; will be: %s",
                    node._payload, *prefCount(node), *prefCount(node) + 1);
        }
        static if (is(Qualified == immutable) || is(Qualified == const))
        {
            atomicOp!"+="(*prefCount(node), 1);
        }
        else
        {
            ++*prefCount(node);
        }
    }

    @trusted void delRef(Node *node)
    {
        assert(node !is null);
        uint *pref = prefCount(node);
        debug(CollectionDList) writefln("DList.delRef: Node %s has refcount: %s; will be: %s",
                node._payload, *pref, *pref - 1);
        if (*pref == 0)
        {
            debug(CollectionDList) writefln("DList.delRef: Deleting node %s", node._payload);
            _allocator.dispose(node);
        }
        else
        {
            --*pref;
        }
    }

    @trusted auto prefCount(QualNode, this Qualified)(QualNode node)
    {
        assert(node !is null);
        version (unittest)
        {
            alias _alloc = _allocator.parent;
        } else
        {
            alias _alloc = _allocator;
        }
        static if (is(Qualified == immutable) || is(Qualified == const))
        {
            return cast(shared uint*)(&_alloc.prefix(cast(void[Node.sizeof])(*node)));
        }
        else
        {
            return cast(uint*)(&_alloc.prefix(cast(void[Node.sizeof])(*node)));
        }
    }

    static string immutableInsert(string stuff)
    {
        return ""
            ~"Node *tmpNode;"
            ~"Node *tmpHead;"
            ~"foreach (item; " ~ stuff ~ ")"
            ~"{"
                ~"Node *newNode = _allocator.make!(Node)(item, null, null);"
                ~"(tmpHead ? tmpNode._next : tmpHead) = newNode;"
                ~"tmpNode = newNode;"
            ~"}"
            ~"_head = cast(immutable Node*)(tmpHead);";
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
        debug(CollectionDList)
        {
            writefln("DList.ctor: begin");
            scope(exit) writefln("DList.ctor: end");
        }
        version (unittest) { } else
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
        debug(CollectionDList)
        {
            writefln("DList.ctor: begin");
            scope(exit) writefln("DList.ctor: end");
        }
        version (unittest) { } else
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
        debug(CollectionDList)
        {
            writefln("DList.postblit: begin");
            scope(exit) writefln("DList.postblit: end");
        }
        if (_head !is null)
        {
            uint *pref = prefCount(_head);
            addRef(_head);
            debug(CollectionDList) writefln("DList.postblit: Node %s has refcount: %s",
                    _head._payload, *pref);
        }
    }

    // Immutable ctors
    private this(NodeQual, this Qualified)(NodeQual _newHead)
        if (is(Qualified == immutable) || is(Qualified == const))
    {
        _head = _newHead;
        if (_head !is null)
        {
            shared uint *pref = prefCount(_head);
            addRef(_head);
            debug(CollectionDList) writefln("DList.ctor immutable: Node %s has "
                    ~ "refcount: %s", _head._payload, *pref);
        }
    }

    ~this()
    {
        debug(CollectionDList)
        {
            writefln("DList.dtor: Begin for instance %s of type %s",
                cast(size_t)(&this), typeof(this).stringof);
            scope(exit) writefln("DList.dtor: End for instance %s of type %s",
                    cast(size_t)(&this), typeof(this).stringof);
        }
        delRef(_head);
        destroyUnused(_head);
    }

    void destroyUnused(Node *startNode)
    {
        debug(CollectionDList)
        {
            writefln("DList.destoryUnused: begin");
            scope(exit) writefln("DList.destoryUnused: end");
        }

        Node *tmpNode = startNode;
        bool isCycle = true;
        while (tmpNode !is null)
        {
            //debug(CollectionDList) writefln("Node %s has refcount %s",
                    //tmpNode._payload, *(prefCount(tmpNode)));
            //debug(CollectionDList) writefln("Node._prev is null %s %s", tmpNode._prev
                    //is null, *prefCount(tmpNode));
            if (((tmpNode._next is null || tmpNode._prev is null)
                  && *prefCount(tmpNode) == 0)
                || (tmpNode._next !is null && tmpNode._prev !is null
                    && *prefCount(tmpNode) == 1))
            {
                // The last node should always have rc == 0 (only one ref,
                // from prev._next)
                // The first node should always have rc == 0 (only one ref,
                // from next._prev), since we don't take into account
                // the head ref
                // Nodes within the cycle should always have rc == 1
                tmpNode = tmpNode._next;
            }
            else
            {
                isCycle = false;
                break;
            }
        }

        tmpNode = startNode._prev;
        while (isCycle && tmpNode !is null)
        {
            if (((tmpNode._next is null || tmpNode._prev is null)
                  && *prefCount(tmpNode) == 0)
                || (tmpNode._next !is null && tmpNode._prev !is null
                    && *prefCount(tmpNode) == 1))
            {
                // The last node should always have rc == 0 (only one ref,
                // from prev._next)
                // The first node should always have rc == 0 (only one ref,
                // from next._prev), since we don't take into account
                // the head ref
                // Nodes within the cycle should always have rc == 1
                tmpNode = tmpNode._prev;
            }
            else
            {
                isCycle = false;
                break;
            }
        }

        if (isCycle)
        {
            // We can safely deallocate memory
            tmpNode = startNode._next;
            while (tmpNode !is null)
            {
                Node *oldNode = tmpNode;
                tmpNode = tmpNode._next;
                _allocator.dispose(oldNode);
            }
            tmpNode = startNode;
            while (tmpNode !is null)
            {
                Node *oldNode = tmpNode;
                tmpNode = tmpNode._prev;
                _allocator.dispose(oldNode);
            }
        }
    }

    bool empty()
    {
        return _head is null;
    }

    ref T front()
    {
        assert(!empty, "DList.front: List is empty");
        return _head._payload;
    }

    void popFront()
    {
        debug(CollectionDList)
        {
            writefln("DList.popFront: begin");
            scope(exit) writefln("DList.popFront: end");
        }
        assert(!empty, "DList.popFront: List is empty");
        Node *tmpNode = _head;
        _head = _head._next;
        if (_head !is null) {
            addRef(_head);
            delRef(tmpNode);
        }
        else
        {
            destroyUnused(tmpNode);
        }
    }

    void popPrev()
    {
        debug(CollectionDList)
        {
            writefln("DList.popPrev: begin");
            scope(exit) writefln("DList.popPrev: end");
        }
        assert(!empty, "DList.popPrev: List is empty");
        Node *tmpNode = _head;
        _head = _head._prev;
        if (_head !is null) {
            addRef(_head);
            delRef(tmpNode);
        }
        else
        {
            destroyUnused(tmpNode);
        }
    }

    typeof(this) save()
    {
        debug(CollectionDList)
        {
            writefln("DList.save: begin");
            scope(exit) writefln("DList.save: end");
        }
        return this;
    }

    typeof(this) dup()
    {
        debug(CollectionDList)
        {
            writefln("DList.dup: begin");
            scope(exit) writefln("DList.dup: end");
        }
        return typeof(this)(this);
    }

    size_t insert(Stuff)(Stuff stuff)
    if (isInputRange!Stuff && isImplicitlyConvertible!(ElementType!Stuff, T))
    {
        debug(CollectionDList)
        {
            writefln("DList.insert: begin");
            scope(exit) writefln("DList.insert: end");
        }
        //if (_allocator is null) _allocator = theAllocator;

        size_t result;
        Node *tmpNode;
        Node *tmpHead;
        foreach (item; stuff)
        {
            Node *newNode = _allocator.make!(Node)(item, null, null);
            if (tmpHead is null)
            {
                tmpHead = tmpNode = newNode;
            }
            else
            {
                tmpNode._next = newNode;
                newNode._prev = tmpNode;
                addRef(newNode._prev);
                tmpNode = newNode;
            }
            ++result;
        }

        if (!tmpNode)
        {
            return 0;
        }

        tmpNode._next = _head;
        if (_head !is null)
        {
            _head._prev = tmpNode;
            addRef(_head._prev);
        }
        _head = tmpHead;
        return result;
    }

    size_t insert(Stuff)(Stuff[] stuff...)
    if (isImplicitlyConvertible!(Stuff, T))
    {
        return insert(stuff);
    }

    void remove()
    {
        debug(CollectionDList)
        {
            writefln("SDist.remove: begin");
            scope(exit) writefln("SDist.remove: end");
        }
        assert(!empty, "SDist.remove: List is empty");

        Node *tmpNode = _head;
        _head = _head._next;
        _head._prev = tmpNode._prev;
        if (*prefCount(tmpNode) > 0 &&  _head !is null)
        {
            // If we have another copy of the list then the refcount
            // must increase, otherwise it will remain the same
            // This condition is needed because the recounting is zero based
            addRef(_head);
        }
        delRef(tmpNode);
    }

    void printRefCount()
    {
        import std.stdio;
        writefln("DList.printRefCount: begin");
        scope(exit) writefln("DList.printRefCount: end");

        Node *tmpNode = _head;
        while (tmpNode !is null)
        {
            writefln("DList.printRefCount: Node %s has ref count %s",
                    tmpNode._payload, *prefCount(tmpNode));
            tmpNode = tmpNode._next;
        }
    }
}

version (unittest) private @trusted void testSimpleInit()
{
    DList!int dl = DList!int(1, 2, 3);
    dl.popFront();
    dl.popPrev();
    dl.printRefCount();
}

version (unittest) private @trusted void testCopyAndRef()
{
    import std.algorithm.comparison : equal;

    auto slFromList = DList!int(1, 2, 3);
    auto slFromRange = DList!int(slFromList);
    assert(equal(slFromList, slFromRange));

    slFromList.popFront();
    assert(equal(slFromList, [2, 3]));
    assert(equal(slFromRange, [1, 2, 3]));

    DList!int slInsFromRange;
    slInsFromRange.insert(slFromList);
    slFromList.popFront();
    assert(equal(slFromList, [3]));
    assert(equal(slInsFromRange, [2, 3]));

    DList!int slInsBackFromRange;
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
    import std.conv;
    //testCopyAndRef();
    testSimpleInit();
    assert(_allocator.bytesUsed == 0, "DList ref count leaks memory; leaked "
                                    ~ to!string(_allocator.bytesUsed) ~ " bytes");
}

void main(string[] args)
{
}
