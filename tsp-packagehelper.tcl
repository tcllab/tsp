##############################################################################
#tsp package helper commands for tccide
#
# package building process
#
# package structure
# PACKAGENAME_tsp_YYYY-MM-DD-hh-mm-ss.tcl (with tsp directives to create package)
# pkgIndex.tcl
# PACKAGENAME.puretcl.tcl (Untouched, pure TCL procs)
# PACKAGENAME.tclprocs.tcl (TCL Replacment procs)
# PACKAGENAME.c (sourcecode, final)
# PACKAGENAME.dll (binary file)
# 
##############################################################################

package require tcc4tcl
source [file join [file dirname [info script]] tcc4tcl_helper.tcl]

namespace eval ::tsp {
    # added for code package making MiR, also defined and used in tsp.tcl
    variable COMPILE_PACKAGE 0
    variable PACKAGE_NAMESPACE ""
    variable PACKAGE_HEADER ""
    variable PACKAGE_PROCS ""
    variable NAMESPACE_VARS ""
    variable TCC_HANDLE 

    variable TSP_VERSION "-unknown-"
    
    # these variables are NOT to be used elsewhere in tsp
    variable PACKAGE_NAME ""
    variable PACKAGE_VERSION "1.0"
    variable PACKAGE_DIR ""
    variable writepkg 1 ;# controls if any code is written out
    variable TEST_PROC ""
    #variable TSPPACKAGE_SPACE [file normalize [file dirname [info script]]]
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
    variable ACTSOURCE ""
    
    variable _HOOK_LEVEL 0
}

proc ::tsp::hook_proc {level} {
    # we hook the proc construct to get information about package defined procs
    variable _HOOK_LEVEL
    set _HOOK_LEVEL $level
    #puts "Hooking proc $level"
    if {[info command ::__proc] eq ""} {
        rename ::proc ::__proc
        ::__proc ::proc {procName procargs procbody} {
            #puts "Hook hit $procName in -[info script]- lv [info level]==$::tsp::_HOOK_LEVEL ?"
            set nsprocname $procName
            if {(([info script] eq "")||([info script] eq $::tsp::ACTSOURCE))&&([info level]==$::tsp::_HOOK_LEVEL)} {
                #puts "lappend ::tsp::TCL_PROCS  [list $procName $procargs $procbody]"
                if {$::tsp::PACKAGE_NAMESPACE ne ""} {
                    set nsprocname ::${::tsp::PACKAGE_NAMESPACE}::$procName
                    puts "Namespace rewriting $procName to $nsprocname"
                    # check if namespace exists or create it
                    if {[namespace exists ::${::tsp::PACKAGE_NAMESPACE}]==0} {
                        namespace eval ::${::tsp::PACKAGE_NAMESPACE} {}
                    }
                }
                lappend ::tsp::TCL_PROCS  [list $nsprocname $procargs $procbody]
            }
            if {[catch {uplevel 0 ::__proc [list $nsprocname $procargs $procbody]} err]} {
                rename ::proc ""
                rename ::__proc ::proc
                return -code error "Error in proc $err"
            }
        }
    }

}

