package provide tcc4tcl_helper 0.1

namespace eval tccenv {
    # some common envelope vars for our ide
    # this tries to analyze the surrounding dirs
    # to find a suitable external compiler
    # on windows this would be tcc.exe
    # or gcc.exe
    # someday this should be moved into tccide, since it's nothing to do with tcc4tcl
    
    variable localdir [pwd]
    variable pathprefix [file dirname [file dirname [file dirname [info script]]]]
    variable tccexecutabledir $localdir
    variable tccexecutable  tcc.exe
    variable tccmaindir     ${tccexecutabledir}
    variable tccincludedir  ${tccexecutabledir}/include
    variable tcclibdir      ${tccexecutabledir}/lib
    
    variable gccexecutabledir $localdir
    variable gccexecutable  gcc.exe
    variable gccmaindir     ${gccexecutabledir}
    variable gccincludedir  ${gccexecutabledir}/include
    variable gcclibdir      ${gccexecutabledir}/lib
    
    variable projectdir     ${tccexecutabledir}/project
    variable projectincludedir  ${projectdir}/include
    variable projectlibdir      ${projectdir}/lib
    
    variable includes_missing ""
    
    variable EXTERNAL_COMPILERS ""
    variable CC_DIRECTIVES ""
    
    # the following routines try to find tcc.exe and gcc.exe under win32 and set the tccenv vars accordingly
    
    proc setprojectdir {pdir} {
        variable projectdir
        variable projectincludedir
        variable projectlibdir
        set projectdir $pdir
        set projectincludedir  ${projectdir}/include
        set projectlibdir      ${projectdir}/lib
    }
    proc settccexedir {pdir {searchpathin ""}} {
        variable tccexecutabledir
        variable tccexecutable
        variable tccmaindir
        variable tccincludedir
        variable tcclibdir
        set searchpath {""}
        foreach path $searchpathin {
            lappend searchpath "$path"
        }
        set tccexecutabledir [findfiledir $pdir $searchpath "tcc.exe"]
        set tccmaindir  [file normalize ${tccexecutabledir}/]
        set tccincludedir  ${tccexecutabledir}/include
        set tcclibdir      ${tccexecutabledir}/lib
    }
    proc setgccexedir {pdir {searchpathin ""}} {
        variable gccexecutabledir
        variable gccexecutable
        variable gccmaindir
        variable gccincludedir
        variable gcclibdir
        set searchpath {"" "gcc/bin"}
        foreach path $searchpathin {
            lappend searchpath "$path" "$path/gcc/bin" 
        }
        set gccexecutabledir [findfiledir $pdir $searchpath "gcc.exe"]
        set gccmaindir  [file normalize ${gccexecutabledir}/../../]
        set gccincludedir  ${gccmaindir}/include
        set gcclibdir      ${gccmaindir}/lib
    }
    
    proc findfiledir {pdir searchpath filetofind} {
        #
        foreach p $searchpath {
            set founddir [file join $pdir $p]
            
            if {![file exists [file join ${founddir} $filetofind]]} {
                # try finding gcc            
                puts "not found $filetofind in $founddir"
            } else {
                puts "!found $filetofind in $founddir"
                return [file join $founddir ""]
            }
        }
        return ""
    }
}

proc ::tcc4tcl::getsubdirs {includepath} {
    set retpath {}
    foreach path $includepath {
        if {![file isdir $path]} {
            #try guessing in current subdirs
            if {[file isdir [::tcc4tcl::shortenpath $path]]} {
                set path [::tcc4tcl::shortenpath $path]; lappend retpath $path
            } else {
                if {[file isdir [file tail $path]]} {set path [file tail $path]; lappend retpath $path}
            }
        }
        update
        set subdirs ""
        catch {
            set subdirs [glob -nocomplain -directory $path -types d *]
        }
        foreach sub $subdirs {
            set sub [file tail $sub]
            lappend retpath [file join $path $sub]
            append retpath " [::tcc4tcl::getsubdirs [file join $path $sub]]"
        }
    }
    return $retpath
}

