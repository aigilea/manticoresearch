if ( __cmake_helpers_included )
	return ()
endif ()
set ( __cmake_helpers_included YES )

include (printers)
include(CheckFunctionExists)
function(add_lib_for FUNCTION_NAME LIBS_REQUIRED LIB_TRG)
	# check if we can use FUNCTION_NAME first.
	# if possible without extra libs - ok. If no - try to use LIB_REQUIRED list.
	# finally append found (if necessary) library to the link of LIB_TRG
	string(TOUPPER ${FUNCTION_NAME} _fupcase_name)
	set(HAVE_NAME HAVE_${_fupcase_name})
	set(FUNC_FOR_NAME FUNC_FOR_${_fupcase_name})
	if (NOT DEFINED ${HAVE_NAME})
		check_function_exists(${FUNCTION_NAME} ${HAVE_NAME})
		if (NOT ${HAVE_NAME})
			foreach (LIB ${LIBS_REQUIRED})
				set(LIB_XXX "LIB_${LIB}")
				UNSET(${HAVE_NAME} CACHE)
				set(CMAKE_REQUIRED_LIBRARIES ${LIB})
				check_function_exists(${FUNCTION_NAME} ${HAVE_NAME})
				if (${${HAVE_NAME}})
					find_library(LIB_${LIB} ${LIB})
					set(${FUNC_FOR_NAME} "${LIB}" CACHE INTERNAL "Library for function ${FUNCTION}")
					mark_as_advanced(${FUNC_FOR_NAME} LIB_${LIB})
					break()
				endif ()
			endforeach (LIB)
		endif ()
	endif ()
	if (DEFINED ${FUNC_FOR_NAME})
		target_link_libraries(${LIB_TRG} INTERFACE ${${FUNC_FOR_NAME}})
	endif ()
	mark_as_advanced(${HAVE_NAME})
endfunction()

function (with_menu_comp PACKAGE Component NAME INFO)
	string (TOUPPER "${Component}" COMPONENT)
	if (NOT DEFINED WITH_${COMPONENT})
		find_package (${PACKAGE} COMPONENTS ${Component})
		if ( ${PACKAGE}_FOUND)
			set (WITH_${COMPONENT} ON CACHE BOOL "link with ${NAME} library")
		endif()
		mark_as_advanced (${PACKAGE}_FOUND)
	elseif (WITH_${COMPONENT} AND NOT TARGET ${PACKAGE}::${Component})
		find_package (${PACKAGE} REQUIRED COMPONENTS ${Component})
	endif()
	add_feature_info (${PACKAGE} WITH_${COMPONENT} "${INFO}")
	trace (${PACKAGE}::${Component})
	bannervar (WITH_${Component})
endfunction ()

function (with_menu Package NAME INFO)
	string (TOUPPER "${Package}" PACKAGE)
	if (NOT DEFINED WITH_${PACKAGE})
		find_package (${Package})
		if (${Package}_FOUND)
			set (WITH_${PACKAGE} ON CACHE BOOL "link with ${NAME} library")
		endif ()
		mark_as_advanced(${Package}_FOUND)
	elseif (WITH_${PACKAGE} AND NOT TARGET ${Package}::${Package})
		find_package (${Package} REQUIRED)
	endif ()
	add_feature_info (${Package} WITH_${PACKAGE} "${INFO}")
	trace (${Package}::${Package})
	bannervar (WITH_${PACKAGE})
endfunction()

function (with_get Package NAME INFO)
	string (TOUPPER "${Package}" PACKAGE)
	if (NOT DEFINED WITH_${PACKAGE} OR WITH_${PACKAGE} )
		include (Get${PACKAGE})
		set (WITH_${PACKAGE} ON CACHE BOOL "compile with ${NAME} library")
	endif()
	add_feature_info (${Package} WITH_${PACKAGE} "${INFO}")
	trace (${Package}::${Package})
	bannervar (WITH_${PACKAGE})
	if (WITH_${PACKAGE})
		bannervar (WITH_${PACKAGE}_FORCE_STATIC)
	endif()
endfunction()

function (__get_imported_soname TRG OUTVAR)
	get_target_property (_lib ${TRG} LOCATION)
	if (NOT _lib)
		diags ("${TRG}: location is not determined")
		return()
	endif()
	GET_SONAME ("${_lib}" _solib)
	if (NOT _solib)
		diags ("${TRG}: no soname")
		return ()
	endif ()
	set ("${OUTVAR}" "${_solib}" PARENT_SCOPE)
endfunction()

function (__copyp SRC DST PROPERTY) # copy property from SRC to DST, if exists
	get_target_property (_prp ${SRC} ${PROPERTY})
	if (_prp)
		set_target_properties (${DST} PROPERTIES ${PROPERTY} "${_prp}" )
	endif ()
