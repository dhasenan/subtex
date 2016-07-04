module subtex.books;

import std.conv;
import std.encoding;
import std.file;
import std.format;
import std.path;
import std.stdio;
import std.string;
import std.zip;

import pegged.grammar;

// Fixed stuff
enum container_xml = import("container.xml");
enum subtex_css = import("subtex.css");

void save(ZipArchive zf, string name, string content) {
  writefln("saving %s", name);
  auto member = new ArchiveMember();
  member.name = name;
  member.expandedData = cast(ubyte[])content;
  zf.addMember(member);
}

void writeVayne(alias method)(ZipArchive zf, string name, Book book) {
  save(zf, name, method(book));
}

string contentOpf(Book book) {
  auto s = `
<?xml version='1.0' encoding='utf-8'?>
<package xmlns="http://www.idpf.org/2007/opf" unique-identifier="uuid_id" version="2.0">
  <metadata xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:opf="http://www.idpf.org/2007/opf" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:language>en</dc:language>
    <dc:creator>Unknown</dc:creator>
    <dc:title>` ~ book.title ~ `</dc:title>
    <meta name="cover" content="cover"/>
    <dc:identifier id="uuid_id" opf:scheme="uuid">` ~ book.id ~ `</dc:identifier>
  </metadata>
  <manifest>`;
  foreach (file; book.stylesheets) {
    s ~= `<item href="` ~ file.name ~ `" id="` ~ file.id ~ `" media-type="` ~ file.type ~ `"/>`;
  }
  foreach (chapter; book.chapters) {
    s ~= `<item href="` ~ chapter.filename ~ `" id="` ~ chapter.fileid ~ `" media-type="application/xhtml+xml"/>`;
  }
  s ~= `
    <item href="toc.ncx" id="ncx" media-type="application/x-dtbncx+xml"/>
    <item href="titlepage.xhtml" id="titlepage" media-type="application/xhtml+xml"/>
  </manifest>
  <spine toc="ncx">
    <itemref idref="titlepage"/>`;
  foreach (chapter; book.chapters) {
    s ~= `<itemref idref="` ~ chapter.fileid ~ `"/>`;
  }
  s ~= `
  </spine>
  <guide>
    <reference href="titlepage.xhtml" title="Title Page" type="cover"/>
  </guide>
</package>
`;
  return s;
}

string htmlPrelude(Book book, string bdy) {
  return `<?xml version='1.0' encoding='utf-8'?>
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en">
    <head>
        <meta http-equiv="Content-Type" content="text/html; charset=UTF-8"/>
        <link rel="stylesheet" href="subtex.css">
        <title>` ~ book.title ~ `</title>
    </head>
    <body>
    ` ~ bdy ~ `
    </body>
</html>`;
}

string titlepageXhtml(Book book) {
  return book.htmlPrelude(`
        <div style="text-align: center">
          <!-- TODO cover image -->
          <h1 class="title">%1$s</h1>
          <h3 class="author">%2$s</h3>
        </div>`.format(book.title, book.author));
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

void save(Book book, ZipArchive zf) {
  // We need to write several files:
  // * mimetype (hardcoded)
  // * META-INF/container.xml (hardcoded)
  // * content.opf
  // * toc.ncx (templated)
  // * titlepage.xhtml
  //mkdirRecurse(zf ~ "/META-INF");
  .save(zf, "META-INF/container.xml", container_xml);
  .save(zf, "mimetype", "application/epub+zip");
  .save(zf, "subtex.css", subtex_css);
  writeVayne!contentOpf(zf, "content.opf", book);
  writeVayne!titlepageXhtml(zf, "titlepage.xhtml", book);
  writeVayne!tocNcx(zf, "toc.ncx", book);
  foreach (chapter; book.chapters) {
    auto h2 = `<h2 class="chapter">%s</h2>`.format(chapter.header);
    save(zf, chapter.filename, book.htmlPrelude(h2 ~ chapter.html));
  }
  /*
  foreach (file; book.files) {
    file.save(path);
  }
  */
}

struct ExtFile {
  string name;
  string path;
  string id;
  string type;
}

class Chapter {
  string title;
  string html;
  int index = -1;
  string filename;
  string fileid;

  string header() {
    if (index > 0) {
      return `Chapter %s: %s`.format(index, title);
    }
    return title;
  }
}

class Book {
  string id;
  string title, author;
  ExtFile[] stylesheets;
  Chapter[] chapters;
  // TODO images?
}
