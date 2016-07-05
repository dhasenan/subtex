module subtex.parser;

/+
import subtex.books;

import std.algorithm;
import std.array;
import std.string;

class Parser {
  string data;
  Book book;
  this(string data) {
    this.data = data;
  }

  size_t next = 0;

  void parse() {
    book = new Book();
    while (next < data.length) {
      // We are guaranteed to get some set of \info bits, possibly empty, followed by \chapter.
      if (tryConsume("%", true)) {
        consumeUntil("\n");
      }
      if (tryConsume("\\info{", true)) {
        skipWhitespace();
        auto s = consumeIdentifier();
        if (!tryConsume(",", true)) {
          error("expected: `\\info{id, value}' -- you need a comma after the id");
        }
        auto val = consumeUntil("}").strip();
        switch (s) {
          case "author":
            book.author = val;
            break;
          case "title":
            book.title = val;
            break;
          case "stylesheet":
            ExtFile sheet;
            sheet.path = val;
            book.stylesheets ~= sheet;
            break;
          default:
            error("unrecognized info item `" ~ s ~ "'. Allowed is \\info{author, Author Name}," ~
                " \\info{title, Book Title}, and \\info{stylesheet, url}");
            break;
        }
      }
      if (peek("\\chapter{", true)) {
        break;
      }
    }
    while (next < data.length) {
      readChapter() || readText() || readCommand();
    }
  }
}
+/