proc ::tcc4tcl::searchDir {dir inDir} {
        set subdirs ""
        if {$dir==$inDir} {
            return $inDir
        }
        catch {
            set subdirs [glob -nocomplain -directory $inDir -types d *]
        }
        foreach sub $subdirs {
            if {[file tail $sub]==$dir} {
                return $sub
            }
        }
        foreach sub $subdirs {
             set d [::tcc4tcl::searchDir $dir $sub]
             if {$d!=""} {
                return $d
            }
        }
        return ""
}

proc ::tcc4tcl::shortenpath {path {prefix ""}} {
    set shortincludepath ""
    if {$prefix==""} {
        set prefix $::tccenv::pathprefix/
    }
    set prefix1 ${prefix}lib/
    set prefix2 ${prefix}lib/tcc4tcl-0.30/
    
    set shortresult ""
    set shortpath [string map [list $prefix ""] $path]
    set shortpath1 [string map [list $prefix1 ""] $path] 
    set shortpath2 [string map [list $prefix2 ""] $path] 
    if {$shortpath2!=$path} { set shortresult $shortpath2; }
    if {$shortpath1!=$path} { set shortresult $shortpath1; }
    if {$shortpath!=$path} { set shortresult $shortpath; }
    return shortresult
}

proc ::tcc4tcl::analyse_includes {handle {prefix ""}} {
    variable includes_missing
    set includes_missing ""
    set usedpath [$handle add_include_path]
    set shortincludepath ""
    if {$prefix==""} {
        set prefix $::tccenv::pathprefix/
    }
    set prefix1 ${prefix}lib/
    set prefix2 ${prefix}lib/tcc4tcl-0.30/
    
    foreach path $usedpath {
        set shortpath [string map [list $prefix ""] $path]
        set shortpath1 [string map [list $prefix1 ""] $path] 
        set shortpath2 [string map [list $prefix2 ""] $path] 
        if {$shortpath2!=$path} { lappend shortincludepath $shortpath2; continue}
        if {$shortpath1!=$path} { lappend shortincludepath $shortpath1; continue}
        if {$shortpath!=$path} { lappend shortincludepath $shortpath; continue}
        lappend shortincludepath $shortpath;       
    }
    return $shortincludepath
}

proc ::tcc4tcl::addExternalCompiler {compiler ccOptions exeDir exeFile {compilertype gccwin32}} {
    # add external compiler to list EXTERNAL_COMPILERS
    # $compiler:        compilername cc
    # $ccOptions       additional options to use with cc
    # $exeDir           directory to execute cc in
    # $exeFile          cc to execute
    # compilertype      can be gccwin32/gcclin64/tccwin32/tcclin64/user   and defines prebuilt ccOptions to use; set to user to have no predefined options
    dict set ::tccenv::EXTERNAL_COMPILERS $compiler [list $compiler $ccOptions $exeDir $exeFile $compilertype]
}

