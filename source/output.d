module subtex.output;

import subtex.books;

import std.array;
import std.conv;
import std.format;
import std.math;
import std.path;
import std.stdio;
import std.string;
import std.uuid;

static import epub;

alias Attachment = epub.Attachment;

void htmlPrelude(OutRange)(Book book, ref OutRange sink, bool includeStylesheets,
        void delegate(ref OutRange) bdy)
{
    sink.put(`<?xml version='1.0' encoding='utf-8'?>
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en">
    <head>
        <meta http-equiv="Content-Type" content="text/html; charset=UTF-8"/>
        <link rel="stylesheet" href="subtex.css" type="text/css"/>
        `);
    if (includeStylesheets && "stylesheet" in book.info)
    {
        foreach (stylesheet; book.info["stylesheet"])
        {
            sink.put(`<link rel="stylesheet" href="`);
            sink.put(stylesheet);
            sink.put(`" type="text"/>
          `);
        }
    }
    sink.put(`
        <title>`);
    sink.put(book.info["title"][0]);
    sink.put(`</title>
    </head>
    <body>
    `);
    bdy(sink);
    sink.put(`
    </body>
</html>`);
}

void nodeToHtml(OutRange)(Book book, Node node, ref OutRange sink)
{
    int quoteNest = 0;

    string startQuote(int i = -1)
    {
        if (i == -1)
            i = quoteNest;
        if (i % 2 == 0)
        {
            return "&#x201C;";
        }
        else
        {
            return "&#x2018;";
        }
    }

    string endQuote()
    {
        if (quoteNest % 2 == 0)
        {
            return "&#x201D;";
        }
        else
        {
            return "&#x2019;";
        }
    }

    void asHtml(Node node)
    {
        if (auto cmd = cast(Cmd) node)
        {
            switch (cmd.text)
            {
            case "e":
                sink.put(startQuote);
                quoteNest++;
                foreach (kid; node.kids)
                    asHtml(kid);
                quoteNest--;
                sink.put(endQuote);
                break;
            case "i":
            case "emph":
            case "think":
            case "spell":
                sink.put(`<em class="`);
                sink.put(cmd.text);
                sink.put(`">`);
                foreach (kid; node.kids)
                    asHtml(kid);
                sink.put(`</em>`);
                break;
            case "b":
                sink.put(`<b class="`);
                sink.put(cmd.text);
                sink.put(`">`);
                foreach (kid; node.kids)
                    asHtml(kid);
                sink.put(`</b>`);
                break;
            case "timeskip":
            case "scenebreak":
                // This has to come between paragraphs
                sink.put(`</p><hr class="`);
                sink.put(cmd.text);
                sink.put(`" /><p>`);
                break;
            case "img":
                sink.put(`<img src="`);
                sink.put(cmd.uri);
                sink.put(`" />`);
                break;
            default:
                sink.put(`<span class="`);
                sink.put(cmd.text);
                sink.put(`">`);
                auto key = DefIdent(cmd.text, "html");
                if (auto p = key in book.defs)
                {
                    sink.put(*p);
                }
                else
                {
                    foreach (kid; node.kids)
                        asHtml(kid);
                }
                sink.put(`</span>`);
                break;
            }
        }
        else
        {
            if (node.text && !cast(Chapter) node && node.text.length)
            {
                auto parts = node.text.split("\n\n");
                // This will be empty string if the node started with '\n\n'
                sink.put(sanitize(parts[0]));
                foreach (part; parts[1 .. $])
                {
                    sink.put(`</p>

<p>`);
                    for (int i = quoteNest - 1; i >= 0; i--)
                    {
                        sink.put(startQuote(i));
                    }
                    sink.put(part.replace("&", "&amp;").replace(" -- ", "&#x2014;")
                            .replace(" --", "&#x2013;").replace("-- ",
                                "&#x2013;").replace("--", "&#x2013;"));
                }
            }
            if (node.kids)
            {
                foreach (kid; node.kids)
                    asHtml(kid);
            }
        }
    }

    asHtml(node);
}

string sanitize(string fragment)
{
    // TODO more replacements needed?
    return fragment.replace("&", "&amp;").replace(" -- ", "&#x2014;").replace("--", "&#x2013;");
}

class ToMarkdown(OutRange)
{
    // TODO quotes!
    bool simple = true;
    OutRange sink;
    Book book;
    int quoteNest = 0;
    this(Book book, OutRange sink)
    {
        this.book = book;
        this.sink = sink;
    }

