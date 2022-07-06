##############################################################################
#tsp package helper commands for tccide
#
# package building process
#
# package structure
# PACKAGENAME_tsp_YYYY-MM-DD-hh-mm-ss.tcl (with tsp directives to create package)
# pkgIndex.tcl
# PACKAGENAME.puretcl.tcl (Untouched, pure TCL procs)
# PACKAGENAME.tclorig.tcl (TCL Replacment procs)
# PACKAGENAME.c (sourcecode, final)
# PACKAGENAME.dll (binary file)
# 
##############################################################################

namespace eval ::tsp {
    # added for code package making MiR
    variable COMPILE_PACKAGE 0
    variable PACKAGE_NAMESPACE ""
    variable NAMESPACE_VARS ""
    variable PACKAGE_HEADER ""
    variable TCC_HANDLE 
    variable PACKAGE_PROCS ""

    variable PACKAGE_NAME ""
    variable PACKAGE_VERSION "1.0"
    variable PACKAGE_DIR ""
    variable TCL_VERSION "TCL_VERSION"
    variable TCL_PROCS ""
    # load tcls for additional sources
    variable LOAD_TCLS ""
    # load_dlls for dlls wich should be loaded into interp
    variable LOAD_DLLS ""
    # external dlls wich are dependencies and do not get loaded into interp
    variable EXTERNAL_DLLS ""
    variable COMPILE_DIRECTIVES ""
    
    # give name of save tcl source here, otherwise we use __lastsaved__.tcl
    variable ACTSOURCE "__lastsaved__.tcl"
}

proc ::tsp::init_package {packagename {packagenamespace ""} {packageversion 1.0} {tclversion TCL_VERSION}} {
    if {$packagename eq ""} {
        puts "Err: No package name given: use init_package packagename {packagenamespace ""} {packageversion 1.0} {tclversion TCL_VERSION}"
        set ::tsp::COMPILE_PACKAGE 0
        return
    }
    set ::tsp::COMPILE_PACKAGE 1
    set ::tsp::PACKAGE_NAME $packagename
    set ::tsp::PACKAGE_NAMESPACE $packagenamespace
    set ::tsp::PACKAGE_VERSION $packageversion
    set ::tsp::TCL_VERSION $tclversion
    # reset system in case
    set ::tsp::COMPILER_LOG [dict create]
    set ::tsp::COMPILED_PROCS [dict create]
    set ::tsp::TRACE_PROC ""
    set ::tsp::PACKAGE_PROCS ""
    
    catch { unset ::tsp::TCC_HANDLE}
    set ::tsp::TCC_HANDLE [tcc4tcl::new]

    set ::tsp::PACKAGE_PROCS ""
    set ::tsp::PACKAGE_INIT_PROC 0
    set ::tsp::TCL_PROCS ""
    #if {$::tsp::PACKAGE_HEADER eq ""} {
        # $::tsp::PACKAGE_HEADER gets include from tcc4tcl handle later
    set ::tsp::PACKAGE_HEADER \
        {
/* START OF PACKAGE_HEADER */
/* don't forget to declare includedir tsp-package/native/clang/ in the right way */
#include <string.h>
#include <tclInt.h>
#include "TSP_cmd.c"
#include "TSP_func.c"
#include "TSP_util.c"

/* for tcc to work we need some constants defined */
#define __i386__ 1
#if defined(__i386__)
// FPU control word for rounding to nearest mode
unsigned short __tcc_fpu_control = 0x137f;
// FPU control word for round to zero mode for int conversion
unsigned short __tcc_int_fpu_control = 0x137f | 0x0c00;
#endif

/* END OF PACKAGE_HEADER */
    }
    #}
    
    $::tsp::TCC_HANDLE add_include_path "$::tsp::HOME_DIR/native/clang/"
    $::tsp::TCC_HANDLE add_include_path $packagename
    $::tsp::TCC_HANDLE add_library_path $packagename

    $::tsp::TCC_HANDLE ccode $::tsp::PACKAGE_HEADER
    
    set ::tsp::LOAD_TCLS "" 
    set ::tsp::LOAD_DLLS "" 
    set ::tsp::EXTERNAL_DLLS "" 
    
}

