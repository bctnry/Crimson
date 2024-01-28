import progdef
import regexdef
import regexcompile
import instrdef
import std/unicode
import std/sequtils
import std/tables
import std/strformat
import std/bitops

proc pass1(x: Program): Program =
  var d: TableRef[string,seq[Regex]] = newTable[string,seq[Regex]]()
  for decl in x:
    if not d.hasKey(decl.name): d[decl.name] = @[]
    d[decl.name].add(decl.regex)
  var res: Program = @[]
  for tokenName, tokenRegexList in d.pairs:
    res.add(makeTokenDecl(tokenName,if tokenRegexList.len <= 1:
                                      tokenRegexList[0]
                                    else:
                                      Regex(regexType: UNION, ubody: tokenRegexList)))
  return res

proc charToHex(x: char): string =
  let z = x.ord
  let a = z.bitand(0xf0).uint8.rotateRightBits(4)
  let b = z.bitand(0x0f).uint8
  let ac = if a >= 0x0a: ('a'.ord+a).chr else: ('0'.ord+a).chr
  let bc = if b >= 0x0a: ('a'.ord+b).chr else: ('0'.ord+b).chr
  return ac & bc
  
proc encodeRune(x: Rune): string =
  var res: string = ""
  let z = x.toUTF8
  for k in z:
    res &= &"\\x{k.charToHex}"
  return res
  
proc encode(x: Instr, intToTokenTypeMapping: TableRef[int,string]): string =
  case x.insType:
    of CHAR:
      &"Instr(insType: CHAR, ch: \"{x.ch.encodeRune}\".toRunes[0])"
    of CHRANGE:
      &"Instr(insType: CHRANGE, rst: \"{x.rst.encodeRune}\".toRunes[0], re: \"{x.re.encodeRune}\".toRunes[0])"
    of IN:
      let chsetstr = x.ichset.mapIt(it.encodeRune).join("")
      &"Instr(insType: IN, ichset: \"{chsetstr}\".toRunes)"
    of NOT_IN:
      let chsetstr = x.ichset.mapIt(it.encodeRune).join("")
      &"Instr(insType: NOT_IN, ichset: \"{chsetstr}\".toRunes)"
    of MATCH:
      &"Instr(insType: MATCH, tag: TOKEN_{intToTokenTypeMapping[x.tag]})"
    of JUMP:
      &"Instr(insType: JUMP, offset: {x.offset})"
    of SPLIT:
      &"Instr(insType: SPLIT, x: {x.x}, y: {x.y})"
    of SAVE:
      &"Instr(insType: SAVE, svindex: {x.svindex})"

# NOTE: this is a direct copy of the compiling of UNION in regexcompile;
#       the explanation is also there too.
proc combineProgram(x: seq[seq[Instr]]): seq[Instr] =
  var res: seq[Instr] = @[]
  let ubodyLen = x.len()
  if ubodyLen <= 0:
    return @[]
  # NOTE: we treat a union length of 1 as the regexp itself;
  #       the regexp (|E) is expressed with Union(Empty,E).
  elif ubodyLen <= 1:
    return x[0]
  else:
    var rollingSumBase = 0
    var rollingSum: seq[int] = @[]
    var lengths: seq[int] = @[]
    var buf: seq[seq[Instr]] = @[]
    for i in 0..<ubodyLen:
      let r = x[i]
      lengths.add(r.len())
      buf.add(r)
      rollingSum.add(rollingSumBase + r.len())
      rollingSumBase = rollingSum[i]
    for i in 0..<ubodyLen-1:
      res.add(Instr(insType: SPLIT, x: 1, y: 2+lengths[i]))
      res &= buf[i]
      res.add(Instr(
        insType: JUMP,
        offset: 1+(ubodyLen-i-2)*2+rollingSum[rollingSum.len()-1]-rollingSum[i]
      ))
      res &= buf[ubodyLen-1]
  return res