    void run()
    {
        sink.put(book.title);
        for (int i = 0; i < book.title.length; i++)
        {
            sink.put("=");
        }
        sink.put("\n");
        sink.put(book.author);
        sink.put("\n");
        sink.put("\n");
        foreach (chapter; book.chapters)
        {
            size_t count = 0;
            if (!chapter.silent)
            {
                sink.put("Chapter ");
                sink.put(chapter.chapterNum.to!string);
                sink.put(": ");
                count += 10;
                count += cast(size_t) ceil(chapter.chapterNum / 10.0);
            }
            sink.put(chapter.title);
            count += chapter.title.length;
            for (int i = 0; i < count; i++)
            {
                sink.put("-");
            }
            sink.put("\n");
            writeNode(chapter);
            sink.put("\n");
            sink.put("\n");
        }
    }

    void writeNode(Node node)
    {
        if (auto cmd = cast(Cmd) node)
        {
            switch (cmd.text)
            {
            case "e":
                auto quote = quoteNest % 2 == 0 ? `"` : `'`;
                sink.put(quote);
                quoteNest++;
                foreach (kid; node.kids)
                {
                    writeNode(kid);
                }
                quoteNest--;
                sink.put(quote);
                return;
            case "spell":
            case "think":
            case "emph":
            case "i":
                sink.put(`_`);
                foreach (kid; node.kids)
                {
                    writeNode(kid);
                }
                sink.put(`_`);
                return;
            case "b":
                sink.put(`**`);
                foreach (kid; node.kids)
                {
                    writeNode(kid);
                }
                sink.put(`**`);
                return;
            default:
                foreach (kid; node.kids)
                {
                    writeNode(kid);
                }
                break;
            }
        }
        else
        {
            // If you have 40+ levels of quote nesting, you have issues.
            auto lineStartQuote = `

"'"'"'"'"'"'"'"'"'"'"'"'"'"'"'"'"'"'"'"'`[0 .. quoteNest + 2];
            if (simple)
            {
                if (quoteNest > 0)
                {
                    sink.put(node.text.replace("\n\n", lineStartQuote));
                }
                else
                {
                    sink.put(node.text);
                }
            }
            else
            {
                sink.put(node.text.replace(`\`, `\\`).replace(`_`, `\_`)
                        .replace(`*`, `\*`).replace(`+`, `\+`).replace(`-`, `\-`)
                        .replace(`.`, `\.`).replace(`[`, `\[`).replace(`]`, `\]`)
                        .replace(`#`, `\#`).replace(`!`, `\!`).replace("`",
                            "\\`").replace("\n\n", lineStartQuote));
            }
        }
        foreach (kid; node.kids)
        {
            writeNode(kid);
        }
    }
}

class ToText(OutRange)
{
    // TODO quotes!
    OutRange sink;
    Book book;
    int quoteNest = 0;
    this(Book book, OutRange sink)
    {
        this.book = book;
        this.sink = sink;
    }

    void run()
    {
        sink.put(book.title);
        sink.put("\n");
        sink.put(book.author);
        sink.put("\n");
        sink.put("\n");
        foreach (chapter; book.chapters)
        {
            if (!chapter.silent)
            {
                sink.put("Chapter ");
                sink.put(chapter.chapterNum.to!string);
                sink.put(": ");
            }
            sink.put(chapter.title);
            sink.put("\n");
            writeNode(chapter);
        }
    }

    void writeNode(Node node)
    {
        if (auto cmd = cast(Cmd) node)
        {
            if (cmd.text == "e")
            {
                auto quote = quoteNest % 2 == 0 ? `"` : `'`;
                sink.put(quote);
                quoteNest++;
                foreach (kid; node.kids)
                {
                    writeNode(kid);
                }
                quoteNest--;
                sink.put(quote);
                return;
            }
        }
        if (node.text.length && !cast(Cmd) node)
        {
            auto lineStartQuote = `

"'"'"'"'"'"'"'"'"'"'"'"'"'"'"'"'"'"'"'"'`[0 .. quoteNest + 2];
            sink.put(node.text.replace("\n\n", lineStartQuote));
        }
        foreach (kid; node.kids)
        {
            writeNode(kid);
        }
    }
}

class ToEpub
{
    import std.zip;

    string basePath;
    this(string basePath)
    {
        this.basePath = basePath;
    }

