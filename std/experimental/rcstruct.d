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

    @nogc nothrow pure
    void pureDeallocate(T)(T[] b) { pureFree(b.ptr); }
}

struct __mutable(T)
{
    private union
    {
        T _unused;
        size_t _ref = cast(size_t) null;
    }

    @nogc nothrow pure @trusted
    this(T val) const
    {
        _ref = cast(size_t) val;
    }

    @nogc nothrow pure @trusted
    this(shared T val) const
    {
        _ref = cast(size_t) val;
    }

    @nogc nothrow pure @trusted
    T unwrap() const
    {
        return cast(T) _ref;
    }
}

struct RefCount
{
    import core.atomic : atomicOp;

    alias CounterType = uint;
    private __mutable!(CounterType*) rc;

    @nogc nothrow pure @safe scope
    bool isShared() const
    {
        return (cast(size_t) rc.unwrap) % 8 == 0;
    }

    @nogc nothrow pure @trusted scope
    private CounterType rcOp(string op)(CounterType val) const
    {
        if (isShared())
        {
            return cast(CounterType)(atomicOp!op(*(cast(shared CounterType*) rc.unwrap), val));
        }
        else
        {
            mixin("return cast(CounterType)(*(cast(CounterType*) rc.unwrap)" ~ op ~ "val);");
        }
    }

    @nogc nothrow pure @trusted scope
    this(this Q)(int) const
    {
        CounterType* t = cast(CounterType*) pureAllocate(2 * CounterType.sizeof);
        static if (is(Q == immutable))
        {
            rc = cast(shared CounterType*) t;
        }
        else
        {
            rc = cast(CounterType*) (t + 1);
        }
        *rc.unwrap = 0;
        addRef();
    }

    private enum copyCtorIncRef = q{
        rc = rhs.rc;
        assert(rc.unwrap == rhs.rc.unwrap);
        if (rhs.rc.unwrap !is null)
        {
            assert(isShared() == rhs.isShared());
            addRef();
        }
    };

    @nogc nothrow pure @safe scope
    this(ref typeof(this) rhs)
    {
        mixin(copyCtorIncRef);
    }

    // { Get a const obj
    @nogc nothrow pure @safe scope
    this(ref typeof(this) rhs) const
    {
        mixin(copyCtorIncRef);
    }

    @nogc nothrow pure @safe scope
    this(const ref typeof(this) rhs) const
    {
        mixin(copyCtorIncRef);
    }

    @nogc nothrow pure @safe scope
    this(immutable ref typeof(this) rhs) const
    {
        mixin(copyCtorIncRef);
    }
    // } Get a const obj

    // { Get an immutable obj
    @nogc nothrow pure @safe scope
    this(ref typeof(this) rhs) immutable
    {
        // Can't have an immutable ref to a mutable. Create a new RC
        rc = (() @trusted => cast(shared CounterType*) pureAllocate(2 * CounterType.sizeof))();
        *rc.unwrap = 0;
        addRef();
    }

    @nogc nothrow pure @safe scope
    this(const ref typeof(this) rhs) immutable
    {
        if (rhs.isShared)
        {
            // By implementation, only immutable RC is shared, so it's ok to inc ref
            //rc = (() @trusted => cast(shared int *) rhs.rc.unwrap)();
            rc = (() @trusted => cast(immutable) rhs.rc)();
            if (rc.unwrap !is null)
            {
                addRef();
            }
        }
        else
        {
            // Can't have an immutable ref to a mutable. Create a new RC
            rc = (() @trusted => cast(shared CounterType*) pureAllocate(2 * CounterType.sizeof))();
            *rc.unwrap = 0;
            addRef();
        }
    }

    @nogc nothrow pure @safe scope
    this(immutable ref typeof(this) rhs) immutable
    {
        mixin(copyCtorIncRef);
    }
    // } Get an immutable obj

    @nogc nothrow pure @safe scope
    private void* addRef() const
    {
        assert(rc.unwrap !is null);
        rcOp!"+="(1);
        return null;
    }

    @nogc nothrow pure @trusted scope
    private void* delRef() const
    {
        assert(rc.unwrap !is null);
        CounterType counter = rcOp!"-="(1);
        if (counter == 0)
        {
            deallocate();
        }
        return null;
    }

    @nogc nothrow pure @system scope
    private void deallocate() const
    {
        if (isShared())
        {
            pureDeallocate(rc.unwrap[0 .. 2]);
        }
        else
        {
            pureDeallocate((rc.unwrap - 1)[0 .. 2]);
        }
    }

    @nogc nothrow pure @trusted scope
    ~this() const
    {
        if (rc.unwrap !is null)
        {
            delRef();
        }
    }

    pure nothrow @safe @nogc scope
    bool isUnique() const
    {
        return (rc.unwrap is null) || rcOp!"=="(1);
    }

    pure nothrow @nogc @system scope
    CounterType* getUnsafeValue() const
    {
        return rc.unwrap;
    }
}

version(CoreUnittest)
unittest
{
    () @safe @nogc pure nothrow
    {
        RefCount a = RefCount(1);
        assert(a.isUnique);
        const RefCount ca = const RefCount(1);
        assert(ca.isUnique);
        immutable RefCount ia = immutable RefCount(1);
        assert(ia.isUnique);

        // A const reference will increase the ref count
        const c_cp_a = a;
        assert((() @trusted => *cast(int*)a.getUnsafeValue() == 2)());
        const c_cp_ca = ca;
        assert((() @trusted => *cast(int*)ca.getUnsafeValue() == 2)());
        const c_cp_ia = ia;
        assert((() @trusted => *cast(int*)ia.getUnsafeValue() == 2)());

        // An immutable from a mutable reference will create a copy
        immutable i_cp_a = a;
        assert((() @trusted => *cast(int*)a.getUnsafeValue() == 2)());
        assert((() @trusted => *cast(int*)i_cp_a.getUnsafeValue() == 1)());
        // An immutable from a const to a mutable reference will create a copy
        immutable i_cp_ca = ca;
        assert((() @trusted => *cast(int*)ca.getUnsafeValue() == 2)());
        assert((() @trusted => *cast(int*)i_cp_ca.getUnsafeValue() == 1)());
        // An immutable from an immutable reference will increase the ref count
        immutable i_cp_ia = ia;
        assert((() @trusted => *cast(int*)ia.getUnsafeValue() == 3)());
        assert((() @trusted => *cast(int*)i_cp_ia.getUnsafeValue() == 3)());
        // An immutable from a const to an immutable reference will increase the ref count
        immutable i_cp_c_cp_ia = c_cp_ia;
        assert((() @trusted => *cast(int*)c_cp_ia.getUnsafeValue() == 4)());
        assert((() @trusted => *cast(int*)i_cp_c_cp_ia.getUnsafeValue() == 4)());
        assert((() @trusted => i_cp_c_cp_ia.getUnsafeValue() == c_cp_ia.getUnsafeValue())());

        RefCount t;
        assert(t.isUnique());
        RefCount t2 = t;
        assert(t.isUnique());
        assert(t2.isUnique());
    }();

    assert(allocator.bytesUsed == 0, "RefCount leakes memory");
}
