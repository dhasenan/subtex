module subtex.formats;

import std.zip;
import std.file;
import std.stdio;
import std.path;
import subtex.books;
import subtex.output;

struct Writer
{
    string format;
    string kind;
    bool delegate(Book, string) write;
}

Writer[string] writers()
{
    Writer[string] w;
    w["epub"] = Writer("epub", "html", (book, outpath)
    {
        auto epubOut = outpath.stripExtension() ~ ".epub";
        auto zf = new ZipArchive();
        auto toEpub = new ToEpub();
        if (!toEpub.run(book, zf)) return false;
        auto outfile = File(epubOut, "w");
        outfile.rawWrite(zf.build());
        outfile.close();
        return true;
    });
    w["html"] = Writer("html", "html", (book, outpath)
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
        return true;
    });
    w["markdown"] = Writer("markdown", "text", (book, outpath)
    {
        auto mdOut = outpath.stripExtension() ~ ".md";
        auto outfile = File(mdOut, "w");
        auto writer = outfile.lockingTextWriter();
        auto toHtml = new ToMarkdown!(typeof(writer))(book, writer);
        toHtml.run();
        outfile.flush();
        outfile.close();
        return true;
    });
    w["bbcode"] = Writer("bbcode", "bbcode", (book, outpath)
    {
        auto mdOut = outpath.stripExtension() ~ ".bbcode";
        auto outfile = File(mdOut, "w");
        auto writer = outfile.lockingTextWriter();
        auto toHtml = new ToBbcode!(typeof(writer))(book, writer);
        toHtml.run();
        outfile.flush();
        outfile.close();
        return true;
    });
    w["text"] = Writer("text", "text", (book, outpath)
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
        return true;
    });
    w["chapters"] = Writer("chapters", "html", (book, outpath)
    {
        auto outdir = outpath.stripExtension;
        new ToChapters(book, outdir).toChapters();
        return true;
    });
    return w;
}
