# General format

Subtex is a lightweight textual format. You write text, and by default that text is inserted into
the output document.

It contains commands, which are generally of the syntax:

```
\name{content}
```

It also contains one-line comments:
```
% This is a comment that won't appear in the output.
This text is inserted into the output document.
```



# The preamble

A subtex document begins with a preamble. The preamble is everything in the document before the
first chapter -- which is marked with the `\chapter` or `\chapter*` command.

There are special commands that are only interpreted in the preamble.


## Info commands

The `\info{key, value}` command sets parameters for the document as a whole.

Allowed keys are:

* `author`: set the authors of the document. This should appear exactly once.
* `title`: set the title of the document. This should appear exactly once.
* `stylesheet`: add a stylesheet. This may appear zero or more times.
* `cover`: add a cover image. Optional.
* `autocover`: set to `true` to have subtex create a cover image for you.

A typical preamble might start:

```LaTeX
\info{author, Leo Tolstoy}
\info{title, Anna Karenina}
\info{autocover, true}
```


## Definitions

Subtex allows you to define variables with different values for each output type:

* `\defbb{name, value}`: define a variable for bbcode output
* `\defhtml{name, value}`: define a variable for html output (including epub)

Once you've defined something, you can use it like a command:

```LaTeX
\defbb{cool, [b]subtex is cool[/b]}
\defhtml{cool, <marquee>subtex is awesome</marquee>}

\cool{}
```

When outputting bbcode, this will show `[b]subtex is cool[/b]`. When outputting html and related
types, it will show `<marquee>subtex is awesome</marquee>`. This lets you do formatting that you
can't do with the builtin commands.


## Macros

A macro is a way to save yourself some typing.

You can define basic macros in subtex:

```LaTeX
\macro{like, And he was like, \e{\content{},} ya know?}
\like{Subtex macros are \emph{spiffy}}
```

This is mostly equivalent to typing:

```
And he was like, \e{Subtex macros are \emph{spiffy},} ya know?
```

The "mostly" is because the HTML output will wrap the text in a `<span class="like">`, just like
using an undefined command.

Within a macro, the special `\content{}` command refers to the stuff you passed into the macro. It
turns into a `<span class="content">`.

If you're so inclined, you can include the content multiple times:

```
\macro{repeat, \content{}
\emph{\content{}}}
\repeat{Very nice.}
```

This produces the HTML output:

```HTML
<span class="repeat"><span class="content">Very nice.</span>
<em><span class="content">Very nice.</span></em></span>
```


### Limitations

Macros can refer to each other. However, a macro cannot refer to itself, even indirectly.

A macro can only refer to macros and definitions defined before it.



# Chapters

A subtex file is a series of chapters.

1. `\chapter{title}` starts a numbered chapter named `title`.
2. `\chapter*{title}` starts an unnumbered chapter named `title`.
3. `\import{filename}` reads in one or more chapters from `filename` and inserts them into the book.

For example:

```LaTeX
\info{title, Anna Karenina}
\chapter*{Foreward}
Leo Tolstoy's classic work.

% Chapter 1: Stiva
\chapter{Stiva}
Happy families are all alike in their happiness; unhappy families are each unique in their misery.

% contains chapters 2, 3, and 4
\import{part1.sub}

% Chapter 5: To the spa!
\chapter{To the spa!}
Vronsky's rejection hit hard.
```

That's fine as a top level document.

Here's a document that's not valid for importing:

```LaTeX
This is part of the previous chapter.
```

Why not? Because the imported file must be a series of chapters.

## Macros in imported documents

Imported documents inherit all the macros, definitions, and options defined where they are imported.
They cannot create new macros or definitions.

Most of the time, this should work just as you'd expect, but you can do some madlibs-style parlor
tricks with it.


# Main content

After the preamble comes the body, which consists of zero or more chapters. If you don't
explicitly create a chapter, there is an implicit "Foreward" chapter.

## Default commands

The default body commands are:

* `\e{text}` -- quoted text. This yields curly quotes, handles nesting, and does the right thing for
  multiline quotes.
* `\emph{text}` -- emphasized text. This turns into HTML `em` tags.
* `\think{text}` -- a character thinking. Also turns into HTML `em` tags.
* `\spell{text}` -- a character casting a spell. Also turns into HTML `em` tags.
* `\scenebreak` -- a break between scenes. Turns into HTML `hr` tags.
* `\timeskip` -- a break between scenes, specifically indicating a time break. Turns into HTML `hr`
  tags.
* `\img{path}` -- include an image here. Can be a path or a URL.

All commands, recognized or not, with the exception of `\e`, yield HTML elements with a `class` that
matches the command name you used. So while both `\emph` and `\think` result in the same HTML tag,
you can distinguish them with CSS:

```LaTeX
\think{Is this cool?} \emph{It sure is!}
```

```HTML
<em class="think">Is this cool?</em> <em class="emph">It sure is!</em>
```

You can use macros and definitions to extend the set of commands.

## Implicit commands

A command that isn't recognized turns into a `<span class="commandname">`:

```LaTeX
\undefinedCommand{This is some text!}
```

turns into

```HTML
<span class="undefinedCommand">This is some text!</span>
```

