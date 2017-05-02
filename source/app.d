module subtex.app;

import subtex.books;
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

int main(string[] args)
{
    import std.getopt;

    string[] formats = [];
    string userOutPath;
    bool count = false;
    bool chapterCount = false;
    auto info = getopt(args, std.getopt.config.passThrough, "formats|f",
            "The output formats (epub, html, text, markdown, bbcode, chapters)",
            &formats, "out|o", "Output file base name.",
            &userOutPath, "count|c", "Count words in input documents", &count,
            "chaptercount|d", "Count words in input documents", &chapterCount,);
    if (info.helpWanted)
    {
        defaultGetoptPrinter("subtex: producing ebooks from a simple TeX-like language",
                info.options);
        return 0;
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

    bool success = true;
    foreach (infile; args[1 .. $])
    {
        auto basePath = infile.dirName.absolutePath;
        string outpath = userOutPath;
        if (outpath == "")
        {
            outpath = infile.baseName;
        }
        auto parser = new Parser(infile.readText());
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
        if (formats.canFind("epub"))
        {
            auto epubOut = outpath.stripExtension() ~ ".epub";
            auto zf = new ZipArchive();
            auto toEpub = new ToEpub(basePath);
            success = success && toEpub.run(book, zf);
            auto outfile = File(epubOut, "w");
            outfile.rawWrite(zf.build());
            outfile.close();
        }
        if (formats.canFind("html"))
        {
            if (outpath == "-")
            {
                auto writer = stdout.lockingTextWriter();
                auto toHtml = new ToHtml!(typeof(writer))(book, writer);
                toHtml.run();
            }
            else
            {
                auto htmlOut = outpath.stripExtension() ~ ".html";
                auto outfile = File(htmlOut, "w");
                auto writer = outfile.lockingTextWriter();
                auto toHtml = new ToHtml!(typeof(writer))(book, writer);
                toHtml.run();
                outfile.flush();
                outfile.close();
            }
        }
        if (formats.canFind("markdown"))
        {
            auto mdOut = outpath.stripExtension() ~ ".md";
            auto outfile = File(mdOut, "w");
            auto writer = outfile.lockingTextWriter();
            auto toHtml = new ToMarkdown!(typeof(writer))(book, writer);
            toHtml.run();
            outfile.flush();
            outfile.close();
        }
        if (formats.canFind("bbcode"))
        {
            auto mdOut = outpath.stripExtension() ~ ".bbcode";
            auto outfile = File(mdOut, "w");
            auto writer = outfile.lockingTextWriter();
            auto toHtml = new ToBbcode!(typeof(writer))(book, writer);
            toHtml.run();
            outfile.flush();
            outfile.close();
        }
        if (formats.canFind("text"))
        {
            if (outpath == "-")
            {
                auto writer = stdout.lockingTextWriter();
                auto toHtml = new ToText!(typeof(writer))(book, writer);
                toHtml.run();
            }
            else
            {
                auto mdOut = outpath.stripExtension() ~ ".txt";
                auto outfile = File(mdOut, "w");
                auto writer = outfile.lockingTextWriter();
                auto toHtml = new ToText!(typeof(writer))(book, writer);
                toHtml.run();
                outfile.flush();
                outfile.close();
            }
        }
        if (formats.canFind("chapters"))
        {
            auto outdir = outpath.stripExtension;
            new ToChapters(book, outdir).toChapters();
        }
    }
    if (success)
        return 0;
    return 1;
}
