#  compiled control commands:
#  for, while, foreach, if, break, continue, return, switch, case,
#  catch, error, etc.


#########################################################
# generate code for "for" command (assumed to be first parse word)
# only braced arguments are generated, anything else generates an error
# return list of: type rhsVarName code
#
proc ::tsp::gen_command_for {compUnitDict tree} {
    upvar $compUnitDict compUnit

    if {[llength $tree] != 5} {
        ::tsp::addError compUnit "wrong # args: should be \"for start test next command\""
        return [list void "" ""]
    }


    set rawtext [::tsp::parse_getstring compUnit [lindex $tree 1]]
    if {[string range $rawtext 0 0] ne "\{"} {
        ::tsp::addError compUnit "start code argument not a braced word"
        return [list void "" ""]
    }
    set pretext [lindex $rawtext 0]

    set rawtext [::tsp::parse_getstring compUnit [lindex $tree 2]]
    if {[string range $rawtext 0 0] ne "\{"} {
        ::tsp::addError compUnit "test expr argument not a braced expression"
        return [list void "" ""]
    }
    set exprtext [lindex $rawtext 0]

    set rawtext [::tsp::parse_getstring compUnit [lindex $tree 3]]
    if {[string range $rawtext 0 0] ne "\{"} {
        ::tsp::addError compUnit "next code argument not a braced word"
        return [list void "" ""]
    }
    set posttext [lindex $rawtext 0]

    set rawtext [::tsp::parse_getstring compUnit [lindex $tree 4]]
    if {[string range $rawtext 0 0] ne "\{"} {
        ::tsp::addError compUnit "body code argument not a braced word"
        return [list void "" ""]
    }
    set bodytext [lindex $rawtext 0]

    set rc [catch {set exprTypeCode [::tsp::compileBooleanExpr compUnit $exprtext]} result]
    if {$rc != 0} {
        ::tsp::addError compUnit "couldn't parse expr: \"$exprtext\", $result"
        return [list void "" ""]
    }
    
    set loopVar [::tsp::get_tmpvar compUnit boolean]
    ::tsp::lock_tmpvar compUnit $loopVar
    
    lassign $exprTypeCode type exprCode

    set preRange [lindex [lindex $tree 1] 1]
    lassign $preRange start end
    incr start
    incr end -2
    set preRange [list $start $end]
    set preCode [lindex [::tsp::parse_body compUnit $preRange] 2]

    set postRange [lindex [lindex $tree 3] 1]
    lassign $postRange start end
    incr start
    incr end -2
    set postRange [list $start $end]
    set postCode [lindex [::tsp::parse_body compUnit $postRange] 2]

    set bodyRange [lindex [lindex $tree 4] 1]
    lassign $bodyRange start end
    incr start
    incr end -2
    set bodyRange [list $start $end]
    ::tsp::incrDepth compUnit

    set bodyCode [lindex [::tsp::parse_body compUnit $bodyRange] 2]

    append code "\n/***** ::tsp::gen_command_for */\n"
    append code "\n/* ::tsp::gen_command_for initializer*/\n"
    append code $preCode

    append bodyCode \n "/* ::tsp::gen_command_for postloop */" \n $postCode \n

    append code [::tsp::lang_while compUnit $loopVar $exprCode [::tsp::indent compUnit $bodyCode]]

    ::tsp::incrDepth compUnit -1
    ::tsp::unlock_tmpvar compUnit $loopVar

    return [list void "" $code]
}