proc ::tsp::finalize_package {{packagedir ""} {compiler none}} {
    if {$::tsp::PACKAGE_NAME eq ""} {
         puts "Err: No package name given: use init_package packagename"
        set ::tsp::COMPILE_PACKAGE 0
    }
    if {$::tsp::COMPILE_PACKAGE==0} {
        puts "Err: No package building started: use init_package"
        return
    }

    set tsp::PACKAGE_DIR $packagedir
    if {![file isdir $tsp::PACKAGE_DIR]} {
        file mkdir $tsp::PACKAGE_DIR
    }
    
    ::tsp::rewrite_procnamespace
    
    if {$compiler eq ""} {
        set compiler "intern"
    }
    if {$compiler ni "intern memory"} {
        if {[info commands "::tcc4tcl::write_packagecode"] ne "::tcc4tcl::write_packagecode"} {
            set ::tsp::COMPILE_DIRECTIVES ""
            puts "failed crafting compiledirectives... use package require tcc4tcc-helper"
        } else {
            set ::tsp::COMPILE_DIRECTIVES [::tcc4tcl::write_packagecode $::tsp::TCC_HANDLE $::tsp::PACKAGE_NAME $tsp::PACKAGE_DIR $::tsp::PACKAGE_VERSION $::tsp::TCL_VERSION]
        }
    }
    # list with four commandlines, tcc_compile, gcc_compile, cross_compile, lin64_compile
    
    ::tsp::write_pkgAltTcl $::tsp::PACKAGE_NAME
    ::tsp::write_pkgIndex $::tsp::PACKAGE_NAME
    
    # copy source to package... if already in place, rename
    set t [clock format [clock seconds] -format "%Y-%m-%d_%H-%M-%S"]
    set srcname "${::tsp::PACKAGE_NAME}_tsp_${t}.tcl"
    set srcname [file join $tsp::PACKAGE_DIR $srcname]
    set vdiff 1
    catch {
        set lastsrcname [file join $tsp::PACKAGE_DIR "${::tsp::PACKAGE_NAME}_tsp_*.tcl"]
        set lastsrcname [lindex [lsort -decreasing [glob $lastsrcname]] 0]
        set vdiff [version:filediff $::tsp::ACTSOURCE $lastsrcname]
    }
    if {$vdiff >0} {
        puts "Copy src to $srcname"
        file copy "$::tsp::ACTSOURCE" "$srcname"
    }
    
    ::tsp::compile_package $::tsp::PACKAGE_NAME $compiler
    set ::tsp::COMPILE_PACKAGE 0
    set ::tsp::PACKAGE_NAME ""
}

proc ::tsp::add_tclinclude {fname} {
    # load tcls for additional sources
    lappend ::tsp::LOAD_TCLS $fname
}
proc ::tsp::add_bininclude {fname} {
    # load_dlls for dlls wich should be loaded into interp
    lappend ::tsp::LOAD_DLLS $fname
}
proc ::tsp::add_dllinclude {fname} {
    # external dlls wich are dependencies and do not get loaded into interp
    lappend ::tsp::EXTERNAL_DLLS $fname
}