proc compileProgram*(x: Program): string =
  var res: string = ""
  let program = x.pass1
  let tokenNameList = program.mapIt(it.name)
  let intToTokenNameMapping = newTable[int,string]()
  for i in 0..<program.len:
    intToTokenNameMapping[i] = program[i].name
  res &= """# NOTE: Generated using Crimson. DO NOT DIRECTLY EDIT THIS (UNLESS YOU KNOW WHAT YOU'RE DOING)

import std/strformat
import std/options
import std/unicode
import std/tables

type
  TokenType* = enum
"""
  for tt in tokenNameList:
    res &= &"    TOKEN_{tt}\n"
  res &= """
type
  Token* = ref object
    line: uint
    col: uint
    st: uint
    e: uint
    ttype*: TokenType

proc `$`(x: Token): string =
  return "Token(" & $x.st & "," & $x.e & "," & $x.ttype & ")"

type
  InstrType = enum
    CHAR
    CHRANGE
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
    of CHRANGE:
      rst: Rune
      re: Rune
    of IN:
      ichset: seq[Rune]
    of NOT_IN:
      nchset: seq[Rune]
    of MATCH:
      tag: TokenType
    of JUMP:
      offset: int
    of SPLIT:
      x: int
      y: int
    of SAVE:
      svindex: int

type
  Thread = ref object
    pc: int
    strindex: uint
    save: array[20, uint]
    line: uint
    col: uint
proc `$`(x: Thread): string =
  return "Thread(" & $x.pc & "," & $x.strindex & "," & ")"

let NEWLINE = "\n\v\f".toRunes
  
proc runVM(prog: seq[Instr], str: string, stp: uint, line: uint, col: uint): Option[Token] =
  var threadPool: array[2, seq[Thread]] = [@[], @[]]
  var poolIndex: int = 0
  var save: array[2, uint] = [stp, stp]
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
          of CHRANGE:
            if thread.strindex == strLen or str.runeAt(thread.strindex) <% instr.rst or instr.re <% str.runeAt(thread.strindex): break chk
            if str.runeAt(thread.strindex) in NEWLINE:
              thread.line += 1
              thread.col = 0
            else:
              thread.col += 1
            thread.pc += 1
            thread.strindex += uint(str.runeLenAt(thread.strindex))
            threadPool[1-poolIndex].add(thread)
          of IN:
            if thread.strindex == strLen or not (str.runeAt(thread.strindex) in instr.ichset): break chk
            if str.runeAt(thread.strindex) in NEWLINE:
              thread.line += 1
              thread.col = 0
            else:
              thread.col += 1
            thread.pc += 1
            thread.strindex += uint(str.runeLenAt(thread.strindex))
            threadPool[1-poolIndex].add(thread)
          of NOT_IN:
            if thread.strindex == strLen or str.runeAt(thread.strindex) in instr.ichset: break chk
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
            while threadPool[poolIndex].len() > 0: discard threadPool[poolIndex].pop()
          of JUMP:
            let target = thread.pc+instr.offset
            thread.pc = target
            threadPool[1-poolIndex].add(thread)
          of SPLIT:
            let targetX = thread.pc+instr.x
            let targetY = thread.pc+instr.y
            thread.pc = targetX
            threadPool[1-poolIndex].add(thread)
            var newth = Thread(pc: targetY, strindex: thread.strindex, line: thread.line, col: thread.col)
            for z in 0..<20: newth.save[z] = thread.save[z]
            threadPool[1-poolIndex].add(newth)
          of SAVE:
            thread.save[instr.svindex] = thread.strindex
            thread.pc += 1
            threadPool[1-poolIndex].add(thread)
      j += 1
    while threadPool[poolIndex].len() > 0: discard threadPool[poolIndex].pop()
    poolIndex = 1-poolIndex
  if matched:
    return some(Token(st: stp, e: e, ttype: ttype, line: line, col: col))
  else:
    return none(Token)

"""
  var compiledClauses: seq[seq[Instr]] = @[]
  for i in 0..<program.len:
    let clause = program[i]
    let z = clause.regex.compileRegex(i)
    compiledClauses.add(z)
  let bundleVMProg: seq[Instr] = combineProgram(compiledClauses)
  res &= "let machine = @[\n"
  for i in bundleVMProg:
    res &= &"  {i.encode(intToTokenNameMapping)},\n"
  res &= "]\n\n"
  res &= """
proc lex*(x: string): seq[Token] =
  var res: seq[Token] = @[]
  var line: uint = 0
  var col: uint = 0
  var stp: uint = 0
  let lenx = x.len.uint
  while stp < lenx:
    let z = runVM(machine, x, stp, line, col)
    if z.isNone():
      raise newException(ValueError, &"Tokenizing fail at line {line} col {col}")
    let t = z.get()
    res.add(t)
    line = t.line
    col = t.col
    stp = t.e
  return res
"""
  
  return res
  


