#FIXME: be consistent in quoting strings, esp those that are array index
#       probaby ok to quote them once when recognized


#########################################################
# check if target variable is undefined, if so then make
#     it same as sourcetype
# return ERROR if targetVarName is a proc arg var or is invalid identifier
#
proc ::tsp::gen_check_target_var {compUnitDict targetVarName targetType sourceType} {
    upvar $compUnitDict compUnit

    if {$targetType eq "undefined" && $sourceType ne "void"} {

        if {[::tsp::isProcArg compUnit $targetVarName]} {
            ::tsp::addError compUnit "proc argument variable \"$targetVarName\" not previously defined"
            return ERROR
        } elseif {[::tsp::isValidIdent $targetVarName]} {
            set targetType $sourceType
            ::tsp::addWarning compUnit "variable \"$targetVarName\" implicitly defined as type: \"$targetType\" (set)"
            ::tsp::setVarType compUnit $targetVarName $targetType
        } else {
            ::tsp::addError compUnit "invalid identifier: \"$targetVarName\""
            return ERROR
        }

    }
    return $targetType
}


#########################################################
# generate a set command, the basic assignment command
# we only compile: 
#     set var arg
#    where var is:
#       text    e.g., a scalar var
#       arr(idx) 
#       arr($idx) 
#    where arg is:
#       \backslashed escape character 
#       text
#       interpolated text  e.g., "this $is \n$stuff" (string/var target only)
#       $var
#       $arr(idx)
#       $arr($idx)
#       [cmd text/$var text/$var ...] 
#    where idx is:
#       text
#       $var
#
# returns list of [void "" code] - note return type is always void, and assignment var is empty string
#
# NOTE that anywhere a tcl var is used, it is prefixed with "__" for native compilation, except
#      for "array" variables, which are only accessed in the interp.  This is done anytime we
#      call a lang specific proc [::tsp::lang_*], or generate lang indepedent code.
#
proc ::tsp::gen_command_set {compUnitDict tree} {
    upvar $compUnitDict compUnit
    set errors 0
    set body [dict get $compUnit body]
  
    set len [llength $tree]
    if {$len != 3} {
        ::tsp::addError compUnit "set command must have two args"
        return [list void "" ""]
    }
    set targetStr [parse getstring $body [lindex [lindex $tree 1] 1]]
    set sourceStr [parse getstring $body [lindex [lindex $tree 2] 1]]

    # check target, should be a single text, text_array_idxtext, or text_array_idxvar
    set targetComponents [::tsp::parse_word compUnit [lindex $tree 1]]
    set firstType [lindex [lindex $targetComponents 0] 0]
    if { !($firstType eq "text" || $firstType eq "text_array_idxtext" || $firstType eq "text_array_idxvar")} {
        set errors 1
        ::tsp::addError compUnit "set target is not a scalar or array variable name: \"$targetStr\""
    }

    # check source word components
    set sourceComponents [::tsp::parse_word compUnit [lindex $tree 2]]
    set firstType [lindex [lindex $sourceComponents 0] 0]
    if {$firstType eq "invalid"} {
        set errors 1
        ::tsp::addError compUnit "set arg 2 invalid: \"$sourceStr\""
    }

    if {$errors} {
        return [list void "" ""]
    }
    return [::tsp::produce_set compUnit $tree $targetComponents $sourceComponents]
}



