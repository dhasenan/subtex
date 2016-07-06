module subtex.output;

import subtex.books;

import std.array;
import std.conv;
import std.format;

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

void nodeToHtml(OutRange)(Node node, ref OutRange sink) {
  int quoteNest = 0;

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

  void asHtml(Node node) {
    if (auto cmd = cast(Cmd) node) {
      switch (cmd.text) {
        case "e":
          sink.put(startQuote);
          quoteNest++;
          foreach (kid; node.kids) asHtml(kid);
          quoteNest--;
          sink.put(endQuote);
          break;
        case "emph":
        case "think":
        case "spell":
          sink.put(`<em class="`);
          sink.put(cmd.text);
          sink.put(`">`);
          foreach (kid; node.kids) asHtml(kid);
          sink.put(`</em>`);
          break;
        case "timeskip":
        case "scenebreak":
          sink.put(`<hr class="`);
          sink.put(cmd.text);
          sink.put(`" />`);
        default:
          sink.put(`<span class="`);
          sink.put(cmd.text);
          sink.put(`">`);
          foreach (kid; node.kids) asHtml(kid);
          sink.put(`</em>`);
          break;
      }
    } else {
      if (node.text && !cast(Chapter) node) {
        auto parts = node.text.split("\n\n");
        sink.put(parts[0]);
        foreach (part; parts[1..$]) {
          for (int i = quoteNest; i > 0; i--) {
            sink.put(startQuote(i));
          }
          sink.put(`

<p>`);
          sink.put(part);
        }
      }
      if (node.kids) {
        foreach (kid; node.kids) asHtml(kid);
      }
    }
  }

  asHtml(node);
}

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
      book.htmlPrelude(sink,
           delegate void (ref Appender!string s) { nodeToHtml(chapter, s); });
      save(zf, chapter.filename, sink.data);
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
    foreach (file; book.info["stylesheet"]) {
      auto parts = file.split('/').array;
      auto name = parts[$-1];
      auto id = name.replace('.', '_');
      s ~= `<item href="`;
      s ~= name;
      s ~= `" id="`;
      s ~= id;
      s ~= `" media-type="text/css"/>`;
    }
    foreach (chapter; book.chapters) {
      s ~= `<item href="`;
      s ~= chapter.filename;
      s ~= `" id="`;
      s ~= chapter.fileid;
      s ~= `" media-type="application/xhtml+xml"/>`;
    }
    s ~= `
      <item href="subtex.css" id="subtex_css" media-type="text/css"/>
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
    book.htmlPrelude(s, delegate void (ref Appender!string s) {
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
    return s.data;
  }

  string tocNcx(Book book) {
    Appender!string s;
    s.reserve(1000);
    s ~= `
  <?xml version='1.0' encoding='utf-8'?>
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
    <navMap><navPoint id="titlepage.xhtml" playOrder="1">
        <navLabel>
          <text>Title</text>
        </navLabel>
        <content src="titlepage.xhtml"/>
      </navPoint>`;
    foreach (i, chapter; book.chapters) {
      s ~= `<navPoint id="`;
      s ~= chapter.fileid;
      s ~= `" playOrder="`;
      s ~= (i + 2).to!string;
      s ~= `">
        <navLabel>
          <text> `;
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
}

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
        sink.put(chapter.title);
        sink.put(`</h2>`);
        nodeToHtml!OutRange(chapter, sink);
      }
    });
  }
}

unittest {
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
