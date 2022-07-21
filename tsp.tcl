package provide tsp 0.1

package require parser

namespace eval ::tsp {
    # types allowed for variables and procs
    variable VAR_TYPES [list boolean int double string array var]
    variable NATIVE_TYPES [list boolean int double string]
    variable RETURN_TYPES [list void boolean int double string var]
    
    # added for code package making MiR see also tsp-packagehelper.tcl
    variable COMPILE_PACKAGE 0
    variable PACKAGE_NAMESPACE ""
    variable NAMESPACE_VARS ""
    variable PACKAGE_HEADER ""
    variable TCC_HANDLE 
    variable PACKAGE_PROCS ""
    
    # Locked global vars from stdlib in WIN32 and MINGW ... this is rather annoying MiR
    # TSP rewrites variable/argmunetnames with __
    # this interfers with some #defines from stdlib.h at least
    # if compiled code crashes for no obvious reason
    # maybe we found another reserved extern defined global variable
    # That's what I hate C for :-) lots of included headers and getting a pointer conversion warning at best if you redefine those (tcc won't even warn on this)
    # so did a quick search for every __ prefixed symbol and locked it up... lets see how far we get
    
    variable LOCKED_WINVARS {argc argv targv wargv mb_cur_max mb_cur_max_dll argc_dll argv_dll imp__environ_dll imp__sys_nerr imp__sys_nerr_dll imp__sys_errlist CRT_INLINE CRT_STRINGIZE CRT_UNALIGNED CRT_WIDE DEFINE_CPP_OVERLOAD_SECURE_FUNC_0_0 DEFINE_CPP_OVERLOAD_SECURE_FUNC_0_1 DEFINE_CPP_OVERLOAD_SECURE_FUNC_0_1_ARGLIST DEFINE_CPP_OVERLOAD_SECURE_FUNC_0_2 DEFINE_CPP_OVERLOAD_SECURE_FUNC_0_2_ARGLIST DEFINE_CPP_OVERLOAD_SECURE_FUNC_0_3 DEFINE_CPP_OVERLOAD_SECURE_FUNC_0_4 DEFINE_CPP_OVERLOAD_SECURE_FUNC_1_1 DEFINE_CPP_OVERLOAD_SECURE_FUNC_1_2 DEFINE_CPP_OVERLOAD_SECURE_FUNC_1_3 DEFINE_CPP_OVERLOAD_SECURE_FUNC_2_0 DEFINE_CPP_OVERLOAD_SECURE_FUNC_SPLITPATH EMPTY_DECLSPEC ERRCODE_DEFINED_MS GNUC_VA_LIST MINGW_ATTRIB_CONST MINGW_ATTRIB_DEPRECATED MINGW_ATTRIB_MALLOC MINGW_ATTRIB_NONNULL MINGW_ATTRIB_NORETURN MINGW_ATTRIB_PURE MINGW_FPCLASS_DEFINED MINGW_H MINGW_IMPORT MINGW_NOTHROW MSVCRT__ RETURN_POLICY_DST RETURN_POLICY_SAME RETURN_POLICY_VOID TRY__ WIN32__ _mb_cur_max_func argc argv attribute__ builtin_alloca builtin_isgreater builtin_isgreaterequal builtin_isless builtin_islessequal builtin_islessgreater builtin_isunordered crt_typefix declspec dst fastcall finddata64_t fpclassifyf i386__ inline__ int16 int32 int64 int8 int8_t_defined intptr_t_defined iob_func mb_cur_max mbcur_max mingw_access mingw_snprintf mingw_vsnprintf signbitf stat64 static_assert_t stdcall swprintf_l try__ uintptr_t_defined unaligned va_copy va_end va_start vswprintf_l wargv x86_64}

    # compiler log for all procs, keys are "filename,procname" errors|warnings, entries are list of: errors/warnings
    # most recent compilation has key of _
    variable COMPILER_LOG [dict create]

    # dict of compiled procs, entries are list of: returns argTypes compiledReference
    variable COMPILED_PROCS [dict create]

    # directory name of debug output, if any
    variable DEBUG_DIR ""

    # output of traces, default stderr
    # when ::tsp::debug is called, a file is created in that directory
    variable TRACE_FD stderr

    # the last traced proc that returned a value (or void), so the we can check their return types
    variable TRACE_PROC ""

    # inline - whether to inline code or use utility methods/functions where applicable
    variable INLINE 0

    # home_dir - tsp installation dir, so we can find native files
    variable HOME_DIR

    # other ::tsp namespace variables are set in language specific files, 
    # e.g., tsp-java.tcl, tsp-clang.tcl
}                                                                           

set ::tsp::HOME_DIR [file normalize [file dirname [info script]]]

source [file join [file dirname [info script]] tsp-logging.tcl]
source [file join [file dirname [info script]] tsp-compile.tcl]
source [file join [file dirname [info script]] tsp-trace.tcl]
source [file join [file dirname [info script]] tsp-expr.tcl]
source [file join [file dirname [info script]] tsp-parse.tcl]
source [file join [file dirname [info script]] tsp-types.tcl]
source [file join [file dirname [info script]] tsp-generate.tcl]
source [file join [file dirname [info script]] tsp-generate-set.tcl]
source [file join [file dirname [info script]] tsp-generate-math.tcl]
source [file join [file dirname [info script]] tsp-generate-control.tcl]
source [file join [file dirname [info script]] tsp-generate-var.tcl]
source [file join [file dirname [info script]] tsp-generate-list.tcl]
source [file join [file dirname [info script]] tsp-generate-string.tcl]

source [file join [file dirname [info script]] tsp-packagehelper.tcl]

# source the language specific module
if {$::tcl_platform(platform) eq "java"} {
    source [file join [file dirname [info script]] tsp-java.tcl]
} else {
    source [file join [file dirname [info script]] tsp-clang.tcl]
}

format ""