#########################################################
# produce the set command from target and source components (from parse_word)
# note - tree can be empty when sourceComponents is not a [command]
#
proc ::tsp::produce_set {compUnitDict tree targetComponents sourceComponents} {
    upvar $compUnitDict compUnit
    set errors 0

    # determine target variable name a type
    set targetComponent [lindex $targetComponents 0]
    set targetWordType [lindex $targetComponent 0]
    set targetVarName ""
    set targetType invalid
    set targetArrayIdxtext ""
    set targetArrayIdxvar ""
    if {$targetWordType eq "text"} {
        set targetVarName [lindex $targetComponent 2]
        set targetType [::tsp::getVarType compUnit $targetVarName]
        # targetType could be undefined, if this is the first reference to this scalar
        # resolve later, but make sure it's a valid identifier
        if {$targetType eq "undefined"} {
            # make sure this can be a valid variable
            if {! [::tsp::isValidIdent $targetVarName] } {
                set errors 1
                ::tsp::addError compUnit "set arg 1 previously undefined variable not a valid identifer: \"$targetVarName\""
                return [list void "" ""]
            }
        }
    } elseif {$targetWordType eq "text_array_idxtext" || $targetWordType eq "text_array_idxvar"} {
        set targetVarName [lindex $targetComponents 1]
        set targetType [::tsp::getVarType compUnit $targetVarName]
        if {$targetType eq "undefined"} {
            # make sure this can be a valid variable and is not a proc arg var
            if {[::tsp::isProcArg compUnit $targetVarName]} {
                set errors 1
                ::tsp::addError compUnit "proc argument variable \"$targetVarName\" not previously defined"
                return [list void "" ""]
            } elseif {! [::tsp::isValidIdent $targetVarName] } {
                set errors 1
                ::tsp::addError compUnit "set arg 1 previously undefined variable not a valid identifer: \"$targetVarName\""
                return [list void "" ""]
             } else {
                set targetType array
                ::tsp::setVarType compUnit $targetVarName array
                ::tsp::addWarning compUnit "variable \"${targetVarName}\" implicitly defined as type: \"array\" (set)"
             }
        } elseif {$targetType ne "array"} {
            # variable parsed as an array, but some other type
            set errors 1
            ::tsp::addError compUnit "set arg 1 \"$targetVarName\" previously defined as type: \"$targetType\", now referenced as array"
        }

        # is index a string or variable?
        if {$targetWordType eq "text_array_idxtext"} {
            set targetArrayIdxtext [lindex $targetComponents 2]
            set targetArrayIdxvarType string
        } else {
            set targetArrayIdxvar  [lindex $targetComponents 2]
            set targetArrayIdxvarType [::tsp::getVarType compUnit $targetArrayIdxvar]
            if {$targetArrayIdxvarType eq "array"} {
                # we don't support index variables as arrays
                set errors 1
                ::tsp::addError compUnit "set arg 1 index variable \"$targetArrayIdxvar\" cannot be an defined as \"array\""
            } elseif {$targetArrayIdxvarType eq "undefined"} {
                set errors 1
                ::tsp::addError compUnit "set arg 1 array index undefined identifer: \"$targetArrayIdxvar\""
            }
        }
    } else {
        set errors 1
        ::tsp::addError compUnit "set arg 1 unexpected target type: \"$targetWordType: $targetComponents\""
    }

    if {$errors} {
        return [list void "" ""]
    }
    
    # determine source variable/expression and type
    set sourceText ""
    set sourceType ""
    set sourceVarName ""
    set sourceArrayIdxtext ""
    set sourceArrayIdxvar ""
    set sourceCode ""
    # is source an interpolated string?
    if {[llength $sourceComponents] > 1} {
        if {$targetType eq "array"} {
            return [list void "" [::tsp::gen_assign_array_interpolated_string compUnit $targetVarName \
			$targetArrayIdxtext $targetArrayIdxvar $targetArrayIdxvarType $targetType $sourceComponents ]]

        } else {
            set sourceType string
            set targetType [::tsp::gen_check_target_var compUnit $targetVarName $targetType $sourceType]
            if {$targetType eq "ERROR"} {
                return [list void "" ""]
            }

            # append source components into a single string or var assignment
            # check that target is either string or var or array
            if {$targetType eq "string" || $targetType eq "var"} {
                # will fail if embedded command or array is found 
                return [list void "" [::tsp::gen_assign_var_string_interpolated_string compUnit $targetVarName $targetType $sourceComponents]]
    
            } else {
                ::tsp::addError compUnit "set command arg 1 variable must be string or var for interpolated string assignment: \"$targetVarName\""
                return [list void "" ""]
            }
        }

    } else {

        set sourceComponent [lindex $sourceComponents 0]
        set sourceWordType [lindex $sourceComponent 0]

        if {$sourceWordType eq "backslash"} {
            # backslashed string to string or var assignment
            # subst the backslashed constant, so that we can quote as a native string
            set sourceText [subst [lindex $sourceComponent 1]]
            set sourceType string
            set targetType [::tsp::gen_check_target_var compUnit $targetVarName $targetType $sourceType]
            if {$targetType eq "ERROR"} {
                return [list void "" ""]
            }

            # generate assigment
            if {$targetType eq "string"} {
                return [list void "" [::tsp::lang_assign_string_const $targetVarName $sourceText]]

            } elseif {$targetType eq "var"} {
                return [list void "" [::tsp::lang_assign_var_string $targetVarName [::tsp::lang_quote_string $sourceText]]]

            } elseif {$targetWordType eq "text_array_idxtext" || $targetWordType eq "text_array_idxvar"} {
                return [list void "" [::tsp::gen_assign_array_text compUnit $targetVarName $targetArrayIdxtext \
				$targetArrayIdxvar $targetArrayIdxvarType $targetType $sourceText $sourceType]]

            } else {
                ::tsp::addError compUnit "set command arg 1 variable must be string, var, or array for backslash assignment: \"$targetVarName\""
                return [list void "" ""]
            }


        } elseif {$sourceWordType eq "text"} {
            # possibly could be a int, double, or boolean literal, otherwise string
            set sourceType [::tsp::literalExprTypes [lindex $sourceComponent 2]]
            if {$sourceType ne "int" && $sourceType ne "double"} {
                set sourceType string
            }
            set sourceText [lindex $sourceComponent 2]
            set targetType [::tsp::gen_check_target_var compUnit $targetVarName $targetType $sourceType]
            if {$targetType eq "ERROR"} {
                return [list void "" ""]
            }

            # generate assigment
            if {$targetWordType eq "text"} {
                return [list void "" [::tsp::gen_assign_scalar_text compUnit $targetVarName $targetType $sourceText $sourceType]]

            } elseif {$targetWordType eq "text_array_idxtext" || $targetWordType eq "text_array_idxvar"} {
                return [list void "" [::tsp::gen_assign_array_text compUnit $targetVarName $targetArrayIdxtext \
				$targetArrayIdxvar $targetArrayIdxvarType $targetType $sourceText $sourceType]]

            } else {
                if {$errors} {
                    return [list void "" ""]
                }
                error "unexpected target word type: $targetWordType \n[::tsp::currentLine compUnit]\n[::tsp::error_stacktrace]"
            }
            

        } elseif {$sourceWordType eq "scalar"} {
            # assignment from native variable or var, possible type coersion 
            set sourceVarName [lindex $sourceComponent 1]
            set sourceType [::tsp::getVarType compUnit $sourceVarName]
            if {$sourceType eq "undefined"} {
                ::tsp::addError compUnit "set command arg 2 variable not defined: \"$sourceVarName\""
                return [list void "" ""]
            }
            set targetType [::tsp::gen_check_target_var compUnit $targetVarName $targetType $sourceType]
            if {$targetType eq "ERROR"} {
                return [list void "" ""]
            }

            # generate assigment
            if {$targetWordType eq "text"} {
                # don't generate assignment if target and source are the same
                if {$targetVarName eq $sourceVarName} {
                    if {[::tsp:::is_tmpvar $targetVarName]} {
                        error "self assignment of temp var: $$targetVarName\n[::tsp::currentLine compUnit]\n[::tsp::error_stacktrace]"
                    }
                    ::tsp::addWarning compUnit "ignoring self assignment: target \"$targetVarName\"  source \"$sourceVarName\""
                    return [list void "" ""]
                }
                return [list void "" [::tsp::gen_assign_scalar_scalar compUnit $targetVarName $targetType $sourceVarName $sourceType]]

            } elseif {$targetWordType eq "text_array_idxtext" || $targetWordType eq "text_array_idxvar"} {
                return [list void "" [::tsp::gen_assign_array_scalar compUnit $targetVarName $targetArrayIdxtext \
				$targetArrayIdxvar $targetArrayIdxvarType $targetType $sourceVarName $sourceType]]

            } else {
                error "unexpected target word type: $targetWordType \n[::tsp::currentLine compUnit]\n[::tsp::error_stacktrace]"
            }

        } elseif {$sourceWordType eq "array_idxtext"} {
            set sourceVarName [lindex $sourceComponent 1]
            set sourceType [::tsp::getVarType compUnit $sourceVarName]
            if {$sourceType ne "array"} {
                ::tsp::addError compUnit "set command arg 2 variable not defined, referenced as array: \"$sourceVarName\""
                return [list void "" ""]
            }
            set sourceArrayIdxtext [lindex $sourceComponent 2]
            set sourceType var
            # assignment from var, possible type coersion 
            set targetType [::tsp::gen_check_target_var compUnit $targetVarName $targetType $sourceType]
            if {$targetType eq "ERROR"} {
                return [list void "" ""]
            }

            # generate assigment
            if {$targetWordType eq "text"} {
		return [list void "" [::tsp::gen_assign_scalar_array compUnit  $targetVarName $targetType \
			$sourceVarName "" "" $sourceArrayIdxtext]]
		

            } elseif {$targetWordType eq "text_array_idxtext" || $targetWordType eq "text_array_idxvar"} {
                # don't generate assignment if target and source are the same
                if {$targetVarName eq $sourceVarName && $targetArrayIdxtext eq $sourceArrayIdxtext} {
                    ::tsp::addWarning compUnit "ignoring self assignment: target \"$targetVarName\($targetArrayIdxtext)\"  source \"$sourceVarName\($sourceArrayIdxtext)\""
                    return [list void "" ""]
                }
                return [list void "" [::tsp::gen_assign_array_array compUnit $targetVarName $targetArrayIdxtext \
				$targetArrayIdxvar $targetArrayIdxvarType $targetType $sourceVarName "" "" $sourceArrayIdxtext]]

            } else {
                error "unexpected target word type: $targetWordType \n[::tsp::currentLine compUnit]\n[::tsp::error_stacktrace]"
            }

        } elseif {$sourceWordType eq "array_idxvar"} {
            set sourceVarName [lindex $sourceComponent 1]
            set sourceType [::tsp::getVarType compUnit $sourceVarName]
            if {$sourceType ne "array"} {
                ::tsp::addError compUnit "set command arg 2 variable not defined, referenced as array: \"$sourceVarName\""
                return [list void "" ""]
            }
            set sourceArrayIdxvar [lindex $sourceComponent 2]
            set sourceArrayIdxvarType [::tsp::getVarType compUnit $sourceArrayIdxvar]
            if {$sourceArrayIdxvarType eq "undefined"} {
                ::tsp::addError compUnit "set command arg 2 array index variable not defined: \"$sourceArrayIdxvar\""
                return [list void "" ""]
            }
            set sourceType var
            # assignment from var, possible type coersion 
            set targetType [::tsp::gen_check_target_var compUnit $targetVarName $targetType $sourceType]
            if {$targetType eq "ERROR"} {
                return [list void "" ""]
            }

            # generate assigment
            if {$targetWordType eq "text"} {
		return [list void "" [::tsp::gen_assign_scalar_array compUnit  $targetVarName $targetType \
			$sourceVarName $sourceArrayIdxvar $sourceArrayIdxvarType ""]]
		

            } elseif {$targetWordType eq "text_array_idxtext" || $targetWordType eq "text_array_idxvar"} {
                # don't generate assignment if target and source are the same
                if {$targetVarName eq $sourceVarName && $targetArrayIdxvar eq $sourceArrayIdxvar} {
                    ::tsp::addWarning compUnit "ignoring self assignment: target \"$targetVarName\($targetArrayIdxvar)\"  source \"$sourceVarName\($sourceArrayIdxvar)\""
                    return [list void "" ""]
                }
                return [list void "" [::tsp::gen_assign_array_array compUnit $targetVarName $targetArrayIdxtext \
				$targetArrayIdxvar $targetArrayIdxvarType $targetType $sourceVarName $sourceArrayIdxvar $sourceArrayIdxvarType ""]]

            } else {
                error "unexpected target word type: $targetWordType \n[::tsp::currentLine compUnit]\n[::tsp::error_stacktrace]"
            }

        } elseif {$sourceWordType eq "command"} {
            # assignment from command execution
            set sourceCmdRange [lindex $sourceComponent 2]
            lassign [::tsp::parse_nestedbody compUnit $sourceCmdRange] sourceType sourceRhsVar sourceCode

	    if {$sourceCode eq ""} {
		::tsp::addError compUnit "assignment from nested command: no code generated: target \"$targetVarName\" "
		return [list void "" ""]
            }

	    if {$sourceType eq "void"} {
		::tsp::addError compUnit "void assignment from nested command: target \"$targetVarName\""
		return [list void "" ""]
	    }

	    set targetType [::tsp::gen_check_target_var compUnit $targetVarName $targetType $sourceType]
	    if {$targetType eq "ERROR"} {
		return [list void "" ""]
	    }

	    # generate assignment
	    # mostly same as a scalar from scalar assignment
	    set sourceVarName $sourceRhsVar
	    append result "\n/***** ::tsp::generate_set assign from command */\n"
	    append code $sourceCode
	    set targetType [::tsp::gen_check_target_var compUnit $targetVarName $targetType $sourceType]
	    if {$targetType eq "ERROR"} {
		return [list void "" ""]
	    }

	    # generate assigment
	    if {$targetWordType eq "text"} {
		# don't generate assignment if target and source are the same
		if {$targetVarName eq $sourceVarName} {
                    if {[::tsp:::is_tmpvar $targetVarName]} {
                        error "self assignment of temp var: $$targetVarName\n[::tsp::currentLine compUnit]\n[::tsp::error_stacktrace]"
                    }
		    ::tsp::addWarning compUnit "ignoring self assignment: target \"$targetVarName\"  source \"$sourceVarName\""
		    return [list void "" ""]
		}
		append code [::tsp::gen_assign_scalar_scalar compUnit $targetVarName $targetType $sourceVarName $sourceType]

	    } elseif {$targetWordType eq "text_array_idxtext" || $targetWordType eq "text_array_idxvar"} {
		append code [::tsp::gen_assign_array_scalar compUnit $targetVarName $targetArrayIdxtext \
				$targetArrayIdxvar $targetArrayIdxvarType $targetType $sourceVarName $sourceType]

	    } else {
		error "unexpected target word type: $targetWordType"
	    }
	    append result $code
	    append result "\n"
	    return [list void "" $result]

        } else {
            set errors 1
            ::tsp::addError compUnit "set arg 2 unexpected source type: \"$sourceWordType\""
        }
    }
    
    # if any errors, return here
    if {$errors} {
        return [list void "" ""]
    }

}



