" subtex syntax highlighting for vim

if exists("b:subtexSyntax")
  finish
endif

syn match cmd '\\\w\+'
syn match lineComment '%.*$'
high def link cmd Macro
high def link lineComment Comment
