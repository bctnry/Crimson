import std/unicode

type
  RegexType* = enum
    EMPTY
    CHARACTER
    STAR
    PLUS
    OPTIONAL
    CONCAT
    UNION
    CHSET    # Character set
    COMPCHSET    # Complement character set (matches characters that are not in the set)
    RANGE
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
    of CHSET:
      cset*: seq[Rune]
    of COMPCHSET:
      ccset*: seq[Rune]
    of RANGE:
      rst*: Rune
      re*: Rune

    
