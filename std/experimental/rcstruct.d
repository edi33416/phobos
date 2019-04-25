import core.memory : pureMalloc, pureFree;

private struct StatsAllocator
{
    version(CoreUnittest) size_t bytesUsed;

    @trusted @nogc nothrow pure
    void* allocate(size_t bytes) shared
    {
        import core.memory : pureMalloc;
        if (!bytes) return null;

        auto p = pureMalloc(bytes);
        if (p is null) return null;
        enum alignment = size_t.sizeof;
        assert(cast(size_t) p % alignment == 0);

        version (CoreUnittest)
        {
            static if (is(typeof(this) == shared))
            {
                import core.atomic : atomicOp;
                atomicOp!"+="(bytesUsed, bytes);
            }
            else
            {
                bytesUsed += bytes;
            }
        }
        return p;
    }

    @system @nogc nothrow pure
    bool deallocate(void[] b) shared
    {
        import core.memory : pureFree;
        assert(b !is null);

        version (CoreUnittest)
        {
            static if (is(typeof(this) == shared))
            {
                import core.atomic : atomicOp;
                assert(atomicOp!">="(bytesUsed, b.length));
                atomicOp!"-="(bytesUsed, b.length);
            }
            else
            {
                assert(bytesUsed >= b.length);
                bytesUsed -= b.length;
            }
        }
        pureFree(b.ptr);
        return true;
    }

    static shared StatsAllocator instance;
}

version (CoreUnittest)
{
    private shared StatsAllocator allocator;

    private @nogc nothrow pure @trusted
    void* pureAllocate(size_t n)
    {
        return (cast(void* function(size_t) @nogc nothrow pure)(&_allocate))(n);
    }

    private @nogc nothrow @safe
    void* _allocate(size_t n)
    {
        return allocator.allocate(n);
    }

    private @nogc nothrow pure
    void pureDeallocate(T)(T[] b)
    {
        return (cast(void function(T[]) @nogc nothrow pure)(&_deallocate!(T)))(b);
    }

    private @nogc nothrow
    void _deallocate(T)(T[] b)
    {
        allocator.deallocate(b);
    }
}
else
{
    alias pureAllocate = pureMalloc;

    void pureDeallocate(T)(T[] b) { pureFree(b.ptr); }
}

struct __mutable(T)
{
    private union
    {
        T _unused;
        size_t _ref = cast(size_t) null;
    }

    this(T val) pure const nothrow
    {
        _ref = cast(size_t) val;
    }

    this(shared T val) pure const nothrow
    {
        _ref = cast(size_t) val;
    }

    T unwrap() const
    {
        return cast(T) _ref;
    }
}

struct rcstruct
{
    import core.atomic : atomicOp;

    alias RC_T = int;
    __mutable!(RC_T*) rc;

    private static enum isSharedMask = 1 << ((RC_T.sizeof * 8) - 1);

    pure nothrow @nogc @safe scope
    bool isShared() const
    {
        return !!atomicOp!">="(*((() @trusted => cast(shared RC_T*) rc.unwrap)()), isSharedMask);
    }

    pure nothrow @nogc @safe scope
    void setIsShared(bool _isShared) const
    {
        if (_isShared)
        {
            atomicOp!"|="(*((() @trusted => cast(shared RC_T*) rc.unwrap)()), isSharedMask);
        }
    }

    pure nothrow @nogc @trusted scope
    RC_T rcOp(string op)(RC_T val) const
    {
        if (isShared())
        {
            return cast(RC_T)(atomicOp!op(*(cast(shared RC_T*) rc.unwrap), val));
        }
        else
        {
            mixin("return cast(RC_T)(*(cast(RC_T*) rc.unwrap)" ~ op ~ "val);");
        }
    }

    this(this Q)(int) const pure scope
    {
        static if (is(Q == immutable))
        {
            rc = cast(shared RC_T*) pureAllocate(RC_T.sizeof);
            setIsShared(true);
        }
        else
        {
            rc = cast(RC_T*) pureAllocate(RC_T.sizeof);
        }
        *rc.unwrap = 0;
        addRef();
    }

    private enum copyCtorIncRef = q{
        rc = rhs.rc;
        if (rc.unwrap !is null)
        {
            setIsShared(rhs.isShared());
            addRef();
        }
    };

    this(ref typeof(this) rhs)
    {
        mixin(copyCtorIncRef);
    }

    // { Get a const obj
    this(ref typeof(this) rhs) const
    {
        mixin(copyCtorIncRef);
    }

    this(const ref typeof(this) rhs) const
    {
        mixin(copyCtorIncRef);
    }

    this(immutable ref typeof(this) rhs) const
    {
        mixin(copyCtorIncRef);
    }
    // } Get a const obj

    // { Get an immutable obj
    this(ref typeof(this) rhs) immutable
    {
        // Can't have an immutable ref to a mutable. Create a new RC
        rc = cast(shared RC_T*) pureAllocate(RC_T.sizeof);
        setIsShared(true);
    }

    @trusted
    this(const ref typeof(this) rhs) immutable
    {
        if (isShared)
        {
            // By implementation, only immutable RC is shared, so it's ok to inc ref
            rc = cast(immutable) rhs.rc;
            if (rc.unwrap !is null)
            {
                setIsShared(rhs.isShared());
                addRef();
            }
        }
        else
        {
            // Can't have an immutable ref to a mutable. Create a new RC
            rc = cast(shared RC_T*) pureAllocate(RC_T.sizeof);
            setIsShared(true);
        }
    }

    this(immutable ref typeof(this) rhs) immutable
    {
        mixin(copyCtorIncRef);
    }
    // } Get an immutable obj

    private void* addRef() pure const @trusted scope
    {
        assert(rc.unwrap !is null);
        rcOp!"+="(1);
        return null;
    }

    private void* delRef() pure const @trusted scope
    {
        assert(rc.unwrap !is null);
        RC_T counter = rcOp!"-="(1);
        if ((counter == 0) || (isShared() && counter == isSharedMask))
        {
            deallocate();
        }
        return null;
    }

    private void deallocate() pure const scope
    {
        pureDeallocate(rc.unwrap[0 .. 1]);
    }

    ~this() pure const scope
    {
        if (rc.unwrap !is null)
        {
            delRef();
        }
    }

    pure nothrow @safe @nogc scope
    bool isUnique() const
    {
        return rcOp!"=="(1) || rcOp!"=="(isSharedMask | 1);
    }

    pure nothrow @nogc scope
    auto getUnsafeValue() const
    {
        return rc.unwrap;
    }
}

version(CoreUnittest)
unittest
{
    {
        rcstruct a = rcstruct(1);
        const rcstruct ca = const rcstruct(1);
        immutable rcstruct ia = immutable rcstruct(1);
    }

    assert(allocator.bytesUsed == 0, "rcstruct leakes memory");
}
