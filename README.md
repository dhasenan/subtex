SubTex
======

SubTex is a miniature version of LaTeX that only does a few things. It's intended to give you a few
semantic commands that you can use to produce a reasonable ebook.

Currently, it can produce all-in-one-document HTML or an epub file.

Why SubTex?
-----------
If you could be using LaTeX, why would you use SubTex?

* Simplicity
* Speed
* Easy publication

If LaTeX is HTML5, SubTex is MarkDown. The relative complexity is just that stark. SubTex only
supports a handful of mostly-semantic commands, defined simply; LaTeX is a whole world of
typesetting that you don't need to author a typical work of fiction.

SubTex is blazingly fast. In a sample document weighing in at 410kb, `htlatex` alone took 1.6
seconds to execute, with over three seconds to invoke both it and `ebook-convert`. In contrast,
SubTex created both epub and html documents in 0.04 seconds. It's done by the time you realize you
finished pressing the 'enter' key. There's no competition.

SubTex offers easy publication to epub. It's builtin -- the default option. In contrast, with LaTeX,
it's very difficult. Your choice is `latexml`, which has issues with including certain packages, or
`htlatex`, which doesn't play nice with Calibre's `ebook-convert` command.

Language
--------
See `examples/` and `language.md` for more information.

However, a brief example should give a good impression of what SubTex is capable of:

```LaTeX
\info{author, Suetonius}
\info{title, The Twelve Caesars}
\info{stylesheet, suetonius.css}

\chapter{Caius Julius Caesar}
Julius Caesar, the Divine, lost his father when he was in his sixteenth year of age.
% Blank lines are transformed into new paragraphs.

% The \e{} commanad enquotes text.
One day, Sylla said to some friends, who were entreating him to be nice to Caesar: \e{Yeah, sure,
he can hang with us.

% It can handle multiline quotes.
But you do know, right, that this kid you're so worked up about his safety, he's gonna be our
downfall eventually?

I mean, you told me to take care of the nobles, but this guy's cut from the same cloth as Marius.}
```


Building
--------
If you have [Dub](https://code.dlang.org/download) installed and working, just check out the
repository and use `dub build`. Dub is installed by default with versions of
[DMD](http://dlang.org/download.html) 2.072 and later.

The result is an all-in-one binary; you can copy it, move it around, whatever, without worrying
about whether it can find any dependent files.


Invocation
----------
The simplest way to invoke subtex is to generate an epub file:

```
subtex twelve_caesars.sub
```

This produces a file named `twelve_caesars.epub` that you can open with Calibre or put on your Nook
or read with FBReader or what have you.

Running `subtex --help` should give you some indication of what the options are:

```
$ subtex --help
subtex: producing ebooks from a simple TeX-like language
-f --formats The output formats (epub, html, text, markdown)
-o     --out Output file base name.
-c   --count Count words in input documents
-h    --help This help information.
```

The default is to output an epub document with the same path as the input, but with the extension
changed. This is in the same directory as the input file.

You can also use subtex to count the words in a document. This will suppress file generation and
just print out the number of words.

Example document
----------------
The above example document produces the following document:

```HTML
<?xml version='1.0' encoding='utf-8'?>
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en">
    <head>
        <meta http-equiv="Content-Type" content="text/html; charset=UTF-8"/>
        <link rel="stylesheet" href="subtex.css">
        <link rel="stylesheet" href="suetonius.css">
        
        <title>The Twelve Caesars</title>
    </head>
    <body>
    <h1 class="title">The Twelve Caesars</h1>
    <h3 class="author">Suetonius</h3>
    <h2 class="chapter">Chapter 1: Caius Julius Caesar</h2>
    
Julius Caesar, the Divine, lost his father when he was in his sixteenth year of age.

<p>One day, Sylla said to some friends, who were entreating him to be nice to Caesar: &ldquo;Yeah, sure,
he can hang with us.

<p>&lsquo;But you do know, right, that this kid you're so worked up about his safety, he's gonna be our
downfall eventually?

<p>&lsquo;I mean, you told me to take care of the nobles, but this guy's cut from the same cloth as Marius.&rdquo;

    </body>
</html>
```