proc ::tcc4tcl::prepare_compilerdirectives {filepath handle} {
    proc relTo {targetfile currentpath } {
        # Get relative path to target file from current path
        # First argument is a file name, second a directory name (not checked)
        set result ""
        set cc [file split [file normalize $currentpath]]
        set tt [file split [file normalize $targetfile]]
        set shorthandpath [file join [file normalize [pwd]] $targetfile]
        if {![file exists $shorthandpath]} {
            set shorthandpath [file join [file normalize $currentpath] $targetfile]
            if {[file exists $shorthandpath]} {
                # seems to be a direct hit
                return $targetfile
            }
        }
            
        if {![string equal [lindex $cc 0] [lindex $tt 0]]} {
            # not on *n*x then
            return -code error "$targetfile not on same volume as $currentpath"
        }
        while {[string equal [lindex $cc 0] [lindex $tt 0]] && [llength $cc] > 0} {
            # discard matching components from the front
            set cc [lreplace $cc 0 0]
            set tt [lreplace $tt 0 0]
        }
        set prefix {} 
        if {[llength $cc] == 0} {
            # just the file name, so targetfile is lower down (or in same place)
            set prefix .
        }
        # step up the tree
        for {set i 0} {$i < [llength $cc]} {incr i} {
            append prefix { ..}
        }
        # stick it all together
        set result [file join {*}$prefix {*}$tt]
        return $result
        
    }
    proc eol {} {
        switch -- $::tcl_platform(platform) {
            windows {return \r\n}
            unix {return \n}
            macintosh {return \r}
            default {\n}
        }
    }
    
    # This proc tries to guess the shell commands to invoke an external compiler
    # therefor it uses $::tccenv::tccmaindir as a base directory
    # ideally, tccide gets executed from $::tccenv::tccmaindir
    # usually, your directory struct should look like this
    #
    # ::tccenv::tccmaindir/
    # tcc.exe                   executable for external compiler (tcc)
    # include/...               standard include dir for tcc, holding also tcl.h etc in include/generic
    # win32/...                 standard win32 includes for tcc
    # lib/...                   here go libtclstub86.a etc, tcc win32 defs libtcc1.a etc
    # tsp-package/native/clang  the include files for TSP go here
    #
    # when using gcc win32, all gcc stuff goes into
    # ::tccenv::tccmaindir/gcc
    # the binaries gcc.exe etc now are under 
    # ::tccenv::tccmaindir/gcc/bin
    # 
    # under linux, gcc oder xgcc should be installed and bring there own includes etc.
    # 
    # other compilers may need different treatment
    # so be shure to set tccmaindir accordingly beforehand
    
    # add external compiler to list EXTERNAL_COMPILERS
    # $compiler:        compilername cc
    # $ccOptions       additional options to use with cc
    # $exeDir           directory to execute cc in
    # $exeFile          cc to execute
    # $compilertype      can be gccwin32/gcclin64/tccwin32/tcclin64/user   and defines prebuilt ccOptions to use; set to user to have no predefined options
    puts "Making Directives for $filepath ($::tccenv::tccmaindir)" 
    set pathway [::tcc4tcl::analyse_includes $handle]
    set includestccwin32 "-Iinclude -Iinclude/stdinc -Iinclude/generic -Iinclude/generic/win -Iinclude/xlib -Iwin32 -Iwin32/winapi "
    set includesgccwin32 "-Iinclude -Iinclude/generic -Iinclude/generic/win -Iinclude/xlib"
    set includestcclin64 "-Iinclude -Iinclude/stdinc -Iinclude/generic -Iinclude/generic/unix -Iinclude/xlib "
    set includesgcclin64 "-Iinclude -Iinclude/generic -Iinclude/generic/unix -Iinclude/xlib"
    set includesuser ""

    set librariestccwin32 "-ltclstub86elf -ltkstub86elf"
    set librariestcclin64 "-ltclstub86elf -ltkstub86elf"
    set librariesgccwin32 "-Llib -ltclstub86 -ltkstub86"
    set librariesgcclin64 "-Llib -ltclstub86_64 -ltkstub86_64"
    set librariesuser ""
    
    set ccoptionstccwin32 "-m32 -D_WIN32 "
    set ccoptionsgccwin32 "-s -m32 -D_WIN32 -static-libgcc "
    set ccoptionstcclin64 ""
    set ccoptionsgcclin64 "-s -fPIC -D_GNU_SOURCE "
    
    set ccoptionstccuser ""
    
    set includes_generic ""
    
    foreach incpath $pathway {
        if {[string first include/ [string tolower $incpath]]<0} {
            if {[string first win32 [string tolower $incpath]]<0} {
                lappend includes_generic "-I[relTo $incpath $::tccenv::tccmaindir]"
            }
        }
    }
    
    set libraries_addon ""
    lappend libraries_addon "-Llib"
    set libps [$handle add_library_path]
    set libs [$handle add_library]
    foreach inclib $libs {
        lappend libraries_addon "-l$inclib"
    }
    foreach incpath $libps {
        lappend libraries_addon "-L[relTo $incpath $::tccenv::tccmaindir]"
    }

    set packagename [file rootname [file tail $filepath]]
    set filepath [file dirname $filepath]
    
    if {[string first $::tccenv::tccmaindir $::tccenv::localdir]<0} {
        set absfilepath [file normalize $filepath]
    } else {
        set absfilepath $filepath
    }
    
    set relfilepath [relTo $filepath $::tccenv::tccmaindir]
    set ccdirectives ""
    foreach {compiler ccdetails} $::tccenv::EXTERNAL_COMPILERS {
        # ok, spit out all directives and put it into dict CC_DIRECTIVES
        set cc ""
        lassign $ccdetails cc ccOptions exeDir exeFile compilertype
        if {$cc eq ""} {
            puts "ERROR: Unknown compiler $compiler or given none..."
            continue;
        }
        
        set includes [set [subst includes[set compilertype]]]
        set libraries [set [subst libraries[set compilertype]]]
        set ccoptions [set [subst ccoptions[set compilertype]]]
        append libraries " $libraries_addon"
        append inlcudes " $includes_generic"
        
        set dlext "dll"
        if {[string first "lin64" $compilertype]>-1} {
            set dlext "so"
        }
        
        set cfile [file join $relfilepath "$packagename.c"]
        set ofile [file join $relfilepath "$packagename.$dlext"]
        
        set ccpath [file join $exeDir $exeFile]
        append ccoptions " -shared -DUSE_TCL_STUBS -O2"
        append ccOptions " $ccoptions"
        
        puts "Directive for $compiler"
        puts "$ccpath $ccOptions $includes $includes_generic $cfile -o$ofile $libraries"
        lappend ccdirectives $compiler "$ccpath $ccOptions $includes $includes_generic $cfile -o$ofile $libraries"
    }
    return $ccdirectives
}

