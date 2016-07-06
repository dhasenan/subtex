module subtex.books;

import std.conv;
import std.uuid;

class Book {
  string id;
  this() {
    id = randomUUID().to!string;
  }
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

class Cmd : Node {
  this(string text, size_t start) {
    super(text, start);
  }
}

class Chapter : Node {
  this(bool silent, size_t start) {
    super("", start);
    this.silent = silent;
  }
  string title;
  bool silent;
  // Absolute index, corresponds to position in Book.chapters
  int index;
  // For chapter numbering
  int chapterNum;

  string fileid() {
    return `chapter_` ~ index.to!string;
  }

  string filename() {
    return `chapter_` ~ index.to!string ~ `.html`;
  }
}

