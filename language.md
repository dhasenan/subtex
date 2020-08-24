# General format

Subtex is a lightweight textual format. You write text, and by default that text is inserted into
the output document.

## Commands

For special formatting and operations, you use commands, which look like:

```LaTeX
\name{content}
\name
\name{}
```

## Comments

Subtex has two types of comment: a line comment, starting with `%` and continuing to the end of the current line; and a block comment, starting with `<%` and ending with `%>`.

```LaTeX
% This line is a comment that won't appear in the output.
This text is inserted into the output document.

<% This is a multi-line comment.
This second line is still part of the comment.
But look: %> This text is not in the comment. It's part of the output!
```

That's equivalent to:
```LaTeX
This text is inserted into the output document.

This text is not in the comment. It's part of the output!
```

Note that, for block comments, you must always have two or more `%` signs. `<%%>` is a block comment; `<%>` is the start of a block comment, but it doesn't contain the end of one.

## Escaping

If you want to have one character that would normally be interpreted specially instead included in the output, put a backslash before it:

```LaTeX
\em{stuff}   % invoke a command
\\em{stuff}  % put a literal \ in the output, then put foo

% A line comment
\% A line starting with the percent symbol
```

Which turns into:

```HTML
<p><em>stuff</em>
\em{stuff}</p>

<p>% A line starting with the percent symbol</p>
```

If you have a large block of text that should be treated as regular text instead of special symbols, surround it with `<![CDATA[` and `]]>`:

```LaTeX
Welcome to my subtex tutorial!

To start out, open a document and type:

<![CDATA[
% My first document!
\info{title, SubTex Tutorial}
\chapter{Chapter One}
\em{Hello, world!}
]]>
```

This will produce the output:

```HTML
<p>Welcome to my subtex tutorial!</p>

<p>To start out, open a document and type:</p>

<p>% My first document!
\info{title, SubTex Tutorial}
\chapter{Chapter One}
\em{Hello, world!}</p>
```


# The preamble

A subtex document begins with a preamble. The preamble is everything in the document before the
first chapter -- which is marked with `\chapter`, `\chapter*`, or `\import`.

In the preamble, you may use `\info` commands and define [macros](#macros).

## Info commands

The `\info{key, value}` command sets parameters for the document as a whole.

Allowed keys are:

* `author`: set the authors of the document. This should appear exactly once.
* `title`: set the title of the document. This should appear exactly once.
* `stylesheet`: add a stylesheet file. This may appear zero or more times.
* `css`: add CSS declarations inline.
* `cover`: add a cover image. Optional.
* `autocover`: set to `true` to have subtex create a cover image for you.

A typical preamble might start:

```LaTeX
\info{author, Leo Tolstoy}
\info{title, Anna Karenina}
\info{autocover, true}
```


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


# Macros

## The basics

A macro is a set of instructions for making some text that you can insert later.

A basic macro is just some text to save you some typing. This can be useful for something you might want to change later, or something that's difficult for you to type:

```LaTeX
\macro{spacebucks, ₳}
\macro{kaldurahm, Kαλδυρ'αμ}
\kaldurahm earned \spacebux{}200,000!
```

This turns into:

```
Kαλδυρ'αμ earned ₳200,000!
```

The `\macro{...}` part is the **definition**. Once you've defined a macro, you can **call** it.


## Parameters

A macro can be parameterized: it can take a piece of text and include it where and when it likes. This text can contain commands and macros.

To define a macro with a parameter, use the `\content` command inside it:

```LaTeX
\macro{like, And he was like, \e{\content,} ya know?}
```

And to call it with a parameter, you do just like the builtins:

```LaTeX
\like{Subtex macros are \emph{spiffy}}
% And he was like, Subtex macros are \emph{spiffy}, ya know?
```

If you're so inclined, you can include the content multiple times:

```LaTeX
\macro{repeat, \content \emph{\content}}
\repeat{Very nice.}
% Very nice. \emph{Very nice.}
```


## Multiple parameters

A macro can take multiple parameters. To define a multi-parameter macro, write:

```
\macro{chat, \red{\emph{\content{1} said:}} \content{2}}
```

The `\content` command takes an optional parameter indicating the *nth* argument to the macro. This macro takes two parameters, one for who said the thing and the second for what they said.

To use this, use the pipe character, `|`, to separate the arguments:

```
\chat{Sarah|Are you coming to the party tonight?}

\chat{Becca|What part of "I'm studying" don't you understand??}
```

This expands to:

```
\red{\emph{Sarah said:}} Are you coming to the party tonight?

\red{\emph{Becca said:}} What part of "I'm studying" don't you understand??
```

## Specializing macros for an output type

Let's say you want to write a macro to indicate that certain text should be bold and red, and you want this to work in both bbcode and html.

The commands `\macrohtml` and `\macrobb` will create macros specifically for html and bbcode respectively:

```LaTeX
% Define what this should look like in HTML.
\macrohtml{boldred, <strong><span color="red">\content</span></strong>}
% Define what this should look like in BBCode.
\macrobb{boldred, [b][font color="red"]\content[/font][/b]}
```

## A note on HTML macros

Because epub requires XHTML content rather than just HTML content, subtex always produces XHTML. This means that macros interact with paragraphs poorly:

```LaTeX
\macrohtml{boldred, <span style="color: red; font-weight: bold">\content</span>}
\boldred{Hi there!

Long time no see!}
```

This would produce:

```HTML
<p><span style="color: red; font-weight: bold">Hi there!</p>
<p>Long time no see!</span></p>
```

This is not valid XHTML. However, you can address this issue with CSS:

```LaTeX
\info{css, <![CDATA[
.boldred {
    font-weight: bold;
    color: red;
}
]]>}
\boldred{Hi there!

Haven't seen you in ages!}
```

*This* produces valid output:

```HTML
<p><span class="boldred">Hi there!</span></p>
<p><span class="boldred">Haven't seen you in ages!</span></p>
```

However, if you need a block-level element spanning multiple paragraphs, that might be enough:

```LaTeX
\info{css, <![CDATA[

]]>}
```


## Alias `\def`

Some aliases are defined for legacy reasons:

* `\def` is the same as `\macro`
* `\defbb` is the same as `\macrobb`
* `\defhtml` is the same as `\macrohtml`


## Limitations

Macros can refer to each other. However, a macro cannot refer to itself, even indirectly.

## Macros in imported documents

Imported documents inherit all the macros, definitions, and options defined where they are imported.
They cannot create new macros or definitions.

Most of the time, this should work just as you'd expect, but you can do some madlibs-style parlor
tricks with it.

