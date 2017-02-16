import std.stdio;
import std.algorithm.searching : canFind;
import std.experimental.allocator : IAllocator, theAllocator, make, dispose;
import std.experimental.allocator.building_blocks.affix_allocator;
import std.experimental.allocator.gc_allocator;

struct SList(T, Allocator = IAllocator)
{
    import std.traits : isImplicitlyConvertible;
    import std.range.primitives : isInputRange, isForwardRange, ElementType;

private:
    struct Node
    {
        T _payload;
        Node *_next;

        this(T v, Node *n)
        {
            writefln("Constructing Node with payload: %s", v);
            _payload = v;
            _next = n;
        }

        ~this()
        {
            writefln("Destroying Node with payload: %s", _payload);
        }
    }

    Node *_head;

    alias Alloc = AffixAllocator!(GCAllocator, uint);
    alias _allocator = Alloc.instance;
    //Alloc _allocator;

    @trusted void addRef(Node *node)
    {
        assert(node !is null);
        ++*prefCount(node);
    }

    @trusted void delRef(Node *node)
    {
        assert(node !is null);
        uint *pref = prefCount(node);
        if (!*pref)
        {
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
        return cast(uint*)(&_allocator.prefix(node));
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
        insert(stuff);
    }

    this(this)
    {
        addRef(_head);
    }

    ~this()
    {
        if (*prefCount(_head) > 0)
        {
            // Then this is a copy, so just remove the head ref, thus deleting
            // the copy in constant time
            delRef(_head);
        }
        else
        {
            while (!empty)
            {
                remove();
            }
        }
    }

    bool empty()
    {
        return _head is null;
    }

    T front()
    {
        assert(!empty, "SList.front: List is empty");
        return _head._payload;
    }

    void popFront()
    {
        assert(!empty, "SList.popFront: List is empty");
        Node *tmpNode = _head;
        _head = _head._next;
        addRef(_head);
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

        size_t result;
        Node *tmpNode;
        Node *tmpHead;
        foreach (item; stuff)
        {
            Node *newNode = _allocator.make!(Node)(item, null);
            (tmpHead ? tmpNode._next : tmpHead) = newNode;
            tmpNode = newNode;
            addRef(newNode);
            ++result;
        }

        if (!tmpNode)
        {
            return 0;
        }

        tmpNode._next = _head;
        if (tmpNode._next !is null)
        {
            addRef(tmpNode._next);
        }
        _head = tmpHead;
        addRef(_head);
        return result;
    }

    size_t insert(Stuff)(Stuff[] stuff...)
    if (isImplicitlyConvertible!(Stuff, T))
    {
        return insert(stuff);
    }

    void remove()
    {
        Node *tmpNode = _head;
        _head = _head._next;
        addRef(_head);
        delRef(tmpNode);
    }

}

void main(string[] args)
{
    writefln("Begining of main\n");

    auto sl = SList!(int)();
    sl.insert(10);
    //if (sl !is null)
        //writeln(sl.empty());
    sl.insert(11, 21, 31, 41, 51);
    sl.insert([12, 22, 32, 42, 52]);

    int i;
    auto sl2 = sl.save();
    while (!sl.empty())
    {
        writefln("Elem %s: %s", ++i, sl.front);
        sl.popFront;
    }
    writeln();

    int needle = 10;
    writefln("Can find %s in list? A: %s\n", needle, canFind(sl2, needle));

    writefln("Removing Node with value: %s\n", sl2.front);
    sl2.remove();
    i = 0;
    while (!sl2.empty())
    {
        writefln("Elem %s: %s", ++i, sl2.front);
        sl2.popFront;
    }

    writefln("\nLeaving main");
}
