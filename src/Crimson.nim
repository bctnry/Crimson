import regexdef
import regexcompile
import instrdef
import progcompile
import progdef
import std/options
import std/unicode


type
  Token = ref object
    line: uint
    col: uint
    st: uint
    e: uint
    ttype: int

proc `$`(x: Token): string =
  return "Token(" & $x.st & "," & $x.e & "," & $x.ttype & ")"

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
  
proc runVM(prog: seq[Instr], str: string, stp: uint): Option[Token] =
  var threadPool: array[2, seq[Thread]] = [@[], @[]]
  var poolIndex: int = 0
  var save: array[2, uint] = [stp, stp]
  threadPool[poolIndex].add(Thread(pc: 0, strindex: 0, line: 0, col: 0))
  let strLen = uint(str.len())
  var e: uint = stp
  var matched = false
  var ttype: int
  var line: uint = 0
  var col: uint = 0
  while threadPool[poolIndex].len() > 0 or threadPool[1-poolIndex].len() > 0:
    var j = 0
    while true:
      let currentQueueIndex = threadPool[poolIndex].len()
      if j >= currentQueueIndex: break
      let thread = threadPool[poolIndex][j]
      # echo "take thread ", thread.pc
      let instr = prog[thread.pc]
      block chk:
        case instr.instype:
          of CHAR:
            # NOTE: forks created by SPLIT (from the last round) lives in threadPool[poolIndex]
            #       has a fixed priority (SPLIT high, low). for SPLITs compiled from UNION this
            #       shouldn't be a problem (properly written regexes should have disjoint subexpr),
            #       and this enables us to control which path we prefer (thus we are able to
            #       control greedy vs. non-greedy.). this code will cut off low priority thread
            #       when high priority thread matches, but low priority thread would never cut
            #       off high priority thread because they've already been processed at this point.
            # TODO: test this; this might be wrong.
            # thread.strindex always uses byte index instead of rune index in the vm.
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
            # echo "match found. throw away: ", threadPool[poolIndex]
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
            # echo "split thread: ", targetX, " ", targetY
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


  
let z1 = Regex(regexType: CHARACTER, ch: "a".runeAt(0)).compileRegex(1)
let z3 = Regex(regexType: CONCAT, cbody: @[
  Regex(regexType: UNION, ubody: @[
    Regex(regexType: CHARACTER, ch: "你".runeAt(0)),
    Regex(regexType: CHARACTER, ch: "a".runeAt(0)),
    Regex(regexType: CHARACTER, ch: "b".runeAt(0)),
    Regex(regexType: CHARACTER, ch: "c".runeAt(0)),
  ]),
  Regex(regexType: UNION, ubody: @[
    Regex(regexType: CHARACTER, ch: "d".runeAt(0)),
    Regex(regexType: CHARACTER, ch: "e".runeAt(0)),
    Regex(regexType: CHARACTER, ch: "f".runeAt(0)),
  ])
]).compileRegex(1)
let z4 = Regex(regexType: PLUS, pgreedy: true, pbody: 
  Regex(regexType: CHARACTER, ch: "a".runeAt(0))
).compileRegex(1)
let z4r = Regex(regexType: PLUS, pgreedy: true, pbody: 
  Regex(regexType: CHARACTER, ch: "a".runeAt(0))
)
let z4r2 = Regex(regexType: PLUS, pgreedy: true, pbody:
  Regex(regexType: UNION, ubody: @[
    Regex(regexType: CHARACTER, ch: "b".runeAt(0)),
    Regex(regexType: CHARACTER, ch: "c".runeAt(0)),
  ])
)
# # echo z1
# echo runVM(z1, "a", 0)
# echo runVM(z1, "b", 0)
# # echo z3
# echo runVM(z3, "你d", 0)
# echo runVM(z3, "ae", 0)
# echo runVM(z3, "af", 0)
# echo runVM(z3, "bd", 0)
# echo runVM(z3, "be", 0)
# echo runVM(z3, "bf", 0)
# echo runVM(z3, "cd", 0)
# echo runVM(z3, "ce", 0)
# echo runVM(z3, "cf", 0)
# echo runVM(z3, "ac", 0)
# # echo z4
# echo runVM(z4, "a", 0)
# echo runVM(z4, "aa", 0)
# echo runVM(z4, "aaa", 0)
# echo runVM(z4, "b", 0)

echo compileProgram(@[
# discard compileProgram(@[
  # TokenDecl(precond: none(seq[string]),
  makeTokenDecl("BLAH", z4r),
  makeTokenDecl("ZSSZ", z4r2),
])

