/**
Utility and ancillary artifacts of `std.experimental.collection`.
*/
module std.experimental.collection.common;
import std.range: isInputRange;

auto tail(Collection)(Collection collection)
    if (isInputRange!Collection)
{
    collection.popFront();
    return collection;
}
