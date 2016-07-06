module subtex.parser;

import subtex.books;

import std.algorithm;
import std.array;
import std.string;

class Parser {
  string data, originalData;
  this(string data) {
    this.originalData = this.data = data;
  }

  void skipWhitespace() {
    data = data.stripLeft;
  }

  Book parse() {
    import core.memory;
    // We're going to allocate a decent chunk and we're not going to release
    // anything we allocate. Specifically, we allocate our AST nodes, and we're
    // not allocating anything else, so it does us no good to enable the GC.
    //GC.disable();
    //scope(exit) GC.enable();

    this.data = this.originalData;
    auto book = new Book();
    auto oldLength = data.length + 1;
    while (data.length && data.length < oldLength) {
      oldLength = data.length;
      // We are guaranteed to get some set of \info bits, possibly empty, followed by \chapter.
      skipWhitespace;
      if (data.startsWith("%")) {
        auto end = data.indexOf("\n");
        if (end == -1) {
          return book;
        }
        data = data[end..$];
      }
      if (data.startsWith(infoStart)) {
        data = data[infoStart.length .. $];
        auto next = data.indexOfAny("\n,");
        if (next == -1 || data[next] == '\n') {
          error("expected: `\\info{id, value}' -- you need a comma after the id");
        }
        auto s = data[0..next].strip();
        data = data[next + 1 .. $];
        next = data.indexOf("}");
        if (next < 0) {
          error("expected: `\\info{id, value}' -- you need a `}' after the value");
        }
        auto val = data[0..next].strip();
        data = data[next + 1 .. $];
        if (s in book.info) {
          auto v = book.info[s];
          v ~= val;
          book.info[s] = v;
        } else {
          book.info[s] = [val];
        }
      }
      skipWhitespace();
      if (data.startsWith(chapterStart) || data.startsWith(silentChapterStart)) {
        break;
      }
    }
    parseChapters(book);
    return book;
  }

  enum infoStart = "\\info{";
  enum chapterStart = "\\chapter{";
  enum silentChapterStart = "\\chapter*{";

  void parseChapters(Book book) {
    while (data.length > 0) {
      bool silent = false;
      if (data.startsWith(chapterStart)) {
        data = data[chapterStart.length..$];
      } else if (data.startsWith(silentChapterStart)) {
        silent = true;
        data = data[silentChapterStart.length..$];
      } else {
        error("failed to parse");
      }
      auto chapter = new Chapter(silent, getPosition);
      book.chapters ~= chapter;
      auto end = data.indexOf("}");
      if (end == -1) {
        error("expected `}' after chapter title", chapter.start);
      }
      chapter.title = data[0..end];
      data = data[end + 1 .. $];
      parseNodeContents(chapter);
    }
  }

  void parseNodeContents(Node parent) {
    while (data.length > 0) {
      if (data.startsWith(chapterStart)) {
        return;
      }
      if (data[0] == '}') {
        return;
      }
      auto i = data.indexOfAny("%\\}");
      if (i == -1) {
        // We don't have any more special characters for the rest of time.
        // Done!
        parent.kids ~= new Node(data, getPosition());
        data = "";
        break;
      }
      if (i > 0) {
        // We have some text before the next thing. Cool!
        parent.kids ~= new Node(data[0..i], getPosition());
        data = data[i..$];
        continue;
      }
      if (data.startsWith("\\%")) {
        // You have \% -- escaped percent sign.
        // Take it for real text.
        parent.kids ~= new Node("%", getPosition());
        data = data[2..$];
        continue;
      }
      if (data.startsWith("\\\\")) {
        // You have \% -- escaped backslash.
        // Take it for real text.
        parent.kids ~= new Node("\\", getPosition());
        data = data[2..$];
        continue;
      }
      if (data.startsWith("%")) {
        auto j = data.indexOf("\n");
        if (j < 0) {
          break;
        }
        data = data[j+1..$];
        continue;
      }
      if (data.startsWith("\\")) {
        data = data[1..$];
        size_t k = 0;
        while (k < data.length && isIdentChar(data[k])) k++;
        if (k == 0) {
          error("Found single backslash '\\'. " ~
              "If you meant to include a literal backslash, type it twice.");
          continue;
        }
        auto cmd = new Cmd(data[0..k], getPosition());
        data = data[k..$];
        if (data.length && data[0] == '{') {
          data = data[1..$];
          parseNodeContents(cmd);
          if (data.length && data[0] == '}') {
            data = data[1..$];
          } else {
            error("unterminated command", cmd.start);
          }
        }
        parent.kids ~= cmd;
      }
    }
  }

  private void error(string message) {
    error(message, getPosition());
  }

