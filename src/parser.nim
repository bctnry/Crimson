import std/unicode
import std/options
import std/strformat
import progdef
import regexdef

# Program ::= TokenDecl*
# TokenDecl ::= "~"? NAME "=" "/" Regex "/" RetainingClause?
# NAME = /[a-zA-Z_][0-9a-zA-Z_]*/
# AtomicRegex ::= CharOrNormalEsc
#               | In
#               | NotIn
#               | "(?:" Regex ("|" Regex)* ")"
#               | "{" NAME "}"
# RegexSegment ::= AtomicRegex ("?" | "*" | "+" | "??" | "*?" | "+?")?
# RetainingClause ::= "{" NUMBER (":" NAME)? "}"
# Regex ::= RegexSegment+
# In ::= "[" (Range|CharOrInEsc) "]"
# NotIn ::= "[^" (Range|CharOrInEsc) "]"
# Range ::= CHAR "-" CHAR
# CharOrInEsc ::= NonInEscChar | Esc
# CharOrNormalEsc ::= NonNormalEscChar | Esc
# Esc ::= "\x" /[0-9a-fA-F][0-9a-fA-F]/
#       | "\u" /[0-9a-fA-F]+/
#       | "\s"    # whitespace
#       | "\b" | "\n" | "\t" | "\r" | "\f" | "\v"
#       | "\." | "\[" | "\\" | "\]" | "\(" | "\)" | "\*" | "\+" | "\?" | "\/"
# NonInEscChar = /[^\[\]\.\\]/
# NonNormalEscChar = /[^\.\*\?\[\]\\]/

type
  ParserState = ref object
    line: int
    col: int
    x: string
    stp: int

proc raiseErrorWithReason(x: ParserState, reason: string): void =
  raise newException(ValueError, &"({x.line},{x.col}) {reason}")
    
proc isNameHeadChar(x: char): bool =
  ('a' <= x and x <= 'z') or ('A' <= x and x <= 'Z') or x == '_'
proc isNameChar(x: char): bool =
  ('0' <= x and x <= '9') or x.isNameHeadChar
proc isDigit(x: char): bool =
  ('0' <= x and x <= '9')

proc takeName(x: ParserState): Option[string] =
  var i = x.stp
  let lenx = x.x.len
  if i < lenx and x.x[i].isNameHeadChar: i += 1
  else: return none(string)
  while i < lenx and x.x[i].isNameChar: i += 1
  let name = x.x[x.stp..<i]
  x.col += i-x.stp
  x.stp = i
  return some(name)

proc takeNumber(x: ParserState): Option[string] =
  var i = x.stp
  let lenx = x.x.len
  if i < lenx and x.x[i].isDigit: i += 1
  else: return none(string)
  while i < lenx and x.x[i].isDigit: i += 1
  let numstr = x.x[x.stp..<i]
  x.col += i - x.stp
  x.stp = i
  return some(numstr)
  
proc stringToInt(x: string): int =
  var res = 0
  var i = 0
  var lenx = x.len
  while i < lenx:
    res *= 10
    res += ord(x[i]) - ord('0')
    i += 1
  return res

proc skipWhite(x: ParserState): ParserState =
  var i = x.stp
  let lenx = x.x.len
  while i < lenx and x.x[i] in " \n\r\v\t\b\f":
    if x.x[i] in "\n\v\f":
      x.line += 1
      x.col = 0
    else:
      x.col += 1
    i += 1
  x.stp = i
  return x

proc expect(x: ParserState, pat: string): bool =
  let lenx = x.x.len
  if lenx-x.stp < pat.len: return false
  let prefix = x.x[x.stp..<x.stp+pat.len]
  if prefix != pat: return false
  for i in pat:
    if i in "\n\v\f":
      x.line += 1
      x.col = 0
    else:
      x.col += 1
  x.stp += pat.len
  return true

proc peek(x: ParserState, pat: string): bool = 
  let lenx = x.x.len
  if lenx-x.stp < pat.len: return false
  let prefix = x.x[x.stp..<x.stp+pat.len]
  if prefix != pat: return false
  return true

