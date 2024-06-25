import progdef
import regexcompile
import instrdef
import std/unicode
import std/sequtils
import std/tables
import std/strformat
import std/strutils
import std/bitops
import std/options
import regexdef

proc charToHex(x: char): string =
  let z = x.ord
  let a = z.bitand(0xf0).uint8.rotateRightBits(4)
  let b = z.bitand(0x0f).uint8
  let ac = if a >= 0x0a: ('a'.ord+a-10).chr else: ('0'.ord+a).chr
  let bc = if b >= 0x0a: ('a'.ord+b-10).chr else: ('0'.ord+b).chr
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
    of IN:
      let chsetstr = x.ichset.mapIt(it.encodeRune).join("")
      let chrangestr = x.ichrange.mapIt("(\""&it[0].encodeRune&"\".toRunes[0], \""&it[1].encodeRune&"\".toRunes[0])").join(",")
      &"Instr(insType: IN, ichset: \"{chsetstr}\".toRunes, ichrange: @[{chrangestr}])"
    of NOT_IN:
      let chsetstr = x.nchset.mapIt(it.encodeRune).join("")
      let chrangestr = x.nchrange.mapIt("(\""&it[0].encodeRune&"\".toRunes[0], \""&it[1].encodeRune&"\".toRunes[0])").join(",")
      &"Instr(insType: NOT_IN, nchset: \"{chsetstr}\".toRunes, nchrange: @[{chrangestr}])"
    of MATCH:
      &"Instr(insType: MATCH, tag: TOKEN_{intToTokenTypeMapping[x.tag]})"
    of JUMP:
      &"Instr(insType: JUMP, offset: {x.offset})"
    of SPLIT:
      &"Instr(insType: SPLIT, target: {x.target})"
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
    var targetOffsetList: seq[int] = @[1]
    for i in 0..<ubodyLen-1:
      targetOffsetList.add(targetOffsetList[^1]+1+lengths[i])
    res.add(Instr(insType: SPLIT, target: targetOffsetList))
    for i in 0..<ubodyLen-1:
      res &= buf[i]
      res.add(Instr(
        insType: JUMP,
        offset: 1+(ubodyLen-i-2)+rollingSum[rollingSum.len()-1]-rollingSum[i]
      ))
    res &= buf[ubodyLen-1]
  return res

proc allRefs(x: Regex): seq[string] =
  var res: seq[string] = @[]
  case x.regexType:
    of STAR:
      res &= x.sbody.allRefs
    of PLUS:
      res &= x.pbody.allRefs
    of OPTIONAL:
      res &= x.obody.allRefs
    of CONCAT:
      for k in x.cbody:
        res &= k.allRefs
    of UNION:
      for k in x.ubody:
        res &= k.allRefs
    of NAME_REF:
      res.add(x.name)
    else:
      discard
  res

proc detectRefLoop(name: string, body: Regex, pool: var seq[string], x: TableRef[string, Regex]): Option[string] =
  if name in pool: return some(name)
  if not x.hasKey(name): raise newException(ValueError, "Undefined name: "&name)
  let z = body.allRefs
  pool.add(name)
  for k in z:
    if not x.hasKey(k): raise newException(ValueError, "Undefined name reference for "&name&": "&k)
    let v = k.detectRefLoop(x[k], pool, x)
    if v.isSome(): return v
  discard pool.pop()
  none(string)

proc detectRefLoop(x: Program): Option[string] =
  var prog = newTable[string,Regex]()
  for k in x:
    prog[k.name] = k.regex
  var pool: seq[string] = @[]
  for k in x:
    let s = k.name.detectRefLoop(k.regex, pool, prog)
    if s.isSome(): return s
  return none(string)

proc flattenSingle(regex: Regex, x: TableRef[string, Regex]): Regex =
  if regex.regexType == NAME_REF: return x[regex.name]
  case regex.regexType:
    of STAR:
      regex.sbody = regex.sbody.flattenSingle(x)
    of PLUS:
      regex.pbody = regex.pbody.flattenSingle(x)
    of OPTIONAL:
      regex.obody = regex.obody.flattenSingle(x)
    of CONCAT:
      for i in 0..<regex.cbody.len:
        regex.cbody[i] = regex.cbody[i].flattenSingle(x)
    of UNION:
      for i in 0..<regex.ubody.len:
        regex.ubody[i] = regex.ubody[i].flattenSingle(x)
    else:
      discard
  return regex
  
proc flatten(x: Program): void =
  var prog = newTable[string,Regex]()
  for k in x:
    prog[k.name] = k.regex
  for k in x:
    k.regex = k.regex.flattenSingle(prog)

proc compileProgram*(x: Program): string =
  var res: string = ""
  var program = x
  let loopCheckRes = program.detectRefLoop
  if loopCheckRes.isSome():
    raise newException(ValueError, "Loop detected for "&loopCheckRes.get)
  program.flatten
  program = program.filterIt(it.exported)
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
"""
  var shouldCombine = false
  for k in program:
    if k.retaining.len > 0:
      shouldCombine = true
      break
  if shouldCombine:
    res &= """
let combineDict: Table[TokenType, Table[int, string]] = {
"""
    for k in program:
      let tt = k.name
      let retaining = k.retaining
      if retaining.len > 0:
        res &= &"  TOKEN_{tt}: " & "{\n"
        for r in retaining:
          res &= &"    {r.groupId}: \"{r.groupName}\",\n"
        res &= "  }.toTable,\n"
    res &= """
}.toTable
"""
  res &= """
proc combineToken(stp: uint, e: uint, ttype: TokenType, line: uint, col: uint, save: seq[uint]): Token =
"""
  if shouldCombine:
    res &= """
  if not combineDict.hasKey(ttype):
    return Token(line: line, col: col, st: stp, e: e, ttype: ttype)
  var captureDict: TableRef[string,tuple[st: uint, e: uint]] = newTable[string,tuple[st: uint, e: uint]]()
  let tokenCombineDict: Table[int, string] = combineDict[ttype]
  for i in tokenCombineDict.keys:
    captureDict[tokenCombineDict[i]] = (st: save[i*2], e: save[i*2+1])
  return Token(line: line, col: col, st: stp, e: e, ttype: ttype, capture: captureDict)
"""
  else:
    res &= """  return Token(line: line, col: col, st: stp, e: e, ttype: ttype)
"""

  res &= """
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
  


