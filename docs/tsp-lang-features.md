
# Tcl Language Subset

## Limited subset of Tcl, upwardly compatible with standard Tcl

TSP requires that compiled procs use a limited subset of the Tcl language rules.
This subset is entirely upwardly compatible with standard Tcl (other than the 
semantics of variable type conversion discussed earlier.)  

For limitations for compiling specific commands, see compiled-commands.md.

# Summary of limitations

## Expressions use only native types, not all expr operators/functions implemented

The **expr** command and logical expressions used in **for** and **while** only 
operate on native types (boolean, int, double, string.)
If a *var* or *array* type in encountered during expression parsing, the compilation will
fail.  

String variables should only be used in logical comparison **eq** and **ne**, or with logical
operators ** == != < <= > >= ** .  When using string types, both sides of the operator must be
strings.  

Standard Tcl operators and functions are supported: **cos(), sin(), rand(),** etc., with 
the exception that **in** and **ni** operators are not supported.

Expression must be enclosed by braces, quoted or bare expressions cannot be compiled.

```


    # illegal expressions
    set n [ expr "$a $s $c" ]        ;# invalid: expression not enclosed by braces

    #tsp::var v
    if {$v + $x($c)} {               ;# invalid: var type and array references not allowed
    }

    while {[string length $s]} {     ;# invalid: nested command not allowed
    }
```

## Expansion syntax not supported {*}

The Tcl 8.5+ list expansion syntax **{*}** is not supported, since this introduces
a level of additional runtime interpretation.

```
    lappend foo {*}$s                ;# invalid: expansion syntax not allows
```

## limited Namespace support for proc names and variables

Procedures can be defined in the global namespace. Namespace qualifiers in the proc name are invalid 

```
    tsp::proc ::pkg::foo {} {        ;# invalid: 
        #tsp::procdef void
    }
```

But you can define a project namespace with the variable tsp::PACKAGE_NAMESPACE; if defined, ALL procs will be rewritten to this namespace

```
set tsp::PACKAGE_NAMESPACE pkg
    tsp::proc foo {} {        ;# will be rewritten pkg::foo
        #tsp::procdef void
        #tsp::var v
        variable v            ;# will be connected to $pkg::v
    }
    
```
## Package support
Package support depends on the package tcc4tcl_helper to work, someday it will be integrated here, meanwhile find it here https://github.com/MichaelMiR01/tccide/tree/main/subpackages

Package support (tsp_packagehelper.tcl) introduces two commands
* ::tsp::init_package {packagename {packagenamespace ""} {packageversion 1.0} {tclversion TCL_VERSION}}
* ::tsp::finalize_package {{packagedir ""} {compiler none}}

TSP will generate package code in the given packagedir (packagedir defaults to packagename).
It writes out

* packagename.c
* packagename.tclprocs.tcl
* packagename.puretcl.tcl
* pkgIndex.tcl
* packagename.dll

compiler can be **intern/memory** or **export**. 

   **intern** (eq memory) will compile to memory and immediatly install the compiled procs
    
   **export** will build a shared lib (.so//.dll) an write it into the package dir as **packagename.dll // packagename.so**

* packagename.tclprocs.tcl    contains all TSP procs defined as tcl-only and will be sourced, if loading the dll fails
* packagename.puretcl.tcl     TSP collects all proc definitions between init_package and finalize_package and spits them here. This will be sourced from pkgIndex, so not only tsp and tcc proc are loaded, but tcl procs can also be defined as helpers

```
#example
package require tsp

::tsp::init_package tnop 

set handle $tsp::TCC_HANDLE
$handle cproc cnop {Tcl_Interp* interp } char* {
    // this is a pure c-function
     return "cnop";
}
::tsp::proc tspnop {} {
    #this is a transpiled function, its tcl code will go to tnop.tclprocs.tcl
    #tsp::procdef void
    puts "tspnop"
}
proc tclnop {} {
    # this is a pure tcl function. its code will go to tnop.puretcl.tcl
    puts "tclnop "
}
::tsp::printLog 
::tsp::finalize_package tnop export
```

The exported package can now be loaded with package require packagename.

Furthermore, TSP will try to spit out some compiler directives for tcc/gcc you can use as boilerplate to recompile the sourcecode with an optimizing compiler.

Packages can be enriched with external libraries with the following directives:
```
proc ::tsp::add_tclinclude {fname}
    # load tcls for additional sources, issues a source (fname) command into pkgIndex

proc ::tsp::add_bininclude {fname} 
    # load_dlls for dlls wich should be loaded into interp, issues a load (fname) command into pkgIndex

proc ::tsp::add_dllinclude {fname}
    # external dlls wich are dependencies and do not get loaded into interp but linked to your c-code (like jpeg.dll)
    # tries to copy fname.dll into [pwd], so tcl can find it and dload
```

## Limitation on proc name and variable names

Procedure names and variable names inside of procedures must follow strict naming conventions.
Valid identifiers consist of a upper or lower case character A-Z or an underscore, and the following
characters can only contain those characters, plus digits 0-9.  Procedure and variable names
are compiled into native code without using a translation table, so names must be valid in the 
target language.

```
    tsp::proc foo.bar {} {           ;# invalid: characters other than _ in proc name
        #tsp::procdef void
        set {bing baz} "hello"       ;# invalid: whitespace in variable name
    }
```

## Procedure default arguments and **args** not supported

Procedure arguments may not contain default values, and the use of **args** as the last procedure 
argument is not supported.

```
    tsp::proc foo {a {b 0} args} {   ;# invalid: default argument value and 'args' argument not allowed
        #tsp::procdef void
    }
```

## String and list indices

String and list commands that use indices (e.g., **string range**, **lindex**) may only specify
indices as a literal integer constant, a integer variable,  a variable that can be converted
to an integer, or the literal **end-** with an integer constant or variable.  

```
    set idx "end-$i"
    puts [string index $str $idx]    ;# invalid: "end-n" specifier only allowed as literal

    puts [string index $str end-$i]  ;# OK
```

## Return must be used for all code paths

An explicit return statement must be encountered in all code paths, returning
a constant or variable of the defined proc return type (or a value or variable that can
be converted to the return type.)  The only exception is for procs defined as
**void**, in which the end of proc can be encountered without an explicit return.

```
    tsp::proc foo {} {
        #tsp::procdef int
        set n 1                      ;# invalid: return must be coded
    }
```

## Code bodies for if, while, for, foreach, switch, catch must be enclosed by braces 

Code enclosed by double quotes, or bare code is not compilable, as this implies
possible substitution by the Tcl interpreter.

```
    if {$i > 0} "puts hello_$world"  ;# invalid: runtime interpolation of body

    if {$i > 0} {puts hello_$world}  ;# OK
```


