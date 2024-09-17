
#########################################################
# add an error for the compUnit
#
proc ::tsp::addError {compUnitDict errorMsg} {
    upvar $compUnitDict compUnit
    dict lappend compUnit errors "[dict get $compUnit lineNum]: $errorMsg"
}


#########################################################
# get all of the logged warnings for the compUnit
#
proc ::tsp::getErrors {compUnitDict} {
    upvar $compUnitDict compUnit
    return [dict get $compUnit errors]
}


#########################################################
# get all of the logged errors for the compUnit with
# proc name and filename information
#
proc ::tsp::getLoggedErrors {compUnitDict} {
    upvar $compUnitDict compUnit
    set errors [dict get $compUnit errors]
    if {[llength $errors] == 0} {
        return [list]
    } 
    set filename [dict get $compUnit file]
    set name [dict get $compUnit name]
    set result [list]
    foreach error $errors {
        lappend result "$filename:$name - $error"
    }
    return $result
}


#########################################################
# add a warning for the compUnit
#
proc ::tsp::addWarning {compUnitDict warningMsg} {
    upvar $compUnitDict compUnit
    dict lappend compUnit warnings "[dict get $compUnit lineNum]: $warningMsg"
}


#########################################################
# get all of the current logged warnings for the compUnit

proc ::tsp::getWarnings {compUnitDict} {
    upvar $compUnitDict compUnit
    return [dict get $compUnit warnings]
}


#########################################################
# get all of the logged warnings for the compUnit with
# proc name and filename information
#
proc ::tsp::getLoggedWarnings {compUnitDict} {
    upvar $compUnitDict compUnit
    set warnings [dict get $compUnit warnings]
    if {[llength $warnings] == 0} {
        return [list]
    } 
    set filename [dict get $compUnit file]
    set name [dict get $compUnit name]
    set result [list]
    foreach warning $warnings {
        lappend result "$filename:$name - $warning"
    }
    return $result
}


#########################################################
# add the compUnit as a known compiled proc
#
proc ::tsp::addCompiledProc {compUnitDict} {
    upvar $compUnitDict compUnit
    set name [dict get $compUnit name]
    set returns [dict get $compUnit returns]
    set argTypes [dict get $compUnit argTypes]
    if {$argTypes eq "invalid"} {
        # invalid was just a placeholder, make it empty list
        set argTypes ""
    }
    set compiledReference [dict get $compUnit compiledReference]
    dict set ::tsp::COMPILED_PROCS $name [list $returns $argTypes $compiledReference]
}


#########################################################
# get the names of the compile proces
#
proc ::tsp::getCompiledProcs {} {
    return [dict keys $::tsp::COMPILED_PROCS]
}


#########################################################
# format file, proc name, line number
#
proc ::tsp::currentLine {compUnitDict} {
    upvar $compUnitDict compUnit
    set lineNum [dict get $compUnit lineNum]
    append result "file: [dict get $compUnit file]"
    append result " proc: [dict get $compUnit name]"
    append result " line: $lineNum"
    append result " text: [lindex [split [dict get $compUnit body] \n] $lineNum]"
    return $result
}


#########################################################
# log all of the errors and warnings from a compilation
# last compilation has index of "_"
#
proc ::tsp::logErrorsWarnings {compUnitDict} {
    upvar $compUnitDict compUnit
    set errors [::tsp::getLoggedErrors compUnit]
    set warnings [::tsp::getLoggedWarnings compUnit]
    set filename [dict get $compUnit file]
    set name [dict get $compUnit name]
    set logDict [dict create filename $filename errors $errors warnings $warnings]
    dict set ::tsp::COMPILER_LOG $name $logDict
    dict set ::tsp::COMPILER_LOG  _    $logDict
    
    if {$::tsp::DEBUG_DIR eq ""} {
        return
    }
    set path [file join $::tsp::DEBUG_DIR $name.log]
    set fd [open $path w]
    ::tsp::printLog $fd $name
    close $fd 
}

