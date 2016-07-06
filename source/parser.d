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
    int chapNum = 0;
    foreach (i, chapter; book.chapters) {
      if (!chapter.silent) {
        chapNum++;
        chapter.chapterNum = chapNum;
      }
      chapter.index = cast(int)i;
    }
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
