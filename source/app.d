module subtex.app;

import subtex.books;
import subtex.formats;
import subtex.output;
import subtex.parser;
import subtex.util;

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
    auto allWriters = subtex.formats.writers();

    string[] formats = ["epub", "html"];
    string userOutPath;
    bool quiet = false;
    bool count = false;
    bool chapterCount = false;
    bool watch = false;
    bool lexOnly = false;
    auto info = getopt(args, std.getopt.config.passThrough,
            "formats|f", "Output formats. Use -f list to list.", &formats,
            "out|o", "Output file base name.", &userOutPath,
            "count|c", "Count words in input documents", &count,
            "chaptercount|d", "Count words in input documents", &chapterCount,
            "quiet|q", "Write minimal output", &quiet,
            "lex-only", "Debug: only lex the file, don't parse", &lexOnly,
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
        foreach (k, v; allWriters)
        {
            writeln(k);
        }
    }
    if (args.length < 2)
    {
        stderr.writeln("You must provide an input file");
        return 1;
    }

    if (lexOnly)
    {
        foreach (arg; args[1..$])
        {
            auto lexer = Lexer(arg.absolutePath);
            long tokcount = 0;
            while (!lexer.empty)
            {
                tokcount++;
                writeln(lexer.front);
                lexer.popFront;
            }
            writefln("%s: %s tokens", arg, tokcount);
        }
        return 0;
    }

    auto writers = formats
        .map!(x => x in allWriters)
        .filter!(x => x !is null)
        .map!(x => *x);

    bool success = true;
    string[] filesToWatch;
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
            auto lexer = Lexer(infile.absolutePath);
            auto parser = new Parser(lexer);
            Book book;
            try
            {
                book = parser.parseBook;
                filesToWatch ~= book.files;
            }
            catch (ParseException e)
            {
                filesToWatch ~= infile;
                if (!quiet)
                {
                    stderr.writefln("%s\nerror processing %s", e.msg, infile);
                }
                if (!watch)
                {
                    return 1;
                }
                continue;
            }

            // Do we need multiple output kinds?
            auto kinds = writers.map!(x => x.kind).array.sort.uniq.array;
            if (kinds.length == 1)
            {
                expandMacros(book, kinds[0]);
                foreach (ww; writers)
                    if (!ww.write(book, outpath))
                        stderr.writefln("%s: failed to write %s", infile, ww.format);
            }
            else
            {
                Book[string] byKind;
                foreach (kind; kinds)
                {
                    auto b = book.dup;
                    expandMacros(b, kind);
                    byKind[kind] = b;
                }
                foreach (ww; writers)
                    if (!ww.write(byKind[ww.kind], outpath))
                        stderr.writefln("%s: failed to write %s", infile, ww.format);
            }

            if (count)
            {
                Appender!string writer;
                writer.reserve(500_000);
                auto toHtml = new ToText!(typeof(writer))(book, writer);
                toHtml.run();
                auto words = std.algorithm.count(splitter(writer.data));
                if (args.length > 2)
                {
                    writefln("%s: %s", infile, words);
                }
                else
                {
                    writeln(words);
                }
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
            int inotifyfd;
            immutable(char)*[] waitPaths;
            if (watch)
            {
                inotifyfd = inotify_init;
                waitPaths = filesToWatch.map!toStringz.array;
            }
            void[] inotifybuf = new void[4096];
            foreach (name; waitPaths)
            {
                inotify_add_watch(inotifyfd, name, 2);
            }
            // It would be more efficient to update only the affected items.
            // However, that would mean more complex code.
            read(inotifyfd, inotifybuf.ptr, inotifybuf.length);
        }
    } while (watch);
    if (success)
        return 0;
    return 1;
}
