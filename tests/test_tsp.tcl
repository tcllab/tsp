package require tsp
#tsp::debug ./dbg

#::tsp::init_package testpkg
tsp::proc fib0 {n} {
	#tsp::procdef int -args int
	#tsp::int fib_2 fib_1
	if {$n < 2} {return 1}
	#tsp::volatile fib_2
         set fib_2 [fib [expr {$n -2}]]
         set fib_1 [fib [expr {$n -1}]]
	set result [expr {$fib_2 + $fib_1}]
	return $result
}
tsp::proc fib {n} {
	#tsp::procdef int -args int
	#tsp::int fib_2 fib_1
	if {$n < 2} {return 1}
        set fib_2 [fib [expr {$n -2}]]
        set fib_1 [fib [expr {$n -1}]]
	set result [expr {$fib_2 + $fib_1}]
	return $result
}

tsp::proc wordsplit {str} {
	#tsp::procdef var -args string
	#tsp::var list char
	#tsp::string word
	#tsp::boolean is_space
	#tsp::int strlen len i
	set list {}
	set word {}
        set strlen [string length $str]
	for {set i 0} {$i < $strlen} {incr i} {
                set char [string index $str $i]
		set is_space [string is space $char]
		if {$is_space} {
			set len [string length $word]
			if {$len > 0} {
				lappend list $word
			}
			set word {}
		} else {
			append word $char
		}
	}
	set len [string length $word]
	if {$len > 0} {
		lappend list $word
	}
	return $list
}


tsp::proc foo {} { 
        #tsp::procdef var
        #tsp::var ll ll2 
        set ll {}
        set ll2 {}
        puts "ok";
        set a "test"
        puts "ok for $a"
        set ll [list 0 8 7 1 2 3]
        set ll2 [lsort $ll]
        #set ll $ll2; # this will crash in execution, due to DecrRef/incrRef error...
        foreach buf $ll2 {
            puts $buf
        }
        puts "ok $ll2"
        return "ok"
}
# ::tsp::printLog
#::tsp::finalize_package

proc run_fib {} {
    set i 0
    while {$i <= 30} {
	    puts "n=$i => [fib $i]"
	    incr i
    }
}

proc fib2 {n} {
	if {$n < 2} {return 1}
        set fib_2 [fib2 [expr {$n -2}]]
        set fib_1 [fib2 [expr {$n -1}]]
	set result [expr {$fib_2 + $fib_1}]
	return $result
}

proc run_fib2 {} {
    set i 0
    while {$i <= 30} {
	    puts "n=$i => [fib2 $i]"
	    incr i
    }
}
#



