import std.stdio;

struct SharedPtr(T)
{
    T *_pointee;
    size_t *_count;

    this(T *pointee)
    {
        writeln("Here");
        _count = new size_t(1);
        _pointee = pointee;
    }

    this(this)
    {
        ++*_count;
    }

    ~this()
    {
        if (--*_count == 0)
        {
            writeln("Deleting");
            delete _count;
            delete _pointee;
        }
    }

    typeof(this) opAssign(SharedPtr!T sp)
    {
        writeln("In opAssign");
        if (_pointee != sp._pointee)
        {
            if (_count !is null && --*_count == 0)
            {
                delete _count;
                delete _pointee;
            }

            _count = sp._count;
            ++*_count;
            _pointee = sp._pointee;
        }

        return this;
    }
}

@trusted unittest
{
    // Test ctor
    SharedPtr!int sp = new int(10);
    assert(sp._count !is null);
    assert(sp._pointee !is null);
    assert(*sp._count == 1);
    assert(*sp._pointee == 10);
    writefln("sp has count %s and value %s", *sp._count, *sp._pointee);

    // Test postblit
    auto sp2 = sp;
    assert(sp._count == sp2._count);
    assert(sp._pointee == sp2._pointee);
    assert(*sp._count == 2);
    writefln("sp2 has count %s and value %s", *sp._count, *sp._pointee);

    {
        // Test opAssign
        SharedPtr!int sp3;
        SharedPtr!int sp4;
        sp4 = sp3 = sp;
        assert(*sp._count == 4);
        writefln("sp3 has count %s and value %s", *sp._count, *sp._pointee);
    }
    assert(*sp._count == 2);

    writefln("sp2 has count %s and value %s", *sp._count, *sp._pointee);
}

void main(string[] args)
{
     /*code*/
}
