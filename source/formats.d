module subtex.formats;

import std.zip;
import std.file;
import std.stdio;
import std.path;
import subtex.books;
import subtex.output;

alias writer = bool delegate(Book, string);

writer[string] writers()
{
    writer[string] w;
    w["epub"] = (book, outpath)
    {
        auto epubOut = outpath.stripExtension() ~ ".epub";
        auto zf = new ZipArchive();
        auto basePath = outpath.dirName;
        auto toEpub = new ToEpub(basePath);
        if (!toEpub.run(book, zf)) return false;
        auto outfile = File(epubOut, "w");
        outfile.rawWrite(zf.build());
        outfile.close();
        return true;
    };
    w["html"] = (book, outpath)
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
    };
    w["markdown"] = (book, outpath)
    {
        auto mdOut = outpath.stripExtension() ~ ".md";
        auto outfile = File(mdOut, "w");
        auto writer = outfile.lockingTextWriter();
        auto toHtml = new ToMarkdown!(typeof(writer))(book, writer);
        toHtml.run();
        outfile.flush();
        outfile.close();
        return true;
    };
    w["bbcode"] = (book, outpath)
    {
        auto mdOut = outpath.stripExtension() ~ ".bbcode";
        auto outfile = File(mdOut, "w");
        auto writer = outfile.lockingTextWriter();
        auto toHtml = new ToBbcode!(typeof(writer))(book, writer);
        toHtml.run();
        outfile.flush();
        outfile.close();
        return true;
    };
    w["text"] = (book, outpath)
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
    };
    w["chapters"] = (book, outpath)
    {
        auto outdir = outpath.stripExtension;
        new ToChapters(book, outdir).toChapters();
        return true;
    };
    return w;
}