  private void error(string message, size_t position) {
    auto prefix = originalData[0..position];
    auto line = prefix.count!(x => x == '\n') + 1;
    auto col = prefix.length - prefix.lastIndexOf('\n');
    throw new ParseException("line %s col %s: %s".format(line, col, message));
  }

  size_t getPosition() {
    return originalData.length - data.length;
  }

  bool isIdentChar(char c) {
    import std.uni;
    return c == '_' || isAlpha(c) || isNumber(c);
  }
}

class ParseException : Exception {
  this(string msg) { super(msg); }
}

class Book {
  string[][string] info;
  Chapter[] chapters;

  string author() {
    if (auto p = "author" in info) {
      return (*p)[0];
    }
    return "Writer";
  }

  string title() {
    if (auto p = "title" in info) {
      return (*p)[0];
    }
    return "Book";
  }
}

class Cmd : Node {
  this(string text, size_t start) {
    super(text, start);
  }
}

// A standard node is either a plain string, or a command, or a series of nodes.
// Only one at a time.
class Node {
  this(string text, size_t start) {
    this.text = text;
    this.start = start;
  }

  string text;
  Node[] kids;
  size_t start;

  // Approximate end of this node.
  size_t end() {
    if (kids) {
      return kids[$-1].end;
    }
    return start + text.length;
  }

  size_t length() {
    return end() - start;
  }
}

class Chapter : Node {
  this(bool silent, size_t start) {
    super("chapter", start);
    this.silent = silent;
  }
  string title;
  bool silent;
}

