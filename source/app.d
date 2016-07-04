module subtex.app;

import subtex.books;

import std.algorithm;
import std.file;
import std.format;
import std.path;
import std.string;
import std.stdio;
import std.zip;

import pegged.grammar;

// In this grammar, note that we *always* want to keep whitespace.
// It's moderately significant, and if you remove it some of the time,
// it's going to vanish in unexpected places.
enum st = grammar(`
SubTex:
  Book      <- Preamble? Node*
  Preamble < Info*
  Info     < :"\\info{" identifier :"," Text :"}" 
            / :Comment

  Node     <- Chapter
            / Command
            / :Comment
            / Text

# A normal chapter is just \chapter{Foo}.
# That emits <h2 class="chapter">Chapter 1: Foo</h2>
# But for a chapter that doesn't get numbered, you use \chapter*{Foo}
# So an input:
#  \chapter{Foo}\chapter*{Bar}\chapter{Baz}
# produces
#  <h2>Chapter 1: Foo</h2><h2>Bar</h2><h2>Chapter 2: Baz</h2>
  Chapter  <- "\\chapter{" Text :"}"
            / "\\chapter*{" Text :"}"
  Command  <- :"\\" (identifier !"chapter") (:"{" Node* :"}")?
  Comment  <- "%" (!Newline Char)*
  Text     <~ (!Special Char)+
  Special  <~ "\\"
            / "}"
            / "{"
            / "%"
  Newline  <~ "\n"
  Char     <~ .
`);
mixin(st);

class Parser {
  this(string data) { this.data = data; }
  string data;
  Book doc;
  Chapter chapter;
  int chapterNum;
  int quoteNest;
  ParseTree tree;
  string error;

  Book parse() {
    doc = new Book();
    chapterNum = 1;
    quoteNest = 0;
    chapter = new Chapter();
    chapter.fileid = "chapter_%s".format(doc.chapters.length);
    chapter.filename = "chapter_%s.html".format(doc.chapters.length);
    chapter.title = "Foreward";
    chapter.index = 1;
    doc.chapters ~= chapter;

    tree = SubTex(data);
    if (!tree.successful) {
      error = tree.failMsg;
      return null;
    }

    if (tree.end < data.length - 1) {
      auto line = data[0..tree.end].filter!(x => x == '\n').count + 1;
      error = `Error parsing document around line %s`.format(line);
      return null;
    }

    // We have a SubTex node containing a Book node.
    tree = tree.children[0];
    auto kids = tree.children;
    if (tree.children && tree.children[0].name == "SubTex.Preamble") {
      kids = tree.children[1..$];
      auto preamble = tree.children[0];
      // Only allowed children are 'info' nodes
      foreach (info; preamble.children) {
        auto val = info.matches[1];
        switch (info.matches[0]) {
          case "title":
            doc.title = val;
            break;
          case "author":
            doc.author = val;
            break;
          case "stylesheet":
            ExtFile f;
            f.path = val;
            doc.stylesheets ~= f;
            break;
          default:
            throw new Exception("unknown info field %s".format(info.matches[0]));
        }
      }
    }
    foreach (kid; kids) {
      visit(kid);
    }
    return doc;
  }

  private void visit(ParseTree elem) {
    switch (elem.name) {
      case "SubTex.Node":
        visitChildren(elem);
        break;
      case "SubTex.Chapter":
        bool isNumbered = !elem.matches[0].startsWith("\\chapter*");
        if (chapter.html.strip().length != 0) {
          chapter = new Chapter();
          doc.chapters ~= chapter;
          if (isNumbered) {
            chapterNum++;
          }
        }
        chapter.fileid = "chapter_%s".format(doc.chapters.length);
        chapter.filename = "chapter_%s.html".format(doc.chapters.length);
        if (isNumbered) {
          chapter.index = chapterNum;
        }
        chapter.title = elem.children[0].matches[0];
        break;
      case "SubTex.Command":
        string tag = elem.matches[0];
        switch (tag) {
          case "e":
            chapter.html ~= (getStartQuote());
            quoteNest++;
            visitChildren(elem);
            quoteNest--;
            chapter.html ~= (getEndQuote());
            break;
          case "emph":
          case "think":
          case "spell":
            chapter.html ~= (`<em class="%s">`.format(tag));
            visitChildren(elem);
            chapter.html ~= (`</em>`);
            break;
          case "scenebreak":
          case "timeskip":
            chapter.html ~= "\n<hr/>\n";
            break;
          default:
            chapter.html ~= (`<span class="%s">`.format(tag));
            visitChildren(elem);
            chapter.html ~= (`</span>`);
            break;
        }
        break;
      case "SubTex.Text":
        auto replacement = "\n\n<p>";
        for (int i = quoteNest; i > 0; i--) {
          replacement ~= getStartQuote(i);
        }
        chapter.html ~= (elem.matches[0].replace("\n\n", replacement));
        break;
      default:
        throw new Exception("unhandled element type " ~ elem.name);
    }
  }

  private void visitChildren(ParseTree tree) {
    foreach (child; tree.children) {
      visit(child);
    }
  }

