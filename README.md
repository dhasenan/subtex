SubTex
======

SubTex is a miniature version of LaTeX that only does a few things. It's intended to give you a few
semantic commands that you can use to produce a reasonable ebook.

Currently, it can produce all-in-one-document HTML or an epub file.

Language
--------
A SubTex document starts with a *preamble*, which is a set of `\info` options. The allowed `\info` options are:

* `\info{author, Author's Name}` -- set the document's author(s).
* `\info{title, Book Title}` -- set the document's title.
* `\info{stylesheet, stylesheet url}` -- add a stylesheet to the document. May occur multiple times.
  Stylesheets are not currently supported in epub output.

After the preamble comes the *body*, which consists of zero or more *chapters*. If you don't
explicitly create a chapter, there is an implicit "Foreward" chapter.

You may additionally include comments anywhere you wish. A comment begins with a `%` character and
ends with a newline.

The body commands are:

* `\chapter{title}` -- start a chapter with the given title.
* `\chapter*{title}` -- start a chapter with the given title. It does not participate in numbering.
* `\e{text}` -- quoted text. This yields curly quotes, handles nesting, and does the right thing for multiline quotes.
* `\emph{text}` -- emphasized text. This turns into HTML `em` tags.
* `\think{text}` -- a character thinking. Also turns into HTML `em` tags.
* `\spell{text}` -- a character casting a spell. Also turns into HTML `em` tags.
* `\scenebreak` -- a break between scenes. Turns into HTML `hr` tags.
* `\timeskip` -- a break between scenes, specifically indicating a time break. Turns into HTML `hr` tags.

All commands, recognized or not, with the exception of `\e`, yield HTML elements with a `class` that
matches the command name you used. So while both `\emph` and `\think` result in the same HTML tag,
you can distinguish them with CSS.

Example document
----------------
An example document:
```LaTeX
\info{author, Suetonius}
\info{title, The Twelve Caesars}
\info{stylesheet, suetonius.css}

\chapter{Caius Julius Caesar}
Julius Caesar, the Divine, lost his father when he was in his sixteenth year of age.

% Heavily rephrased.
One day, Sylla said to some friends, who were entreating him to be nice to Caesar: \e{Yeah, sure,
he can hang with us.

But you do know, right, that this kid you're so worked up about his safety, he's gonna be our
downfall eventually?

I mean, you told me to take care of the nobles, but this guy's cut from the same cloth as Marius.}
```

And that produces the following document:

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
