; C++ main function
((function_definition
    declarator: (function_declarator
        declarator: (identifier) @run))
  (#eq? @run "main")
  (#set! tag cpp-main))

; GoogleTest TEST/TEST_F/TEST_P macros
; Parsed as function_definition with TEST as the function name and suite/test as parameters
; @SUITE becomes ZED_CUSTOM_SUITE, @run becomes ZED_SYMBOL
((function_definition
    declarator: (function_declarator
        declarator: (identifier) @_macro
        parameters: (parameter_list
            (parameter_declaration
                type: (type_identifier) @SUITE)
            (parameter_declaration
                type: (type_identifier) @run))))
  (#match? @_macro "^TEST(_F|_P)?$")
  (#set! tag cpp-gtest))
