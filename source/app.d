module subtex.app;

import subtex.books;

import std.file;
import std.format;
import std.path;
import std.string;
import std.stdio;

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

  Book parse() {
    doc = new Book();
    chapterNum = 0;
    quoteNest = 0;
    chapter = new Chapter();
    chapter.fileid = "chapter_%s".format(doc.chapters.length);
    chapter.filename = "chapter_%s.html".format(doc.chapters.length);
    chapter.title = "Foreward";
    doc.chapters ~= chapter;

    auto tree = SubTex(data);
    assert(tree.successful);
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
        chapter = new Chapter();
        chapter.fileid = "chapter_%s".format(doc.chapters.length);
        chapter.filename = "chapter_%s.html".format(doc.chapters.length);
        if (!elem.matches[0].startsWith("\\chapter*")) {
          chapterNum++;
          chapter.index = chapterNum;
        }
        chapter.title = elem.children[0].matches[0];
        doc.chapters ~= chapter;
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
          default:
            chapter.html ~= (`<span class="%s">`.format(tag));
            visitChildren(elem);
            chapter.html ~= (`</span>`);
            break;
        }
        break;
      case "SubTex.Text":
        chapter.html ~= (elem.matches[0].replace("\n\n", "\n\n<p>"));
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


void main(string[] args)
{
  //writeln(g.successful);
  auto infile = args[1];
//  auto g = SubTex(infile.readText());
  auto outfile = File(infile.stripExtension() ~ ".html", "w");
  auto outstream = outfile.lockingTextWriter();

  auto doc = new Parser(infile.readText()).parse();
  doc.save("tmp");

//  auto html = new Html!(typeof(outstream))(outstream);
//  html.toHtml(g);
  //writeln(g.matches);
	//writeln(g);
}
