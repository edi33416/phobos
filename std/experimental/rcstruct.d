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

struct __RefCount
{
    private static struct __mutable(T)
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

    version(CoreUnittest) {} else
    {
        import core.memory : pureMalloc, pureFree;

        private alias pureAllocate = pureMalloc;

        @nogc nothrow pure
        private static void pureDeallocate(T)(T[] b)
        {
            pureFree(b.ptr);
        }
    }
    import core.atomic : atomicOp;

    alias CounterType = uint;
    private __mutable!(CounterType*) rc;

    @nogc nothrow pure @safe scope
    bool isShared() const
    {
        // Faster than ((cast(size_t) rc.unwrap) % 8) == 0;
        return !((cast(size_t) rc.unwrap) & 7);
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
        if (rhs.isInitialized())
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
        if (rhs.isShared())
        {
            // By implementation, only immutable RC is shared, so it's ok to inc ref
            //rc = (() @trusted => cast(shared int *) rhs.rc.unwrap)();
            rc = (() @trusted => cast(immutable) rhs.rc)();
            if (isInitialized())
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
    ref __RefCount opAssign(ref typeof(this) rhs)
    {
        if (rhs.isInitialized() && rc.unwrap == rhs.rc.unwrap)
        {
            return this;
        }
        if (rhs.isInitialized())
        {
            rhs.addRef();
        }
        if (isInitialized())
        {
            delRef();
        }
        rc = rhs.rc;
        return this;
    }

    @nogc nothrow pure @safe scope
    private void* addRef() const
    {
        assert(isInitialized());
        rcOp!"+="(1);
        return null;
    }

    @nogc nothrow pure @trusted scope
    private void* delRef() const
    {
        assert(isInitialized());
        if (rcOp!"=="(1) || (rcOp!"-="(1) == 0))
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
    ~this()
    {
        if (isInitialized())
        {
            delRef();
        }
    }

    pure nothrow @safe @nogc scope
    bool isUnique() const
    {
        assert(isInitialized(), "[__RefCount.isUnique] __RefCount is uninitialized");
        return !!rcOp!"=="(1);
    }

    pure nothrow @safe @nogc scope
    bool isInitialized() const
    {
        return rc.unwrap !is null;
    }

    pure nothrow @nogc @system
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
        __RefCount a = __RefCount(1);
        assert(a.isUnique);
        const __RefCount ca = const __RefCount(1);
        assert(ca.isUnique);
        immutable __RefCount ia = immutable __RefCount(1);
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

        __RefCount t;
        assert(!t.isInitialized());
        __RefCount t2 = t;
        assert(!t.isInitialized());
        assert(!t2.isInitialized());
    }();

    assert(allocator.bytesUsed == 0, "__RefCount leakes memory");
}

version(CoreUnittest)
unittest
{
    () @safe @nogc pure nothrow
    {
        __RefCount a = __RefCount(1);
        assert(a.isUnique);
        __RefCount a2 = a;
        assert((() @trusted => *cast(int*)a.getUnsafeValue() == 2)());
        __RefCount a3 = __RefCount(1);
        a2 = a3;
        assert((() @trusted => *cast(int*)a.getUnsafeValue() == 1)());
        assert(a.isUnique);
    }();

    assert(allocator.bytesUsed == 0, "__RefCount leakes memory");
}

version(CoreUnittest)
unittest
{
    struct TestRC
    {
        private __RefCount rc;
        int[] payload;

        @nogc nothrow pure @trusted scope
        this(this Q)(int sz) const
        {
            rc = __RefCount(1);
            static if (is(Q == immutable))
            {
                payload = (cast(immutable int*) pureAllocate(sz * int.sizeof))[0 .. sz];
            }
            else
            {
                payload = (cast(int*) pureAllocate(sz * int.sizeof))[0 .. sz];
            }
        }

        private enum copyCtorIncRef = q{
            rc = rhs.rc;
            payload = rhs.payload;
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
        @nogc nothrow pure @trusted scope
        this(ref typeof(this) rhs) immutable
        {
            // Can't have an immutable ref to a mutable. Create a new RC
            rc = rhs.rc;
            auto sz = rhs.payload.length;
            int[] tmp = (cast(int*) pureAllocate(sz * int.sizeof))[0 .. sz];
            tmp[] = rhs.payload[];
            payload = cast(immutable) tmp;
        }

        @nogc nothrow pure @safe scope
        this(const ref typeof(this) rhs) immutable
        {
            rc = rhs.rc;
            if (rhs.rc.isShared)
            {
                // By implementation, only immutable RC is shared, so it's ok to inc ref
                payload = (() @trusted => cast(immutable) rhs.payload)();
            }
            else
            {
                // Can't have an immutable ref to a mutable. Create a new RC
                auto sz = rhs.payload.length;
                int[] tmp = (() @trusted => (cast(int*) pureAllocate(sz * int.sizeof))[0 .. sz])();
                tmp[] = rhs.payload[];
                payload = (() @trusted => cast(immutable) tmp)();
            }
        }

        @nogc nothrow pure @safe scope
        this(immutable ref typeof(this) rhs) immutable
        {
            mixin(copyCtorIncRef);
        }
        // } Get an immutable obj

        @nogc nothrow pure @safe scope
        ref TestRC opAssign(ref typeof(this) rhs)
        {
            if (payload is rhs.payload)
            {
                return this;
            }
            if (rc.isInitialized && rc.isUnique)
            {
                () @trusted { pureDeallocate(payload); }();
            }
            payload = rhs.payload;
            rc = rhs.rc;
            return this;
        }

        @nogc nothrow pure @trusted scope
        ~this()
        {
            if (rc.isInitialized() && rc.isUnique())
            {
                pureDeallocate(cast(int[]) payload);
            }
        }
    }

    () @safe @nogc pure nothrow
    {
        enum numElem = 10;
        auto t = TestRC(numElem);
        assert(t.rc.isUnique);
        const TestRC ct = const TestRC(numElem);
        assert(ct.rc.isUnique);
        immutable TestRC it = immutable TestRC(numElem);
        assert(it.rc.isUnique);

        // A const reference will increase the ref count
        const c_cp_t = t;
        assert((() @trusted => *cast(int*)t.rc.getUnsafeValue() == 2)());
        assert(t.payload is c_cp_t.payload);
        const c_cp_ct = ct;
        assert((() @trusted => *cast(int*)ct.rc.getUnsafeValue() == 2)());
        assert(ct.payload is c_cp_ct.payload);
        const c_cp_it = it;
        assert((() @trusted => *cast(int*)it.rc.getUnsafeValue() == 2)());
        assert(it.payload is c_cp_it.payload);

        // An immutable from a mutable reference will create a copy
        immutable i_cp_t = t;
        assert((() @trusted => *cast(int*)t.rc.getUnsafeValue() == 2)());
        assert((() @trusted => *cast(int*)i_cp_t.rc.getUnsafeValue() == 1)());
        assert(t.payload !is i_cp_t.payload);
        // An immutable from a const to a mutable reference will create a copy
        immutable i_cp_ct = ct;
        assert((() @trusted => *cast(int*)ct.rc.getUnsafeValue() == 2)());
        assert((() @trusted => *cast(int*)i_cp_ct.rc.getUnsafeValue() == 1)());
        assert(ct.payload !is i_cp_ct.payload);
        // An immutable from an immutable reference will increase the ref count
        immutable i_cp_it = it;
        assert((() @trusted => *cast(int*)it.rc.getUnsafeValue() == 3)());
        assert((() @trusted => *cast(int*)i_cp_it.rc.getUnsafeValue() == 3)());
        assert(it.payload is i_cp_it.payload);
        // An immutable from a const to an immutable reference will increase the ref count
        immutable i_cp_c_cp_it = c_cp_it;
        assert((() @trusted => *cast(int*)c_cp_it.rc.getUnsafeValue() == 4)());
        assert((() @trusted => *cast(int*)i_cp_c_cp_it.rc.getUnsafeValue() == 4)());
        assert((() @trusted => i_cp_c_cp_it.rc.getUnsafeValue() == c_cp_it.rc.getUnsafeValue())());
        assert(c_cp_it.payload is i_cp_c_cp_it.payload);

        // Ensure uninitialized structs don't crash
        TestRC t1;
        assert(!t1.rc.isInitialized);
        TestRC t2 = t1;
        assert(!t1.rc.isInitialized);
        assert(!t2.rc.isInitialized);
        TestRC t3 = TestRC(numElem);
        t2 = t3;
    }();

    assert(allocator.bytesUsed == 0, "__RefCount leakes memory");
}
