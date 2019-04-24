import core.memory : pureMalloc, pureFree;

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
            rc = cast(shared RC_T*) pureMalloc(RC_T.sizeof);
            setIsShared(true);
        }
        else
        {
            rc = cast(RC_T*) pureMalloc(RC_T.sizeof);
        }
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
        rc = cast(shared RC_T*) pureMalloc(RC_T.sizeof);
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
            rc = cast(shared RC_T*) pureMalloc(RC_T.sizeof);
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
        if (counter == 0) deallocate();
        return null;
    }

    private void deallocate() pure const scope
    {
        pureFree(rc.unwrap);
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

unittest
{
    rcstruct a = rcstruct(1);
    const rcstruct ca = const rcstruct(1);
    immutable rcstruct ia = immutable rcstruct(1);
}