#########################################################
# generate code for "while" command (assumed to be first parse word)
# only braced arguments are generated, anything else generates an error
# return list of: type rhsVarName code
#
proc ::tsp::gen_command_while {compUnitDict tree} {
    upvar $compUnitDict compUnit

    if {[llength $tree] != 3} {
        ::tsp::addError compUnit "wrong # args: should be \"while test command\""
        return [list void "" ""]
    }

    # get expr component, make sure it is braced
    set rawtext [::tsp::parse_getstring compUnit [lindex $tree 1]]
    if {[string range $rawtext 0 0] ne "\{"} {
        ::tsp::addError compUnit "expr argument not a braced expression"
        return [list void "" ""]
    }
    set exprtext [lindex $rawtext 0]

    set rc [catch {set exprTypeCode [::tsp::compileBooleanExpr compUnit $exprtext]} result]
    if {$rc != 0} {
        ::tsp::addError compUnit "couldn't parse expr: \"$exprtext\", $result"
        return [list void "" ""]
    }
    
    set loopVar [::tsp::get_tmpvar compUnit boolean]
    ::tsp::lock_tmpvar compUnit $loopVar
    
    lassign $exprTypeCode type exprCode

    # get body component make sure it is braced
    set rawtext [::tsp::parse_getstring compUnit [lindex $tree 2]]
    if {[string range $rawtext 0 0] ne "\{"} {
        ::tsp::addError compUnit "body argument not a braced expression"
        return [list void "" ""]
    }
    set bodytext [lindex $rawtext 0]

    set bodyRange [lindex [lindex $tree 2] 1]
    lassign $bodyRange start end
    incr start
    incr end -2
    set bodyRange [list $start $end]
    ::tsp::incrDepth compUnit

    set bodyCode [lindex [::tsp::parse_body compUnit $bodyRange] 2]

    append code "\n/***** ::tsp::gen_command_while */\n"

    append code [::tsp::lang_while compUnit $loopVar $exprCode [::tsp::indent compUnit $bodyCode]]

    ::tsp::incrDepth compUnit -1
    ::tsp::unlock_tmpvar compUnit $loopVar

    return [list void "" $code]
}



#########################################################
# generate code for "if" command (assumed to be first parse word)
# only braced arguments are generated, anything else generates an error
# return list of: type rhsVarName code
#
proc ::tsp::gen_command_if {compUnitDict tree} {
    upvar $compUnitDict compUnit

    if {[llength $tree] < 3} {
        ::tsp::addError compUnit "wrong # args: should be \"if expression script ...\""
        return [list void "" ""]
    }

    set argMax [llength $tree]
    append code "\n/***** ::tsp::gen_command_if */\n"
    append code "if ( "
    
    set i 1
    # expect "condition"  "script" 
    while {$i < $argMax} {

        # get the condition
        set rawtext [::tsp::parse_getstring compUnit [lindex $tree $i]]
        if {[string range $rawtext 0 0] ne "\{"} {
            ::tsp::addError compUnit "unbraced \"if\" argument (expression): \"[string trim [string range $rawtext 0 30]]\""
            return [list void "" ""]
        }
        set text [lindex $rawtext 0]
        # compile the expression
        set rc [catch {set exprTypeCode [::tsp::compileBooleanExpr compUnit $text]} result]
        if {$rc != 0} {
            ::tsp::addError compUnit "couldn't parse expr: \"$text\", $result"
            return [list void "" ""]
        }
        lassign $exprTypeCode type exprCode
        append code $exprCode " ) \{\n"
        

        # get the script, passing over optional "then"
        incr i
        if {$i == $argMax} {
            ::tsp::addError compUnit "no script after \"if\" condition"
            return [list void "" ""]
        }
        set nextComponent [lindex [::tsp::parse_word compUnit [lindex $tree $i]] 0]
        lassign $nextComponent type rawtext text
        if {$type eq "text" && $text eq "then"} {
            incr i
            if {$i == $argMax} {
                ::tsp::addError compUnit "no script after \"if\" then"
                return [list void "" ""]
            }
            set nextComponent [lindex [::tsp::parse_word compUnit [lindex $tree $i]] 0]
            lassign $nextComponent type rawtext text
        }
        if {$type ne "text" || [string range $rawtext 0 0] ne "\{"} {
            ::tsp::addError compUnit "unbraced \"if\" argument (if body): \"[string trim [string range $rawtext 0 30]]\""
            return [list void "" ""]
        } 
        set bodyRange [lindex [lindex $tree $i] 1]
        lassign $bodyRange start end
        incr start
        incr end -2
        set bodyRange [list $start $end]
        set bodyCode [lindex [::tsp::parse_body compUnit $bodyRange] 2]
        append code [::tsp::indent compUnit $bodyCode 1]
        append code "\n\}"
        

        # set up loop for "elseif" if any, or break 
        # on implied "?else? script" or last arg.
        incr i
        if {$i == ($argMax - 1)} {
            break
        }
        set nextComponent [lindex [::tsp::parse_word compUnit [lindex $tree $i]] 0]
        lassign $nextComponent type rawtext text
        if {$type eq "text" && $text eq "elseif"} {
            incr i
            if {$i >= ($argMax - 1)} {
                ::tsp::addError compUnit "\"elseif\" missing condition and/or script arguments"
                return [list void "" ""]
            }
            append code " else if ( "
            continue
        } else {
            break
        }
    }

    # process "else" script, if any
    if {$i < $argMax} {
        set nextComponent [lindex [::tsp::parse_word compUnit [lindex $tree $i]] 0]
        lassign $nextComponent type rawtext text
        if {$type eq "text" && $text eq "else"} {
            incr i
            if {$i == $argMax} {
                ::tsp::addError compUnit "no script after \"if\" else"
                return [list void "" ""]
            }
            set nextComponent [lindex [::tsp::parse_word compUnit [lindex $tree $i]] 0]
            lassign $nextComponent type rawtext text
        }
        if {$type ne "text" || [string range $rawtext 0 0] ne "\{"} {
            ::tsp::addError compUnit "unbraced \"if\" argument (else body): \"[string trim [string range $rawtext 0 30]]\""
            return [list void "" ""]
        } 
        append code " else \{\n"
        set bodyRange [lindex [lindex $tree $i] 1]
        lassign $bodyRange start end
        incr start
        incr end -2
        set bodyRange [list $start $end]
        set bodyCode [lindex [::tsp::parse_body compUnit $bodyRange] 2]
        append code [::tsp::indent compUnit $bodyCode 1]
        append code "\n\}"
        incr i
    } 
    append code \n

    # should have used up all arguments by now.....
    if {$i < $argMax} { 
        ::tsp::addError compUnit "extra arguments after \"else\" argument"
        return [list void "" ""]
    }

    return [list void "" $code]
}