proc ::tsp::test_packageX {packagename {callcmd ""} {shell "./tclkit_866_3.upx.exe"}} {
    # ok, now things really get difficult, if the directory structure doesn't work
    set result "failed testloading package $packagename"
    set callresult ""
    puts "Testing package $packagename"
    if {[catch {
        puts "Creating new exec"
        set fd [open resrc.tcl w]
        puts "appending auto_path with [file dir $tsp::PACKAGE_DIR]"
        puts $fd "console show"
        puts $fd "lappend auto_path [file dir $tsp::PACKAGE_DIR]"
        puts "Loading package... $packagename"
        puts $fd "package require $packagename"
        
        if {$callcmd ne ""} {
            puts "Calling $callcmd"
            puts $fd $callcmd
        }
    } err]} {
        puts "Error while preparing package $packagename\n$err"
    }
    close $fd
    puts "Go"
    
    # shell actually hardcoded... todo implement some clever routine to find nearest kit
    
    if {[catch {
        if {![file exists $shell]} {
            puts "Shell not found $shell... searching"
            # mark your shells as tclkit-8.6.6.exe to get found 866 8-6-6 all will do
            # this will search for 8.6.6 shell
            # or at least any 8.6 shell
            set flist [glob tclkit*.exe]
            set cand ""
            foreach kit $flist {
                set vnum [join [regexp -all -inline "\[0-9\]" $kit]]
                set vstring2 [join [lrange $vnum 0 1] "."]
                set vstring3 [join [lrange $vnum 0 2] "."]
                if {$vstring2 eq "8.6"} {
                    lappend cand $kit $vstring3
                }
                if {$vstring3 eq "8.6.6"} {
                    # found an 866, use it
                    set shell $kit
                    puts "found $shell"
                    break;
                }
            }
            if {[llength $cand]==0} {
                puts "Error: Shell not found"
                return 
            }
            set cand [lsort -decreasing -stride 2 $cand]
            puts "Candidates $cand"
            set shell [lindex $cand 0]
            puts "using $shell"
            
        }
        exec $shell resrc.tcl &
    } err]} {
            puts "Error while preparing package $packagename\n$err"
        }
    return 
}

proc ::tsp::test_package {packagename {callcmd ""}} {
    # ok, now things really get difficult, if the directory structure doesn't work
    set result "failed testloading package $packagename"
    set callresult ""
    puts "Testing package $packagename"
    if {[catch {
        puts "Creating new interp"
        set ip [interp create]
        puts "appending auto_path with [file dir $tsp::PACKAGE_DIR]"
        $ip eval lappend auto_path [file dir $tsp::PACKAGE_DIR]
        puts "Loading package... $packagename"
        set result [$ip eval package require $packagename]
        if {$callcmd ne ""} {
            puts "Calling $callcmd"
            catch {
                set callresult [$ip eval $callcmd]
            } errcall
            puts "...result:"
            puts $callresult
            if {$errcall ne ""} {
                puts $errcall
            }
        }
    } err]} {
        puts "Error while testing package $packagename\n$err"
    }
    puts "Got Result: $result"
    puts "deleting interp"
    interp delete $ip
    return $result
}

proc ::tsp::test_altpackage {packagename {callcmd ""}} {
    # ok, now things really get difficult, if the directory structure doesn't work
    set result "failed testloading package $packagename"
    set callresult ""
    puts "Testing package $packagename"
    if {[catch {
        puts "Creating new interp"
        set ip [interp create]
        puts "Loading TCL package... $packagename.tclprocs.tcl"
        set result [$ip eval source [file join $tsp::PACKAGE_DIR "${packagename}.tclprocs.tcl"]]
        puts "Loading TCL package... $packagename.puretcl.tcl"
        set result [$ip eval source [file join $tsp::PACKAGE_DIR "${packagename}.puretcl.tcl"]]

        #$ip eval  ${packagename}_pkgInit
        
        if {$callcmd ne ""} {
            puts "Calling $callcmd"
            catch {
                set callresult [$ip eval $callcmd]
            } errcall
            puts "...result:"
            puts $callresult
            if {$errcall ne ""} {
                puts $errcall
            }
        }
    } err]} {
        puts "Error while testing package $packagename\n$err"
    }
    puts "Got Result: $result"
    puts "deleting interp"
    interp delete $ip
    return $result
}
    
