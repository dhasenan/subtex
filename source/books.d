module subtex.books;

import std.conv;
import std.uuid;

class Book
{
    string id;
    this()
    {
        id = randomUUID().to!string;
    }

    string[][string] info;
    Chapter[] chapters;

    string author()
    {
        if (auto p = "author" in info)
        {
            return (*p)[0];
        }
        return "Writer";
    }

    string title()
    {
        if (auto p = "title" in info)
        {
            return (*p)[0];
        }
        return "Book";
    }

    string[] stylesheets()
    {
        if (auto p = "stylesheet" in info)
        {
            return *p;
        }
        return null;
    }
}

// A standard node is either a plain string, or a command, or a series of nodes.
// Only one at a time.
class Node
{
    this(string text, size_t start)
    {
        this.text = text;
        this.start = start;
    }

    string text; // for commands: the name of the command; else text contents
    string uri; // for URI-oriented commands (img)
    Node[] kids;
    size_t start;

    // Approximate end of this node.
    size_t end()
    {
        if (kids)
        {
            return kids[$ - 1].end;
        }
        return start + text.length;
    }

    size_t length()
    {
        return end() - start;
    }
}

class Cmd : Node
{
    this(string text, size_t start)
    {
        super(text, start);
    }
}

class Chapter : Node
{
    this(bool silent, size_t start)
    {
        super("", start);
        this.silent = silent;
    }

    string title;
    bool silent;
    // Absolute index, corresponds to position in Book.chapters
    int index;
    // For chapter numbering
    int chapterNum;

    string fileid()
    {
        return `chapter` ~ index.to!string;
    }

    string filename()
    {
        return `chapter` ~ index.to!string ~ `.html`;
    }

    string fullTitle()
    {
        import std.format;

        if (silent)
        {
            return title;
        }
        return `Chapter %s: %s`.format(chapterNum, title);
    }

    string id()
    {
        return title.sha1UUID().to!string;
    }
}