#########################################################
# generate code for "break" command (assumed to be first parse word)
# return list of: type rhsVarName code
#
proc ::tsp::gen_command_break {compUnitDict tree} {
    upvar $compUnitDict compUnit

    if {[llength $tree] > 1} {
        ::tsp::addError compUnit "wrong # args: should be \"break\""
        return [list void "" ""]
    }

    # make sure we are in a loop, as indicated by 'depth'
    if {[dict get $compUnit depth] < 1} {
        ::tsp::addError compUnit "\"break\" used outside of loop"
        return [list void "" ""]
    }
    append code "\n/***** ::tsp::gen_command_break */\n"
    append code "\nbreak;\n"
    return [list void "" $code]
}


#########################################################
# generate code for "continue" command (assumed to be first parse word)
# return list of: type rhsVarName code
#
proc ::tsp::gen_command_continue {compUnitDict tree} {
    upvar $compUnitDict compUnit

    if {[llength $tree] > 1} {
        ::tsp::addError compUnit "wrong # args: should be \"continue\""
        return [list void "" ""]
    }

    # make sure we are in a loop, as indicated by 'depth'
    if {[dict get $compUnit depth] < 1} {
        ::tsp::addError compUnit "\"continue\" used outside of loop"
        return [list void "" ""]
    }
    append code "\n/***** ::tsp::gen_command_continue */\n"
    append code "\ncontinue;\n"
    return [list void "" $code]
}