#########################################################
# assign a scalar variable from text string
#
proc ::tsp::gen_assign_scalar_text {compUnitDict targetVarName targetType sourceText sourceType} {

    upvar $compUnitDict compUnit

    # set the target as dirty
    # puts "gen_assign_scalar_text- ::tsp::setDirty compUnit $targetVarName"
    ::tsp::setDirty compUnit $targetVarName 

    set targetPre [::tsp::var_prefix $targetVarName]

    append result "\n/***** ::tsp::gen_assign_scalar_text */\n"
    switch $targetType {
         boolean {
             switch $sourceType {
                 int {
                     append result "$targetPre$targetVarName = ([::tsp::lang_int_const $sourceText] != 0) ? [::tsp::lang_true_const] : [::tsp::lang_false_const];\n"
                     return $result
                 }
                 double {
                     append result "$targetPre$targetVarName = ([::tsp::lang_double_const $sourceText] != 0) ? [::tsp::lang_true_const] : [::tsp::lang_false_const];\n"
                     return $result
                 }
                 string {
                     if {[string is true $sourceText]} {
                         append result "$targetPre$targetVarName = [::tsp::lang_true_const];\n";
                         return $result
                     } elseif {[string is false $sourceText]} {
                         append result "$targetPre$targetVarName = [::tsp::lang_false_const];\n";
                         return $result
                     } else {
                         ::tsp::addError compUnit "set arg 2 string is not a valid boolean value: \"$sourceText\""
                         return ""
                     }
                 }
                 error "unexpected sourceType: $sourceType \n[::tsp::currentLine compUnit]\n[::tsp::error_stacktrace]"
             }
         }

         int {
             switch $sourceType {
                 int {
                     append result "$targetPre$targetVarName = [::tsp::lang_int_const $sourceText];\n"
                     return $result
                 }
                 double {
                     append result "$targetPre$targetVarName = ([::tsp::lang_type_int]) [::tsp::lang_double_const $sourceText];\n"
                     return $result
                 }
                 string {
                     ::tsp::addError compUnit "set arg 2 string not an $targetType value: \"$sourceText\""
                     return ""
                 }
                 error "unexpected sourceType: $sourceType \n[::tsp::currentLine compUnit]\n[::tsp::error_stacktrace]"
             }
         }
         double {
             switch $sourceType {
                 int {
                     append result "$targetPre$targetVarName = ([::tsp::lang_type_double]) [::tsp::lang_int_const $sourceText];\n"
                     return $result
                 }
                 double {
                     append result "$targetPre$targetVarName = [::tsp::lang_double_const $sourceText];\n"
                     return $result
                 }
                 string {
                     ::tsp::addError compUnit "set arg 2 string not an $targetType value: \"$sourceText\""
                     return ""
                 }
                 error "unexpected sourceType: $sourceType \n[::tsp::currentLine compUnit]\n[::tsp::error_stacktrace]"
             }
         }

         string {
             append result [::tsp::lang_assign_string_const $targetPre$targetVarName $sourceText]
             return $result
         }

         var {
             switch $sourceType {
                 int {
                     append result [::tsp::lang_assign_var_int  $targetPre$targetVarName $sourceText]
                     return $result
                 }
                 double {
                     append result [::tsp::lang_assign_var_double  $targetPre$targetVarName $sourceText]
                     return $result
                 }
                 string {
                     append result [::tsp::lang_assign_var_string  $targetPre$targetVarName [::tsp::lang_quote_string $sourceText]]
                     return $result
                 }
                 error "unexpected sourceType: $sourceType \n[::tsp::currentLine compUnit]\n[::tsp::error_stacktrace]"
             }
         }
    }

    ::tsp::addError compUnit "set: error don't know how to assign $targetVarName $targetType from $sourceText $sourceType"
    return ""
}