##############################################################################
# internal routines
##############################################################################

proc ::tsp::rewrite_procnamespace {} {
    if {$::tsp::PACKAGE_NAMESPACE eq ""} {
        #return 0
    }
    set handle $::tsp::TCC_HANDLE
    upvar #0 $handle state 
    if {![array exists state]} { return}
    if {[catch { set p $state(procs)} e]} {return}
    set nsprocs ""
    foreach {procname cprocname} $state(procs) {
        if {[lsearch $::tsp::PACKAGE_PROCS [namespace tail $procname]]<0} {
            # pure c implemented... probs ahead :-)
            set procdef [list $procname "args" [list puts "Not implemented \"$procname\""]]
            puts "found pure c proc $procname, replacing dummy $procdef"
            lappend ::tsp::PACKAGE_PROCS $procname $procdef
            set cdef [dict get $state(procdefs) $procname]
            lassign $cdef cprocname rtype cprocargs
            set procargs ""
            foreach {ctype vname} $cprocargs {
                lappend procargs $ctype
            }
            #lappend ::tsp::COMPILED_PROCS $procname [list $rtype $procargs $cprocname]
        }
    }
    if {$::tsp::PACKAGE_NAMESPACE eq ""} {
        return 0
    }
    foreach {procname cprocname} $state(procs) {
        if {[namespace qualifier $procname] eq ""} {
            set nsprocname "::${::tsp::PACKAGE_NAMESPACE}::$procname"
            puts "Namespace rewriting $procname to $nsprocname"
        } else {
            set nsprocname $procname
        }
        lappend nsprocs $nsprocname $cprocname
    }
    set state(procs) $nsprocs
}

