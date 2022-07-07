package provide tcc4tcl_helper 0.1

namespace eval tccenv {
    # some common envelope vars for our ide
    variable localdir [pwd]
    variable pathprefix [file dirname [file dirname [file dirname [info script]]]]
    #puts "pwd [pwd] exe [info nameofexecutable] script [info script] prefix $pathprefix"
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
    
    proc setprojectdir {pdir} {
        variable projectdir
        variable projectincludedir
        variable projectlibdir
        set projectdir $pdir
        set projectincludedir  ${projectdir}/include
        set projectlibdir      ${projectdir}/lib
    }
    proc settccexedir {pdir} {
        variable tccexecutabledir
        variable tccexecutable
        variable tccmaindir
        variable tccincludedir
        variable tcclibdir
        set searchpath {"" "tcc_0.9.27-bin"}
        set tccexecutabledir [findfiledir $pdir $searchpath "tcc.exe"]
        set tccmaindir  [file normalize ${tccexecutabledir}/]
        set tccincludedir  ${tccexecutabledir}/include
        set tcclibdir      ${tccexecutabledir}/lib
    }
    proc setgccexedir {pdir} {
        variable gccexecutabledir
        variable gccexecutable
        variable gccmaindir
        variable gccincludedir
        variable gcclibdir
        set searchpath {"" "gcc/bin" "tcc_0.9.27-bin/gcc/bin"}
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
    #puts "Entering..."
    foreach path $includepath {
        #puts "Searching $path..."
        if {![file isdir $path]} {
            #try guessing in current subdirs
            if {[file isdir [::tcc4tcl::shortenpath $path]]} {
                set path [::tcc4tcl::shortenpath $path]; lappend retpath $path
            } else {
                if {[file isdir [file tail $path]]} {set path [file tail $path]; lappend retpath $path}
            }
            #puts "replacing path $path"
        }
        update
        set subdirs ""
        catch {
            set subdirs [glob -nocomplain -directory $path -types d *]
        }
        foreach sub $subdirs {
            #puts "got subdir ...$sub..."
            set sub [file tail $sub]
            lappend retpath [file join $path $sub]
            append retpath " [::tcc4tcl::getsubdirs [file join $path $sub]]"
        }
    }
    return $retpath
}

proc ::tcc4tcl::searchDir {dir inDir} {
        #puts "Searching $dir in $inDir"
        set subdirs ""
        if {$dir==$inDir} {
            return $inDir
        }
        catch {
            set subdirs [glob -nocomplain -directory $inDir -types d *]
        }
        foreach sub $subdirs {
            #puts "got subdir ...$sub..."
            if {[file tail $sub]==$dir} {
                return $sub
            }
        }
        foreach sub $subdirs {
             #puts "search subdir ...$sub..."
             set d [::tcc4tcl::searchDir $dir $sub]
             if {$d!=""} {
                return $d
            }
        }
        return ""
}

proc ::tcc4tcl::commonsubdir {d1 d2} {
    # returns a list of three
    # common dirpath
    # rest of dir1
    # rest of dir2
    
    set d1 [split [string map {\\ /} $d1] /]
    set d2 [split [string map {\\ /} $d2] /]
    set l1 [llength $d1]
    set l2 [llength $d2]
    if {$l1>$l2} {
        # swap d1 d2
        set d $d1
        set d1 $d2
        set d2 $d
        set l1 $l2
    }
    set outlist {}
    for {set i 0} {$i< $l1} {incr i} {
        if {[lindex $d1 $i]==[lindex $d2 $i]} {
            lappend outlist [lindex $d1 $i]
        } else {
            break;
        }
    }
    set rest1 [lrange $d1 $i end]
    set rest2 [lrange $d2 $i end]
        
    return [list [join $outlist /]/ [join $rest1 /] [join $rest2 /]]
}

proc ::tcc4tcl::makefileglob {includepath {filelist {}} {subdirs 1}} {
    # create a filelist withh every file in every subpath as a lookup table
    foreach path $includepath {
        #puts "Searching $path"
        set files [glob -tails -nocomplain -directory $path *.{h,c}]
        foreach file $files {
            lappend filelist $file $path
        }
        if {$subdirs>0} {
            set subpaths [glob -nocomplain -directory $path -types d *]
            set filelist [::tcc4tcl::makefileglob $subpaths $filelist $subdirs]
        }
    }
    return $filelist
}

proc ::tcc4tcl::shortenpath {path {prefix ""}} {
    #
    set shortincludepath ""
    if {$prefix==""} {
        set prefix $::tccenv::pathprefix/
    }
    set prefix1 ${prefix}lib/
    set prefix2 ${prefix}lib/tcc4tcl-0.30/
    
    #puts "Analysing $path"
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
    set code [$handle code]
    #puts [string range $code 0 1024]
    set includepath [$handle add_include_path]
    append includepath " [::tcc4tcl::getsubdirs $includepath]"
    set includepath [lsort -unique $includepath]
    #puts $includepath
    set filelist [::tcc4tcl::makefileglob $includepath]
    
    set usedpath [analyse_codeincludes "main source" $code $includepath ""]
    puts "Possibly missing files: [expr [llength $includes_missing]/2]"
    puts "list is in tcc4tcl::includes_missing"
    set shortincludepath ""
    if {$prefix==""} {
        set prefix $::tccenv::pathprefix/
    }
    set prefix1 ${prefix}lib/
    set prefix2 ${prefix}lib/tcc4tcl-0.30/
    
    foreach path $usedpath {
        #puts "Analysing $path"
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

proc ::tcc4tcl::analyse_codeincludes {fromfile code includepath mdone {usedpath ""}} {
    # a simple (too simple) routine to find all include files and their paths recursivly
    # unable to parse any kind of ifdef ifndef
    # so will mostly try to find ANY file thats behind an #include directive
    
    variable done
    variable includes_missing
    #puts "Analysing ... $fromfile"
    update
    set done $mdone
    set cinc 0
    set includer "#include"
    set rgincluder "#(\\s*)include"
    set lines [split $code \n]
    foreach line $lines {
        #set pos [string first $includer [string tolower $line]]
        set pos [regexp -nocase $rgincluder $line]
        if {$pos>0} {
            # found includer
            set line [string range $line $pos end]
            set rest [string range $line [string length $includer] end]
            set start [string first "\"" $rest]
            set end [string first "\"" $rest $start+1]
            if {$start==-1} {
                set start [string first "<" $rest]
                set end [string first ">" $rest $start+1]
            }
            set filename [string trim [string range $rest $start+1 $end-1]]
            if {$filename==""} {
                continue
            }
            if {[lsearch $done $filename]==-1} {
                while {[string range $filename 0 2] eq "../"} {
                    set filename [string range $filename 3 end]
                }
                #puts "Searching ...$filename..."
                #update
                set undone 1
                foreach path $includepath {
                    if {[file exists [file join $path $filename]]} {
                        set undone 0
                        lappend done $filename
                        lappend usedpath $path
                        if {[file tail $filename]!=$filename} {
                            #lappend done [file tail $filename]
                            lappend usedpath [file join $path [file dir $filename]]
                            #puts "Found $filename (adding [file join $path [file dir $filename]] and [file tail $filename])"
                        }
                        set fp [open [file join $path $filename]]
                        set codenew [read $fp]
                        close $fp
                        #puts "found [file join $path $filename]"
                        incr cinc
                        set usedpath [analyse_codeincludes $filename $codenew $includepath $done $usedpath]
                    } 
                }
                if {$undone>0} {
                    #puts "Not found include  $fromfile -> $filename";
                    lappend includes_missing $fromfile $filename
                    lappend done $filename
                }
            }
        }
    }
    return [lsort -unique $usedpath]
}

proc ::tcc4tcl::write_packagecode {handle packagename {filepath ""} {packageversion 1.0} {tclversion TCL_VERSION}} {
    proc relTo {targetfile currentpath} {
    # Get relative path to target file from current path
    # First argument is a file name, second a directory name (not checked)
        set cc [file split [file normalize $currentpath]]
        set tt [file split [file normalize $targetfile]]
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
        file join {*}$prefix {*}$tt
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
    puts [$handle add_include_path] 
    
    set pathway [::tcc4tcl::analyse_includes $handle]
    #puts "Paths: $pathway"
    set includestcc "-Iinclude -Iinclude/stdinc -Iinclude/generic -Iinclude/generic/win -Iinclude/xlib -Iwin32 -Iwin32/winapi "
    set includesgcc "-Iinclude -Iinclude/generic -Iinclude/generic/win -Iinclude/xlib"
    set includeslin64 "-Iinclude -Iinclude/generic -Iinclude/generic/unix -Iinclude/xlib"
    set librariestcc "-ltclstub86elf -ltkstub86elf"
    set librariesgcc "-Llib -ltclstub86 -ltkstub86"
    set librarieslin64 "-Llib -ltclstub86_64 -ltkstub86_64"
    
    foreach incpath $pathway {
        #lappend includestcc "-I$incpath"
        if {[string first include/ [string tolower $incpath]]<0} {
            if {[string first win32 [string tolower $incpath]]<0} {
                lappend includestcc "-I$incpath"
                lappend includesgcc "-I$incpath"
                lappend includeslin64 "-I$incpath"
            }
        }
    }
    lappend librariestcc "-Llib"
    lappend librariesgcc "-Llib"
    lappend librarieslin64 "-Llib"
    set libps [$handle add_library_path]
    set libs [$handle add_library]
    foreach inclib $libs {
        lappend librariestcc "-l$inclib"
        set found 0
        foreach incpath $libps {
            if {[file exists [file join $incpath ${inclib}.dll]]} {
                lappend librariesgcc [file join $incpath $inclib.dll]
                set found 1
                break
            }
            if {[file exists [file join $incpath ${inclib}.so]]} {
                lappend librarieslin64 [file join $incpath $inclib.so]
                set found 1
                break
            }
        }
        foreach incpath $libps {
            if {[file exists [file join $incpath lib${inclib}.a]]} {
                lappend librariesgcc [file join $incpath $inclib.dll]
                set found 1
                break
            }
            if {[file exists [file join $incpath lib${inclib}.so]]} {
                lappend librarieslin64 [file join $incpath $inclib.so]
                set found 1
                break
            }
        }
        if {$found ==0} {
            puts "Warning: Not found library $inclib"
            lappend librariesgcc $inclib
        }
            
    }
    foreach incpath $libps {
        lappend librariestcc "-L$incpath"
        lappend librariesgcc "-L$incpath"
    }
    
    if {[string first $::tccenv::tccexecutabledir $::tccenv::localdir]<0} {
        set absfilepath [file normalize $filepath]
    } else {
        set absfilepath $filepath
    }
    
    set relfilepath [relTo $filepath $::tccenv::tccmaindir]
    
    set tccpath [file join $::tccenv::tccexecutabledir $::tccenv::tccexecutable]
    set gccpath [file join $::tccenv::gccexecutabledir $::tccenv::gccexecutable]
    set gccoptions "-O2 -fwhole-program"
    set gccoptions "-O2 -fdata-sections -ffunction-sections -Wl,--gc-sections -Wl,-s"
    set gccoptions "-O2"
    set tcc_compile "$tccpath -shared -DUSE_TCL_STUBS $includestcc [file join $absfilepath "$packagename.c"] -o[file join $absfilepath "$packagename.dll"] $librariestcc"
    set gcc_compile "$gccpath -shared -s -m32 -D_WIN32 -DUSE_TCL_STUBS -static-libgcc $includesgcc [file join $absfilepath "$packagename.c"] $librariesgcc  -o[file join $absfilepath "$packagename.dll"] $gccoptions"
    set cross_compile "i686-w64-mingw32-gcc -shared -s -m32 -D_WIN32 -DUSE_TCL_STUBS -static-libgcc $includesgcc [file join $relfilepath "$packagename.c"] $librariesgcc  -o[file join $relfilepath "$packagename.dll"] $gccoptions"
    set lin64_compile "gcc -shared -s -fPIC -D_GNU_SOURCE -DUSE_TCL_STUBS $includeslin64 [file join $relfilepath "$packagename.c"] $librarieslin64  -o[file join $relfilepath "$packagename.so"] $gccoptions"

    puts "\n$tcc_compile\n"
    puts "\n$gcc_compile\n"
    puts "\n$cross_compile\n"
    puts "\n$lin64_compile\n"
    
    set filename [file join $filepath "$packagename.c"]

    set fp [open $filename w]
    puts $fp "/***************** Automatically Created with TCC4TCL Helper and maybe TSP **********************************/"
    puts $fp "/* Compiler directives are raw estimates, please adapt to given pathstructure */\n"
    puts $fp "/* $tcc_compile  */\n"
    puts $fp "/* $gcc_compile */\n"
    puts $fp "/* $cross_compile  */\n"
    puts $fp "/* $lin64_compile  */\n"
    puts $fp "/***************** Automatically Created with TCC4TCL Helper and maybe TSP **********************************/"
    puts $fp $mycode
    close $fp
    return [list $tcc_compile $gcc_compile $cross_compile $lin64_compile]
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