proc ::tsp::unhook_proc {} {
    # release the hooked proc construct
    # if you eval external code, don't forget to handle errors in eval and call unhook_proc, just in case
    if {[info command ::__proc] eq "::__proc"} {
        rename ::proc ""
        rename ::__proc ::proc
    }
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
    
    #which version of tsp did create the source? 
    if {$::tsp::TSP_VERSION eq "-unknown-"} {
        # try taking it from application
        catch {set ::tsp::TSP_VERSION $::_version}
    }
    # reset system in case
    set ::tsp::COMPILER_LOG [dict create]
    set ::tsp::COMPILED_PROCS [dict create]
    set ::tsp::TRACE_PROC ""
    set ::tsp::PACKAGE_PROCS ""
    
    catch { unset ::tsp::TCC_HANDLE}
    set ::tsp::TCC_HANDLE [tcc4tcl::new]

    set ::tsp::NAMESPACE_VARS ""
    set ::tsp::PACKAGE_INIT_PROC 0
    set ::tsp::TCL_PROCS ""
    set ::tsp::PACKAGE_HEADER "
/* START OF PACKAGE_HEADER TSP (Version $::tsp::TSP_VERSION) */
/* don't forget to declare includedir tsp-package/native/clang/ in the right way */
#include <string.h>
#include <tclInt.h>
#include \"TSP_cmd.c\"
#include \"TSP_func.c\"
#include \"TSP_util.c\"
/* END OF PACKAGE_HEADER */
    "
    
    $::tsp::TCC_HANDLE add_include_path "$::tsp::HOME_DIR/native/clang/"
    $::tsp::TCC_HANDLE add_include_path $packagename
    $::tsp::TCC_HANDLE add_library_path $packagename

    $::tsp::TCC_HANDLE ccode $::tsp::PACKAGE_HEADER
    
    set ::tsp::LOAD_TCLS "" 
    set ::tsp::LOAD_DLLS "" 
    set ::tsp::EXTERNAL_DLLS "" 
    
    ::tsp::hook_proc [info level]
}
proc ::tsp::package_export {exportprocnames} {
    #
}
proc ::tsp::finalize_package {{packagedir ""} {compiler none}} {
    ::tsp::unhook_proc

    if {$::tsp::PACKAGE_NAME eq ""} {
         puts "Err: No package name given: use init_package packagename"
        set ::tsp::COMPILE_PACKAGE 0
    }
    if {$::tsp::COMPILE_PACKAGE==0} {
        puts "Err: No package building started: use init_package"
        return
    }

    set ::tsp::PACKAGE_DIR $packagedir
    if {![file isdir $::tsp::PACKAGE_DIR]} {
        file mkdir $::tsp::PACKAGE_DIR
    }
    
    ::tsp::rewrite_procnamespace
    ::tcc4tcl::prepare_packagecode $::tsp::TCC_HANDLE
    
    if {$compiler eq ""} {
        set compiler "intern"
    }
    if {$compiler ni "intern memory"} {
        if {[info commands "::tcc4tcl::write_packagecode"] ne "::tcc4tcl::write_packagecode"} {
            set ::tsp::COMPILE_DIRECTIVES ""
            puts "failed crafting compiledirectives... use package require tcc4tcc-helper"
        } else {
            set ::tsp::COMPILE_DIRECTIVES [::tcc4tcl::write_packagecode $::tsp::TCC_HANDLE $::tsp::PACKAGE_NAME $::tsp::PACKAGE_DIR $::tsp::PACKAGE_VERSION $::tsp::TCL_VERSION]
        }
    } 
    
    # add a little help function
    if {$::tsp::PACKAGE_NAMESPACE eq ""} {
        set help_proc ::${::tsp::PACKAGE_NAME}_help
    } else {
        set help_proc ::${::tsp::PACKAGE_NAMESPACE}::help
    }
    # add help-index
    set help_body " puts {\n"
    append help_body [::tsp::getProcIndex $::tsp::PACKAGE_NAME]
    append help_body "\n}\n"
    set help_procdef [list $help_proc "" $help_body]
    set cmd "::$help_proc {} $help_body"
    ::proc ::$help_proc {} $help_body
    lappend ::tsp::TCL_PROCS $help_procdef
    if {$::tsp::writepkg>0} {
        puts "writing pkg $::tsp::PACKAGE_NAME from -$::tsp::ACTSOURCE-"
        ::tsp::write_pkgAltTcl $::tsp::PACKAGE_NAME
        ::tsp::write_pkgIndex $::tsp::PACKAGE_NAME
    }
    # if a source file is given
    # copy source to packagedir... if already in place, rename
    if {($::tsp::ACTSOURCE ne "")&&[file exist $::tsp::ACTSOURCE]} {
        set t [clock format [clock seconds] -format "%Y-%m-%d_%H-%M-%S"]
        set srcname "${::tsp::PACKAGE_NAME}_tsp_${t}.tcl"
        set srcname [file join $::tsp::PACKAGE_DIR $srcname]
        set vdiff 1
        catch {
            set lastsrcname [file join $::tsp::PACKAGE_DIR "${::tsp::PACKAGE_NAME}_tsp_*.tcl"]
            set lastsrcname [lindex [lsort -decreasing [glob $lastsrcname]] 0]
            set vdiff [version:filediff $::tsp::ACTSOURCE $lastsrcname]
        }
        if {$vdiff >0} {
            puts "Copy src $::tsp::ACTSOURCE to $srcname"
            file copy "$::tsp::ACTSOURCE" "$srcname"
        }
    }
    
    ::tsp::compile_package $::tsp::PACKAGE_NAME $compiler

    # pkginit?
    if {$::tsp::PACKAGE_INIT_PROC>0} {
        if {$compiler in "intern memory"} {
            if {[catch {${::tsp::PACKAGE_NAME}_pkgInit} e]} {
                puts "error ${::tsp::PACKAGE_NAME}_pkgInit: $e"
            }
        }
    }
    set ::tsp::COMPILE_PACKAGE 0
    set ::tsp::PACKAGE_NAME ""
        
}