#########################################################
# log the compilable source, only if debug directory is set
#
proc ::tsp::logCompilable {compUnitDict compilable} {
    if {$::tsp::DEBUG_DIR eq ""} {
        return
    }
    upvar $compUnitDict compUnit
    set filename [dict get $compUnit file]
    set name [dict get $compUnit name]
    
    set path [file join $::tsp::DEBUG_DIR $name.$::tsp::PLATFORM]
    set fd [open $path w]
    puts $fd $compilable
    close $fd 
}


#########################################################
# print errors and warnings to a filehandle
# optional filehandle, defaults to stderr
# optional proc name pattern, defaults to * 
#
proc ::tsp::printLog {{fd stdout} {patt *} {breakeval 1}} {
    if {$fd != "stdout"} {
        puts [::tsp::log $patt]
    }
    puts $fd [::tsp::log $patt $breakeval]
}


#########################################################
# format errors and warnings 
# optional filehandle, defaults to stderr
# optional proc name pattern, defaults to * 
#
proc ::tsp::log {{patt *} {breakeval 0}} {
    set result ""
    set numerrors 0
    set keys [lsort [dict keys $::tsp::COMPILER_LOG]]
    foreach key $keys {
        if {[string match $patt $key]} {
            append result "$key (file:  [dict get $::tsp::COMPILER_LOG $key filename])---------------------------------------------------------" \n
            append result "    ERRORS --------------------------------------------------" \n
            foreach err [dict get $::tsp::COMPILER_LOG $key errors] {
                append result "   $err" \n
            }
            append result "    WARNINGS ------------------------------------------------" \n
            foreach warn [dict get $::tsp::COMPILER_LOG $key warnings] {
                append result "    $warn" \n
            }
            incr numerrors [llength [dict get $::tsp::COMPILER_LOG $key errors]]
        }
    }
    if {$numerrors==0} {
        return $result
    }
    if {$breakeval>0} {
        return -code error "$result\n $numerrors errors in transpiling unit, execution halted\n "
    } else {
        return "$result\n $numerrors errors in transpiling unit\n "
    }
}


#########################################################
# get last compile
#
proc ::tsp::lastLog {} {
    return [::tsp::log _]
}


#########################################################
# make a tmp directory, partially borrowed from wiki.tcl.tk/772
#
proc ::tsp::mktmpdir {} {

    if {[catch {set tmp $::env(java.io.tmpdir)}] && \
        [catch {set tmp $::env(TMP)}] && \
        [catch {set tmp $::env(TEMP)}]} {
 
        if {$::tcl_platform(platform) eq "windows"} {
            set tmp C:/temp
        } else {
            set tmp /tmp
        }
    }

    set chars abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789
    for {set i 0} {$i < 10} {incr i} {
        set path $tmp/tcl_
        for {set j 0} {$j < 10} {incr j} {
            append path [string index $chars [expr {int(rand() * 62)}]]
        }
        if {![file exists $path]} {
            file mkdir $path
            return $path
        }
    }
    error "failed to find an unused temporary directory name"
}


#########################################################
# set a directory for debug
#
proc ::tsp::debug {{dir ""}} {
    if {$::tsp::DEBUG_DIR ne ""} {
        error "debug directory already set as: $::tsp::DEBUG_DIR"
    }
    if {$dir eq ""} {
        set dir [::tsp::mktmpdir]
    } else {
        if {! [file isdirectory $dir] || ! [file writable $dir]} {
            error "debug pathname \"$dir\" not writable, or is not a directory"
        }
    }
    set ::tsp::DEBUG_DIR $dir

    set ::tsp::TRACE_FD [open $dir/traces.[clock seconds] w]

    return $dir
}


#########################################################
#
# get an abbreviated stack trace, for internal errors
#
proc ::tsp::error_stacktrace {} {
    set stack "Stack trace:\n"
    set indent 1
    for {set i 1} {$i < [info level]} {incr i} {
        set lvl [info level -$i]
        set pname [lindex $lvl 0]
        append stack [string repeat " " $indent]$pname
        incr indent
        foreach value [lrange $lvl 1 end] arg [info args $pname] {
            if {$value eq ""} {
                info default $pname $arg value
            }
            append stack " $arg='[string range $value 0 20][expr {[string length $value] > 20 ? " ..." : ""}]'"
        }
        append stack \n
    }
    return $stack
}



