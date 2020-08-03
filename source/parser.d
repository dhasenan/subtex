module subtex.parser;

import subtex.books;
import subtex.util;

import std.algorithm;
import std.array;
import std.string;
import std.stdio;
import std.path : absolutePath, dirName;

enum Kind
{
    text,
    command,
    start,
    end,
    arg,
    paragraph,
}

struct Token
{
    Kind kind;
    string content;
    Position position;
}

struct Lexer
{
    import std.typecons : Tuple, tuple;
    private string data, originalData, filename;
    private ushort fileId;

    this(string filename)
    {
        this.filename = filename.absolutePath;
        data = Files.read(filename);
        fileId = Files.id(filename);
        originalData = data;
        popFront;
    }

    private Position position()
    {
        return Position(fileId, cast(uint)(originalData.length - data.length));
    }

    Token front;
    Position previousPosition;

    Tuple!(size_t, size_t) toLineCol(size_t position)
    {
        auto prefix = originalData[0 .. position];
        size_t line = prefix.count!(x => x == '\n') + 1;
        size_t col = prefix.length - prefix.lastIndexOf('\n');
        return tuple(line, col);
    }

    bool empty()
    {
        return data.length == 0;
    }

    void popFront()
    {
        do
        {
            _popFront;
        } while (!empty && front.kind == Kind.text && front.content.strip == "");
    }

    void _popFront()
    {
front:
        if (data.length == 0)
        {
            return;
        }
        previousPosition = front.position;

        if (data[0] == '\\')
        {
            if (data.length == 1)
            {
                throw new ParseException(position, "unexpected '\\' at end of file");
            }

            data = data[1..$];
            if (isIdentChar(data[0]))
            {
                // command
                string ident = data;
                foreach (i, char c; data)
                {
                    if (!isIdentChar(c))
                    {
                        ident = data[0..i];
                        break;
                    }
                }
                front = Token(Kind.command, ident, position);
                data = data[ident.length..$];
                return;
            }

            // escape; treat it as the start of text
            // first, can't escape newline
            if (data[0] == '\n')
            {
                throw new ParseException(position, ": '\\' encountered at end of line");
            }
            goto readTextToken;
        }

        if (data.length > 1 && data.startsWith("<%"))
        {
            data = data[2..$];
            auto end = data.indexOf("%>");
            if (end < 0)
            {
                throw new ParseException(position, "unterminated comment");
            }
            data = data[data.indexOf("%>") + 2 .. $];
            goto front;
        }

        if (data[0] == '%')
        {
            auto end = data.indexOf('\n');
            if (end < 0) end = data.length;
            data = data[end..$];
            goto front;
        }

        if (data[0] == '{')
        {
            front = Token(Kind.start, "{", position);
            data = data[1..$];
            return;
        }

        if (data[0] == '}')
        {
            front = Token(Kind.end, "}", position);
            data = data[1..$];
            return;
        }

        if (data[0] == '|')
        {
            front = Token(Kind.arg, "|", position);
            data = data[1..$];
            return;
        }

        if (data.startsWith("\n\n"))
        {
            front = Token(Kind.paragraph, "\n\n", position);
            data = data[2..$];
            return;
        }

readTextToken:
        auto start = position;
        data = data[1..$]; // we know we're taking at least one character
        size_t end = 0;
        foreach (i, c; data)
        {
            end = i;
            switch (c)
            {
                case '\n':
                    if (data[i..$].startsWith("\n\n")) goto foundEnd;
                    break;
                case '<':
                    if (data[i..$].startsWith("<%")) goto foundEnd;
                    break;
                case '%':
                case '\\':
                case '{':
                case '}':
                case '|':
                    goto foundEnd;
                default:
                    break;
            }
        }

foundEnd:
        data = data[end..$];
        front = Token(Kind.text, originalData[start.offset..position.offset], position);
    }
}

class Parser
{
    private:
    Lexer lexer;
    string baseDir;
    Book book;

    public this(Lexer lexer)
    {
        this.lexer = lexer;
        this.baseDir = dirName(absolutePath(lexer.filename));
    }

    public Chapter[] parseChapters()
    {
        Chapter[] chapters;
        Chapter current;
        while (!lexer.empty)
        {
            auto n = parseOne;
            if (auto imp = cast(Import)n)
            {
                static import std.file;
                auto subparser = new Parser(Lexer(imp.path));
                subparser.book = book;
                book.files ~= imp.path;
                chapters ~= subparser.parseChapters;
                continue;
            }
            if (auto chap = cast(Chapter)n)
            {
                current = chap;
                chapters ~= chap;
                continue;
            }
            if (auto m = cast(Macro)n)
            {
                m.error("macros and definitions must appear in the preamble of the main file");
                continue;
            }
            if (!current)
            {
                if (cast(ParagraphSeparator)n)
                {
                    // You might have several blank lines before the first chapter.
                    continue;
                }
                n.error("expected chapter");
                continue;
            }

            // If it's not any of those special cases, and it's not a chapter, it's got to be part
            // of the current chapter.
            current.kids ~= n;
        }
        return chapters;
    }