# expectNot cannot be simply defined as "not expect" because there's side effect involved.
proc expectNot(x: ParserState, pat: string): bool =
  let lenx = x.x.len
  if lenx-x.stp < pat.len: return true
  let prefix = x.x[x.stp..<x.stp+pat.len]
  if prefix != pat: return true
  for i in pat:
    if i in "\n\v\f":
      x.line += 1
      x.col = 0
    else:
      x.col += 1
  x.stp += pat.len
  return false

proc expectRange(x: ParserState, rst: Rune, re: Rune): Option[Rune] =
  let lenx = x.x.len
  if x.stp >= lenx: return none(Rune)
  let r = x.x.runeAt(x.stp)
  if rst <=% r and r <=% re:
    if x.x[x.stp] in "\n\v\f":
      x.line += 1
      x.col = 0
    else:
      x.col += x.x.runeLenAt(x.stp)
    let res = x.x.runeAt(x.stp)
    x.stp += x.x.runeLenAt(x.stp)
    return some(res)
  else: return none(Rune)

proc expectIn(x: ParserState, chset: seq[Rune]): Option[Rune] =
  let lenx = x.x.len
  if x.stp >= lenx: return none(Rune)
  let r = x.x.runeAt(x.stp)
  if not (r in chset): return none(Rune)
  if x.x[x.stp] in "\n\v\f":
    x.line += 1
    x.col = 0
  else:
    x.col += x.x.runeLenAt(x.stp)
  let res = x.x.runeAt(x.stp)
  x.stp += x.x.runeLenAt(x.stp)
  return some(res)

const zeroRune = "0".toRunes[0]
const nineRune = "9".toRunes[0]
const lowerARune = "a".toRunes[0]
const lowerFRune = "f".toRunes[0]
const upperARune = "A".toRunes[0]
const upperFRune = "F".toRunes[0]
proc expectHexDigit(x: ParserState): Option[int] =
  let lenx = x.x.len
  if x.stp >= lenx: return none(int)
  let r = x.x.runeAt(x.stp)
  if (zeroRune <=% r and r <=% nineRune) or (lowerARune <=% r and r <=% lowerFRune) or (upperARune <=% r and r <=% upperFRune):
    if x.x[x.stp] in "\n\v\f":
      x.line += 1
      x.col = 0
    else:
      x.col += x.x.runeLenAt(x.stp)
    let res = x.x.runeAt(x.stp)
    x.stp += x.x.runeLenAt(x.stp)
    return some(if zeroRune <=% r and r <=% nineRune:
                  r.ord - zeroRune.ord
                elif lowerARune <=% r and r <=% lowerFRune:
                  r.ord - lowerARune.ord + 10
                else:
                  r.ord - upperARune.ord + 10)
  else: return none(int)
proc parseSingleCharEsc(x: ParserState): Option[Rune] =
  if not x.expect("\\"): return none(Rune)
  if x.expect("x"):
    let digit1 = x.expectHexDigit
    let digit2 = x.expectHexDigit
    if digit1.isNone or digit2.isNone: return none(Rune)
    var z = ""
    z.add((digit1.get*16+digit2.get).chr)
    return z.toRunes[0].some
  elif x.expect("u"):
    var codepoint = 0
    while true:
      let digit = x.expectHexDigit
      if digit.isNone: break
      codepoint *= 16
      codepoint += digit.get
    return cast[Rune](codepoint).some
  elif x.expect("b"): return some("\b".toRunes[0])
  elif x.expect("n"): return some("\n".toRunes[0])
  elif x.expect("t"): return some("\t".toRunes[0])
  elif x.expect("r"): return some("\r".toRunes[0])
  elif x.expect("f"): return some("\f".toRunes[0])
  elif x.expect("v"): return some("\v".toRunes[0])
  else:
    let chkres = x.expectIn(".[]()\\*+?/".toRunes)
    if chkres.isNone: return none(Rune)
    else: return some(chkres.get)