proc ::tsp::addExternalCompiler {compiler ccOptions exeDir exeFile {compilertype gccwin32}} {
    # add external compiler to list EXTERNAL_COMPILERS
    # $compiler:        compilername cc
    # $ccOptions       additional options to use with cc
    # $exeDir           directory to execute cc in
    # $exeFile          cc to execute
    # compilertype      can be gccwin32/gcclin64/tccwin32/tcclin64/user   and defines prebuilt ccOptions to use; set to user to have no predefined options
    tcc4tcl::addExternalCompiler $compiler $ccOptions $exeDir $exeFile $compilertype 
}

proc ::tsp::safeEval {cmd} {
    # eval string cmd in global namespace, catch errors and eventually reset proc handler
    if {[catch {
        set r [namespace eval :: "$cmd"]
        puts "Result: $r"
    } err]} {
        interp delete sl
        ::tsp::unhook_proc
        puts "Eval Error: $err"
    }
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

proc ::tsp::test_packageX {packagename {callcmd ""} {shell "tclkit_8.6.12.exe"}} {
    # ok, now things really get difficult, if the directory structure doesn't work "./tclkit_866_3.upx.exe"
    # this actually only works under windows, you need a tclkit named $shell in the current working dir
    set result "failed testloading package $packagename in [pwd]"
    set callresult ""
    set packagedir [file dir $packagename]
    set packagename [file tail $packagename]
    puts "Testing package $packagename in [pwd]"
    if {[catch {
        puts "Creating new exec"
        set res_name [file normalize resrc.tcl]
        set fd [open $res_name w]
        fconfigure $fd -translation lf
        puts $fd "#!/usr/bin/tclsh"
        puts $fd "catch {console show}"
        puts ">>> appending auto_path with [file normalize [file dir $::tsp::PACKAGE_DIR]]"
        puts $fd "lappend auto_path ."
        puts $fd "lappend auto_path [file normalize [file dir $::tsp::PACKAGE_DIR]]"
        #puts "Testing for [file dir $::tsp::PACKAGE_DIR] ne $packagedir"
        if {[file dir $::tsp::PACKAGE_DIR] ne $packagedir} {
            puts ">>> appending auto_path with $packagedir"
            puts $fd "lappend auto_path $packagedir"
        }
        #puts "Appending $::tsp::TSPPACKAGE_SPACE"
        #puts $fd "lappend auto_path $::tsp::TSPPACKAGE_SPACE"
        puts ">>> Load package... $packagename"
        puts $fd "package require $packagename"
        
        if {$callcmd ne ""} {
            puts ">>> Call $callcmd"
            puts $fd $callcmd
        }
    } err]} {
        puts "Error while preparing package $packagename\n$err"
    }
    close $fd
    puts ">>> Go"
    
    # shell actually hardcoded... todo implement some clever routine to find nearest kit
    # and to run under linux
    if {$::tcl_platform(platform)=="unix"} {
        puts "Seems to be a native linux, calling tclsh $res_name"
        #exec >@stdout tclsh resrc.tcl
        # solution:
        set runcmd "exec tclsh \"$res_name\" 2>@stderr"
        #"
        puts "running $runcmd"
        if {[catch $runcmd res]} {
          error "Failed to run command $runcmd: $res"
        }
        
        puts $res
    } else {
        if {[catch {
            if {![file exists $shell]} {
                puts "Shell not found $shell... searching"
                # mark your shells as tclkit-8.6.6.exe to get found 866 8-6-6 all will do
                # this will search for 8.6.6 shell
                # or at least any 8.6 shell
                set flist [glob -nocomplain tclkit*.exe]
                if {[llength $flist]==0} {
                    puts "Shell not found in ./ ... searching $::tccenv::tclexedir"
                    set flist [glob -nocomplain [file join $::tccenv::tclexedir tclkit*.exe]]
                    puts $flist
                }
                set cand ""
                foreach kit $flist {
                    set vnum [join [regexp -all -inline "\[0-9\]" [file tail $kit]]]
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
            exec $shell $res_name &
        } err]} {
                puts "Error while preparing package $packagename\n$err"
        }
    }
    return 
}

proc ::tsp::test_package {packagename {callcmd ""}} {
    # ok, now things really get difficult, if the directory structure doesn't work
    # careful, loading a dll into the interp leads to a lock on the dll file, so recompiling it will fail due to writelock
    set result "failed testloading package $packagename"
    set callresult ""
    puts "Testing package $packagename"
    if {[catch {
        puts "Creating new interp"
        set ip [interp create]
        puts "appending auto_path with [file dir $::tsp::PACKAGE_DIR]"
        $ip eval lappend auto_path [file dir $::tsp::PACKAGE_DIR]
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
        set result [$ip eval source [file join $::tsp::PACKAGE_DIR "${packagename}.tclprocs.tcl"]]
        puts "Loading TCL package... $packagename.puretcl.tcl"
        set result [$ip eval source [file join $::tsp::PACKAGE_DIR "${packagename}.puretcl.tcl"]]
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
            # pure c implemented... there will be no valid TCL representation
            ##set procdef [list $procname "args" [list puts "Not implemented \"$procname\""]]
            ##lappend ::tsp::PACKAGE_PROCS $procname $procdef
            catch {
                set cdef [dict get $state(procdefs) $procname]
                lassign $cdef cprocname rtype cprocargs
                set procargs ""
                set procargsfull ""
                foreach {ctype vname} $cprocargs {
                    lappend procargs $ctype
                    if {$vname!= "interp"} {
                        lappend procargsfull $vname
                    }
                }
                set procdef [list $procname "$procargsfull" [list puts "Not implemented \"$procname\""]]
                lappend ::tsp::PACKAGE_PROCS $procname $procdef
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

proc ::tsp::getProcIndex {packagename} {
    #
    set helpindex ""
    lappend helpindex "# Help Index:"
    lappend helpindex "# Generated at [set t [clock format [clock seconds] -format "%Y-%m-%d_%H-%M-%S"]]"
    lappend helpindex "# Package Index/Loader for $packagename generated by TSP//TCCIDE Version $::_version"
    lappend helpindex ""
    lappend helpindex "# Compiled Procs "
    lappend helpindex ""
    set cpr {}
    catch {set cpr $::tsp::PACKAGE_PROCS}
    foreach {procname procdef} $cpr {
        if {[string range $procname 0 1]!="__"} {
            lassign $procdef cproc cvars cbody
            lappend helpindex "# ${::tsp::PACKAGE_NAMESPACE}::$cproc $cvars"
        }
        if {$procname eq "${packagename}_pkgInit"} {
            set ::tsp::PACKAGE_INIT_PROC 1
            puts "Init via $procname"
        }
    }

    lappend helpindex ""
    lappend helpindex "# TCL Procs "
    lappend helpindex ""
    set tclpr {}
    catch {set tclpr $::tsp::TCL_PROCS}
    foreach tcldef $tclpr {
        lassign $tcldef cproc cvars cbody
        lappend helpindex [string map {\n "."} "# $cproc $cvars"]
        if {$cproc eq "${packagename}_pkgInit"} {
            set ::tsp::PACKAGE_INIT_PROC 1
            puts "Init via $cproc"
        }
    }
    return [join $helpindex \n]
}

proc ::tsp::write_pkgIndex {packagename} {
    # write a pkgindex.tcl file to load package
    if {$::tsp::PACKAGE_DIR eq ""} {
        set filename [file join $::tsp::PACKAGE_DIR "$packagename.pkgIndex.tcl"]
        set loadername [file join $::tsp::PACKAGE_DIR "$packagename.${packagename}.loader.tcl"]
    } else {
        set filename [file join $::tsp::PACKAGE_DIR "pkgIndex.tcl"]
        set loadername [file join $::tsp::PACKAGE_DIR "${packagename}.loader.tcl"]
    }
    
    set fd [open $loadername w]

    puts $fd [::tsp::getProcIndex $packagename]
    
    set handle $::tsp::TCC_HANDLE
    set loadextlibs "proc ${packagename}_loadextdlls {dir} {\ncatch {\n"
    append loadextlibs {
        switch -- $::tcl_platform(platform) {
            windows {set appdir [file dir [info nameofexecutable]]}
            unix {
                set appdir [file dir [info script]]
                if {$appdir==$dir} {
                    set appdir [pwd]
                }
            }
        }
    }
    append loadextlibs "\n"
    
    set libs [$handle add_library]
    set ::tsp::EXTERNAL_DLLS [lsort -unique $::tsp::EXTERNAL_DLLS]
    if {$::tsp::EXTERNAL_DLLS ne ""} {
        lappend libs {*}$::tsp::EXTERNAL_DLLS
    }
    foreach incpath $libs {
        if {![file exists [file join $::tsp::PACKAGE_DIR $incpath[info sharedlibextension]]]} {
            set incpath lib$incpath
        }
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
    if {($loadextlibs ne "")} {
        append pkgloadlib "     ${packagename}_loadextdlls \$dir\n"
    }
    if {($loadextlibs ne "")||($::tsp::LOAD_DLLS ne "")} {
        append pkgloadlib "     ${packagename}_loadext \$dir\n"
    }
    if {$::tsp::PACKAGE_PROCS ne ""} {
        append pkgloadlib "     if {\[catch {load \[file join \$dir \$packagename\[info sharedlibextension\]\] \$packagename} err\]} {\n"
        append pkgloadlib "         source  \[file join \$dir \${packagename}.tclprocs.tcl\]\n"
        append pkgloadlib "     }\n"
    }
    
    if {$::tsp::TCL_PROCS ne ""} {
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
        append pkgloadext "     if {\[catch {load \[file join \$dir $extdll\[info sharedlibextension\]\]} err\]} {\n"
        append pkgloadext "         puts \"Error loading $extdll \$err\"\n"
        append pkgloadext "     }\n"
    }
    foreach exttcl [lsort -unique $::tsp::LOAD_TCLS] {
        append pkgloadext "     if {\[catch {source  \[file join \$dir ${exttcl}.tcl\]} err\]} {\n" 
        append pkgloadext "         puts \"Error loading $exttcl \$err\"\n"
        append pkgloadext "     }\n"
    }
    append pkgloadext "}\n"
    
    set pkgrun "#run loader here\n${packagename}_loadlib \[file dir \[info script\]\] {$packagename}\n"

    puts $fd $loadextlibs
    puts $fd $pkgloadlib
    puts $fd $pkgloadext
    puts $fd $pkgrun
    close $fd
    
    set fd [open $filename w]
    
    set pkgrun "package ifneeded $packagename $::tsp::PACKAGE_VERSION \[list source \[file join \$dir [file tail $loadername]\]\]"
    puts $fd $pkgrun
    close $fd
}

proc ::tsp::write_pkgAltTcl {packagename} {
    # write an tcl file to keep all procs as alternate to compiled procs (can't load)
    # and those procs, that we didn't compile
    
    # add a little help function
    if {$::tsp::PACKAGE_NAMESPACE eq ""} {
        set help_proc ::${packagename}_help
    } else {
        set help_proc ::${::tsp::PACKAGE_NAMESPACE}::help
    }
    
    set help_body " puts {...\n"
    append help_body [::tsp::getProcIndex $packagename]
    append help_body "\n}\n"
    set help_procdef [list $help_proc "" $help_body]
    
    if {[lsearch -index 0 $::tsp::TCL_PROCS $help_proc]==-1} {
        lappend ::tsp::TCL_PROCS $help_procdef
    }
    
    set filename [file join $::tsp::PACKAGE_DIR "$packagename.tclprocs.tcl"]
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
            puts "Init via $procname"
        }
        if {$::tsp::PACKAGE_NAMESPACE ne ""} {
            set procname "::${::tsp::PACKAGE_NAMESPACE}::$procname"
        }
        # replace #tsp::altTCL makro 
        set procbody [string map -nocase {"#tsp::altTCL " ""} $procbody]
        puts $fd "proc $procname {$procargs} {$procbody}\n"
    }
    close $fd
    
    set filename [file join $::tsp::PACKAGE_DIR "${packagename}.puretcl.tcl"]
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

    foreach procdef $::tsp::TCL_PROCS {
        lassign $procdef procname procargs procbody
        if {$procname eq "${packagename}_pkgInit"} {
            set ::tsp::PACKAGE_INIT_PROC 1
            puts "Init via $procname"
        }
        puts $fd "proc ${procname} {$procargs} {$procbody}\n"
    }
    
    close $fd
}

proc ::tsp::compile_package {packagename {compiler tccwin32}} {
    # evtl compile c-source
    # compile directives come from tcc4tcl_helper
    # since tccide is mainly developed for windows
    # it tries to find tcc.exe and gcc.exe in adjacent dirs to pwd
    # so, trying to compile the code on external compiler relies on this mechanism
    # so tcc and gcc options use win32 tcc.exe gcc.exe acoordingly
    # lin64 tries to call gcc on a linux bash
    # cross tries calling i686-w64-mingw32-gcc
    # if this fails, you can still use the generated compiler directives
    # as a boilerplate for manually compiling the source
    # compile to memory (intern or memory) and
    # compile to dynlib (export) 
    # with the integrated tcc4tcl should however work

    set EXTERNAL_COMPILERS $::tccenv::EXTERNAL_COMPILERS
    
    set ctype -1
    catch {
        set ctype [dict get "none -1 intern 9 memory 9 export 9 debug 99" $compiler]
    }
    if {$ctype<0} {
        # call plugin compiler here
        set cc ""
        if {[dict exists $EXTERNAL_COMPILERS $compiler]} {
            set ccl [dict get $EXTERNAL_COMPILERS $compiler]
            lassign $ccl cc ccOptions exeDir exeFile compilertype
        }
        if {$cc ne ""} {
            # call compiler 
        } else {
            # error not found
            puts "ERROR: Unknown compiler $compiler or given none..."
            return -1
        }
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

    if {$::tsp::COMPILE_DIRECTIVES eq ""} {
        puts "ERROR: No compiler directives found"
        return -1
    }
    if {$::tsp::PACKAGE_DIR eq ""} {
        puts "No packagedir given, searching in $packagename/$packagename.c"
        set filename [file join $::tsp::PACKAGE_DIR "$packagename.c"]
        if {![file exists $filename]} {
            set ::tsp::PACKAGE_DIR $packagename
        }
    }

    set filename [file join $::tsp::PACKAGE_DIR "$packagename.c"]
    set dllname [file join $::tsp::PACKAGE_DIR "$packagename.dll"]
    if {![file exists $filename]} {
        puts "ERROR: $filename source not found"
        return -1
    }
    
    set wd [pwd]
    if {$::tccenv::tccexecutabledir ne ""} {
        cd $::tccenv::tccexecutabledir
    }
    
    set cdirect [dict get $::tsp::COMPILE_DIRECTIVES $compiler]
    
    puts "Compiling external $cdirect"
    set  ::errorCode ""
    catch {
        exec {*}$cdirect
    } err
    cd $wd
    puts "Result:\n$err\n"
    if {[llength $::errorCode]>1} {
        puts "Compiling seems to have errors, execution halted"
        puts "errorCode $::errorCode"
        return -code error $err
    }
    return 1
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
    if {[string trim $txt]!=""} {
        append ::actdiff "$line: +$txt\n";update
        incr ::afilediffs
    }
}
proc version:cmdDel {txt line} {
    if {[string trim $txt]!=""} {
        append ::actdiff "$line: -$txt\n";update
        incr ::afilediffs
    }
}
proc version:clear {} {
    set ::lfilediffs ""
    set ::tfilediffs ""
    set ::cfilediffs 0
}
#----------------------------------- Code to remove -----------------------------------------