endfunction ()

function (__make_dl_lib SRC) # copy lib without location
	add_library ("${SRC}_ld" INTERFACE IMPORTED)
	foreach (_prop
			INTERFACE_COMPILE_DEFINITIONS
			INTERFACE_COMPILE_FEATURES
			INTERFACE_COMPILE_OPTIONS
			INTERFACE_INCLUDE_DIRECTORIES
			INTERFACE_LINK_LIBRARIES
			INTERFACE_LINK_DEPENDS
			INTERFACE_LINK_DIRECTORIES
			INTERFACE_LINK_OPTIONS
			INTERFACE_POSITION_INDEPENDENT_CODE
			INTERFACE_SOURCES
			INTERFACE_SYSTEM_INCLUDE_DIRECTORIES
			MAP_IMPORTED_CONFIG_RELEASE
			MAP_IMPORTED_CONFIG_RELWITHDEBINFO
			MAP_IMPORTED_CONFIG_DEBUG
			MAP_IMPORTED_CONFIG_MINSIZEREL)
		__copyp (${SRC} ${SRC}_ld ${_prop})
	endforeach ()
endfunction ()

# windows installation stuff
function(__win_install_lib _lib)
	if (NOT TARGET ${_lib} OR NOT WIN32)
		return()
	endif()
	get_property (_type TARGET ${_lib} PROPERTY TYPE)
	if (_type STREQUAL SHARED_LIBRARY OR _type STREQUAL INTERFACE_LIBRARY)
		get_property (_file TARGET ${_lib} PROPERTY LOCATION)
		addruntime ("${_file}")
		get_property (_deps TARGET ${_lib} PROPERTY INTERFACE_LINK_LIBRARIES)
		foreach (_dep ${_deps})
			trace (${_dep})
			__win_install_lib(${_dep})
		endforeach()
	endif()
endfunction()

function (win_install_c Package Component)
	string (TOUPPER "${Component}" COMPONENT)
	if (NOT WITH_${COMPONENT})
		return()
	endif()
	__win_install_lib ("${Package}::${Component}")
endfunction()

function (win_install Package)
	win_install_c (${Package} ${Package})
endfunction ()

function (dl_package Package NAME)
	string (TOUPPER "${Package}" PACKAGE)
	if (NOT WITH_${PACKAGE} OR NOT (HAVE_DLOPEN OR WIN32))
		diag (WITH_${PACKAGE} HAVE_DLOPEN WIN32)
		diags ("can't make dl_${PACKAGE} - package not found, or no dlopen, or not windows")
		return()
	endif()

	if (DEFINED DL_${PACKAGE} AND NOT DL_${PACKAGE})
		diags ("DL_${PACKAGE} is explicitly set to FALSE - will not dynamically-load")
		return()
	endif()

	__get_imported_soname ( "${Package}::${Package}" _lib)
	if (NOT _lib)
		if (DL_${PACKAGE})
			message (FATAL_ERROR "Cant dynamicaly load ${Package}: library is not present")
		endif()
		diags ("imported soname of ${Package}::${Package} is empty (no location, or no soname) - will not dynamically-load")
		return() # library is not preset as external essence, can't dlopen it
	endif()

	set (DL_${PACKAGE} ON CACHE BOOL "load ${NAME} dynamically in runtime (usually with dlopen)")
	set (${PACKAGE}_LIB "${_lib}" CACHE FILEPATH "Library file of ${NAME}")
	__make_dl_lib (${Package}::${Package})

	GET_FILENAME_COMPONENT (_FNAME ${_lib} NAME)
	infomsg ("${PACKAGE} will be loaded dynamically in runtime as ${_FNAME} (${_lib})")
	trace (${Package}::${Package}_ld)
	bannervar (DL_${PACKAGE})
	bannervar (${PACKAGE}_LIB)
endfunction()