void htmlPrelude(OutRange)(Book book, ref OutRange sink, void delegate(ref OutRange) bdy) {
  sink.put(`<?xml version='1.0' encoding='utf-8'?>
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en">
    <head>
        <meta http-equiv="Content-Type" content="text/html; charset=UTF-8"/>
        <link rel="stylesheet" href="subtex.css">
        `);
  if ("stylesheet" in book.info) {
    foreach (stylesheet; book.info["stylesheet"]) {
      sink.put(`<link rel="stylesheet" href="`);
      sink.put(stylesheet);
      sink.put(`">
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

/+
class ToEpub {
  import std.zip;
  void run(Book book, ZipArchive zf) {
    save(zf, "META-INF/container.xml", container_xml);
    save(zf, "mimetype", "application/epub+zip");
    save(zf, "subtex.css", subtex_css);
    writeVayne!contentOpf(zf, "content.opf", book);
    writeVayne!titlepageXhtml(zf, "titlepage.xhtml", book);
    writeVayne!tocNcx(zf, "toc.ncx", book);
    foreach (chapter; book.chapters) {
      Appender!string sink;
      sink.reserve(cast(size_t)(chapter.length * 1.2));
      save(zf, chapter.filename, book.htmlPrelude(sink,
           delegate void (ref Appender!string s) { chapterHtml(chapter, s); }));
    }
  }
private:
  enum container_xml = import("container.xml");
  enum subtex_css = import("subtex.css");

  void save(ZipArchive zf, string name, string content) {
    auto member = new ArchiveMember();
    member.name = name;
    member.expandedData = cast(ubyte[])content;
    zf.addMember(member);
  }

  void writeVayne(alias method)(ZipArchive zf, string name, Book book) {
    save(zf, name, method(book));
  }

  string contentOpf(Book book) {
    Appender!string s;
    s.reserve(2000);
    s ~= `
  <?xml version='1.0' encoding='utf-8'?>
  <package xmlns="http://www.idpf.org/2007/opf" unique-identifier="uuid_id" version="2.0">
    <metadata xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:opf="http://www.idpf.org/2007/opf" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:dc="http://purl.org/dc/elements/1.1/">
      <dc:language>en</dc:language>
      <dc:creator>Unknown</dc:creator>
      <dc:title>`;
    s ~= book.title;
    s ~= `</dc:title>
      <meta name="cover" content="cover"/>
      <dc:identifier id="uuid_id" opf:scheme="uuid">` ~ book.id ~ `</dc:identifier>
    </metadata>
    <manifest>`;
    foreach (file; book.stylesheets) {
      s ~= `<item href="`;
      s ~= file.name;
      s ~= `" id="`;
      s ~= file.id;
      s ~= `" media-type="`;
      s ~= file.type;
      s ~= `"/>`;
    }
    foreach (chapter; book.chapters) {
      s ~= `<item href="`;
      s ~= chapter.filename;
      s ~= `" id="`;
      s ~= chapter.fileid;
      s ~= `" media-type="application/xhtml+xml"/>`;
    }
    s ~= `
      <item href="toc.ncx" id="ncx" media-type="application/x-dtbncx+xml"/>
      <item href="titlepage.xhtml" id="titlepage" media-type="application/xhtml+xml"/>
    </manifest>
    <spine toc="ncx">
      <itemref idref="titlepage"/>`;
    foreach (chapter; book.chapters) {
      s ~= `<itemref idref="`;
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

  string titlepageXhtml(Book book) {
    Appender!string s;
    s.reserve(2000);
    return book.htmlPrelude(s, delegate void (ref Appender!string s) {
      s ~= `
        <div style="text-align: center">
          <!-- TODO cover image -->
          <h1 class="title">`;
      s ~= book.title;
      s ~= `</h1>
          <h3 class="author">`;
      s ~= book.author;
      s ~= `</h3>
        </div>`;
    });
  }

  string tocNcx(Book book) {
    auto s = `
  <?xml version='1.0' encoding='utf-8'?>
  <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1" xml:lang="en">
    <head>
      <meta content="` ~ book.id ~ `" name="dtb:uid"/>
      <meta content="2" name="dtb:depth"/>
      <meta content="bookmaker" name="dtb:generator"/>
      <meta content="0" name="dtb:totalPageCount"/>
      <meta content="0" name="dtb:maxPageNumber"/>
    </head>
    <docTitle>
      <text>` ~ book.title ~ `</text>
    </docTitle>
    <navMap><navPoint id="titlepage.xhtml" playOrder="1">
        <navLabel>
          <text>Title</text>
        </navLabel>
        <content src="titlepage.xhtml"/>
      </navPoint>`;
    foreach (i, chapter; book.chapters) {
      s ~= `<navPoint id="` ~ chapter.fileid ~ `" playOrder="` ~ (i + 2).to!string ~ `">
        <navLabel>
          <text> ` ~ chapter.title ~ `</text>
        </navLabel>
        <content src="` ~ chapter.filename ~ `"/>
      </navPoint>`;
    }
    s ~= `
    </navMap>
  </ncx>`;
    return s;
  }
}
+/

class ToHtml(OutRange) {
  this(Book book, OutRange sink) {
    this.book = book;
    this.sink = sink;
  }

  void run() {
    toHtml();
  }

private:
  Book book;
  OutRange sink;
  int quoteNest = 0;

  void toHtml() {
    auto header = `<h1 class="title">%s</h1>
      <h3 class="author">%s</h3>
      `.format(book.title, book.author);

    book.htmlPrelude(sink, delegate void (ref OutRange s) {
      sink.put(header);
      foreach (chapter; book.chapters) {
        sink.put(`<h2 class="chapter">`);
        sink.put(`TODO!!!`);
        //sink.put(chapter.header);
        sink.put(`</h2>`);
        chapterHtml(chapter);
      }
    });
  }

  void chapterHtml(Node node) {
    if (auto cmd = cast(Cmd) node) {
      switch (cmd.text) {
        case "e":
          sink.put(startQuote);
          quoteNest++;
          foreach (kid; node.kids) chapterHtml(kid);
          quoteNest--;
          sink.put(endQuote);
          break;
        case "emph":
        case "think":
        case "spell":
          sink.put(`<em class="`);
          sink.put(cmd.text);
          sink.put(`">`);
          foreach (kid; node.kids) chapterHtml(kid);
          sink.put(`</em>`);
          break;
        default:
          sink.put(`<span class="`);
          sink.put(cmd.text);
          sink.put(`">`);
          foreach (kid; node.kids) chapterHtml(kid);
          sink.put(`</em>`);
          break;
      }
    } else {
      if (node.text) {
        auto parts = node.text.split("\n\n");
        sink.put(parts[0]);
        foreach (part; parts[1..$]) {
          for (int i = quoteNest; i > 0; i--) {
            sink.put(startQuote(i));
          }
          sink.put(`<p>`);
          sink.put(part);
        }
      }
      if (node.kids) {
        foreach (kid; node.kids) chapterHtml(kid);
      }
    }
  }

  string startQuote(int i = -1) {
    if (i == -1) i = quoteNest;
    if (i % 2 == 0) {
      return "&ldquo;";
    } else {
      return "&lsquo;";
    }
  }

  string endQuote() {
    if (quoteNest % 2 == 0) {
      return "&rdquo;";
    } else {
      return "&rsquo;";
    }
  }
}

unittest {
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
  assert((cast(Cmd)e.kids[1]).kids[0].text == "it");
  assert(kids[2].text == "\n\nCan we stop him?\n");
  assert(kids.length == 3);

  assert(book.chapters[1].title == "Ending");
}

unittest {
  import std.stdio;
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
  assert(false, sink.data);
}
