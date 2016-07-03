module subtex;

import std.format;
import std.stdio;
import pegged.grammar;

enum st = grammar(`
SubTex:
  Doc      < Preamble? Node*
  Preamble < Info*
  Info     < :"\\info{" identifier :"," Text :"}" 

  Node     < Chapter
           / Command
           / :Comment
           / Text

  Chapter  < :"\\chapter{" Text :"}"
  Command  < :"\\" (identifier !"chapter") (:"{" Node* :"}")?
  Comment  <- "%" (!Newline Char)*
  Text     <~ (!Special Char)+
  Special  <~ "\\"
            / "}"
            / "%"
  Newline  <~ "\n"
  Char     <~ .
`);
mixin(st);

class Html(OutRange) {
  OutRange sink;
  this(OutRange sink) { this.sink = sink; }

  void toHtml(ParseTree doc) {
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
      <title>%s</title>`.format(title));
    if (stylesheet) {
      sink.put(`
      <link rel="stylesheet" href="%s" />`.format(stylesheet));
    }
    sink.put(`
    </head>
    <body>
      <h1 class="title">%s</h1>
      <h2 class="author">%s</h2>`.format(title, author));
    foreach (child; kids) {
      toHtmlRecurse(child, sink);
    }
    sink.put(`
    </body>
  </html>`);
  }

  void toHtmlRecurse(ParseTree elem) {
    switch (elem.name) {
      case "SubTex.Node":
        visitChildren(elem, sink);
        break;
      case "SubTex.Chapter":
        sink.put(`


      <h2 class="chapter">
      `);
        visitChildren(elem, sink);
        break;
      case "SubTex.Command":
        string start, close;
        switch (elem.matches[0]) {
          case "e":
            sink.put(getStartQuote());
            quoteNest++;
            visitChildren(elem, sink);
            quoteNest--;
            sink.put(getEndQuote());
            break;
          case "todo":
            sink.put(`<span class="todo">`);
            visitChildren(elem, sink);
            sink.put(`</span>`);
            break;
        }
        break;
    }
  }

  private string getStartQuote() {
    if (quoteNest % 2 == 0) {
      return "&ldquot;";
    } else {
      return "&lquot;";
    }
  }

  private string getEndQuote() {
    if (quoteNest % 2 == 0) {
      return "&rdquot;";
    } else {
      return "&rquot;";
    }
  }
}


void main(string[] args)
{
  auto g = SubTex(`
    \info{author, Chris Wright}
    \info{title, Test Article}
    \chapter{First chapter}

    % This is a comment
    Here is real text.
    \e{Quote!}

    This is another paragraph
  `);
  writeln(g.successful);
  //toHtml(g, stdout.lockingTextWriter);
  //writeln(g.matches);
	writeln(g);
}