function ( GET_SONAME RAWLIB OUTVAR )
	if ( NOT MSVC )
		if ( NOT DEFINED CMAKE_OBJDUMP )
			find_package ( BinUtils QUIET )
		endif ()
		if ( NOT DEFINED CMAKE_OBJDUMP )
			find_program ( CMAKE_OBJDUMP objdump )
		endif ()
		mark_as_advanced ( CMAKE_OBJDUMP BinUtils_DIR )
		if ( APPLE )
			GET_FILENAME_COMPONENT(EXTNAME "${RAWLIB}" EXT)
			if (EXTNAME STREQUAL ".tbd")
				return() # library is present in system by design, no need to unbind from it via dlopen at all.
			endif()
			execute_process ( COMMAND "${CMAKE_OBJDUMP}" -macho -dylib-id "${RAWLIB}"
					WORKING_DIRECTORY "${SOURCE_DIR}"
					RESULT_VARIABLE res
					OUTPUT_VARIABLE _CONTENT
					ERROR_QUIET
					OUTPUT_STRIP_TRAILING_WHITESPACE )

			STRING ( REGEX REPLACE ".*:\n" "" _CONTENT "${_CONTENT}" )
			set ( "${OUTVAR}" "${_CONTENT}" PARENT_SCOPE )
		else()
			execute_process ( COMMAND "${CMAKE_OBJDUMP}" -p "${RAWLIB}"
					WORKING_DIRECTORY "${SOURCE_DIR}"
					RESULT_VARIABLE res
					OUTPUT_VARIABLE _CONTENT
					ERROR_QUIET
					OUTPUT_STRIP_TRAILING_WHITESPACE )

			STRING ( REGEX REPLACE "\n" ";" _CONTENT "${_CONTENT}" )
			FOREACH ( LINE ${_CONTENT} )
				IF ( "${LINE}" MATCHES "^[ \t]+SONAME[ \t]+(.*)" )
					set ( "${OUTVAR}" "${CMAKE_MATCH_1}" PARENT_SCOPE)
					break()
				endif ()
			endforeach ()
		endif(APPLE)
	else()
		GET_FILENAME_COMPONENT (LIBNAME "${RAWLIB}" NAME_WE)
		set("${OUTVAR}" "${LIBNAME}.dll" PARENT_SCOPE)
	endif()
endfunction()

function(configure_config data)
	# generate config files
	set (RUNDIR "${CMAKE_INSTALL_FULL_RUNSTATEDIR}/manticore")
	set (LOGDIR "${CMAKE_INSTALL_FULL_LOCALSTATEDIR}/log/manticore")
	set (CONFDIR "${CMAKE_INSTALL_FULL_LOCALSTATEDIR}/${data}")
	configure_file ("${MANTICORE_SOURCE_DIR}/manticore.conf.in" "${MANTICORE_BINARY_DIR}/manticore.conf" @ONLY)
endfunction()

macro (return_if_target_found TRG LEGEND)
	if (TARGET ${TRG})
		diagst (${TRG} "${LEGEND}")
		return ()
	endif ()
endmacro ()

macro (getruntime OUTVAR)
	if (TARGET RUNTIME)
		get_target_property (${OUTVAR} RUNTIME LIBS)
	endif()
endmacro ()

# append any text to build info
function (addruntime library)
	if (NOT TARGET RUNTIME)
		add_library (RUNTIME INTERFACE)
	endif()
	set_property (TARGET RUNTIME APPEND PROPERTY LIBS "${library}")
endfunction ()

# helpers vars to shorten generate lines
set ( CLANGCXX "$<COMPILE_LANG_AND_ID:CXX,Clang,AppleClang>" )
set ( GNUCXX "$<COMPILE_LANG_AND_ID:CXX,GNU>" )
set ( GNUCLANGCXX "$<COMPILE_LANG_AND_ID:CXX,Clang,AppleClang,GNU>" )
set ( CLANGC "$<COMPILE_LANG_AND_ID:C,Clang,AppleClang>" )
set ( GNUC "$<COMPILE_LANG_AND_ID:C,GNU>" )
set ( GNUCLANGC "$<COMPILE_LANG_AND_ID:C,Clang,AppleClang,GNU>" )
set ( GNUC_CXX "$<OR:${GNUCXX},${GNUC}>" )
set ( CLANGC_CXX "$<OR:${CLANGCXX},${CLANGC}>" )
set ( GNUCLANGC_CXX "$<OR:${GNUCLANGCXX},${GNUCLANGC}>" )
if (CMAKE_CXX_COMPILER_ID STREQUAL "Clang" AND CMAKE_CXX_COMPILER_FRONTEND_VARIANT STREQUAL "MSVC")
	set ( CLANG_CL 1 )
	set ( ONLYGNUCLANGCXX 0 )
	set ( ONLYCLANGCXX 0 )
	set ( ONLYGNUCLANGC 0 )
	set ( ONLYGNUCLANGC_CXX 0 )
	set ( MSCXX 1 )
else ()
	set ( CLANG_CL 0 )
	set ( ONLYGNUCLANGCXX "${GNUCLANGCXX}" )
	set ( ONLYCLANGCXX "${CLANGCXX}" )
	set ( ONLYGNUCLANGC "${GNUCLANGC}" )
	set ( ONLYGNUCLANGC_CXX "${GNUCLANGC_CXX}" )
	set ( MSCXX "$<COMPILE_LANG_AND_ID:CXX,MSVC>" )
endif ()
