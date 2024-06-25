import regexdef
import std/strformat
import std/strutils
import std/sequtils

type
  TokenDeclRetaining* = tuple
    groupId: int
    groupName: string
  TokenDecl* = ref object
    name*: string
    regex*: Regex
    retaining*: seq[TokenDeclRetaining]

  Program* = seq[TokenDecl]

proc makeTokenDecl*(name: string, regex: Regex): TokenDecl =
  TokenDecl(name: name,
            regex: regex,
            retaining: @[])
proc makeTokenDecl*(name: string, regex: Regex, retaining: seq[TokenDeclRetaining]): TokenDecl =
  TokenDecl(name: name,
            regex: regex,
            retaining: retaining)

proc `$`*(x: TokenDecl): string =
  let regexStr = $x.regex
  let retainingStr = if x.retaining.len <= 0:
                       ""
                     else:
                       x.retaining.mapIt(if it.groupName == "":
                                           $it.groupId
                                         else:
                                           &"{it.groupId}:{it.groupName}").join(",")
  return &"{x.name} = /{regexStr}/" & "{" & &"{retainingStr}" & "}"

  