    public Book parseBook()
    {
        book = new Book;
        book.mainFile = lexer.filename.absolutePath;
        while (!lexer.empty)
        {
            if (!tryParseHeaderBit)
            {
                break;
            }
        }
        book.chapters = parseChapters;
        int chapterNum = 1;
        foreach (c; book.chapters)
        {
            if (!c.silent)
            {
                c.chapterNum = chapterNum;
                chapterNum++;
            }
        }
        // expand only the output-agnostic macros
        expandMacros(book, null);
        return book;
    }

    private:

    bool tryParseHeaderBit()
    {
        while (!lexer.empty && lexer.front.kind == Kind.paragraph) lexer.popFront;
        if (lexer.empty) return false;

        auto tok = lexer.front;
        if (tok.kind != Kind.command) return false;
        switch (tok.content)
        {
            case "import":
            case "chapter":
            case "chapter*":
                return false;
            case "info":
            case "def":
            case "defhtml":
            case "defbb":
            case "macro":
            case "macrohtml":
            case "macrobb":
                lexer.popFront;
                parseCommand(tok);
                return true;
            default:
                error("expected preamble element or chapter");
                return false;
        }
    }

    private void parseBody(Node parent)
    {
        while (!lexer.empty && lexer.front.kind != Kind.end)
        {
            auto kid = parseOne;
            kid.parent = parent;
            parent.kids ~= kid;
        }
    }

    Node parseOne()
    {
        if (lexer.empty)
            return new Node("", Position(lexer.fileId, cast(uint)lexer.originalData.length));
        auto tok = lexer.front;
        lexer.popFront;
        final switch (tok.kind) with (Kind)
        {
            case Kind.command:
                return parseCommand(tok);
            case Kind.arg:
                return new ArgSeparator(tok.position);
            case Kind.end:
                return error("unexpected '}'");
            case Kind.start:
                return error("unexpected '}'");
            case Kind.text:
                return new Node(tok.content, tok.position);
            case Kind.paragraph:
                return new ParagraphSeparator(tok.position);
        }
    }

    Node parseBuiltin(string name, string content, Position start)
    {
        import std.conv : to;
        import std.path : absolutePath;
        switch (name)
        {
            case "content":
                auto index = content ? content.to!size_t : Content.all;
                return new Content(index, start);
            case "import":
                return new Import(absolutePath(content, baseDir), start);
            case "chapter":
                return new Chapter(false, content, start);
            case "chapter*":
                return new Chapter(true, content, start);
            case "img":
                return new Image(absolutePath(content, baseDir), start);
            case "info":
                auto c = content.indexOf(',');
                book.info[content[0..c].strip] ~= content[c+1 .. $].strip;
                break;
            default:
                break;
        }
        return new Node("", start);
    }

    Node parseCommand(Token tok)
    {
        switch (tok.content)
        {
            case "content":
            case "import":
            case "info":
            case "chapter":
            case "chapter*":
            case "img":
            case "author":
            case "title":
            case "stylesheet":
                // These are all things that expect a text block instead of a node tree.
                string data;
                if (!lexer.empty && lexer.front.kind == Kind.start)
                {
                    // Performance: if there's only one token and it's a text token, just use that.
                    lexer.popFront;
                    Appender!string allContent;
                    if (lexer.empty)
                    {
                        error("expected argument or '}'");
                    }
                    while (lexer.front.kind == Kind.text)
                    {
                        allContent ~= lexer.front.content;
                        lexer.popFront;
                    }
                    if (lexer.empty || lexer.front.kind != Kind.end)
                    {
                        error("expected '}'");
                    }
                    lexer.popFront;
                    data = allContent.data.strip;
                }
                return parseBuiltin(tok.content, data, tok.position);
            case "def":
            case "defhtml":
            case "defbb":
            case "macro":
            case "macrohtml":
            case "macrobb":
                // parsed *almost* as a normal node
                if (lexer.empty || lexer.front.kind != Kind.start)
                {
                    error("expected definition");
                }
                lexer.popFront;
                auto start = lexer.front.position;
                auto t = lexer.front.content;
                auto comma = t.indexOf(',');
                string name;
                Node rest;
                if (comma >= 0)
                {
                    name = t[0..comma].strip;
                }
                else
                {
                    name = t.strip;
                    lexer.popFront;
                    t = lexer.front.content;
                    comma = t.indexOf(',');
                    if (comma < 0)
                    {
                        error("expected ','");
                    }
                }
                // In the rare case that you have a definition like:
                // \macro{a<%stuff%>,<%comment%>\content}
                // this will do an extra allocation. I can live with it.
                t = t[comma+1 .. $].stripLeft;
                rest = new Node(t, Position(start.fileId, cast(uint)(start.offset + comma + 1)));
                lexer.popFront;
                auto m = new Macro(name, tok.position);
                parseBody(m);
                if (lexer.empty || lexer.front.kind != Kind.end)
                {
                    error("expected '}'");
                }
                lexer.popFront;
                m.kids = rest ~ m.kids;
                auto ident = DefIdent(m.text, m.kind);
                book.defs[ident] = m;
                break;
            default:

        }
        auto curr = new Cmd(tok.content, tok.position);
        if (!lexer.empty && lexer.front.kind == Kind.start)
        {
            lexer.popFront;
            parseBody(curr);
            if (lexer.empty)
            {
                error("expected '}', got end of file");
            }
            if (lexer.front.kind != Kind.end)
            {
                error("missing '}'");
            }
            lexer.popFront;
        }
        return curr;
    }