#########################################################
# assign a scalar variable from a scalar
#
proc ::tsp::gen_assign_scalar_scalar {compUnitDict targetVarName targetType sourceVarName sourceType} {

    upvar $compUnitDict compUnit

    
    # set the target as dirty
    # puts "gen_assign_scalar_scalar- ::tsp::setDirty compUnit $targetVarName"
    ::tsp::setDirty compUnit $targetVarName 

    set targetPre [::tsp::var_prefix $targetVarName]
    set sourcePre [::tsp::var_prefix $sourceVarName]

    append result "\n/***** ::tsp::gen_assign_scalar_scalar */\n"
    switch $targetType {
         boolean {
             switch $sourceType {
                 boolean {
                     append result "$targetPre$targetVarName = $sourcePre$sourceVarName;\n"
                     return $result
                 }
                 int -
                 double {
                     append result "$targetPre$targetVarName = ($sourcePre$sourceVarName != 0) ? [::tsp::lang_true_const] : [::tsp::lang_false_const];\n"
                     return $result
                 }
                 string {
                     set errMsg [::tsp::gen_runtime_error compUnit [::tsp::lang_quote_string "unable to convert string to boolean, \"$sourceVarName\", value: "]]
                     append result [::tsp::lang_convert_boolean_string $targetPre$targetVarName $sourcePre$sourceVarName $errMsg]
                     return $result
                 }
                 var {
                     set errMsg [::tsp::gen_runtime_error compUnit [::tsp::lang_quote_string "unable to convert var to boolean, \"$sourceVarName\", value: "]]
                     append result [::tsp::lang_convert_boolean_var $targetPre$targetVarName $sourcePre$sourceVarName $errMsg]
                     return $result
                 }
                 error "unexpected sourceType: $sourceType \n[::tsp::currentLine compUnit]\n[::tsp::error_stacktrace]"
             }
         }

         int -
         double {
             switch $sourceType {
                 boolean {
                     append result "$targetPre$targetVarName = ($sourcePre$sourceVarName) ? 1 : 0;\n"
                     return $result
                 }
                 int -
                 double {
                     append result "$targetPre$targetVarName = ([::tsp::lang_type_$targetType]) $sourcePre$sourceVarName;\n"
                     return $result
                 }
                 string {
                     set errMsg [::tsp::gen_runtime_error compUnit [::tsp::lang_quote_string "unable to convert string to $targetType, \"$sourceVarName\", value: "]]
                     append result [::tsp::lang_convert_${targetType}_string $targetPre$targetVarName $sourcePre$sourceVarName $errMsg]
                     return $result
                 }
                 var {
                     set errMsg [::tsp::gen_runtime_error compUnit [::tsp::lang_quote_string "unable to convert var to $targetType, \"$sourceVarName\", value: "]]
                     append result [::tsp::lang_convert_${targetType}_var $targetPre$targetVarName $sourcePre$sourceVarName $errMsg]
                     return $result
                 }
                 error "unexpected sourceType: $sourceType \n[::tsp::currentLine compUnit]\n[::tsp::error_stacktrace]"
             }
         }

         string {
             append result [::tsp::lang_convert_string_$sourceType $targetPre$targetVarName $sourcePre$sourceVarName]
             return $result
         }

         var {
             append result [::tsp::lang_assign_var_$sourceType  $targetPre$targetVarName $sourcePre$sourceVarName]
             return $result
         }
    }

    ::tsp::addError compUnit "set: error don't know how to assign $targetVarName $targetType from $sourceVarName $sourceType"
    return ""
}