proc ::tsp::write_pkgIndex {packagename} {
    # write a pkindex.tcl file to load package
    if {$tsp::PACKAGE_DIR eq ""} {
        set filename [file join $tsp::PACKAGE_DIR "$packagename.pkgIndex.tcl"]
    } else {
        set filename [file join $tsp::PACKAGE_DIR "pkgIndex.tcl"]
    }
    set fd [open $filename w]
    puts $fd "# Package Index for $packagename generated by TSP//TCCIDE Version $::_version"
    puts $fd "# Compiled Procs "
    puts $fd ""
    set cpr {}
    catch {set cpr $::tsp::PACKAGE_PROCS}
    foreach {procname procdef} $cpr {
        lassign $procdef cproc cvars cbody
        puts $fd "# ${::tsp::PACKAGE_NAMESPACE}::$cproc $cvars"
    }
    puts $fd "# TCL Procs "
    puts $fd ""
    set tclpr {}
    catch {set tclpr $::tsp::TCL_PROCS}
    foreach tcldef $tclpr {
        lassign $tcldef cproc cvars cbody
        puts $fd "# $cproc $cvars"
    }
    set handle $::tsp::TCC_HANDLE
    set loadextlibs "proc ${packagename}_loadextdlls {dir} {\ncatch {\n"
    append loadextlibs {set appdir [file dir [info nameofexecutable]]}
    append loadextlibs "\n"
    
    set libs [$handle add_library]
    set ::tsp::EXTERNAL_DLLS [lsort -unique $::tsp::EXTERNAL_DLLS]
    if {$::tsp::EXTERNAL_DLLS ne ""} {
        lappend libs {*}$::tsp::EXTERNAL_DLLS
    }
    foreach incpath $libs {
        append loadextlibs "\nset incdll \[file join \$dir $incpath\[info sharedlibextension\]\]\n"
        append loadextlibs "set appdll \[file join \$appdir $incpath\[info sharedlibextension\]\]\n"
        append loadextlibs "if {!\[file exists \$appdll\]} {\n"
        append loadextlibs "    puts \"Copy \$incdll --> \$appdll\"\n"
        append loadextlibs "    file copy \$incdll \$appdll\n"
        append loadextlibs "}\n"
    }
    append loadextlibs "}\n}\n"
    if {[llength $libs] ==0} {
        set loadextlibs ""
    }
    
    set pkgloadlib  "proc ${packagename}_loadlib {dir packagename} {\n"
    if {$loadextlibs ne ""} {
        append pkgloadlib "     ${packagename}_loadextdlls \$dir\n"
        append pkgloadlib "     ${packagename}_loadext \$dir\n"
    }
    if {$cpr ne ""} {
        append pkgloadlib "     if {\[catch {load \[file join \$dir \$packagename\[info sharedlibextension\]\]} err\]} {\n"
        append pkgloadlib "         source  \[file join \$dir \${packagename}.tclprocs.tcl\]\n"
        append pkgloadlib "     }\n"
    }
    
    if {$tclpr ne ""} {
        # load puretcl proc also
        append pkgloadlib "     source  \[file join \$dir \${packagename}.puretcl.tcl\]\n" 
        if {$::tsp::PACKAGE_INIT_PROC>0} {
            append pkgloadlib "     # call pkgInit procedure to initialise pkg if given\n"
            append pkgloadlib "     return \[ catch {\${packagename}_pkgInit} e\] \n"
        }
    }
    append pkgloadlib "}\n"
    
    set pkgloadext  "proc ${packagename}_loadext {dir} {\n"
    foreach extdll [lsort -unique $::tsp::LOAD_DLLS] {
        #
        append pkgloadext "     if {\[catch {load \[file join \$dir $extdll\[info sharedlibextension\]\]} err\]} {\n"
        append pkgloadext "         puts \"Error loading $extdll \$err\"\n"
        append pkgloadext "     }\n"
    }
    foreach exttcl [lsort -unique $::tsp::LOAD_TCLS] {
        #
        append pkgloadext "     if {\[catch {source  \[file join \$dir ${exttcl}.tcl\]} err\]} {\n" 
        append pkgloadext "         puts \"Error loading $exttcl \$err\"\n"
        append pkgloadext "     }\n"
    }
    append pkgloadext "}\n"
    
    
    set pkgrun "package ifneeded $packagename $::tsp::PACKAGE_VERSION \[list ${packagename}_loadlib \$dir {$packagename}\]\n"

    puts $fd $loadextlibs
    puts $fd $pkgloadlib
    puts $fd $pkgloadext
    puts $fd $pkgrun
    close $fd
}

proc ::tsp::write_pkgAltTcl {packagename} {
    # write an tcl file to keep all procs as alternate to compiled procs (can't load)
    # and those procs, that we didn't compile
    set filename [file join $tsp::PACKAGE_DIR "$packagename.tclprocs.tcl"]
    set fd [open $filename w]
    puts $fd "#  TSP Pure TCL procs for loadlib failure management"
    puts $fd "#   package $packagename"
    puts $fd "package provide $packagename $::tsp::PACKAGE_VERSION" 
    if {$::tsp::PACKAGE_NAMESPACE ne ""} {
        set nsvars [lsort -unique $::tsp::NAMESPACE_VARS]
        puts $fd "namespace eval $::tsp::PACKAGE_NAMESPACE {"
        foreach nsvar $nsvars {
            puts $fd "variable $nsvar"
        }
        puts $fd "}"
    }
    foreach {procname procdef} $::tsp::PACKAGE_PROCS  {
        lassign $procdef procname procargs procbody
        if {$procname eq "${packagename}_pkgInit"} {
            set ::tsp::PACKAGE_INIT_PROC 1
        }
        if {$::tsp::PACKAGE_NAMESPACE ne ""} {
            set procname "::${::tsp::PACKAGE_NAMESPACE}::$procname"
        }
        # replace #tsp::altTCL makro 
        set procbody [string map -nocase {"#tsp::altTCL " ""} $procbody]
        puts $fd "proc $procname {$procargs} {$procbody}\n"
    }
    close $fd
    
    ::tsp::splice_src  "$::tsp::ACTSOURCE"
    set filename [file join $tsp::PACKAGE_DIR "${packagename}.puretcl.tcl"]
    set fd [open $filename w]
    puts $fd "#  TSP Pure TCL procs for loadlib complemenary procs"
    puts $fd "#   package $packagename"
    puts $fd "#   "
    if {$::tsp::COMPILED_PROCS eq ""} {
        puts $fd "package provide $packagename $::tsp::PACKAGE_VERSION" 
    }
    if {$::tsp::PACKAGE_NAMESPACE ne ""} {
        set nsvars [lsort -unique $::tsp::NAMESPACE_VARS]
        puts $fd "namespace eval $::tsp::PACKAGE_NAMESPACE {"
        foreach nsvar $nsvars {
            puts $fd "variable $nsvar"
        }
        puts $fd "}"
    }

    foreach procdef $tsp::TCL_PROCS {
        lassign $procdef procname procargs procbody
        if {$procname eq "${packagename}_pkgInit"} {
            set ::tsp::PACKAGE_INIT_PROC 1
        }
        puts $fd "proc ${procname} {$procargs} {$procbody}"
    }
    
    close $fd
}