proc ::tcc4tcl::write_packagecode {handle packagename {filepath ""} {packageversion 1.0} {tclversion TCL_VERSION}} {
    proc relTo {targetfile currentpath } {
        # Get relative path to target file from current path
        # First argument is a file name, second a directory name (not checked)
        set result ""
        set cc [file split [file normalize $currentpath]]
        set tt [file split [file normalize $targetfile]]
        set shorthandpath [file join [file normalize [pwd]] $targetfile]
        if {![file exists $shorthandpath]} {
            set shorthandpath [file join [file normalize $currentpath] $targetfile]
            if {[file exists $shorthandpath]} {
                # seems to be a direct hit
                return $targetfile
            }
        }
            
        if {![string equal [lindex $cc 0] [lindex $tt 0]]} {
            # not on *n*x then
            return -code error "$targetfile not on same volume as $currentpath"
        }
        while {[string equal [lindex $cc 0] [lindex $tt 0]] && [llength $cc] > 0} {
            # discard matching components from the front
            set cc [lreplace $cc 0 0]
            set tt [lreplace $tt 0 0]
        }
        set prefix {} 
        if {[llength $cc] == 0} {
            # just the file name, so targetfile is lower down (or in same place)
            set prefix .
        }
        # step up the tree
        for {set i 0} {$i < [llength $cc]} {incr i} {
            append prefix { ..}
        }
        # stick it all together
        set result [file join {*}$prefix {*}$tt]
        return $result
        
    }
    proc eol {} {
        switch -- $::tcl_platform(platform) {
            windows {return \r\n}
            unix {return \n}
            macintosh {return \r}
            default {\n}
        }
    }

        set DLEXPORTMAKRO "
/***************** DLL EXPORT MAKRO FOR TCC AND GCC ************/
#if (defined(_WIN32) && (defined(_MSC_VER)|| defined(__TINYC__)  || (defined(__BORLANDC__) && (__BORLANDC__ >= 0x0550)) || defined(__LCC__) || defined(__WATCOMC__) || (defined(__GNUC__) && defined(__declspec))))
#undef DLLIMPORT
#undef DLLEXPORT
#   define DLLIMPORT __declspec(dllimport)
#   define DLLEXPORT __declspec(dllexport)
#else
#   define DLLIMPORT __attribute__(dllimport)
#   if defined(__GNUC__) && __GNUC__ > 3
#       define DLLEXPORT __attribute__ ((visibility(\"default\")))
#   else
#       define DLLEXPORT
#   endif
#endif
/***************************************************************/
"        
    upvar #0 $handle state
    set oldtype "package"
    if {$state(type)!="package"} {
        set oldtype $state(type)
        set state(package) [list $packagename $packageversion $tclversion]
        set state(type) "package"
    }
    
    #modify code with dlexportmakro
    set oldcode $state(code)
    set newcode $DLEXPORTMAKRO
    append newcode $oldcode
    set state(code) $newcode
    
    puts "Writing Package $packagename --> $filepath"
    set mycode [$handle code]
    # beautify code
    set mycode [::tcc4tcl::reformat [string map [list [eol] \n] $mycode] 4]
    set $state(type) $oldtype
    
    set filename [file join $filepath "$packagename.c"]
    set ccdirectives [::tcc4tcl::prepare_compilerdirectives $filename $::tsp::TCC_HANDLE]
    set fp [open $filename w]
    puts $fp "/***************** Automatically Created with TCC4TCL Helper and maybe TSP **********************************/"
    puts $fp "/* Compiler directives are raw estimates, please adapt to given pathstructure */\n"
    foreach {compiler ccdirective} $ccdirectives {
        puts $fp "/* for $compiler use */"
        puts $fp "/* $ccdirective */\n"
    }
    puts $fp "/***************** Automatically Created with TCC4TCL Helper and maybe TSP **********************************/"
    puts $fp $mycode
    close $fp
    return $ccdirectives
}

