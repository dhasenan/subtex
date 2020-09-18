module subtex.books;

import std.algorithm;
import std.array;
import std.conv;
import std.typecons;
import std.uuid;
import std.string;
import std.format;
import subtex.util;

class Book
{
    string id;
    this()
    {
        id = randomUUID().to!string;
    }

    string mainFile;
    string[] files;
    string[][string] info;
    Chapter[] chapters;
    Macro[DefIdent] defs;

    Book dup()
    {
        import std.algorithm, std.array;
        auto b = new Book;
        b.files = files;
        b.info = info.dup;
        b.chapters = chapters.map!(x => cast(Chapter)x.dup).array;
        b.defs = defs.dup;
        return b;
    }

    string author()
    {
        if (auto p = "author" in info)
        {
            return (*p)[0];
        }
        return "Writer";
    }

    string title()
    {
        if (auto p = "title" in info)
        {
            return (*p)[0];
        }
        return "Book";
    }

    string[] stylesheets()
    {
        if (auto p = "stylesheet" in info)
        {
            return *p;
        }
        return null;
    }
}

struct DefIdent
{
    string name;
    string type;
}

// A standard node is either a plain string, or a command, or a series of nodes.
// Only one at a time.
class Node
{
    this(string text, Position position)
    {
        this.text = text;
        this.position = position;
    }

    string text; // for commands: the name of the command; else text contents
    string uri; // for URI-oriented commands (img)
    Node parent;
    Node[] kids;
    Position position;
    protected size_t start() { return position.offset; }

    // Approximate end of this node.
    size_t end()
    {
        if (kids)
        {
            return kids[$ - 1].end;
        }
        return start + text.length;
    }

    size_t length()
    {
        return end() - start;
    }

    Node dup()
    {
        auto n = new Node(text, position);
        _dupeTo(n);
        return n;
    }

    protected void _dupeTo(Node n)
    {
        n.tupleof = this.tupleof;
        n.kids = kids.map!(x => x.dup).array;
        foreach (kid; n.kids) kid.parent = n;
        import std.stdio;
    }

    void error(T...)(string msg, T args)
    {
        import std.file : readText;
        throw new ParseException(position, format(msg, args));
    }

    protected this() {}
}

enum Dup = `
    protected this() {}

    override typeof(this) dup()
    {
        auto d = new typeof(this);
        _dupeTo(d);
        return d;
    }
    protected override void _dupeTo(Node n)
    {
        (cast(typeof(this))n).tupleof = this.tupleof;
        super._dupeTo(n);
    }
`;

class Cmd : Node
{
    this(string text, Position position)
    {
        super(text, position);
    }

    mixin(Dup);
}

class Footnote : Node
{
    this(size_t index, Position position)
    {
        super((index + 1).to!string, position);
        this.index = index;
    }

    size_t index;
}

class Chapter : Node
{
    this(bool silent, Position position)
    {
        super("", position);
        this.silent = silent;
    }

    this(bool silent, string title, Position position)
    {
        // Chapters are special and all.
        super("", position);
        this.title = title;
        this.silent = silent;
        this.kids ~= new Node(title, position);
    }

    string title;
    bool silent;
    // Absolute index, corresponds to position in Book.chapters
    int index;
    // For chapter numbering
    int chapterNum;
    Node[] footnotes;

    string fileid()
    {
        return `chapter` ~ index.to!string;
    }

    string filename()
    {
        return `chapter` ~ index.to!string ~ `.html`;
    }

    string fullTitle()
    {
        import std.format;

        if (silent)
        {
            return title;
        }
        return `Chapter %s: %s`.format(chapterNum, title);
    }

    string id()
    {
        return title.sha1UUID().to!string;
    }
    mixin(Dup);
}

class Macro : Node
{
    this(string name, Position position)
    {
        super(name, position);
    }

    string kind;

    this(Cmd c)
    {
        import std.string : strip;
        auto kn = kindAndName(c);
        super(kn[1].strip, c.position);

        this.kind = kn[0];
        auto firstText = c.kids[0].dup;
        firstText.text = firstText.text[kn[1].length + 1 .. $];
        this.kids = [firstText] ~ c.kids[1..$];
    }

    private static Tuple!(string, string) kindAndName(Cmd c)
    {
        string kind;
        switch (c.text)
        {
            case "macrobb":
            case "defbb":
                kind = "bbcode";
                break;
            case "defhtml":
            case "macrohtml":
                kind = "html";
                break;
            default:
                break;
        }

        auto k = c.kids[0];
        import std.algorithm : splitter;
        auto p = k.text.splitter(',');
        return tuple(kind, p.front);
    }

    mixin(Dup);
}

class ArgSeparator : Node
{
    this(Position position)
    {
        super("|", position);
    }

    mixin(Dup);
}

class Arg : Node
{
    this(Node[] nodes)
    {
        super("", nodes ? nodes[0].position : Position.init);
        this.kids = nodes;
    }
    mixin(Dup);
}

class ParagraphSeparator : Node
{
    this(Position position)
    {
        super("\n\n", position);
    }

    this(string name, Position position)
    {
        super(name, position);
    }

    mixin(Dup);
}

class Content : Node
{
    static immutable size_t all = cast(size_t)-1;

    this(size_t index, Position position)
    {
        super("content", position);
        this.index = index;
    }

    size_t index;

    mixin(Dup);
}

class Import : Node
{
    this(string path, Position position)
    {
        super("import", position);
        this.path = path;
    }

    string path;
}

class Image : Node
{
    this(string path, Position position)
    {
        super("img", position);
        this.path = path;
    }

    string path;

    mixin(Dup);
}
