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

    @trusted void delRef(ref Node *node)
    {
        assert(node !is null);
        uint *pref = prefCount(node);
        debug(CollectionDList) writefln("DList.delRef: Node %s has refcount: %s; will be: %s",
                node._payload, *pref, *pref - 1);
        if (*pref == 0)
        {
            debug(CollectionDList) writefln("DList.delRef: Deleting node %s", node._payload);
            Node *tmpNode = node;
            node = null;
            _allocator.dispose(tmpNode);
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
        if (_head !is null)
        {
            delRef(_head);
            if (_head !is null
                && ((_head._prev !is null) || (_head._next !is null)))
            {
                //If it was a single node list, delRef will suffice
                destroyUnused(_head);
            }
        }
    }

    void destroyUnused(Node *startNode)
    {
        debug(CollectionDList)
        {
            writefln("DList.destoryUnused: begin");
            scope(exit) writefln("DList.destoryUnused: end");
        }

        if (startNode is null) return;

        Node *tmpNode = startNode;
        bool isCycle = true;
        while (tmpNode !is null)
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
                // the head ref (that was deleted either by the dtor or by pop)
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
        if (_head !is null)
        {
            addRef(_head);
            delRef(tmpNode);
        }
        else
        {
            delRef(tmpNode);
            if (tmpNode !is null
                && ((tmpNode._prev !is null) || (tmpNode._next !is null)))
            {
                // If it was a single node list, only delRef must be used
                // in order to avoid premature/double freeing
                destroyUnused(tmpNode);
            }
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
            delRef(tmpNode);
            if (tmpNode !is null
                && ((tmpNode._prev !is null) || (tmpNode._next !is null)))
            {
                // If it was a single node list, only delRef must be used
                // in order to avoid premature/double freeing
                destroyUnused(tmpNode);
            }
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
            addRef(_head);
            if (_head._prev !is null)
            {
                tmpHead._prev = _head._prev;
                _head._prev._next = tmpHead;
                addRef(tmpHead);
                // Delete extra ref, since we already added the ref earlier
                // through tmpNode._next
                delRef(_head);
            }
            // Pass the ref to the new head
            delRef(_head);
            _head._prev = tmpNode;
            if (tmpHead == tmpNode)
            {
                addRef(tmpHead);
            }
            else
            {
                addRef(_head._prev);
            }
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
            writefln("DList.remove: begin");
            scope(exit) writefln("DList.remove: end");
        }
        assert(!empty, "DList.remove: List is empty");

        Node *tmpNode = _head;
        _head = _head._next;
        if (_head !is null)
        {
            //addRef(_head);
            _head._prev = tmpNode._prev;
            delRef(tmpNode); // Remove tmpNode._next._prev ref
            tmpNode._next = null;
            //delRef(_head);
            if (tmpNode._prev !is null)
            {
                addRef(_head);
                tmpNode._prev._next = _head;
                delRef(tmpNode); // Remove tmpNode._prev._next ref
                tmpNode._prev = null;
            }
        }
        else if (tmpNode._prev !is null)
        {
            _head = tmpNode._prev;
            //addRef(_head);
            tmpNode._prev = null;
            //delRef(_head);
            _head._next = null;
            delRef(tmpNode);
        }
        delRef(tmpNode); // Remove old head ref
        destroyUnused(tmpNode);
    }

    private void printRefCount(Node *sn = null)
    {
        import std.stdio;
        writefln("DList.printRefCount: begin");
        scope(exit) writefln("DList.printRefCount: end");

        Node *tmpNode;
        if (sn is null)
            tmpNode = _head;
        else
            tmpNode = sn;

        while (tmpNode !is null && tmpNode._prev !is null)
        {
            // Rewind to the beginning of the list
            tmpNode = tmpNode._prev;
        }
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
    DList!int dl = DList!int(1);
    //dl.popFront();
    //dl.printRefCount();
    //dl.popFront();
    //dl.printRefCount();
    //auto dl2 = dl;
    dl.insert(4, 5);
    //dl.insert(4);
    //dl.popFront();
    //dl.popPrev();
    dl.printRefCount();
}

version (unittest) private @trusted void testInsert()
{
    DList!int dl = DList!int(1);
    dl.insert(2);
    dl.printRefCount();

    DList!int dl2 = DList!int(1);
    dl2.insert(2, 3);
    dl2.printRefCount();

    DList!int dl3 = DList!int(1, 2);
    dl3.insert(3);
    dl3.printRefCount();

    DList!int dl4 = DList!int(1, 2);
    dl4.insert(3, 4);
    dl4.printRefCount();

    DList!int dl5 = DList!int(1, 2);
    dl5.popFront();
    dl5.insert(3);
    dl5.printRefCount();

    DList!int dl6 = DList!int(1, 2);
    dl6.popFront();
    dl6.insert(3, 4);
    dl6.printRefCount();
    //auto dl2 = dl;
    //dl.popFront();
    //dl.insert(4, 5);
    //dl.popPrev();
    //dl.printRefCount();
}

version (unittest) private @trusted void testRemove()
{
    DList!int dl = DList!int(1);
    dl.printRefCount();
    dl.remove();
    dl.printRefCount();
    dl.insert(2);
    dl.printRefCount();
    auto dl2 = dl;
    auto dl3 = dl;
    dl.printRefCount();
    dl.popFront();
    dl2.printRefCount();
    dl2.popPrev();
    dl3.printRefCount();
}

@trusted unittest
{
    import std.conv;
    //testInsert();
    testRemove();
    assert(_allocator.bytesUsed == 0, "DList ref count leaks memory; leaked "
                                    ~ to!string(_allocator.bytesUsed) ~ " bytes");
}

version (unittest) private @trusted void testCopyAndRef()
{
    import std.algorithm.comparison : equal;

    auto dlFromList = DList!int(1, 2, 3);
    auto dlFromRange = DList!int(dlFromList);
    assert(equal(dlFromList, dlFromRange));

    dlFromList.popFront();
    assert(equal(dlFromList, [2, 3]));
    assert(equal(dlFromRange, [1, 2, 3]));

    DList!int dlInsFromRange;
    dlInsFromRange.insert(dlFromList);
    dlFromList.popFront();
    assert(equal(dlFromList, [3]));
    assert(equal(dlInsFromRange, [2, 3]));

    DList!int dlInsBackFromRange;
    dlInsBackFromRange.insert(dlFromList);
    dlFromList.popFront();
    assert(dlFromList.empty);
    assert(equal(dlInsBackFromRange, [3]));

    auto dlFromRef = dlInsFromRange;
    auto dlFromDup = dlInsFromRange.dup;
    assert(dlInsFromRange.front == 2);
    dlFromRef.front = 5;
    assert(dlInsFromRange.front == 5);
    assert(dlFromDup.front == 2);
}

@trusted unittest
{
    import std.conv;
    //testCopyAndRef();
    //testSimpleInit();
    //testInsert();
    assert(_allocator.bytesUsed == 0, "DList ref count leaks memory; leaked "
                                    ~ to!string(_allocator.bytesUsed) ~ " bytes");
}

//@trusted unittest
//{
    //DList!int dl = DList!int(1, 2, 3);

    //auto before = _allocator.bytesUsed;
    //{
        //DList!int dl2 = dl;
        //dl2.popFront();
        //dl.printRefCount();
    //}
    //assert(before == _allocator.bytesUsed);
//}

void main(string[] args)
{
}