proc takeRune(x: ParserState): Option[Rune] =
  let lenx = x.x.len
  if x.stp >= lenx: return none(Rune)
  else:
    if x.x[x.stp] in "\n\f\v":
      x.line += 1
      x.col = 0
    else:
      x.col += x.x.runeLenAt(x.stp)
    let r = x.x.runeAt(x.stp)
    x.stp += x.x.runeLenAt(x.stp)
    return some(r)

proc parseInInner(x: ParserState): Option[(seq[Rune], seq[(Rune,Rune)])] =
  var chset: seq[Rune] = @[]
  var chrange: seq[(Rune, Rune)] = @[]
  while not x.peek("]"):
    if x.peek("\\"):
      let z = x.parseSingleCharEsc
      if z.isNone: x.raiseErrorWithReason("Invalid escape sequence")
      chset.add(z.get)
      continue
    let ch = x.takeRune
    if ch.isNone: x.raiseErrorWithReason("Invalid sequence")
    if x.peek("-"):  # range.
      discard x.expect("-")
      let ch2 = x.takeRune
      if ch2.isNone: x.raiseErrorWithReason("Invalid range sequence")
      chrange.add((ch.get, ch2.get))
    else:
      chset.add(ch.get)
  return some((chset, chrange))
  
proc parseRegexSegmentList(x: ParserState): seq[Regex]
proc parseAtomicRegex(x: ParserState): Option[Regex] =
  let lenx = x.x.len
  if x.stp >= lenx: return none(Regex)
  var i = x.stp
  case x.x[i]:
    of '[':  # In & NotIn
      i += 1
      x.stp += 1
      x.col += 1
      if i >= lenx: x.raiseErrorWithReason("Right bracket required but none found.")
      let reverse = x.x[i] == '^'
      if x.x[i] == '^':
        i += 1
        x.stp = i
        x.col += 1
      let z = x.parseInInner
      if z.isNone: x.raiseErrorWithReason("Invalid syntax for character set")
      if not x.expect("]"): x.raiseErrorWithReason("Right bracket required but none found.")
      return some(if reverse:
                    Regex(regexType: REGEX_NOT_IN, not_in_chset: z.get[0], not_in_chrange: z.get[1])
                  else:
                    Regex(regexType: REGEX_IN, in_chset: z.get[0], in_chrange: z.get[1]))
    of '\\':  # NormalEsc
      let z = x.parseSingleCharEsc
      if z.isNone: x.raiseErrorWithReason("Invalid escape sequence")
      return some(Regex(regexType: CHARACTER, ch: z.get))
    of '(':  # Grouping
      if not x.expect("(?:"): x.raiseErrorWithReason("Invalid syntax for grouping")
      var r: seq[Regex] = @[]
      for k in x.parseRegexSegmentList: r.add(k)
      while not x.peek(")"):
        if not x.expect("|"): break
        let x2 = x.parseRegexSegmentList
        for k in x2: r.add(k)
      if not x.expect(")"): x.raiseErrorWithReason("Right parenthesis required but none found.")
      return some(Regex(regextype: UNION, ubody: r))
    of '/':  # end of regex.
      return none(Regex)
    of ')':  # end of group.
      return none(Regex)
    of '|':  # end of branch.
      return none(Regex)
    of '{':  # name ref.
      i += 1
      x.stp += 1
      x.col += 1
      let n = x.skipWhite.takeName
      if n.isNone: x.raiseErrorWithReason("Invalid syntax for name reference")
      if not x.skipWhite.expect("}"):
        x.raiseErrorWithReason("Invalid syntax for name reference")
      return some(Regex(regexType: NAME_REF, name: n.get))
    else:  # Char.
      let res = some(Regex(regexType: CHARACTER, ch: x.x.runeAt(x.stp)))
      if x.x[x.stp] in "\n\v\f":
        x.line += 1
        x.col = 0
      else:
        x.col += 1
      x.stp += x.x.runeLenAt(x.stp)
      return res
  