#########################################################
# assign a string or var from an interpolated string
# FIXME: be smarter about combining backslash and strings, just append until a scalar is found or last of components
#
proc ::tsp::gen_assign_var_string_interpolated_string {compUnitDict targetVarName targetType sourceComponents} {

    upvar $compUnitDict compUnit

    # set the target as dirty
    # puts "gen_assign_var_string_interpolated_string- ::tsp::setDirty compUnit $targetVarName"
    ::tsp::setDirty compUnit $targetVarName 
    
    set targetPre [::tsp::var_prefix $targetVarName]

    append result "\n/***** ::tsp::gen_assign_var_string_interpolated_string */\n"

    set tmp [::tsp::get_tmpvar compUnit string]
    set tmp2 ""
    set arrVar ""
    if {$targetType eq "var"} {
        set tmp2 [::tsp::get_tmpvar compUnit string]
        append result [::tsp::lang_assign_empty_zero $tmp2 string]
    }
    foreach component $sourceComponents {
        set compType [lindex $component 0]
        switch $compType {
            text -
            backslash {
                # subst the backslashed text, so that we can quote it for a native string
                set sourceText [subst [lindex $component 1]]
                append code [::tsp::lang_assign_string_const $tmp $sourceText]
            }
            scalar {
                # assignment from native variable or var, possible type coersion
                set sourceVarName [lindex $component 1]
                set sourceType [::tsp::getVarType compUnit $sourceVarName]
                if {$sourceType eq "undefined"} {
                    ::tsp::addError compUnit "set command arg 2 interpolated string variable not defined: \"$sourceVarName\""
                    return [list ""]
                }
                append code [::tsp::gen_assign_scalar_scalar compUnit $tmp string $sourceVarName $sourceType]
            }
            command {
                set sourceCmdRange [lindex $component 2]
                lassign [::tsp::parse_nestedbody compUnit $sourceCmdRange] sourceType sourceRhsVar sourceCode
    
                if {$sourceCode eq ""} {
                    ::tsp::addError compUnit "assignment from nested command: no code generated: target \"$targetVarName\" "
                    return [list void "" ""]
                }
        
                if {$sourceType eq "void"} {
                    ::tsp::addError compUnit "void assignment from nested command: target \"$targetVarName\""
                    return [list void "" ""]
                }
                append code $sourceCode
                append code [::tsp::gen_assign_scalar_scalar compUnit $tmp string $sourceRhsVar $sourceType ]
            }
            text_array_idxvar - array_idxvar {
                 append code "//Parsing Array $compType in $component of $sourceComponents\n"
                 #::tsp::addWarning compUnit "$compType not implemented $component $sourceComponents"
                 #append code "// Parsing $component in $sourceComponents\n"
				set tmp_s [::tsp::get_tmpvar compUnit string]
				set doreturn 0

                # assignment from native variable or var, possible type coersion
                set sourceVarName [lindex $component 2]
                #append code "// assignment  |$sourceVarName| to $tmp_s\n"
                set sourceType [::tsp::getVarType compUnit $sourceVarName]
                if {$sourceType eq "undefined"} {
                    ::tsp::addError compUnit "set command arg 2 interpolated string variable not defined: \"$sourceVarName\""
                    return [list ""]
                }
                append code [::tsp::gen_assign_scalar_scalar compUnit $tmp_s string $sourceVarName $sourceType]

				if {($compType=="array_idxvar")} {
					#::tsp::addWarning compUnit "set arg 2 interpolated string cannot contain $compType as $component in $sourceComponents, only commands, text, backslash, or scalar variables"
					set tmp_a [::tsp::get_tmpvar compUnit var tmp_array]
					set tmp_v [::tsp::get_tmpvar compUnit var tmp_idx]
					append code [::tsp::lang_assign_var_string $tmp_v $tmp_s]
					# append code "// Convert array |$tmp_a| to $tmp\n"
                     append code [::tsp::lang_assign_var_array_idxvar $tmp_a [::tsp::get_constvar [::tsp::getConstant compUnit [lindex $component 1]]] $tmp_v "Error loading Array Text"]
					append code [::tsp::lang_convert_string_var $tmp $tmp_a]
				} else {
				    set sourceText [lindex $sourceComponents 3]
				    if {$sourceText eq ""} {
				        append code "//Missing source in $sourceComponents\n"
				        continue
				    } else {
                        #::tsp::addWarning compUnit "set arg 2 interpolated string should not contain $compType as $sourceText in $sourceComponents, only commands, text, backslash, or scalar variables\n"
                        set newsource "[lindex $sourceComponents 1]("
                        #append code "// Convert |$newsource|  to $tmp via $tmp_s\n"
                        append code [::tsp::lang_assign_string_const $tmp $newsource]
                        append code [::tsp::lang_append_string $tmp $tmp_s]
                        append code "Tcl_DStringAppend($tmp,\")\",-1);\n"
                        set doreturn 1
                    }
				}
				if {$targetType eq "string"} {
					#append code "// Append string |$tmp|\n"
					append code [::tsp::lang_append_string $targetPre$targetVarName $tmp]
				} elseif {$targetType eq "var"} {
					#append code "// Append var |$tmp|\n"
					append code [::tsp::lang_assign_var_string $targetVarName $tmp]
				}
				#append code [::tsp::lang_assign_empty_zero $tmp string]
				if {$doreturn>0} {
				    append code "// exiting\n"
					return $code
				}
            }
            text_array_idxtext - array_idxtext {
                 append code "//Parsing Array $compType in $component of $sourceComponents\n"
				set tmp_s [::tsp::get_tmpvar compUnit string]
				set doreturn 0
				if {($compType=="array_idxtext")} {
					#::tsp::addWarning compUnit "set arg 2 interpolated string cannot contain $compType as $component in $sourceComponents, only commands, text, backslash, or scalar variables"
					set tmp_a [::tsp::get_tmpvar compUnit var tmp_array]
					#append code "// Convert array |$tmp_a| to $tmp\n"
					append code [::tsp::lang_assign_var_array_idxvar $tmp_a [::tsp::get_constvar [::tsp::getConstant compUnit [lindex $component 1]]] [::tsp::get_constvar [::tsp::getConstant compUnit [lindex $component 2]]] "Error loading Array Text"]
					append code [::tsp::lang_convert_string_var $tmp $tmp_a]
				} else {
				    set sourceText [lindex $sourceComponents 3]
				    if {$sourceText eq ""} {
				        append code "//Missing source in $sourceComponents\n"
				        continue
				    } else {
                        #::tsp::addWarning compUnit "set arg 2 interpolated string should not contain $compType as $sourceText in $sourceComponents, only commands, text, backslash, or scalar variables\n"
                        #append code "// Convert |$sourceText| to $tmp\n"
                        append code [::tsp::lang_assign_string_const $tmp $sourceText]
                        set doreturn 1
                    }
				}
				if {$targetType eq "string"} {
					#append code "// Append string |$tmp|\n"
					append code [::tsp::lang_append_string $targetPre$targetVarName $tmp]
				} elseif {$targetType eq "var"} {
					#append code "// Append var |$tmp|\n"
					append code [::tsp::lang_assign_var_string $targetVarName $tmp]
				}
				#append code [::tsp::lang_assign_empty_zero $tmp string]
				if {$doreturn>0} {
				    append code "// exiting\n"
					return $code
				}
            }
            default {
                ::tsp::addError compUnit "set arg 2 interpolated string cannot contain $compType, only commands, text, backslash, or scalar variables"
                return ""
            }
        }
        if {$targetType eq "string"} {
            append code [::tsp::lang_append_string $targetPre$targetVarName $tmp]
        } elseif {$targetType eq "var"} {
            append code [::tsp::lang_append_string $tmp2 $tmp]
        }
    }
    if {$targetType eq "var"} {
        append code [::tsp::gen_assign_scalar_scalar compUnit $targetVarName var $tmp2 string]
    }
    append result $code "\n"
    return $result
}


