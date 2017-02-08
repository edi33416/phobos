import std.stdio;
import std.experimental.allocator : IAllocator, theAllocator, make, dispose;
import std.algorithm.searching : canFind;

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
            writefln("Constructing Node with payload: %s\n", v);
            _payload = v;
            _next = n;
        }

        ~this()
        {
            writefln("Destroying Node with payload: %s\n", _payload);
        }
    }

    Node *_head;
    Allocator _allocator;

public:
    this(U)(U[] values...)
    if (isImplicitlyConvertible!(U, T))
    {
        this(theAllocator, values);
    }

    this(U)(Allocator allocator, U[] values...)
    if (isImplicitlyConvertible!(U, T))
    {
        _allocator = allocator;
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
        _allocator = allocator;
        insert(stuff);
    }

    ~this()
    {
        while (!empty)
        {
            remove();
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
        _head = _head._next;
    }

    SList save()
    {
        return this;
    }

    size_t insert(Stuff)(Stuff stuff)
    if (isInputRange!Stuff && isImplicitlyConvertible!(ElementType!Stuff, T))
    {
        if (_allocator is null) _allocator = theAllocator;

        size_t result;
        Node *tmpNode;
        Node *tmpHead;
        foreach (item; stuff)
        {
            //Node *newNode = make!(Node, Allocator)(item, null);
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

    void remove()
    {
        Node *tmpNode = _head;
        _head = _head._next;
        _allocator.dispose(tmpNode);
    }

}

void main(string[] args)
{
    writefln("Begining of main\n\n");

    auto sl = new SList!(int)();
    sl.insert(10);
    //if (sl !is null)
        //writeln(sl.empty());
    sl.insert(11, 21, 31, 41, 51);
    sl.insert([11, 21, 31, 41, 51]);

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
