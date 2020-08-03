module subtex.util;

class ParseException : Exception
{
    this(string msg)
    {
        super(msg);
    }

    this(Position position, string msg)
    {
        this(position.toLocation, msg);
    }

    this(Location location, string msg)
    {
        import std.format : format;
        super("%s: %s".format(location, msg));
    }
}

struct Position
{
    ushort fileId;
    uint offset;

    Location toLocation()
    {
        import std.path : relativePath;
        import std.algorithm : count;
        import std.string : lastIndexOf;
        auto shortFileName = relativePath(Files.name(fileId));
        auto data = Files.read(fileId);
        auto prefix = data[0..offset-1];
        auto line = prefix.count!(x => x == '\n') + 1;
        auto col = prefix.length - prefix.lastIndexOf('\n');
        return Location(shortFileName, line, col);
    }
}

struct Location
{
    string filename;
    size_t line, col;

    string toString() const
    {
        import std.format;
        return format("%s(%s:%s)", filename, line, col);
    }
}

bool isIdentChar(dchar c)
{
    import std.uni;

    return c == '_' || c == '*' || isAlpha(c) || isNumber(c);
}

class Files
{
static:
    void clear()
    {
        idToData = null;
        idToFilename = null;
        filenameToId = null;
    }

    string name(ushort id)
    {
        import std.conv : to;
        auto p = id in idToFilename;
        if (!p) throw new Exception("invalid file id " ~ id.to!string);
        return *p;
    }

    string read(string filename)
    in
    {
        import std.path : isAbsolute;
        assert(isAbsolute(filename));
    }
    do
    {
        return read(id(filename));
    }

    string read(ushort id)
    {
        if (auto p = id in idToData)
        {
            return *p;
        }
        if (auto p = id in idToFilename)
        {
            static import std.file;
            auto data = std.file.readText(*p);
            idToData[id] = data;
            return data;
        }

        import std.conv : to;
        throw new Exception("invalid file id " ~ id.to!string);
    }

    ushort id(string filename)
    in
    {
        import std.path : isAbsolute;
        assert(isAbsolute(filename));
    }
    do
    {
        if (auto p = filename in filenameToId)
        {
            return *p;
        }
        auto id = cast(ushort)idToFilename.length;
        idToFilename[id] = filename;
        filenameToId[filename] = id;
        return id;
    }

    private:
    string[ushort] idToData;
    string[ushort] idToFilename;
    ushort[string] filenameToId;
}
