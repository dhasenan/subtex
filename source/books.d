module subtex.books;

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

}

class Book {
  string id;
  string title, author;
  ExtFile[] stylesheets;
  Chapter[] chapters;
  // TODO images?
}
