import std/unicode

type
  InstrType* = enum
    CHAR
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
    of IN:
      ichset*: seq[Rune]
      ichrange*: seq[(Rune, Rune)]
    of NOT_IN:
      nchset*: seq[Rune]
      nchrange*: seq[(Rune, Rune)]
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
    of IN: "IN " & $x.ichset & ";" & $x.ichrange
    of NOT_IN: "NOT_IN " & $x.nchset & ";" & $x.nchrange
    of MATCH: "MATCH " & $x.tag
    of JUMP: "JUMP " & $x.offset
    of SPLIT: "SPLIT " & $x.x & ", " & $x.y
    of SAVE: "SAVE " & $x.svindex
    
