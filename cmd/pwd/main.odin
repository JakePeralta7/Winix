package main

import "core:os"
import "../../internal/cliflag"
import "../../internal/winconsole"
import "../../internal/winpath"

VERSION :: "0.1.0"

USAGE :: `Usage: pwd [-L | -P] [--help] [--version]
Print the current working directory.

  -L          logical: honor $PWD when it refers to the actual cwd (default)
  -P          physical: resolve symlinks/junctions to a real path
  --help      print this message and exit
  --version   print version and exit
`

main :: proc() {
    physical, help, version: bool
    spec := cliflag.Spec{
        flags = []cliflag.Flag_Def{
            {short = 'L', kind = .Bool_Last_Wins, target = &physical, value_if_set = false},
            {short = 'P', kind = .Bool_Last_Wins, target = &physical, value_if_set = true},
            {long  = "help",    kind = .Bool_Last_Wins, target = &help,    value_if_set = true},
            {long  = "version", kind = .Bool_Last_Wins, target = &version, value_if_set = true},
        },
    }

    args := os.args[1:] if len(os.args) > 1 else []string{}
    parsed, perr, tok := cliflag.parse(args, spec)

    out := winconsole.stdout()
    errw := winconsole.stderr()

    if perr != .None {
        winconsole.write_string(errw, "pwd: unknown option: ")
        winconsole.write_string(errw, tok)
        winconsole.write_string(errw, "\r\nTry 'pwd --help'.\r\n")
        os.exit(2)
    }
    if help {
        winconsole.write_string(out, USAGE)
        os.exit(0)
    }
    if version {
        winconsole.write_line(out, "pwd (winix) " + VERSION)
        os.exit(0)
    }
    if len(parsed.rest) > 0 {
        winconsole.write_string(errw, "pwd: too many arguments\r\n")
        os.exit(2)
    }

    path: string
    werr: winpath.Error
    if physical {
        path, werr = winpath.get_cwd_physical(context.allocator)
    } else {
        path, werr = winpath.get_cwd_logical(context.allocator)
    }
    if werr != .None {
        msg := message_for(werr)
        winconsole.write_string(errw, "pwd: ")
        winconsole.write_string(errw, msg)
        winconsole.write_string(errw, "\r\n")
        os.exit(1)
    }

    _, wcerr := winconsole.write_line(out, path)
    if wcerr != .None {
        os.exit(1)
    }
    os.exit(0)
}

message_for :: proc(e: winpath.Error) -> string {
    switch e {
    case .None:            return ""
    case .GetCwd_Failed:   return "cannot get current directory"
    case .Env_Read_Failed: return "cannot read environment"
    case .Open_Failed:     return "cannot open directory"
    case .Resolve_Failed:  return "cannot resolve path"
    case .Encoding_Failed: return "encoding error"
    }
    return "unknown error"
}