#########################################################
# assign an array variable from text string
# array index is either a text string, or a variable 
#
#
proc ::tsp::gen_assign_array_text {compUnitDict targetVarName targetArrayIdxtext \
		targetArrayIdxvar targetArrayIdxvarType targetType sourceText sourceType} {

    upvar $compUnitDict compUnit
    
    # make text value into a constant var
    set value [::tsp::get_constvar [::tsp::getConstant compUnit $sourceText]]
    append result "\n/***** ::tsp::gen_assign_array_text */\n"
    if {$targetArrayIdxtext ne ""} {
        # constant string index
        append code [::tsp::lang_assign_array_var [::tsp::get_constvar [::tsp::getConstant compUnit $targetVarName]] \
			[::tsp::get_constvar [::tsp::getConstant compUnit $targetArrayIdxtext]] $value] 
        append result $code
        return $result
    } else {
        # variable index
        set idxPre [::tsp::var_prefix $targetArrayIdxvar]
        if {$targetArrayIdxvarType eq "var"} {
            set idx $idxPre$targetArrayIdxvar
        } else {
            # it's a native var, use a shadow var
            lassign [::tsp::getCleanShadowVar compUnit $targetArrayIdxvar] idx shadowCode
            append code $shadowCode
        }
        append code [::tsp::lang_assign_array_var [::tsp::get_constvar [::tsp::getConstant compUnit $targetVarName]] $idx $value]
        append result $code
        return $result
    }
}