#########################################################
# generate code for "return" command (assumed to be first parse word)
# return list of: type rhsVarName code
#
proc ::tsp::gen_command_return {compUnitDict tree} {
    upvar $compUnitDict compUnit

    set returnType [dict get $compUnit returns]

    if {$returnType eq ""} {
        ::tsp::addError compUnit "invalid proc definition, no return type specified, likely missing #::tsp::procdef (return)"
        return [list void "" ""]
    }

    if {$returnType eq "void"} {
        if {[llength $tree] > 1} {
            ::tsp::addError compUnit "wrong # args: proc return type declared as \"$returnType\", but \"return\" has arguments"
            return [list void "" ""]
        }
        #return [list void "" "\n/*return deffered*/;\n"]
        set result "\n/***** ::tsp::gen_command_return void */\n"
        append result [::tsp::lang_return compUnit "void"] \n
        return [list void "" $result]
    }     
    if {[llength $tree] != 2} {
        ::tsp::addError compUnit "wrong # args: proc return type declared as \"$returnType\", \"return\" requires exactly one argument"
        return [list void "" ""]
    }

    # generate assignment to a tmp var that will be the return type
    # FIXME: probably should just return the return argument when it's the same type
    set argVar [::tsp::get_tmpvar compUnit $returnType]
    ::tsp::lock_tmpvar compUnit $argVar
    set argVarComponents [list [list text $argVar $argVar]]
    set returnNodeComponents [::tsp::parse_word compUnit [lindex $tree 1]]
    set returnNodeType [lindex [lindex $returnNodeComponents 0] 0]
    if {$returnNodeType eq "invalid"} {
        ::tsp::unlock_tmpvar compUnit $argVar
        ::tsp::addError compUnit "return argument parsed as \"$returnNodeType\""
        return [list void "" ""]
    }

    set setTree ""  ;# tree only needed for command parse types, so ok to make it empty here
    set code [lindex [::tsp::produce_set compUnit $setTree $argVarComponents $returnNodeComponents] 2]

    # vi return arg is a var, preserve it from being disposed/freed in this method/function
    if {$returnType eq "var"} {
        append code [::tsp::lang_preserve $argVar]\n
    }
    append result "\n/***** ::tsp::gen_command_return */\n"
    append result "\n${code}\n"
    append result [::tsp::lang_return compUnit $argVar] \n
    ::tsp::unlock_tmpvar compUnit $argVar
    return [list void "" $result]
}

#########################################################
# generate code for "foreach" command (assumed to be first parse word)
# list of variables must be a single word, or a literal list enclosed
# in braces.  List to iterate must be a literal list enclosed in braces,
# or a variable reference.  code must be a braced arguments. 
# currenlty, only a single list can be iterated.
# return list of: type rhsVarName code
#
#FIXME: support multi lists??
#
proc ::tsp::gen_command_foreach {compUnitDict tree} {
    upvar $compUnitDict compUnit

    if {[llength $tree] != 4} {
        ::tsp::addError compUnit "wrong # args: should be \"foreach var-list list code\""
        return [list void "" ""]
    }

    set varlistComponent [lindex [::tsp::parse_word compUnit [lindex $tree 1]] 0]
    lassign $varlistComponent type rawtext vartext
    if {$type ne "text" && [string range $rawtext 0 0] ne "\{"} {
        ::tsp::addError compUnit "varlist argument not a single var or braced list literal"
        return [list void "" ""]
    }
    # check that varlist are all variables, if any are not defined, make them a var
    foreach var $vartext {
        set type [::tsp::getVarType compUnit $var]
        if {$type eq "undefined"} {
            if {[::tsp::isProcArg compUnit $var]} {
                ::tsp::addError compUnit "proc argument variable \"$var\" not previously defined"
                return [list void "" ""]
            } elseif {[::tsp::isValidIdent $var]} {
                ::tsp::addWarning compUnit "variable \"${var}\" implicitly defined as type: \"var\" (catch)"
                ::tsp::setVarType compUnit $var var
            } else {
                ::tsp::addError compUnit "invalid identifier: \"$var\""
                return [list void "" ""]
            }
        }
    }
    set varList $vartext

    set datalistComponent [lindex [::tsp::parse_word compUnit [lindex $tree 2]] 0]
    lassign $datalistComponent type rawtext listtext
    #FIXME: support array variables as lists
    if {$type ne "scalar" && $type ne "text" && [string range $rawtext 0 0] ne "\{"} {
        ::tsp::addError compUnit "varlist argument not a scalar, single var, or braced list literal"
        return [list void "" ""]
    }
    if {$type eq "scalar"} {
        set dataList $rawtext
        set dataString ""
    } else {
        set dataList ""
        set dataString $listtext
        if {[catch {llength $dataString}]} {
            ::tsp::addError compUnit "foreach data list is not a proper list"
            return [list void "" ""]
        }
    }

    set bodyComponent [lindex [::tsp::parse_word compUnit [lindex $tree 3]] 0]
    lassign $bodyComponent type rawtext bodytext
    #FIXME: support array variables as lists
    if {$type ne "text" && [string range $rawtext 0 0] ne "\{"} {
        ::tsp::addError compUnit "body argument not a braced literal"
        return [list void "" ""]
    }

    # get tmp idx, len, convert, and datalist vars; lock them to prevent 
    # body code from re-using them 
    set idxVar [::tsp::get_tmpvar compUnit int]
    set lenVar [::tsp::get_tmpvar compUnit int]
    set dataVar [::tsp::get_tmpvar compUnit var]
    set convertVar [::tsp::get_tmpvar compUnit var]
    ::tsp::lock_tmpvar compUnit $idxVar
    ::tsp::lock_tmpvar compUnit $lenVar
    ::tsp::lock_tmpvar compUnit $dataVar
    ::tsp::lock_tmpvar compUnit $convertVar

    set bodyRange [lindex [lindex $tree 3] 1]
    lassign $bodyRange start end
    incr start
    incr end -2
    set bodyRange [list $start $end]

    # incr nesting depth and parse body code
    ::tsp::incrDepth compUnit
    set bodyCode [lindex [::tsp::parse_body compUnit $bodyRange] 2]

    append code "\n/***** ::tsp::gen_command_foreach */\n"
    append code [::tsp::lang_foreach compUnit $idxVar $lenVar $convertVar $dataVar $varList $dataList $dataString $bodyCode]

    # decr nesting depth and unlock tmp vars
    ::tsp::incrDepth compUnit -1
    ::tsp::unlock_tmpvar compUnit $idxVar
    ::tsp::unlock_tmpvar compUnit $lenVar
    ::tsp::unlock_tmpvar compUnit $dataVar
    ::tsp::unlock_tmpvar compUnit $convertVar
    
    return [list void "" $code]
}