proc parseRegexSegment(x: ParserState): Option[Regex] =
  let atomicRegex = x.parseAtomicRegex
  if atomicRegex.isNone: return none(Regex)
  let lenx = x.x.len
  if x.stp >= lenx: return atomicRegex
  var res = atomicRegex.get
  case x.x[x.stp]:
    of '*':
      x.col += 1
      x.stp += 1
      var greedy = true
      if x.stp < lenx and x.x[x.stp] == '?':
        x.col += 1
        x.stp += 1
        greedy = false
      res = Regex(regexType: STAR, sbody: res, sgreedy: greedy)
    of '+':
      x.col += 1
      x.stp += 1
      var greedy = true
      if x.stp < lenx and x.x[x.stp] == '?':
        x.col += 1
        x.stp += 1
        greedy = false
      res = Regex(regexType: PLUS, pbody: res, pgreedy: greedy)
    of '?':
      x.col += 1
      x.stp += 1
      var greedy = true
      if x.stp < lenx and x.x[x.stp] == '?':
        x.col += 1
        x.stp += 1
        greedy = false
      res = Regex(regexType: OPTIONAL, obody: res, ogreedy: greedy)
    else:
      discard
  return some(res)

proc parseRegexSegmentList(x: ParserState): seq[Regex] =
  var res: seq[Regex] = @[]
  while true:
    let this = x.parseRegexSegment
    if this.isNone: break
    res.add(this.get)
  return res
  
proc parseRegex(x: ParserState): Regex =
  if not x.skipWhite.expect("/"): x.raiseErrorWithReason("Slash required but none found.")
  var res: seq[Regex] = @[]
  while true:
    let this = x.parseRegexSegment
    if this.isNone: break
    res.add(this.get)
  if not x.expect("/"): x.raiseErrorWithReason("Slash required but none found.")
  if res.len <= 0: return Regex(regexType: EMPTY)
  else: return Regex(regexType: CONCAT, cbody: res)

proc parseRetainingPair(x: ParserState): Option[TokenDeclRetaining] =
  let groupIdStr = x.skipWhite.takeNumber
  if groupIdStr.isNone: return none(TokenDeclRetaining)
  let groupId = groupIdStr.get.stringToInt
  if not x.expect(":"): return some((groupId: groupId, groupName: ""))
  let groupName = x.takeName
  return some((groupId: groupId, groupName: if groupName.isNone: "" else: groupName.get))

proc parseRetainingClause(x: ParserState): Option[seq[TokenDeclRetaining]] =
  if not x.skipWhite.expect("{"): return none(seq[TokenDeclRetaining])
  var retainingClauseList: seq[TokenDeclRetaining] = @[]
  let z = x.skipWhite.parseRetainingPair
  if not z.isSome:
    if not x.expect("}"): x.raiseErrorWithReason("Group saving specification or right brace required but none found.")
    else: return none(seq[TokenDeclRetaining])
  else:
    retainingClauseList.add(z.get)
  while not x.peek("}"):
    discard x.skipWhite
    if x.expect("}"): return some(retainingClauseList)
    if not x.skipWhite.expect(","): x.raiseErrorWithReason("Comma required but none found")
    let z = x.skipWhite.parseRetainingPair
    if not z.isSome:
      if not x.skipWhite.expect("}"): x.raiseErrorWithReason("Group saving specification or right brace required but none found.")
      else: return some(retainingClauseList)
    else:
      retainingClauseList.add(z.get)
  discard x.skipWhite.expect("}")
  return some(retainingClauseList)
  
proc parseClause(x: ParserState): Option[TokenDecl] =
  var exported: bool = true
  if x.skipWhite.expect("~"): exported = false
  let name = x.skipWhite.takeName
  if name.isNone: return none(TokenDecl)
  if not x.skipWhite.expect("="): x.raiseErrorWithReason("Equal sign required but none found.")
  let regex = x.skipWhite.parseRegex
  let retainingClause = x.skipWhite.parseRetainingClause
  return some(makeTokenDecl(name.get, regex, if retainingClause.isSome: retainingClause.get else: @[], exported))
  
proc parseLexerSource*(x: string): Program =
  var res: Program = @[]
  var st = ParserState(line: 0, col: 0, x: x, stp: 0)
  while true:
    let z = st.parseClause
    if z.isNone: break
    res.add(z.get)
  return res
    
  
  