#########################################################
# assign an array variable from scalar
# array index is either a text string, or a variable 
#
#FIXME: this should use shadow vars, and create/update if needed when var is dirty
#
proc ::tsp::gen_assign_array_scalar {compUnitDict targetVarName targetArrayIdxtext \
		targetArrayIdxvar targetArrayIdxvarType targetType sourceVarName sourceType} {

    upvar $compUnitDict compUnit
    
    append result "\n/***** ::tsp::gen_assign_array_scalar */\n"

    # prepare the source variable
    if {$sourceType eq "var"} {
        set pre [::tsp::var_prefix $sourceVarName]
        set value  $pre$sourceVarName
    } else {
        set pre [::tsp::var_prefix $sourceVarName]
        if {$pre eq ""} { 
            # it's a tmp var, so just assign into a tmp var type
            set value [::tsp::get_tmpvar compUnit var]
            append code [::tsp::lang_assign_var_$sourceType $value $pre$sourceVarName]
        } else {
            # it's a native var, use a shadow var
            lassign [::tsp::getCleanShadowVar compUnit $sourceVarName] value shadowCode
            append code $shadowCode
        }
    }

    if {$targetArrayIdxtext ne ""} {
        # constant string index

        append code [::tsp::lang_assign_array_var [::tsp::get_constvar [::tsp::getConstant compUnit $targetVarName]] \
			[::tsp::get_constvar [::tsp::getConstant compUnit $targetArrayIdxtext]] $value] 
        append result $code
        return $result

    } else {
        # variable index

        set idxPre [::tsp::var_prefix $targetArrayIdxvar]
        if {$targetArrayIdxvarType eq "var"} {
            set idx $idxPre$targetArrayIdxvar
        } else {
            # it's a native var, use a shadow var
            lassign [::tsp::getCleanShadowVar compUnit $targetArrayIdxvar] idx shadowCode
            append code $shadowCode
        }
        append code [::tsp::lang_assign_array_var [::tsp::get_constvar [::tsp::getConstant compUnit $targetVarName]] $idx $value]
        append result $code
        return $result
    }
}


