import std/unicode

type
  InstrType* = enum
    CHAR
    CHRANGE
    IN
    NOT_IN
    MATCH
    JUMP
    SPLIT
    SAVE
  Instr* = ref object
    case insType*: InstrType
    of CHAR:
      ch*: Rune
    of CHRANGE:
      rst*: Rune
      re*: Rune
    of IN:
      ichset*: seq[Rune]
    of NOT_IN:
      nchset*: seq[Rune]
    of MATCH:
      tag*: int
    of JUMP:
      offset*: int
    of SPLIT:
      x*: int
      y*: int
    of SAVE:
      svindex*: int

proc `$`*(x: Instr): string =
  return case x.insType:
    of CHAR: "CHAR " & $x.ch
    of CHRANGE: "CHRANGE " & $x.rst & ", " & $x.re
    of IN: "IN " & $x.ichset
    of NOT_IN: "NOT_IN " & $x.nchset
    of MATCH: "MATCH " & $x.tag
    of JUMP: "JUMP " & $x.offset
    of SPLIT: "SPLIT " & $x.x & ", " & $x.y
    of SAVE: "SAVE " & $x.svindex
    
