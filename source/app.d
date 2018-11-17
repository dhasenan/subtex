module subtex.app;

import subtex.books;
import subtex.formats;
import subtex.output;
import subtex.parser;

import core.memory;

import std.algorithm;
import std.array;
import std.file;
import std.format;
import std.path;
import std.string;
import std.stdio;
import std.zip;

version(linux)
{
    extern(C) int inotify_init();
    extern(C) int inotify_add_watch(int fd, const char* filename, int mask);
    extern(C) int read(int fd, void* buf, size_t count);
}

int main(string[] args)
{
    version (linux)
    {
        import etc.linux.memoryerror;
        registerMemoryErrorHandler();
    }
    import std.getopt;
    auto writers = subtex.formats.writers();

    string[] formats = [];
    string userOutPath;
    bool count = false;
    bool chapterCount = false;
    bool watch = false;
    auto info = getopt(args, std.getopt.config.passThrough,
            "formats|f", "Output formats. Use -f list to list.", &formats,
            "out|o", "Output file base name.", &userOutPath,
            "count|c", "Count words in input documents", &count,
            "chaptercount|d", "Count words in input documents", &chapterCount,
            "watch", "Watch for changes and rerun (linux only)", &watch);
    if (info.helpWanted)
    {
        defaultGetoptPrinter("subtex: producing ebooks from a simple TeX-like language",
                info.options);
        return 0;
    }
    version(linux) {} else
    {
        if (watch)
        {
            stderr.writeln("--watch only supported on linux");
            return 1;
        }
    }
    if (formats.canFind("list"))
    {
        foreach (k, v; writers)
        {
            writeln(k);
        }
    }
    if (args.length < 2)
    {
        stderr.writeln("You must provide an input file");
        return 1;
    }

    if (formats.length == 0)
    {
        formats = ["epub", "html"];
    }

    auto w = formats
        .map!(x => x in writers)
        .filter!(x => x !is null)
        .map!(x => *x);

    int inotifyfd;
    immutable(char)*[] waitPaths;
    if (watch)
    {
        inotifyfd = inotify_init;
        waitPaths = args[1..$].map!toStringz.array;
    }
    void[] inotifybuf = new void[4096];
    bool success = true;
    do
    {
        foreach (infile; args[1 .. $])
        {
            auto basePath = infile.dirName.absolutePath;
            string outpath = userOutPath;
            if (outpath == "")
            {
                outpath = infile.baseName;
            }
            string readFile(string filename)
            {
                return buildPath(basePath, filename).readText;
            }
            auto parser = new Parser(infile, infile.readText, &readFile);
            Book book;
            try
            {
                book = parser.parse();
            }
            catch (ParseException e)
            {
                writefln("%s\nerror processing %s", e.msg, infile);
            }
            if (book is null)
            {
                stderr.writefln("Failed to parse %s", infile);
                return 1;
            }

            foreach (ww; w)
            {
                if (!ww(book, outpath))
                {
                    stderr.writefln("failed to write %s", infile);
                }
            }

            if (count)
            {
                Appender!string writer;
                writer.reserve(500_000);
                auto toHtml = new ToText!(typeof(writer))(book, writer);
                toHtml.run();
                auto words = std.algorithm.count(splitter(writer.data));
                writefln("%s: %s", infile, words);
            }
            if (chapterCount)
            {
                foreach (c; book.chapters)
                {
                    Appender!string writer;
                    writer.reserve(50_000);
                    auto b2 = new Book;
                    b2.chapters = [c];
                    auto toText = new ToText!(typeof(writer))(b2, writer);
                    toText.run();
                    auto words = std.algorithm.count(splitter(writer.data));
                    writefln("%s %s: %s", infile, c.title, words);
                }
            }
        }
        import core.memory : GC;
        GC.collect();
        if (watch)
        {
            writeln("created ebooks");
            foreach (name; waitPaths)
            {
                inotify_add_watch(inotifyfd, name, 2);
            }
            // It would be more efficient to update only the affected items.
            // However, that would mean more complex code.
            // TODO: make this work for multifile books
            read(inotifyfd, inotifybuf.ptr, inotifybuf.length);
        }
    } while (watch);
    if (success)
        return 0;
    return 1;
}
