; C++ main function
((function_definition
    declarator: (function_declarator
        declarator: (identifier) @run))
  (#eq? @run "main")
  (#set! tag cpp-main))

; GoogleTest TEST/TEST_F/TEST_P macros
; Parsed as function_definition with TEST as the function name and suite/test as parameters
((function_definition
    declarator: (function_declarator
        declarator: (identifier) @_macro
        parameters: (parameter_list
            (parameter_declaration
                type: (type_identifier) @GTEST_SUITE)
            (parameter_declaration
                type: (type_identifier) @run @GTEST_NAME))))
  (#match? @_macro "^TEST(_F|_P)?$")
  (#set! tag cpp-gtest))