#########################################################
# generate code for "catch" command (assumed to be first parse word)
# return list of: type rhsVarName code
#
proc ::tsp::gen_command_catch {compUnitDict tree} {
    upvar $compUnitDict compUnit
    
    if {[llength $tree]  < 2 || [llength $tree] > 3} {
        ::tsp::addError compUnit "wrong # args: should be \"catch command ?varName?\""
        return [list void "" ""]
    }

    # check if result var is present
    if {[llength $tree] == 3} {
        set varNameComponent [lindex [::tsp::parse_word compUnit [lindex $tree 2]] 0]
        lassign $varNameComponent type var text
        if {$type ne "text"} {
            ::tsp::addError compUnit "catch result var must be a scalar"
            return [list void "" ""]
        }
        set varType [::tsp::getVarType compUnit $var]
        if {$varType eq "undefined"} {
            if {[::tsp::isProcArg compUnit $var]} {
                ::tsp::addError compUnit "proc argument variable \"$var\" not previously defined"
                return [list void "" ""]
            } elseif {[::tsp::isValidIdent $var]} {
                ::tsp::addWarning compUnit "variable \"${var}\" implicitly defined as type: \"var\" (catch)"
                ::tsp::setVarType compUnit $var var
                set varType var
            } else {
                ::tsp::addError compUnit "invalid identifier: \"$var\""
                return [list void "" ""]
            }
        }
        set var __$var
    } else {
        set var ""
        set varType ""
    }

    # compile the catch body
    set bodyRange [lindex [lindex $tree 1] 1]
    lassign $bodyRange start end
    incr start
    incr end -2
    set bodyRange [list $start $end]
    ::tsp::incrDepth compUnit
    set bodyCode [lindex [::tsp::parse_body compUnit $bodyRange] 2]
    set returnVar [::tsp::get_tmpvar compUnit int]

    append code "\n/***** ::tsp::gen_command_catch */\n"
    set code [::tsp::lang_catch compUnit $returnVar $bodyCode $var $varType]
    ::tsp::incrDepth compUnit -1
    return [list int $returnVar $code]
}


