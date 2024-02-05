import std/syncio
import std/cmdline
import std/paths
import std/strutils
import progcompile
# import progdef
# import regexdef

let f = open(paramStr(1), fmRead)
let s = f.readAll()
f.close()
import parser

let res = s.parseLexerSource

let outputFileName = paramStr(1).Path.extractFilename.string.replace(".", "_") & ".nim"
let outputPath = paramStr(1).Path.parentDir / outputFileName.Path

let compiled = res.compileProgram
let r = open(outputPath.string, fmWrite)
r.write(compiled)
r.flushFile()
r.close()

