module subtex.books;

import std.conv;
import std.typecons;
import std.uuid;

struct Loc
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

class Context
{
    string filename;
    Context parent;
    string[string] info;
    string[] stylesheets;

    this(string filename, string filetext)
    {
        this.filename = filename;
        this.filetext = filetext;
    }

    private string filetext;
    private Macro[DefIdent] macros;

    Loc loc(size_t offset)
    {
        import std.algorithm : count;
        import std.string : lastIndexOf;
        auto prefix = filetext[0 .. offset];
        size_t line = prefix.count!(x => x == '\n') + 1;
        size_t col = prefix.length - prefix.lastIndexOf('\n');
        return Loc(filename, line, col);
    }

    void define(Macro m)
    {
        auto ident = DefIdent(m.text, m.kind);
        if (auto p = ident in macros)
        {
            auto dup = *p;
            auto loc = dup.context.loc(dup.start);
            m.error("duplicate definition of macro '%s' -- previous definition %s", m.text, loc);
            return;
        }
        macros[ident] = m;
    }

    Macro findMacro(Cmd cmd, string outputType)
    {
        if (auto p = DefIdent(cmd.text, outputType) in macros)
        {
            return (*p);
        }
        if (parent)
        {
            return parent.findMacro(cmd, outputType);
        }
        return null;
    }

    Import[] imports;
    bool[string] importedFiles;

    void addImport(Import im)
    {
        imports ~= im;
        importedFiles[im.path] = true;
    }

    void addInfo(string name, string value)
    {
        import std.string : strip;
        info[name.strip] = value.strip;
    }
}

// A standard node is either a plain string, or a command, or a series of nodes.
// Only one at a time.
class Node
{
    this(string text, size_t start)
    {
        this.text = text;
        this.start = start;
    }

    string text; // for commands: the name of the command; else text contents
    string uri; // for URI-oriented commands (img)
    Context context;
    Node parent;
    Node[] kids;
    size_t start;

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
        auto n = new Node(text, start);
        n.kids = kids.dup;
        n.uri = uri;
        return n;
    }

    void error(T...)(string msg, T args)
    {
        import std.format : format;
        msg = format(msg, args);
        auto loc = context.loc(start);
        throw new ParseException("%s: %s".format(loc, msg));
    }
}

class Cmd : Node
{
    this(string text, size_t start)
    {
        super(text, start);
    }

    override Node dup()
    {
        auto n = new Cmd(text, start);
        n.kids = kids.dup;
        n.uri = uri;
        return n;
    }
}

class Chapter : Node
{
    this(bool silent, size_t start)
    {
        super("", start);
        this.silent = silent;
    }

    this(bool silent, string title, size_t start)
    {
        super(title, start);
        this.title = title;
        this.silent = silent;
        this.kids ~= new Node(title, start);
    }

    string title;
    bool silent;
    // Absolute index, corresponds to position in Book.chapters
    int index;
    // For chapter numbering
    int chapterNum;

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

    override Node dup()
    {
        auto n = new Chapter(silent, start);
        n.kids = kids.dup;
        n.uri = uri;
        n.index = index;
        n.chapterNum = chapterNum;
        n.context = context;
        return n;
    }
}

class Macro : Node
{
    this(string name, size_t start)
    {
        super(name, start);
    }

    string kind;

    this(Cmd c)
    {
        import std.string : strip;
        auto kn = kindAndName(c);
        super(kn[1].strip, c.start);

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

    override Node dup()
    {
        auto n = new Macro(text, start);
        n.kids = kids.dup;
        n.context = context;
        n.kind = kind;
        return n;
    }
}

class ArgSeparator : Node
{
    this(size_t start)
    {
        super("|", start);
    }

    override Node dup()
    {
        auto n = new ArgSeparator(start);
        n.context = context;
        return n;
    }
}

class Arg : Node
{
    this(Node[] nodes)
    {
        super("", nodes ? nodes[0].start : 0);
        this.kids = nodes;
    }
}

class Empty : Node
{
    this()
    {
        super("", 0);
    }
}

class ParagraphSeparator : Node
{
    this(size_t start)
    {
        super("\n\n", start);
    }

    this(string name, size_t start)
    {
        super(name, start);
    }

    override Node dup()
    {
        auto n = new ParagraphSeparator(text, start);
        n.context = context;
        return n;
    }
}

class Content : Node
{
    static immutable size_t all = cast(size_t)-1;

    this(size_t index, size_t start)
    {
        super("content", start);
        this.index = index;
    }

    size_t index;
}

class ParseException : Exception
{
    this(string msg)
    {
        super(msg);
    }
}

class Import : Node
{
    this(string path, size_t start)
    {
        super("import", start);
        this.path = path;
    }

    string path;
}

class Image : Node
{
    this(string path, size_t start)
    {
        super("img", start);
        this.path = path;
    }

    string path;
}