    bool run(Book book, ZipArchive zf)
    {
        bool success = true;
        auto b = new epub.Book;
        epub.Chapter titlepage = {
        title:
            "titlepage", showInTOC : true, content : titlepageXhtml(book)};
            b.chapters ~= titlepage;
            foreach (chapter; book.chapters)
            {
                // TODO find referenced images
                Appender!string sink;
                sink.reserve(cast(size_t)(chapter.length * 1.2));
                book.htmlPrelude(sink, false, delegate void(ref Appender!string s) {
                    s ~= `<h2 class="chapter">`;
                    s ~= chapter.fullTitle;
                    s ~= `</h2><p>`;
                    nodeToHtml(book, chapter, s);
                    s ~= `</p>`;
                });
                epub.Chapter ch = {
                title:
                    chapter.title, showInTOC : true, content : sink.data};
                    b.chapters ~= ch;
                }

                if ("autocover" in book.info)
                {
                    Attachment cover = {
                    filename:
                        "subtex_cover.svg", mimeType : "image/svg+xml", content
                            : cast(const(ubyte[])) cover(book)};
                        b.attachments ~= cover;
                    }

                    foreach (stylesheet; book.stylesheets)
                    {
                        import path = std.path;
                        import std.stdio : writefln;
                        import std.file : readText;

                        string data;
                        string fullPath = path.absolutePath(stylesheet, basePath);
                        try
                        {
                            data = readText(fullPath);
                        }
                        catch (Exception e)
                        {
                            writefln("Failed to read a stylesheet. "
                                    ~ "You specified its path as [%s], which I inferred to be [%s]. "
                                    ~ "Please make sure it exists, you can read it, and it's got valid UTF8 text. "
                                    ~ "I'm still making your ebook, but it might not look quite like you expect, "
                                    ~ "and some applications might not read it properly.",
                                    stylesheet, fullPath);
                            success = false;
                        }
                        Attachment css = {
                        filename:
                            path.baseName(stylesheet), mimeType : "text/css",
                        content : cast(const(ubyte[])) data};
                            b.attachments ~= css;
                        }

                        Attachment defaultCss = {
                        filename:
                            "subtex.css", mimeType : "text/css", content
                                : cast(const(ubyte[])) subtex_css};
                            b.attachments ~= defaultCss;

                            epub.toEpub(b, zf);

                            return success;
                        }

                    private:
                        enum subtex_css = import("subtex.css");

                        void save(ZipArchive zf, string name, string content)
                        {
                            auto member = new ArchiveMember();
                            member.name = name;
                            member.expandedData = cast(ubyte[]) content;
                            zf.addMember(member);
                        }

                        void writeVayne(alias method)(ZipArchive zf, string name, Book book)
                        {
                            save(zf, name, method(book));
                        }

                        static string contentOpf(Book book)
                        {
                            Appender!string s;
                            s.reserve(2000);
                            s ~= `<?xml version='1.0' encoding='utf-8'?>
<package xmlns="http://www.idpf.org/2007/opf" unique-identifier="uuid_id" version="2.0">
  <metadata xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:opf="http://www.idpf.org/2007/opf" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:language>en</dc:language>
    <dc:creator>Unknown</dc:creator>
    <dc:title>`;
                            s ~= book.title;
                            s ~= `</dc:title>
    <meta name="cover" content="cover"/>
    <dc:identifier id="uuid_id" opf:scheme="uuid">`;
                            s ~= book.id;
                            s ~= `</dc:identifier>
  </metadata>
  <manifest>`;
                            if ("stylesheet" in book.info)
                            {
                                foreach (file; book.info["stylesheet"])
                                {
                                    auto parts = file.split('/').array;
                                    auto name = parts[$ - 1];
                                    auto id = name.replace(".", "");
                                    s ~= `
    <item href="`;
                                    s ~= name;
                                    s ~= `" id="`;
                                    s ~= id;
                                    s ~= `" media-type="text/css"/>`;
                                }
                            }
                            if ("autocover" in book.info)
                            {
                                s ~= `
    <item href="subtex_cover.svg" id="cover" media-type="text/svg+xml" />`;
                            }
                            if ("cover" in book.info)
                            {
                                auto cover = book.info["cover"][0];
                                auto ext = cover.extension.toLower;
                                string mimeType;
                                switch (ext)
                                {
                                case "png":
                                    mimeType = `image/png`;
                                    break;
                                case "jpg":
                                case "jpeg":
                                    mimeType = `image/jpeg`;
                                    break;
                                case "gif":
                                    mimeType = `image/gif`;
                                    break;
                                case "svg":
                                    mimeType = `text/svg+xml`;
                                    break;
                                default:
                                    writefln(
                                            "Unrecognized image type %s; skipping. We can handle gif, jpg, png, and svg.",
                                            ext);
                                    break;
                                }
                                if (mimeType.length)
                                {
                                    s ~= `
    <item href="`;
                                    s ~= cover;
                                    s ~= `" id="cover" media-type="`;
                                    s ~= mimeType;
                                    s ~= `" />`;
                                }
                            }
                            foreach (chapter; book.chapters)
                            {
                                s ~= `
    <item href="`;
                                s ~= chapter.filename;
                                s ~= `" id="`;
                                s ~= chapter.fileid;
                                s ~= `" media-type="application/xhtml+xml"/>`;
                            }
                            s ~= `
    <item href="subtex.css" id="subtexcss" media-type="text/css"/>
    <item href="toc.ncx" id="ncx" media-type="application/x-dtbncx+xml"/>
    <item href="titlepage.xhtml" id="titlepage" media-type="application/xhtml+xml"/>
  </manifest>
  <spine toc="ncx">
    <itemref idref="titlepage"/>`;
                            foreach (chapter; book.chapters)
                            {
                                s ~= `
    <itemref idref="`;
                                s ~= chapter.fileid;
                                s ~= `"/>`;
                            }
                            s ~= `
  </spine>
  <guide>
    <reference href="titlepage.xhtml" title="Title Page" type="cover"/>
  </guide>
</package>
`;
                            return s.data;
                        }