    Node error(string message)
    {
        // TODO Rationalize usage for prev vs current
        throw new ParseException(lexer.front.position, message);
    }
}

void expandMacros(Book book, string kind)
{
    foreach (chapter; book.chapters)
    {
        Node n = chapter;
        expandMacros(n, book, kind);
    }
}
void expandMacros(ref Node node, Book book, string kind)
{
    if (auto c = cast(Cmd)node)
    {
        if (auto p = DefIdent(c.text, kind) in book.defs)
        {
            node = Expander(c, *p).expand;
        }
    }
    foreach (ref kid; node.kids) expandMacros(kid, book, kind);
}

struct Expander
{
    Cmd c;
    Macro m;
    Arg kids;
    Arg[] args;

    this(Cmd c, Macro m)
    {
        this.c = c;
        this.m = cast(Macro)m.dup;
        this.kids = new Arg(c.kids);
        this.args = c.kids
            .splitter!(x => cast(ArgSeparator)x)
            .map!(x => new Arg(x))
            .array;
    }

    Node expand()
    {
        Node root = new Cmd(c.text, c.position);
        root.parent = c.parent;
        root.kids = m.kids;
        foreach (kid; root.kids) kid.parent = root;
        _expand(root);
        return root;
    }

    void _expand(ref Node node)
    {
        if (auto kc = cast(Content)node)
        {
            if (kc.index == Content.all)
            {
                node = kids;
            }
            else if (kc.index > args.length)
            {
                node.error("expected at least %s arguments, got %s", kc.index, args.length);
            }
            else
            {
                node = args[kc.index - 1];
            }
        }
        foreach (ref k; node.kids) _expand(k);
    }
}


void setParents(Node node)
{
    foreach (kid; node.kids) kid.parent = node;
    foreach (kid; node.kids) setParents(kid);
}

Book parseFile(string filename)
{
    import std.path : absolutePath;
    filename = absolutePath(filename);
    auto lexer = Lexer(filename);
    auto parser = new Parser(lexer);
    return parser.parseBook;
}

enum infoStart = "\\info{";
enum chapterStart = "\\chapter{";
enum silentChapterStart = "\\chapter*{";
enum importStatement = "\\import{";
enum macroStart = "\\macro{";
enum defbb = "\\defbb{";
enum defhtml = "\\defhtml{";

alias FileReader = string delegate(string);

unittest
{
    auto data = `
\info{author, Bob Dobbs}
\info{title, Subgenius Meeting Notes}
\chapter{The Best Chapter}
Something happens in this chapter. \e{He's at \emph{it} again}

Can we stop him?
% But that's all I can write today.
\chapter{Ending}
It was raining in the city.
    `;
    auto book = new Parser(data).parse();
    assert(book.info["title"][0] == "Subgenius Meeting Notes");
    assert(book.info["author"][0] == "Bob Dobbs");
    assert(book.chapters.length == 2);
    assert(book.chapters[0].title == "The Best Chapter");
    auto kids = book.chapters[0].kids;
    assert(kids[0].text.strip == "Something happens in this chapter.", kids[0].text.strip);
    auto e = cast(Cmd) kids[1];
    assert(e.text == "e");
    assert(e.kids[0].text == "He's at ");
    assert(e.kids[1].text == "emph");
    assert((cast(Cmd) e.kids[1]).kids[0].text == "it");
    assert(kids[2].text == "\n\nCan we stop him?\n");
    assert(kids.length == 3);

    assert(book.chapters[1].title == "Ending");
}

unittest
{
    auto text = `\chapter*{Prelude}
It was raining in the city.
    `;
    assert(text.startsWith(silentChapterStart));
    Book book = new Parser(text).parse();
}
