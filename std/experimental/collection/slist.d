import std.stdio;
import std.algorithm.searching : canFind;
import std.experimental.allocator : IAllocator, theAllocator, make, dispose;
import std.experimental.allocator.building_blocks.affix_allocator;
import std.experimental.allocator.gc_allocator;

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
            debug(CollectionSList) writefln("Constructing Node with payload: %s", v);
            _payload = v;
            _next = n;
        }

        ~this()
        {
            debug(CollectionSList) writefln("Destroying Node with payload: %s", _payload);
        }
    }

    Node *_head;
    Node *_sentinel;

    alias Alloc = AffixAllocator!(GCAllocator, uint);
    alias _allocator = Alloc.instance;
    //Alloc _allocator;

    @trusted void addRef(Node *node)
    {
        assert(node !is null);
        debug(CollectionSList)
        {
            uint *pref = prefCount(node);
            writefln("In addRef for node %s. Has refcount: %s; will be: %s",
                    node._payload, *pref, *pref + 1);
        }
        ++*prefCount(node);
    }

    @trusted void delRef(Node *node)
    {
        assert(node !is null);
        import std.stdio;
        writefln("In delRef bef prefCount Node %s\n", node._payload);
        uint *pref = prefCount(node);
        debug(CollectionSList) writefln("In delRef for node %s. Has refcount: %s; will be: %s",
                node._payload, *pref, *pref - 1);
        if (*pref == 0)
        {
            debug(CollectionSList) writefln("Deleting node %s", node._payload);
            _allocator.dispose(node);
        }
        else
        {
            --*pref;
        }
    }

    @trusted uint* prefCount(Node *node) const
    {
        assert(node !is null);
        return cast(uint*)(&_allocator.prefix(cast(void[Node.sizeof])(*node)));
    }

public:
    this(U)(U[] values...)
    if (isImplicitlyConvertible!(U, T))
    {
        this(theAllocator, values);
    }

    this(U)(Allocator allocator, U[] values...)
    if (isImplicitlyConvertible!(U, T))
    {
        //_allocator = allocator;
        _head = _sentinel = _allocator.make!(Node)(0, null);
        insert(values);
    }

    this(Stuff)(Stuff stuff)
    if (isInputRange!Stuff
        && isImplicitlyConvertible!(ElementType!Stuff, T)
        && !is(Stuff == T[]))
    {
        this(theAllocator, stuff);
    }

    this(Stuff)(Allocator allocator, Stuff stuff)
    if (isInputRange!Stuff
        && isImplicitlyConvertible!(ElementType!Stuff, T)
        && !is(Stuff == T[]))
    {
        //_allocator = allocator;
        _head = _sentinel = _allocator.make!(Node)(0, null);
        insert(stuff);
    }

    this(this)
    {
        if (_sentinel is null)
        {
            _head = _sentinel = _allocator.make!(Node)(0, null);
        }

        uint *pref = prefCount(_head);
        addRef(_head);
        debug(CollectionSList) writefln("In postblit for node %s. Has refcount: %s",
                _head._payload, *pref);
    }

    ~this()
    {
        writefln("Begin Dtor");
        while (_head !is null && *prefCount(_head) == 0)
        {
            debug(CollectionSList) writefln("In dtor once. Head at %s", _head._payload);
            Node *tmpNode = _head;
            _head = _head._next;
            delRef(tmpNode);
            debug(CollectionSList) writeln();
        }

        if (_head !is null && *prefCount(_head) > 0)
        {
            // We reached a copy, so just remove the head ref, thus deleting
            // the copy in constant time (we are undoing the postblit)
            debug(CollectionSList) writefln("In dtor twice. Head at %s", _head._payload);
            delRef(_head);
        }
        writefln("End Dtor");
    }

    typeof(this) opAssign();

    bool empty()
    {
        return _head is _sentinel;
    }

    T front()
    {
        assert(!empty, "SList.front: List is empty");
        return _head._payload;
    }

    void popFront()
    {
        assert(!empty, "SList.popFront: List is empty");

        import std.stdio;
        writefln("In pop front for node %s", _head._payload);

        Node *tmpNode = _head;
        _head = _head._next;
        writeln("PF bef if");
        if (*prefCount(tmpNode) > 0 &&  _head !is null)
        {
            // If we have another copy of the list then the refcount
            // must increase, otherwise it will remain the same
            writeln("PF bef add ref");
            addRef(_head);
        }

        writeln("PF bef del ref");
        delRef(tmpNode);
    }

    SList save()
    {
        return this;
    }

    size_t insert(Stuff)(Stuff stuff)
    if (isInputRange!Stuff && isImplicitlyConvertible!(ElementType!Stuff, T))
    {
        //if (_allocator is null) _allocator = theAllocator;
        writeln("Here");
        if (_sentinel is null)
        {
            _head = _sentinel = _allocator.make!(Node)(0, null);
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

        tmpNode._next = _head;
        //if (tmpNode._next !is null)
        //{
            //--*prefCount(tmpNode._next);
        //}
        _head = tmpHead;
        //addRef(_head);
        return result;
    }

    size_t insert(Stuff)(Stuff[] stuff...)
    if (isImplicitlyConvertible!(Stuff, T))
    {
        return insert(stuff);
    }

    void remove()
    {
        assert(!empty, "SList.remove: List is empty");
        popFront();
    }

    debug(CollectionSList) void printRefCount()
    {
        Node *tmpNode = _head;
        while (tmpNode !is null)
        {
            writefln("Node %s has ref count %s", tmpNode._payload,
                    *prefCount(tmpNode));
            tmpNode = tmpNode._next;
        }
        writeln();
    }

}