                        static string titlepageXhtml(Book book)
                        {
                            Appender!string s;
                            s.reserve(2000);
                            book.htmlPrelude(s, false, delegate void(ref Appender!string s) {
                                s ~= `
        <div style="text-align: center">`;
                                if ("cover" in book.info)
                                {
                                    s ~= `
          <img src="`;
                                    s ~= book.info["cover"][0];
                                    s ~= `" />`;
                                }
                                else if ("autocover" in book.info)
                                {
                                    s ~= `
          <img src="subtex_cover.svg" />`;
                                }
                                s ~= `
          <h1 class="title">`;
                                s ~= book.title;
                                s ~= `</h1>
          <h3 class="author">`;
                                s ~= book.author;
                                s ~= `</h3>
        </div>`;
                            });
                            return s.data;
                        }

                        static string tocNcx(Book book)
                        {
                            Appender!string s;
                            s.reserve(1000);
                            s ~= `<?xml version='1.0' encoding='utf-8'?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1" xml:lang="en">
  <head>
    <meta content="`;
                            s ~= book.id;
                            s ~= `" name="dtb:uid"/>
    <meta content="2" name="dtb:depth"/>
    <meta content="bookmaker" name="dtb:generator"/>
    <meta content="0" name="dtb:totalPageCount"/>
    <meta content="0" name="dtb:maxPageNumber"/>
  </head>
  <docTitle>
    <text>`;
                            s ~= book.title;
                            s ~= `</text>
  </docTitle>
  <navMap>`;
                            foreach (i, chapter; book.chapters)
                            {
                                s ~= `
    <navPoint id="ch`;
                                s ~= chapter.id.replace("-", "");
                                s ~= `" playOrder="`;
                                s ~= (i + 1).to!string;
                                s ~= `">
      <navLabel>
        <text>`;
                                s ~= chapter.title;
                                s ~= `</text>
      </navLabel>
      <content src="`;
                                s ~= chapter.filename;
                                s ~= `"/>
    </navPoint>`;
                            }
                            s ~= `
  </navMap>
</ncx>`;
                            return s.data;
                        }