#########################################################
# assign an array var from an interpolated string
#
proc ::tsp::gen_assign_array_interpolated_string {compUnitDict targetVarName targetArrayIdxtext targetArrayIdxvar targetArrayIdxvarType targetType sourceComponents} {
    upvar $compUnitDict compUnit

    append result "\n/***** ::tsp::gen_assign_array_interpolated_string */\n"
    set sourceVar [::tsp::get_tmpvar compUnit var]
    append code [::tsp::lang_safe_release $sourceVar]
    append code [::tsp::gen_assign_var_string_interpolated_string compUnit $sourceVar var $sourceComponents]
    append code [::tsp::lang_preserve $sourceVar]
    append code [::tsp::gen_assign_array_scalar compUnit $targetVarName $targetArrayIdxtext \
                                $targetArrayIdxvar $targetArrayIdxvarType $targetType $sourceVar var]
    append result $code
    return $result
}


#########################################################
# assign an scalar from an array
# sourceArrayIdx is either a quoted string, or a string 
#
proc ::tsp::gen_assign_scalar_array {compUnitDict targetVarName targetType sourceVarName sourceArrayIdxvar sourceArrayIdxvarType sourceArrayIdxtext} {

    upvar $compUnitDict compUnit
  
    # target will be marked as dirty in ::tsp::gen_assign_scalar_scalar

    append result "\n/***** ::tsp::gen_assign_scalar_array */\n"
    set targetVar [::tsp::get_tmpvar compUnit var]
    append code [::tsp::lang_safe_release $targetVar]
    if {$sourceArrayIdxtext ne ""} {
        set errMsg [::tsp::gen_runtime_error compUnit [::tsp::lang_quote_string "unable to get var from array \"$sourceVarName\", index \"$sourceArrayIdxtext\" "]]
        append code [::tsp::lang_assign_var_array_idxtext $targetVar [::tsp::get_constvar [::tsp::getConstant compUnit $sourceVarName]] \
                                   [::tsp::get_constvar [::tsp::getConstant compUnit $sourceArrayIdxtext]] $errMsg]
    } else {
        set errMsg [::tsp::gen_runtime_error compUnit [::tsp::lang_quote_string "unable to get var from array \"$sourceVarName\", index var \"$sourceArrayIdxvar\" "]]
        set idxPre [::tsp::var_prefix $sourceArrayIdxvar]
        if {$sourceArrayIdxvarType eq "var"} {
            set idx $idxPre$sourceArrayIdxvar
        } else {
            # it's a native var, use a shadow var
            lassign [::tsp::getCleanShadowVar compUnit $sourceArrayIdxvar] idx shadowCode
            append code $shadowCode
        }
        append code [::tsp::lang_assign_var_array_idxvar $targetVar [::tsp::get_constvar [::tsp::getConstant compUnit $sourceVarName]] $idx $errMsg]
    }
    append code [::tsp::lang_preserve $targetVar]
    append code [::tsp::gen_assign_scalar_scalar compUnit $targetVarName $targetType $targetVar var]
    append result $code
    return $result
}

#########################################################
# assign an array from an array
# 
proc ::tsp::gen_assign_array_array {compUnitDict targetVarName targetArrayIdxtext targetArrayIdxvar targetArrayIdxvarType targetType sourceVarName sourceArrayIdxvar sourceArrayIdxvarType sourceArrayIdxtext } {

    upvar $compUnitDict compUnit
  
    append result "\n/***** ::tsp::gen_assign_array_array */\n"
    set assignVar [::tsp::get_tmpvar compUnit var]
    append code [::tsp::lang_safe_release $assignVar]
    if {$sourceArrayIdxtext ne ""} {
        set errMsg [::tsp::gen_runtime_error compUnit [::tsp::lang_quote_string "unable to get var from array \"$sourceVarName\", index \"$sourceArrayIdxtext\" "]]
        append code [::tsp::lang_assign_var_array_idxtext $assignVar [::tsp::get_constvar [::tsp::getConstant compUnit $sourceVarName]] \
                                   [::tsp::get_constvar [::tsp::getConstant compUnit $sourceArrayIdxtext]]  $errMsg]
    } else {
        set errMsg [::tsp::gen_runtime_error compUnit [::tsp::lang_quote_string "unable to get var from array \"$sourceVarName\", index var \"$sourceArrayIdxvar\" "]]
        set idxPre [::tsp::var_prefix $sourceArrayIdxvar]
        if {$sourceArrayIdxvarType eq "var"} {
            set idx $idxPre$sourceArrayIdxvar
        } else {
            set idx [::tsp::get_tmpvar compUnit var]
            append code [::tsp::lang_assign_var_$sourceArrayIdxvarType  $idx $idxPre$sourceArrayIdxvar]
        }
        append code [::tsp::lang_assign_var_array_idxvar $assignVar [::tsp::get_constvar [::tsp::getConstant compUnit $sourceVarName]] $idx $errMsg]
    }
    
    append code [::tsp::lang_preserve $assignVar]
    append code [::tsp::gen_assign_array_scalar compUnit $targetVarName $targetArrayIdxtext \
                $targetArrayIdxvar $targetArrayIdxvarType $targetType $assignVar var ]
    append result $code
    return $result
}