proc ::tcc4tcl::reformat {tclcode {pad 4}} {
    proc count {string char} {
        set count 0
        while {[set idx [string first $char $string]]>=0} {
            set backslashes 0
            set nidx $idx
            while {[string equal [string index $string [incr nidx -1]] \\]} {
                incr backslashes
            }
            if {$backslashes % 2 == 0} {
                incr count
            }
            set string [string range $string [incr idx] end]
        }
        return $count
    }

    set lines [split $tclcode \n]
    set out ""
    set continued no
    set oddquotes 0
    set line [lindex $lines 0]
    set indent [expr {([string length $line]-[string length [string trimleft $line \ \t]])/$pad}]
    set pad [string repeat " " $pad]
    
    foreach orig $lines {
        set newline [string trim $orig \ \t]
        if {$newline eq ""} {
            if {$continued} {
                set line ""
                set continued no
                incr indent -2
            } else {
                continue
            }
        } else {
            set line $orig
        }
        if {[string index $line end] eq "\\"} {
            if {(!$continued)&&(!([string index $line end-1] eq "\*"))} {
                incr indent 2
                set continued yes
            }
        } elseif {$continued} {
            incr indent -2
            set continued no
        }

        if {(0)&&(![regexp {^[ \t]*\#} $line])&&(![regexp {^[ \t]*\\\*} $line]) } {
            # oddquotes contains : 0 when quotes are balanced
            # and 1 when they are not
            set oddquotes [expr {([count $line \"] + $oddquotes) % 2}]
            if {! $oddquotes} {
                set  nbbraces  [count $line \{]
                incr nbbraces -[count $line \}]
                set brace   [string equal [string index $newline end] \{]
                set unbrace [string equal [string index $newline 0] \}]
                if {$nbbraces>0 || $brace} {
                    incr indent $nbbraces ;# [GWM] 010409 multiple open braces
                }
                if {$nbbraces<0 || $unbrace} {
                    incr indent $nbbraces ;# [GWM] 010409 multiple close braces
                    if {$indent<0} {
                        error "unbalanced braces"
                    }
                    ## was: set line [string range $line [string length $pad] end]
                    # 010409 remove multiple brace indentations. Including case
                    # where "\} else \{" needs to unindent this line but not later lines.
                    set np [expr {$unbrace? [string length $pad]:-$nbbraces*[string length $pad]}]
                    set line [string range $line $np end]
                }
            } else {
                # unbalanced quotes, preserve original indentation
                set line $orig
            }
        }
        append out $line\n
    }
    return $out
}

#----------------------------------- remove this code in future versions -----------------------
