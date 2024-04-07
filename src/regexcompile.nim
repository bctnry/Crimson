import regexdef
import instrdef

## The compiler presented here is based on one of my blogpost:
##
##     https://sebastian.graphics/blog/compiling-regular-expressions.html
##
## which is in turn based on:
##
##     https://swtch.com/~rsc/regexp/regexp2.html
##
proc compileRegexMain(x: Regex): seq[Instr] =
  var res: seq[Instr] = @[]
  case x.regexType:
    of EMPTY: discard nil
    of CHARACTER:
      res.add(Instr(insType: CHAR, ch: x.ch))
    of STAR:
      let e = compileRegexMain(x.sbody)
      let xoff = if x.sgreedy: 1 else: e.len()+1
      let yoff = if x.sgreedy: e.len()+1 else: 1
      res.add(Instr(insType: SPLIT, target: @[xoff, yoff]))
      res &= e
    of PLUS:
      let e = compileRegexMain(x.pbody)
      let xoff = if x.pgreedy: -e.len() else: 1
      let yoff = if x.pgreedy: 1 else: -e.len()
      res &= e
      res.add(Instr(insType: SPLIT, target: @[xoff, yoff]))
    of OPTIONAL:
      let e = compileRegexMain(x.obody)
      let xoff = if x.ogreedy: 1 else: 1+e.len()
      let yoff = if x.ogreedy: 1+e.len() else: 1
      res.add(Instr(insType: SPLIT, target: @[xoff, yoff]))
      res &= e
      res.add(Instr(insType: JUMP, offset: -1-e.len()))
    of UNION:
      let ubodyLen = x.ubody.len()
      if ubodyLen <= 0:
        discard nil
      # NOTE: we treat a union length of 1 as the regexp itself;
      #       the regexp (|E) is expressed with Union(Empty,E).
      elif ubodyLen <= 1:
        res &= compileRegexMain(x.ubody[0])
      #  this part is kinda hard to explain. first consider the case (e0|e1).
      #  the output would be:
      #      SPLIT +1, +1+len(e0)
      #      (e0)
      #      JMP +1+len(e1)
      #      (e1)
      #  now consider the case (e0|e1|e2):
      #      SPLIT +1, +1+len(e0)+1, +1+len(e0)+1+len(e1)+1
      #      (e0)
      #      JMP +1+A
      #          (e1)
      #          JMP +1+B
      #          (e2)
      #  B is obviously len(e2); but A should be len(e1)+1+len(e2).
      #  now consider the case (e0|e1|e2|e3):
      #      SPLIT +1, +1+len(e0)+1, +1+len(e0)+1+len(e1)+1, +1+len(e0)+1+len(e1)+1+len(e2)+1, +1+len(e0)+1+len(e1)+1+len(e2)+1+len(e3)
      #      (e0)
      #      JMP +1+A
      #      (e1)
      #      JMP +1+B
      #      (e2)
      #      JMP +1+C
      #      (e3)
      #  C is obviously len(e3), B should be len(e2)+1+len(e3) and A should be len(e1)+1+len(e2)+1+len(e3),
      #  so the JMP instructions would be:
      #      JMP +1+len(e1)+1+len(e2)+1+len(e3)
      #      JMP +1+len(e2)+1+len(e3)
      #      JMP +1+len(e3)
      #  so for a union with n subexpr, the offset for the ith (starting from 0)
      #  JMP would be:
      #      +1 + n-i-2 + Sum{j=i+1 -> n-1, len(e_j)}
      #  e.g. the JMP offsets of a union with 3 subexpr would be:
      #      +1 + 1 + len(e1)+len(e2)
      #      +1 + len(e2)
      #  the JMP offsets of a union with 4 subexpr would be:
      #      +1 + 2 + len(e1)+len(e2)+len(e3)
      #      +1 + 1 + len(e2)+len(e3)
      #      +1 + len(e3)
      #  the offset for the SPLIT instruction is obviously:
      #      +1, +1+(len(e0)+1), +1+(len(e0)+1)+(len(e1)+1), +1+(len(e0)+1)+(len(e1)+1)+(len(e2)+1), ...
      #  so we need a rolling sum of x.e.
      else:
        var rollingSumBase = 0
        var rollingSum: seq[int] = @[]
        var lengths: seq[int] = @[]
        var buf: seq[seq[Instr]] = @[]
        for i in 0..<ubodyLen:
          let r = compileRegexMain(x.ubody[i])
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
    of CONCAT:
      for i in x.cbody:
        res &= compileRegexMain(i)
    of REGEX_IN:
      res.add(Instr(insType: IN, ichset: x.in_chset, ichrange: x.in_chrange))
    of REGEX_NOT_IN:
      res.add(Instr(insType: NOT_IN, nchset: x.not_in_chset, nchrange: x.not_in_chrange))
    of NAME_REF:
      # NOTE: name ref should be resolved before the compiling procedure is called.
      # if we somehow reached here we have an error.
      raise newException(ValueError, "Invalid state")
  return res

proc compileRegex*(x: Regex, tag: int): seq[Instr] =
  var r: seq[Instr] = @[]
  # r.add(Instr(insType: SAVE, svindex: 0))
  r &= compileRegexMain(x)
  # r.add(Instr(insType: SAVE, svindex: 1))
  r.add(Instr(insType: MATCH, tag: tag))
  return r

  
