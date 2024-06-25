# NOTE: Generated using Crimson. DO NOT DIRECTLY EDIT THIS (UNLESS YOU KNOW WHAT YOU'RE DOING)

import std/options
import std/unicode
import std/tables

type
  TokenType* = enum
    TOKEN_TEST2
    TOKEN_TEST3
type
  Token* = ref object
    line*: uint
    col*: uint
    st*: uint
    e*: uint
    ttype*: TokenType
    capture*: TableRef[string,tuple[st: uint, e: uint]]

type
  InstrType = enum
    CHAR
    IN
    NOT_IN
    MATCH
    JUMP
    SPLIT
    SAVE
  Instr = ref object
    case insType: InstrType
    of CHAR:
      ch: Rune
    of IN:
      ichset: seq[Rune]
      ichrange: seq[(Rune, Rune)]
    of NOT_IN:
      nchset: seq[Rune]
      nchrange: seq[(Rune, Rune)]
    of MATCH:
      tag: TokenType
    of JUMP:
      offset: int
    of SPLIT:
      target: seq[int]
    of SAVE:
      svindex: int

type
  Thread = ref object
    pc: int
    strindex: uint
    save: seq[uint]
    line: uint
    col: uint

let NEWLINE = "\n\v\f".toRunes
proc combineToken(stp: uint, e: uint, ttype: TokenType, line: uint, col: uint, save: seq[uint]): Token =
  return Token(line: line, col: col, st: stp, e: e, ttype: ttype)
proc runVM(prog: seq[Instr], str: string, stp: uint, line: uint, col: uint): Option[Token] =
  var threadPool: array[2, seq[Thread]] = [@[], @[]]
  var poolIndex: int = 0
  var endThread: Thread = nil
  threadPool[poolIndex].add(Thread(pc: 0, strindex: stp, line: line, col: col))
  let strLen = uint(str.len())
  var e: uint = stp
  var matched = false
  var ttype: TokenType
  var line: uint
  var col: uint
  while threadPool[poolIndex].len() > 0 or threadPool[1-poolIndex].len() > 0:
    var j = 0
    while true:
      let currentQueueIndex = threadPool[poolIndex].len()
      if j >= currentQueueIndex: break
      let thread = threadPool[poolIndex][j]
      let instr = prog[thread.pc]
      block chk:
        case instr.instype:
          of CHAR:
            if thread.strindex == strLen or instr.ch != str.runeAt(thread.strindex): break chk
            if str.runeAt(thread.strindex) in NEWLINE:
              thread.line += 1
              thread.col = 0
            else:
              thread.col += 1
            thread.pc += 1
            thread.strindex += uint(str.runeLenAt(thread.strindex))
            threadPool[1-poolIndex].add(thread)
          of IN:
            var chkres = thread.strindex < strLen
            if not chkres: break chk
            let currentRune = str.runeAt(thread.strindex)
            chkres = currentRune in instr.ichset
            for z in instr.ichrange:
              chkres = chkres or (z[0] <=% currentRune and currentRune <=% z[1])
            if not chkres: break chk
            if str.runeAt(thread.strindex) in NEWLINE:
              thread.line += 1
              thread.col = 0
            else:
              thread.col += 1
            thread.pc += 1
            thread.strindex += uint(str.runeLenAt(thread.strindex))
            threadPool[1-poolIndex].add(thread)
          of NOT_IN:
            var chkres = thread.strindex < strLen
            if not chkres: break chk
            let currentRune = str.runeAt(thread.strindex)
            chkres = currentRune in instr.nchset
            for z in instr.nchrange:
              chkres = chkres or (z[0] <=% currentRune and currentRune <=% z[1])
            if chkres: break chk
            if str.runeAt(thread.strindex) in NEWLINE:
              thread.line += 1
              thread.col = 0
            else:
              thread.col += 1
            thread.pc += 1
            thread.strindex += uint(str.runeLenAt(thread.strindex))
            threadPool[1-poolIndex].add(thread)
          of MATCH:
            matched = true
            ttype = instr.tag
            e = thread.strindex
            line = thread.line
            col = thread.col
            endThread = thread
            while threadPool[poolIndex].len() > 0: discard threadPool[poolIndex].pop()
          of JUMP:
            let target = thread.pc+instr.offset
            thread.pc = target
            threadPool[1-poolIndex].add(thread)
          of SPLIT:
            for offset in instr.target:
              let t = thread.pc + offset
              var newthSave: seq[uint] = @[]
              for k in thread.save: newthSave.add(k)
              var newth = Thread(pc: t, strindex: thread.strindex, line: thread.line, col: thread.col, save: newthSave)
              threadPool[1-poolIndex].add(newth)
          of SAVE:
            thread.save.add(thread.strindex)
            thread.pc += 1
            threadPool[1-poolIndex].add(thread)
      j += 1
    while threadPool[poolIndex].len() > 0: discard threadPool[poolIndex].pop()
    poolIndex = 1-poolIndex
  if matched:
    return some(combineToken(stp, e, ttype, line, col, endThread.save))
  else:
    return none(Token)

let machine = @[
  Instr(insType: SPLIT, target: @[1, 10]),
  Instr(insType: SAVE, svindex: 0),
  Instr(insType: NOT_IN, nchset: "".toRunes, nchrange: @[("\x63".toRunes[0], "\x66".toRunes[0])]),
  Instr(insType: SPLIT, target: @[1, 4]),
  Instr(insType: CHAR, ch: "\x61".toRunes[0]),
  Instr(insType: SPLIT, target: @[-1, 1]),
  Instr(insType: JUMP, offset: -3),
  Instr(insType: SAVE, svindex: 1),
  Instr(insType: MATCH, tag: TOKEN_TEST2),
  Instr(insType: JUMP, offset: 14),
  Instr(insType: SAVE, svindex: 0),
  Instr(insType: CHAR, ch: "\x63".toRunes[0]),
  Instr(insType: CHAR, ch: "\x64".toRunes[0]),
  Instr(insType: CHAR, ch: "\x65".toRunes[0]),
  Instr(insType: NOT_IN, nchset: "".toRunes, nchrange: @[("\x63".toRunes[0], "\x66".toRunes[0])]),
  Instr(insType: SPLIT, target: @[1, 4]),
  Instr(insType: CHAR, ch: "\x61".toRunes[0]),
  Instr(insType: SPLIT, target: @[-1, 1]),
  Instr(insType: JUMP, offset: -3),
  Instr(insType: SPLIT, target: @[-5, 1]),
  Instr(insType: CHAR, ch: "\x66".toRunes[0]),
  Instr(insType: SAVE, svindex: 1),
  Instr(insType: MATCH, tag: TOKEN_TEST3),
]

proc lex*(x: string): seq[Token] =
  var res: seq[Token] = @[]
  var line: uint = 0
  var col: uint = 0
  var stp: uint = 0
  let lenx = x.len.uint
  while stp < lenx:
    let z = runVM(machine, x, stp, line, col)
    if z.isNone():
      raise newException(ValueError, "Tokenizing fail at line " & $line & " col " & $col)
    let t = z.get()
    res.add(t)
    line = t.line
    col = t.col
    stp = t.e
  return res
