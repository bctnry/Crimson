import std/unicode
import std/strutils
import std/sequtils

type
  RegexType* = enum
    EMPTY
    CHARACTER
    STAR
    PLUS
    OPTIONAL
    CONCAT
    UNION
    REGEX_IN
    REGEX_NOT_IN
    NAME_REF
    CAPTURE
  Regex* = ref object
    case regexType*: RegexType
    of EMPTY: nil
    of CHARACTER:
      ch*: Rune
    of STAR:
      sbody*: Regex
      sgreedy*: bool = true
    of PLUS:
      pbody*: Regex
      pgreedy*: bool = true
    of OPTIONAL:
      obody*: Regex
      ogreedy*: bool = true
    of CONCAT:
      cbody*: seq[Regex]
    of UNION:
      ubody*: seq[Regex]
    of REGEX_IN:
      in_chset*: seq[Rune]
      in_chrange*: seq[(Rune, Rune)]
    of REGEX_NOT_IN:
      not_in_chset*: seq[Rune]
      not_in_chrange*: seq[(Rune, Rune)]
    of NAME_REF:
      name*: string
    of CAPTURE:
      capbody*: Regex

proc `$`*(x: Regex): string =
  case x.regexType:
    of EMPTY: ""
    of CHARACTER: x.ch.toUTF8
    of STAR: $x.sbody & "*" & (if x.sgreedy: "" else: "?")
    of PLUS: $x.pbody & "+" & (if x.pgreedy: "" else: "?")
    of OPTIONAL: $x.obody & "?" & (if x.ogreedy: "" else: "?")
    of CONCAT: x.cbody.mapIt($it).join("")
    of UNION: "(?:"&x.ubody.mapIt($it).join("|")&")"
    of REGEX_IN: "["&x.in_chset.mapIt(it.toUTF8).join("")&x.in_chrange.mapIt(it[0].toUTF8&"-"&it[1].toUTF8).join("")&"]"
    of REGEX_NOT_IN: "[^"&x.not_in_chset.mapIt(it.toUTF8).join("")&x.not_in_chrange.mapIt(it[0].toUTF8&"-"&it[1].toUTF8).join("")&"]"
    of NAME_REF: "{"&x.name&"}"
    of CAPTURE: "(" & $x.capbody & ")"
    
