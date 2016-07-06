module subtex.app;

//import subtex.books;
//import subtex.output;
import subtex.parser;

import core.memory;

import std.algorithm;
import std.file;
import std.format;
import std.path;
import std.string;
import std.stdio;
import std.zip;


int main(string[] args)
{
  import std.getopt;
  bool html = false;
  bool epub = true;
  bool print = false;
  string outpath;
  auto info = getopt(
    args,
    std.getopt.config.passThrough,
    "html|h", "Whether to produce html output (default false).", &html,
    "epub|e", "Whether to produce epub output (default true).", &epub,
    "print|p", "Whether to print the parse tree.", &print,
    "out|o", "Output filename. If producing both epub and html, the appropriate extensions will be used.", &outpath
  );
  if (args.length < 2) {
    stderr.writeln("You must provide an input file");
    return 1;
  }
  auto infile = args[1];
  if (outpath == "") {
    outpath = infile;
  }

  auto parser = new Parser(infile.readText());
  auto book = parser.parse();
  /*
  if (print) {
    writeln(parser.tree);
  }
  */
  if (book is null) {
    stderr.writefln("Failed to parse %s", infile);
    return 1;
  }

  if (!html && !epub) {
    stderr.writeln("No output requested.");
    return 0;
  }

  if (epub) {
    /*
    auto epubOut = outpath.stripExtension() ~ ".epub";
    auto zf = new ZipArchive();
    book.save(zf);
    auto outfile = File(epubOut, "w");
    outfile.rawWrite(zf.build());
    outfile.close();
    */
  }
  if (html) {
    auto htmlOut = outpath.stripExtension() ~ ".html";
    auto outfile = File(htmlOut, "w");
    auto writer = outfile.lockingTextWriter();
    auto toHtml = new ToHtml!(typeof(writer))(book, writer);
    toHtml.run();
    outfile.flush();
    outfile.close();
  }
  return 0;
}