proc ::tsp::compile_package {packagename {compiler tcc}} {
    # evtl compile c-source
    
    set ctype -1
    set ctype [dict get "none -1 tcc 0 gcc 1 cross 2 lin64 3 intern 9 memory 9 export 9 debug 99" $compiler]
    if {$ctype<0} {
        puts "ERROR: Unknown compiler $compiler or given none..."
        return -1
    }
    if {$ctype==9} {
        puts "Compiling in Memory"
        $::tsp::TCC_HANDLE go
        return 1
    }
    if {$ctype==99} {
        puts "Debug Source"
        puts [$::tsp::TCC_HANDLE code]
        return 1
    }

    if {$tsp::COMPILE_DIRECTIVES eq ""} {
        puts "ERROR: No compiler directives found"
        return -1
    }
    if {$tsp::PACKAGE_DIR eq ""} {
        puts "No packagedir given, searching in $packagename/$packagename.c"
        #$tsp::PACKAGE_DIR 
        set filename [file join $tsp::PACKAGE_DIR "$packagename.c"]
        if {![file exists $filename]} {
            set tsp::PACKAGE_DIR $packagename
        }
    }

    set filename [file join $tsp::PACKAGE_DIR "$packagename.c"]
    set dllname [file join $tsp::PACKAGE_DIR "$packagename.dll"]
    if {![file exists $filename]} {
        puts "ERROR: $filename source not found"
        return -1
    }
    
    set wd [pwd]
    if {$::tccenv::tccexecutabledir ne ""} {
        cd $::tccenv::tccexecutabledir
    }
    set cdirect [lindex $tsp::COMPILE_DIRECTIVES $ctype]
    #set cdirect [string map [list "$packagename.c" $filename] $cdirect]
    #set cdirect [string map [list "$packagename.dll" $dllname] $cdirect]
    
    puts "Compiling external $cdirect"
    catch {
        eval exec $cdirect
    } err
    cd $wd
    puts "Result:\n$err\n"
    if {[string first " error: " $err]>-1} {
        puts "Compiling seems to have errors, execution halted"
        return -code error
    }
    return 1
}

proc ::tsp::splice_src {filename} {
    if {![file exists $filename]} {
        puts "ERROR: $filename source not found"
        return -1
    }

    set f [open "$filename"]
    set data [read $f]
    close $f
    set ::tsp::TCL_PROCS ""
    foreach {dummy procName} [regexp -all -inline -line {^[\s:]*proc (\S+)} $data] {
        catch {
            set procargs ""
            set _procargs [info args $procName]
            foreach _procarg $_procargs {
                if {[info default $procName $_procarg def]>0} {
                    set _procarg "$_procarg \"$def\""
                } 
                lappend procargs $_procarg
            }
            set procbody [info body $procName]
            lappend ::tsp::TCL_PROCS  [list $procName $procargs $procbody]
        }
    }
}

