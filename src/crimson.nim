import std/syncio
import std/cmdline
import std/paths
import std/strutils
import std/tables
import std/strformat
import progcompile
import progdef
import regexdef
import parser

let resDict: TableRef[string, Regex] = newTable[string, Regex]()
var errorList: seq[(string, string)] = @[]

# check if any of them is empty.
proc couldRegexBeEmpty(x: Regex): bool =
  case x.regexType:
    of EMPTY:
      return true
    of STAR:
      return true
    of OPTIONAL:
      return true
    of CONCAT:
      var r = true
      for k in x.cbody:
        r = r and k.couldRegexBeEmpty
      return r
    of UNION:
      var r = false
      for k in x.ubody:
        r = r or k.couldRegexBeEmpty
      return r
    of NAME_REF:
      return resDict[x.name].couldRegexBeEmpty
    of CAPTURE:
      return x.capbody.couldRegexBeEmpty
    else:
      return false
  
# name ref check.
proc nameRefCheckRegex(x: Regex, r: string, ): void =
  case x.regexType:
    of STAR:
      x.sbody.nameRefCheckRegex(r)
    of PLUS:
      x.pbody.nameRefCheckRegex(r)
    of OPTIONAL:
      x.obody.nameRefCheckRegex(r)
    of CONCAT:
      for k in x.cbody:
        k.nameRefCheckRegex(r)
    of UNION:
      for k in x.ubody:
        k.nameRefCheckRegex(r)
    of CAPTURE:
      x.capbody.nameRefCheckRegex(r)
    of NAME_REF:
      if not resDict.hasKey(x.name):
        errorList.add((r, x.name))
    else:
      discard

proc main(): void =
  let f = open(paramStr(1), fmRead)
  let s = f.readAll()
  f.close()
   
  let res = s.parseLexerSource
  for k in res:
    resDict[k.name] = k.regex
  for k in res:
    k.regex.nameRefCheckRegex(k.name)
    
  if errorList.len > 0:
    for e in errorList:
      stderr.writeLine(&"Error: name not found at definition of {e[0]}: {e[1]}")
    raise newException(Defect, "")
    
  var couldBeEmptyList: seq[string] = @[]
  for k in res:
    if k.regex.couldRegexBeEmpty:
      couldBeEmptyList.add(k.name)
    if couldBeEmptyList.len > 0:
      for k in couldBeEmptyList:
        stderr.writeLine(&"Warning: definition of {k} could match empty strings; this could lead to unexpected effects")
    
  let outputFileName = paramStr(1).Path.extractFilename.string.replace(".", "_") & ".nim"
  let outputPath = paramStr(1).Path.parentDir / outputFileName.Path
  
  let compiled = res.compileProgram
  let r = open(outputPath.string, fmWrite)
  r.write(compiled)
  r.flushFile()
  r.close()

when isMainModule:
  main()

