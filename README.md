# Tcl Static Prime

Tcl Static Prime (TSP) is an experimental compiler for the Tcl language 
that produces C or Java code, which is then compiled on-the-fly during 
execution of a Tcl program.   TSP is a currently a work-in-progress;
its performance varies greatly depending the Tcl commands that are
currently compiled.

TSP compiles a typed subset of Tcl.  Proc definitions and variables are 
typed by comment-based annotations.  Native types supported are boolean, 
int (64-bit integers), double, string, and var (TclObjects for lists, dicts,
etc.)

TSP language restrictions include restricting all arithmetic expressions
(expr, if, while, etc) to using boolean, int, double, and string data types.
Additionally, expressions may not include array references or nested commands.
TSP also assumes that builtin Tcl commands are not re-defined, as builtin 
commands are compiled to C or Java,  or the native command implementation is 
invoked directly, bypassing the Tcl interpreter.  


TSP is written entirely in Tcl, with support libraries written in C and Java.

Changes to original TSP
* limited Namespace support for proc names and variables (see  [Features](./docs/tsp-lang-features.md))
* package support with ::tsp::init_package // ::tsp::finalize_package (see  [Features](./docs/tsp-lang-features.md))
* #tsp::inlinec and #tsp::altTCL directives to include native c-code and alternative tcl-code (see [Compiler Usage](./docs/compiler-usage.md))
* some bugfixes I ran into 

# Docs

  1. [Introduction](./docs/introduction.md)
  2. [Features](./docs/tsp-lang-features.md)
  3. [Type System](./docs/type-system.md)
  4. [Compiled Commands](./docs/compiled-commands.md)
  5. [Runtime](./docs/runtime.md)
  6. [Compiler Usage](./docs/compiler-usage.md)
  7. [Future Improvements](./docs/future-improvements.md)
  8. [Install](./docs/install.md)
  9. [Misc.](./docs/misc.md)


Wiki (Q & A, discussion, other): http://wiki.tcl.tk/Tcl%20Static%20Prime
