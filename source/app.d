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
  auto info = getopt(
    args,
    std.getopt.config.passThrough,
    "formats|f", "The output formats (epub, html, text, markdown)", &formats,
    "out|o", "Output file base name.", &userOutPath,
    "count|c", "Count words in input documents", &count
  );
  if (info.helpWanted) {
    defaultGetoptPrinter("subtex: producing ebooks from a simple TeX-like language",
        info.options);
    return 0;
  }
  if (args.length < 2) {
    stderr.writeln("You must provide an input file");
    return 1;
  }

  if (formats.length == 0) {
    formats = ["epub", "html"];
  }

  foreach (infile; args[1..$]) {
    string outpath = userOutPath;
    if (outpath == "") {
      outpath = infile;
    }
    auto parser = new Parser(infile.readText());
    Book book;
    try {
      book = parser.parse();
    } catch (ParseException e) {
      writefln("%s\nerror processing %s", e.msg, infile);
    }
    if (book is null) {
      stderr.writefln("Failed to parse %s", infile);
      return 1;
    }

    if (count) {
      Appender!string writer;
      writer.reserve(500_000);
      auto toHtml = new ToText!(typeof(writer))(book, writer);
      toHtml.run();
      auto words = std.algorithm.count(splitter(writer.data));
      writefln("%s: %s", infile, words);
      continue;
    }
    if (formats.canFind("epub")) {
      auto epubOut = outpath.stripExtension() ~ ".epub";
      auto zf = new ZipArchive();
      auto toEpub = new ToEpub();
      toEpub.run(book, zf);
      auto outfile = File(epubOut, "w");
      outfile.rawWrite(zf.build());
      outfile.close();
    }
    if (formats.canFind("html")) {
      if (outpath == "-") {
        auto writer = stdout.lockingTextWriter();
        auto toHtml = new ToHtml!(typeof(writer))(book, writer);
        toHtml.run();
      } else {
        auto htmlOut = outpath.stripExtension() ~ ".html";
        auto outfile = File(htmlOut, "w");
        auto writer = outfile.lockingTextWriter();
        auto toHtml = new ToHtml!(typeof(writer))(book, writer);
        toHtml.run();
        outfile.flush();
        outfile.close();
      }
    }
    if (formats.canFind("markdown")) {
      auto mdOut = outpath.stripExtension() ~ ".md";
      auto outfile = File(mdOut, "w");
      auto writer = outfile.lockingTextWriter();
      auto toHtml = new ToMarkdown!(typeof(writer))(book, writer);
      toHtml.run();
      outfile.flush();
      outfile.close();
    }
    if (formats.canFind("text")) {
      if (outpath == "-") {
        auto writer = stdout.lockingTextWriter();
        auto toHtml = new ToText!(typeof(writer))(book, writer);
        toHtml.run();
      } else {
        auto mdOut = outpath.stripExtension() ~ ".txt";
        auto outfile = File(mdOut, "w");
        auto writer = outfile.lockingTextWriter();
        auto toHtml = new ToText!(typeof(writer))(book, writer);
        toHtml.run();
        outfile.flush();
        outfile.close();
      }
    }
  }
  auto infile = args[1];
  return 0;
}