@trusted unittest
{
    auto sl = SList!int(1);
    //auto sl2 = sl;

    debug(CollectionSList) sl.printRefCount();
    //debug(CollectionSList) sl2.printRefCount();
}

//@trusted unittest
//{
    //import std.algorithm.comparison : equal;
    //import std.algorithm.searching : canFind, find;

    //auto sl = SList!int();
    //assert(sl.empty);

    //sl.insert(1);
    //sl.insert([2]);
    //sl.insert([3, 4, 5]);
    //sl.insert(6, 7, 8);

    //assert(equal(sl, [6, 7, 8, 3, 4, 5, 2, 1]));

    //sl.remove();
    //assert(equal(sl, [7, 8, 3, 4, 5, 2, 1]));

    //assert(canFind(sl, 2));
    //auto sl2 = sl;

    //import std.stdio;
    //writefln("Can find -1? A: %s\n", sl.canFind(-1));
//}

//@trusted unittest
//{
    //import std.algorithm.comparison : equal;

    //auto sl = SList!int();
    //sl.insert(10, 20, 30);

    //auto sl2 = SList!int(sl);

    //assert(equal(sl, sl2));
    //writefln("Are equal? A: %s\n", equal(sl, sl2));
    //debug(CollectionSList)
    //{
        //writefln("For sl");
        //sl.printRefCount();
        //writefln("\nFor sl2");
        //sl2.printRefCount();
    //}

    //sl.popFront();
    //assert(equal(sl, [20, 30]));
    //assert(equal(sl2, [10, 20, 30]));
    //debug(CollectionSList)
    //{
        //writefln("For sl");
        //sl.printRefCount();
        //writefln("\nFor sl2");
        //sl2.printRefCount();
    //}

    //writeln("End of unittest");
//}

void main(string[] args)
{
    //debug(CollectionSList) writefln("Begining of main\n");

    //auto sl = SList!(int)();
    //sl.insert(10);
    ////if (sl !is null)
        ////writeln(sl.empty());
    //debug(CollectionSList)
    //{
        //writeln("After insert");
        //sl.printRefCount();
    //}

    //sl.insert(11, 21, 31, 41, 51);
    //debug(CollectionSList)
    //{
        //writeln("After insert");
        //sl.printRefCount();
    //}

    //sl.insert([12, 22, 32, 42, 52]);
    //debug(CollectionSList)
    //{
        //writeln("After insert");
        //sl.printRefCount();
    //}

    //int i;
    //auto sl2 = sl;
    ////auto sl3 = sl;
    //debug(CollectionSList)
    //{
        //writeln("After sl2");
        //sl.printRefCount();
    //}

    //while (!sl.empty())
    //{
        //writefln("Elem %s: %s", ++i, sl.front);
        //sl.popFront;
        //debug(CollectionSList) sl.printRefCount();
    //}

    //debug(CollectionSList)
    //{
        //writeln();
        //sl2.printRefCount();
    //}

    //auto sl3 = sl2;
    //int needle = 10;
    //debug(CollectionSList)
    //{
        //writeln("\nBefore find");
        //writefln("Can find %s in list? A: %s\n", needle, canFind(sl3, needle));
        //writeln("After find\n");
    //}
    //else
    //{
        //assert(canFind(sl3, needle));
    //}

    //debug(CollectionSList) writefln("Removing Node with value: %s\n", sl2.front);
    ////sl2.remove();
    //sl2.popFront();
    //i = 0;
    //while (!sl2.empty())
    //{
        //debug(CollectionSList) writefln("Elem %s: %s", ++i, sl2.front);
        //sl2.popFront;
    //}

    //debug(CollectionSList) writefln("\nLeaving main");
}