#########################################################
# generate code for "switch" command (assumed to be first parse word)
# switch only processes simple switch, where the switch string is assumed
# to be exact, and where the switch pattern-body pairs are enclosed in
# braces.  Switch string should be a scalar variable, 
# Each pattern must be of the same type as switch string.
# Each body must also be enclosed in braces.
# return list of: type rhsVarName code
#
proc ::tsp::gen_command_switch {compUnitDict tree} {
    upvar $compUnitDict compUnit

    set body [dict get $compUnit body]

    if {[llength $tree] != 3} {
        ::tsp::addError compUnit "wrong # args: should be \"switch string pattern-script-list\""
        return [list void "" ""]
    }

    set switchComponent [lindex [::tsp::parse_word compUnit [lindex $tree 1]] 0]
    lassign $switchComponent type switchVar text
    # FIXME: should also handle arrays
    if {$type ne "scalar"} {
        ::tsp::addError compUnit "switch must specify a scalar variable"
        return [list void "" ""]
    }
    set switchVarType [::tsp::getVarType compUnit $switchVar]
    if {$switchVarType eq "undefined"} {
        ::tsp::addError compUnit "switch variable argument \"$switchVar\" not defined."
        return [list void "" ""]
    }
    
    set pattScriptComponent [lindex [::tsp::parse_word compUnit [lindex $tree 2]] 0]
    lassign $pattScriptComponent type rawtext pattScriptList
    if {$type ne "text" || [string range $rawtext 0 0] ne "\{"} {
        ::tsp::addError compUnit "switch pattern-script list must be text enclosed in braces"
        return [list void "" ""]
    }
    set len -1
    catch {set len [llength $pattScriptList]}
    if {$len == -1} {
        ::tsp::addError compUnit "switch pattern-script argument not a valid list"
        return [list void "" ""]
    }
    if {$len % 2 != 0} {
        ::tsp::addError compUnit "switch pattern-script argument unmatched pattern-script pairs"
        return [list void "" ""]
    }
    set pattScriptRange [lindex [lindex $tree 2] 1]
    lassign $pattScriptRange start end
    incr start
    incr end -2
    set pattScriptRange [list $start $end]
    set pattScriptIdxes [parse list $body $pattScriptRange]

    # check that pattern types are valid for the switch scalar, bodies are
    # enclosed in braces.  parse bodies into code, and assemble a new list.
    # check if "default" if present, is last
    set offending [list]
    set pattCodeList [list]
    set pairNum 0
    set seenDefault 0
    set firstPatt 1
    foreach {patt script} $pattScriptList {pattRange scriptRange} $pattScriptIdxes {
        if {$seenDefault} {
            ::tsp::addError compUnit "switch \"default\" pattern not last in pattern-script pairs"
            return [list void "" ""]
        }
        incr pairNum
        if {$patt eq "default"} {
            if {$firstPatt} {
                ::tsp::addError compUnit "switch \"default\" cannot be first pattern"
                return [list void "" ""]
            }
            if {$script eq "-"} {
                ::tsp::addError compUnit "no body specified for pattern \"default\""
                return [list void "" ""]
            }
            set seenDefault 1
        } else {
            set allTypes [::tsp::literalTypes $patt]
            switch $switchVarType {
                boolean {
                    if {! [::tsp::typeIsBoolean $allTypes]} {lappend offending $patt } 
                    # boolean constants must be able to evaluate true/false
                    if {[catch {if {$patt} {} }]} {
                        lappend offending $patt
                    }
                }
                int     {
                    if {! [::tsp::typeIsInt     $allTypes]} {lappend offending $patt } 
                }
                double  {
                    if {! [::tsp::typeIsNumeric $allTypes]} {lappend offending $patt } 
                }
                default { }
            }
        }
        set firstPatt 0
 
        if {[string trim $script] eq ""} {
            set scriptCode ""
        } elseif {$script eq "-"} { 
            set scriptCode "-"
        } else {
            if {[string range [parse getstring $body $scriptRange] 0 0] ne "\{"} {
                ::tsp::addError compUnit "switch pattern-script pair $pairNum script not enclosed by braces"
                return [list void "" ""]
            }
            lassign $scriptRange start end
            incr start
            incr end -2
            set scriptRange [list $start $end]
            ::tsp::incrDepth compUnit
            set scriptCode [lindex [::tsp::parse_body compUnit $scriptRange] 2]
            ::tsp::incrDepth compUnit -1
        }
        lappend pattCodeList $patt $scriptCode
    }

    if {[llength $offending] > 0} {
        ::tsp::addError compUnit "switch patterns not matching switch type of $switchVarType: $offending"
        return [list void "" ""]
    }

    append code "\n/***** ::tsp::gen_command_switch */\n"
    set code [::tsp::lang_switch compUnit $switchVar $switchVarType $pattCodeList]
    return [list void "" $code]
}
