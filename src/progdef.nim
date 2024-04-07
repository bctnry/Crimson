import regexdef
import std/strformat

type
  TokenDecl* = ref object
    name*: string
    regex*: Regex

  Program* = seq[TokenDecl]

proc makeTokenDecl*(name: string, regex: Regex): TokenDecl =
  TokenDecl(name: name,
            regex: regex)

proc `$`*(x: TokenDecl): string =
  let regexStr = $x.regex
  return &"{x.name} = {regexStr}"

  