                        static string cover(Book book)
                        {
                            Appender!string s;
                            s.reserve(1000);
                            s ~= `<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<svg width="350" height="475">
  <rect x="10" y="10" width="330" height="455" stroke="black" stroke-width="3" fill="#cceeff" stroke-linecap="round"/>
  <text text-anchor="middle" x="175" y="75" font-size="30" font-weight="600" font-family="serif"
  stroke-width="2" stroke-opacity="0.5" stroke="#000000" fill="#000000">`;
                            s ~= book.title;
                            s ~= `</text>
  <text text-anchor="middle" x="175" y="135" font-size="15">`;
                            s ~= book.author;
                            s ~= `</text>
</svg>
`;
                            return s.data;
                        }
                    }

                    class ToChapters
                    {
                        Book book;
                        string outDirectory;

                        this(Book book, string outDirectory)
                        {
                            this.book = book;
                            this.outDirectory = outDirectory;
                        }

                        void toChapters()
                        {
                            import std.file : mkdirRecurse;
                            import std.path : chainPath;

                            mkdirRecurse(outDirectory);

                            foreach (i, chapter; book.chapters)
                            {
                                auto name = `chapter%s.html`.format(i + 1);
                                auto fullPath = chainPath(outDirectory, name);
                                auto outfile = File(fullPath, "w");
                                auto writer = outfile.lockingTextWriter();
                                book.htmlPrelude(writer, true, delegate void(ref typeof(writer) s) {
                                    nodeToHtml!(typeof(s))(book, chapter, s);
                                });
                                outfile.flush();
                                outfile.close();
                            }
                        }
                    }

                    class ToHtml(OutRange)
                    {
                        this(Book book, OutRange sink)
                        {
                            this.book = book;
                            this.sink = sink;
                        }

                        void run()
                        {
                            toHtml();
                        }

                    private:
                        Book book;
                        OutRange sink;
                        int quoteNest = 0;

                        void toHtml()
                        {
                            auto header = `<h1 class="title">%s</h1>
      <h3 class="author">%s</h3>
      `.format(book.title, book.author);

                            book.htmlPrelude(sink, true, delegate void(ref OutRange s) {
                                sink.put(header);
                                foreach (chapter; book.chapters)
                                {
                                    sink.put(`<h2 class="chapter">`);
                                    sink.put(chapter.title);
                                    sink.put(`</h2>`);
                                    nodeToHtml!OutRange(book, chapter, sink);
                                }
                            });
                        }
                    }

                    class ToBbcode(OutRange)
                    {
                        // TODO quotes!
                        bool simple = true;
                        OutRange sink;
                        Book book;
                        int quoteNest = 0;
                        this(Book book, OutRange sink)
                        {
                            this.book = book;
                            this.sink = sink;
                        }

                        void run()
                        {
                            sink.put(`[style size="200%"][b]`);
                            sink.put(book.title);
                            sink.put(`[/b][/style]`);
                            sink.put("\n");
                            sink.put(book.author);
                            sink.put("\n");
                            sink.put("\n");
                            foreach (chapter; book.chapters)
                            {
                                sink.put(`[style size="150%"][b]`);
                                if (!chapter.silent)
                                {
                                    sink.put("Chapter ");
                                    sink.put(chapter.chapterNum.to!string);
                                    sink.put(": ");
                                }
                                sink.put(chapter.title);
                                sink.put(`[/b][/style]`);
                                sink.put("\n");
                                writeNode(chapter);
                                sink.put("\n");
                                sink.put("\n");
                            }
                        }

                        void writeNode(Node node)
                        {
                            if (auto cmd = cast(Cmd) node)
                            {
                                switch (cmd.text)
                                {
                                case "e":
                                    auto quote = quoteNest % 2 == 0 ? `"` : `'`;
                                    sink.put(quote);
                                    quoteNest++;
                                    foreach (kid; node.kids)
                                    {
                                        writeNode(kid);
                                    }
                                    quoteNest--;
                                    sink.put(quote);
                                    return;
                                case "spell":
                                case "think":
                                case "emph":
                                case "i":
                                    sink.put(`[i]`);
                                    foreach (kid; node.kids)
                                    {
                                        writeNode(kid);
                                    }
                                    sink.put(`[/i]`);
                                    return;
                                case "b":
                                    sink.put(`[b]`);
                                    foreach (kid; node.kids)
                                    {
                                        writeNode(kid);
                                    }
                                    sink.put(`[/b]`);
                                    return;
                                case "code":
                                    sink.put(`[inline]`);
                                    foreach (kid; node.kids)
                                    {
                                        writeNode(kid);
                                    }
                                    sink.put(`[/inline]`);
                                    return;
                                default:
                                    foreach (kid; node.kids)
                                    {
                                        writeNode(kid);
                                    }
                                    return;
                                }
                            }
                            else
                            {
                                // If you have 40+ levels of quote nesting, you have issues.
                                auto lineStartQuote = `

"'"'"'"'"'"'"'"'"'"'"'"'"'"'"'"'"'"'"'"'`[0
                                    .. quoteNest + 2];
                                node.text = node.text.replace("\n", "☃").replace("☃☃",
                                        "\n\n").replace("☃", " ").replace("--", "—");
                                if (quoteNest > 0)
                                {
                                    sink.put(node.text.replace("\n\n", lineStartQuote));
                                }
                                else
                                {
                                    sink.put(node.text);
                                }
                                foreach (kid; node.kids)
                                {
                                    writeNode(kid);
                                }
                            }
                        }
                    }

                    unittest
                    {
                        import std.stdio;
                        import subtex.parser;

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
                        Appender!string sink;
                        sink.reserve(1000);
                        new ToHtml!(typeof(sink))(book, sink).run();
                    }
