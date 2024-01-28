import regexdef
import std/options
import std/strformat
import std/sequtils
import std/strutils

type
  # NOTE: not used. this was planned for the tag system, which was postponed
  #       for another time.
  TokenizerActionType* = enum
    TAG
    UNTAG
    TOGGLE
  TokenizerAction* = ref object
    taType*: TokenizerActionType
    tag*: string
    
  TokenDecl* = ref object
    precond: Option[seq[string]]
    name*: string
    regex*: Regex
    action: Option[seq[TokenizerAction]]

  Program* = seq[TokenDecl]

proc makeTokenDecl*(name: string, regex: Regex): TokenDecl =
  TokenDecl(precond: none(seq[string]),
            name: name,
            regex: regex,
            action: none(seq[TokenizerAction]))
  
proc `$`*(x: TokenizerActionType): string =
  case x:
    of TAG: "TAG"
    of UNTAG: "UNTAG"
    of TOGGLE: "TOGGLE"

proc `$`*(x: TokenizerAction): string =
  let a = case x.taType:
            of TAG: "+"
            of UNTAG: "-"
            of TOGGLE: "~"
  return a & x.tag

proc `$`*(x: TokenDecl): string =
  let precondStr = if x.precond.isNone(): "" else: "(" & x.precond.get.join(",") & ") "
  let actionStr = if x.action.isNone(): "" else: " {" & x.action.get.mapIt($it).join(",") & "}"
  return &"{precondstr}{x.name} = <REGEX>{actionStr}"

proc shouldTag*(x: string): TokenizerAction =
  TokenizerAction(taType: TAG, tag: x)

proc shouldNotTag*(x: string): TokenizerAction =
  TokenizerAction(taType: UNTAG, tag: x)

proc shouldToggle*(x: string): TokenizerAction =
  TokenizerAction(taType: TOGGLE, tag: x)
  
