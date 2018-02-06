llvm-hs-quote
=============

[![Build Status](https://travis-ci.org/llvm-hs/llvm-hs-quote.svg?branch=master)](https://travis-ci.org/llvm-hs/llvm-hs-quote)

`llvm-hs-quote` is a quasiquoting-library for llvm-hs.  It aims to support
all language constructs of LLVM.

`llvm-hs-quote` provides both quasiquotes and antiquotes. The following trivial
example uses both a quasiquote and an antiquote.

```haskell
alloc :: Type -> Instruction
alloc t = [lli|alloc $type:t|]
```

`LLVM.Quote.LLVM` provides quasiquoters or antiquoters for the following types.
For each type `a`, there's also a corresponding quasiquoter or antiquoter for
`CodeGen a` with an `M` added to the end of the name. For example,
`Definition`'s quasiquoter is `lldef`; the corresponding quasiquoter for
`CodeGen Definition` is `lldefM`. Its antiquoter is `$def:`; the corresponding
antiquoter for `CodeGen Definition` is `$defM:`.

AST Type                             | Quasiquoter | Antiquoter
-------------------------------------| ----------- | ----------
`LLVM.AST.Module`                    | `llmod`     |
`LLVM.AST.Definition`                | `lldef`     | `$def:`
`[LLVM.AST.Definition]`              |             | `$defs:`
`LLVM.AST.Global`                    | `llg`       |
`LLVM.AST.Instruction.Instruction`   | `lli`       | `$instr:`
`[LLVM.AST.Instruction.Instruction]` |             | `$instrs:`
`LLVM.AST.DataLayout.DataLayout`     |             | `$dl:`
`LLVM.Quote.AST.TargetTriple`        |             | `$tt:`
`LLVM.AST.BasicBlock`                |             | `$bb:`
`[LLVM.AST.BasicBlock]`              |             | `$bbs:`
`LLVM.AST.Type.Type`                 |             | `$type:`
`LLVM.AST.Operand.Operand`           |             | `$opr:`
`LLVM.AST.Constant.Constant`         |             | `$const:`
`LLVM.AST.Name.Name` (local)         |             | `$id:`
`LLVM.AST.Name.Name` (global)        |             | `$gid:`
`LLVM.AST.Parameter`                 |             | `$param:`
`[LLVM.AST.Parameter]`               |             | `$params:`

Examples
--------

### Module Quasiquoter

```haskell
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE OverloadedStrings #-}

module Example where

import LLVM.Prelude
import LLVM.AST as AST
import LLVM.AST.Name as AST
import LLVM.Quote.LLVM as Q
import Data.String (fromString)

example :: AST.Module
example = [Q.llmod|
; ModuleID = 'simple module'

define i32 @foo(i32 %x) {
entry:
  %x.addr = alloca i32
  store i32 %x, i32* %x.addr
  ret i32 1001
}
|]
```

### Instruction Antiquotes

```haskell
example :: Either AST.Instruction AST.Terminator -> AST.Module
example instructionOrTerminator = [Quote.LLVM.llmod|
  ; ModuleID = 'simple module'
  define i32 @myfunc(){
  entry:
    $instr:instructionOrTerminator
    ret i32 0
  }
|]
```

License
-------

Copyright (c) 2014, Timo von Holtz