  private string getStartQuote(int i = -1) {
    if (i == -1) i = quoteNest;
    if (i % 2 == 0) {
      return "&ldquo;";
    } else {
      return "&lsquo;";
    }
  }

  private string getEndQuote() {
    if (quoteNest % 2 == 0) {
      return "&rdquo;";
    } else {
      return "&rsquo;";
    }
  }
}

class Html(OutRange) {
  OutRange sink;
  this(OutRange sink) { this.sink = sink; }

  void toHtml(ParseTree tree) {
    auto doc = tree.children[0];
    string title = "unknown";
    string author = "unknown";
    string stylesheet = "";
    auto kids = doc.children;
    if (doc.children && doc.children[0].name == "SubTex.Preamble") {
      kids = doc.children[1..$];
      auto preamble = doc.children[0];
      // Only allowed children are 'info' nodes
      foreach (info; preamble.children) {
        auto val = info.matches[1];
        switch (info.matches[0]) {
          case "title":
            title = val;
            break;
          case "author":
            author = val;
            break;
          case "stylesheet":
            stylesheet = val;
            break;
          default:
            throw new Exception("unknown info field %s".format(info.matches[0]));
        }
      }
    }
    sink.put(`
<!DOCTYPE html>
<html>
  <head>
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
    <meta name="generator" content="subtex (http://ikeran.org/subtex)">
    <title>%s</title>
    <link rel="stylesheet" href="subtex.css" />`.format(title));
    if (stylesheet) {
      sink.put(`
    <link rel="stylesheet" href="%s" />`.format(stylesheet));
    }
    sink.put(`
  </head>
  <body>
    <h1 class="title">%s</h1>
    <h3 class="author">%s</h3>`.format(title, author));
    foreach (child; kids) {
      toHtmlRecurse(child);
    }
    sink.put(`
  </body>
</html>`);
  }

  int chapter = 0;
  void toHtmlRecurse(ParseTree elem) {
    switch (elem.name) {
      case "SubTex.Node":
        visitChildren(elem);
        break;
      case "SubTex.Chapter":
        sink.put(
            `<h2 class="chapter">`);
        if (!elem.matches[0].startsWith("\\chapter*")) {
          chapter++;
          sink.put(`Chapter %s: `.format(chapter));
        }
        visitChildren(elem);
        sink.put(
            `</h2>`);
        break;
      case "SubTex.Command":
        string tag = elem.matches[0];
        switch (tag) {
          case "e":
            sink.put(getStartQuote());
            quoteNest++;
            visitChildren(elem);
            quoteNest--;
            sink.put(getEndQuote());
            break;
          default:
            sink.put(`<span class="%s">`.format(tag));
            visitChildren(elem);
            sink.put(`</span>`);
            break;
        }
        break;
      case "SubTex.Text":
        sink.put(elem.matches[0].replace("\n\n", "\n\n<p>"));
        break;
      default:
        throw new Exception("unhandled element type " ~ elem.name);
    }
  }
  int quoteNest = 0;

  private void visitChildren(ParseTree elem) {
    foreach (child; elem.children) {
      toHtmlRecurse(child);
    }
  }

  private string getStartQuote() {
    if (quoteNest % 2 == 0) {
      return "&ldquo;";
    } else {
      return "&lsquo;";
    }
  }

  private string getEndQuote() {
    if (quoteNest % 2 == 0) {
      return "&rdquo;";
    } else {
      return "&rsquo;";
    }
  }
}


int main(string[] args)
{
  import std.getopt;
  bool html = false;
  bool epub = true;
  bool print = false;
  string outpath;
  auto info = getopt(
    args,
    std.getopt.config.passThrough,
    "html|h", "Whether to produce html output (default false).", &html,
    "epub|e", "Whether to produce epub output (default true).", &epub,
    "print|p", "Whether to print the parse tree.", &print,
    "out|o", "Output filename. If producing both epub and html, the appropriate extensions will be used.", &outpath
  );
  if (args.length < 2) {
    stderr.writeln("You must provide an input file");
    return 1;
  }
  auto infile = args[1];
  if (outpath == "") {
    outpath = infile;
  }

  auto parser = new Parser(infile.readText());
  auto book = parser.parse();
  if (print) {
    writeln(parser.tree);
  }
  if (book is null) {
    stderr.writefln("Failed to parse %s:\n%s", infile, parser.error);
    return 1;
  }

  if (!html && !epub) {
    stderr.writeln("No output requested.");
    return 0;
  }

  if (epub) {
    auto epubOut = outpath.stripExtension() ~ ".epub";
    auto zf = new ZipArchive();
    book.save(zf);
    auto outfile = File(epubOut, "w");
    outfile.rawWrite(zf.build());
    outfile.close();
  }
  if (html) {
    auto htmlOut = outpath.stripExtension() ~ ".html";
    auto outfile = File(htmlOut, "w");
    auto writer = outfile.lockingTextWriter();
    writer.put(book.toHtml);
    outfile.flush();
    outfile.close();
  }
  return 0;
}