proc version:filediff {file1 file2 {cmdEqual {version:cmdEqual}} {cmdAdd {version:cmdAdd}} {cmdDel {version:cmdDel}}} {
        set sourcefid1 [open $file1 r]
        set sourcefid2 [open $file2 r]
        set ::afilediffs 0
        
        set ::actdiff "#------------------------------------------------\n# Src: $file1\n# Trg $file2\n"
        set diffminor 0;# if this is set to 0, lines will be trimmed befor comparison, empty lines will be dropped
        set found 1
        set srcline 0
        set trgline 0
        while {![eof $sourcefid1] && ![eof $sourcefid2]} {
                set lastmark [tell $sourcefid2] ;# Position in <file2> before reading the next line
                gets $sourcefid1 line1
                gets $sourcefid2 line2
                if {$diffminor==0} {
                    set line1 [string trim $line1]
                    set line2 [string trim $line2]
                }
                incr srcline
                incr trgline
                if {$line1 eq $line2} {
                        $cmdEqual $line1 $srcline
                        continue
                }
                
                # Lines with only whitespace are also equal
                if {[regexp -- {^\s*$} $line1] && [regexp -- {^\s*$} $line2]} {
                        $cmdEqual {} $srcline
                        continue
                }

                # From here both lines are unequal

                set state 0
                while {[regexp -- {^\s*$} $line1]} {
                        # If unequal then directly state empty lines in <file1> as deleted.
                        $cmdDel $line1 $srcline
                        if {![eof $sourcefid1]} {
                                gets $sourcefid1 line1
                                if {$line1 eq $line2} {
                                        $cmdEqual $line1 $srcline
                                        set state 1
                                        break
                                }
                        } else {
                                break
                        }
                }
                if {$state} {
                        continue
                }
                
                # Remember position in <file2> and look forward
                set mark2  [tell $sourcefid2]
                set mark2a $lastmark
                set found 0
                while {![eof $sourcefid2]} {
                        gets $sourcefid2 line2
                        if {$line1 ne $line2} {
                                set mark2a $mark2
                                set mark2 [tell $sourcefid2]
                        } else {
                                # Found a matching line. Everything up to the line before are new lines
                                seek $sourcefid2 $lastmark
                                while {[tell $sourcefid2] <= $mark2a} {
                                        gets $sourcefid2 line2
                                        $cmdAdd $line2 $srcline
                                }
                                gets $sourcefid2 line2
                                $cmdEqual $line2 $srcline
                                set found 1
                                break
                        }
                }
                if {!$found} {
                        # No matching line found in <file2>. Line must be deleted
                        $cmdDel $line1 $srcline
                        seek $sourcefid2 $lastmark
                }
        }
        # Output the rest of <file1> as deleted
        while {![eof $sourcefid1]} {
                gets $sourcefid1 line1
                $cmdDel $line1 $srcline
        }

        # Output the rest of <file2> as added
        while {![eof $sourcefid2]} {
                gets $sourcefid2 line2
                $cmdAdd $line2 $srcline
        }
        close $sourcefid2
        close $sourcefid1
        if {$::afilediffs>0} {
            lappend ::lfilediffs $file1 $file2
            append ::tfilediffs $::actdiff
            incr ::cfilediffs $::afilediffs
        }
        return $::afilediffs
}
proc version:cmdEqual {txt line} {
}
proc version:cmdAdd {txt line} {
        append ::actdiff "$line: +$txt\n";update
        incr ::afilediffs
}
proc version:cmdDel {txt line} {
    if {[string trim $txt]!=""} {
        append ::actdiff "$line: -$txt\n";update
        incr ::afilediffs
    }
}


