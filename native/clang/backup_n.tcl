#!/usr/bin/tclsh
## exec tclkit
## Backup

set t [clock format [clock seconds] -format "%Y-%m-%d_%H-%M"]
catch {console show}
file mkdir "./cvs"
foreach f0 [glob -nocomplain [file join "./" *]] {
    if {[file isfile $f0]} {
        set f [file tail $f0]
        set n [file rootname $f]
        set x [file extension $f]
        set t0 [file mtime $f0]
        set ts0 [clock format $t0 -format "%Y-%m-%d_%H-%M"]
        #if {$f!=[file tail $::argv0]} {
            set f1 "./cvs/$n.$ts0$x"
            if {![file exists $f1]} { 
                puts "copy $f0 $f1"
                file copy $f0 $f1
            }
        #}
    }
}
