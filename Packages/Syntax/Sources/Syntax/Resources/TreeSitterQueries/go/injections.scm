([
  (const_spec
    name: (identifier)
    "="
    (comment) @_comment
    value: (expression_list
      [
        (interpreted_string_literal
          (interpreted_string_literal_content) @injection.content)
        (raw_string_literal
          (raw_string_literal_content) @injection.content)
      ]))
  (var_spec
    name: (identifier)
    "="
    (comment) @_comment
    value: (expression_list
      [
        (interpreted_string_literal
          (interpreted_string_literal_content) @injection.content)
        (raw_string_literal
          (raw_string_literal_content) @injection.content)
      ]))
  (assignment_statement
    left: (expression_list)
    "="
    (comment) @_comment
    right: (expression_list
      [
        (interpreted_string_literal
          (interpreted_string_literal_content) @injection.content)
        (raw_string_literal
          (raw_string_literal_content) @injection.content)
      ]))
  (short_var_declaration
    left: (expression_list)
    ":="
    (comment) @_comment
    right: (expression_list
      [
        (interpreted_string_literal
          (interpreted_string_literal_content) @injection.content)
        (raw_string_literal
          (raw_string_literal_content) @injection.content)
      ]))
  (composite_literal
    body: (literal_value
      (keyed_element
        (comment) @_comment
        value: (literal_element
          [
            (interpreted_string_literal
              (interpreted_string_literal_content) @injection.content)
            (raw_string_literal
              (raw_string_literal_content) @injection.content)
          ]))))
  (expression_statement
    (call_expression
      (argument_list
        (comment) @_comment
        [
          (interpreted_string_literal
            (interpreted_string_literal_content) @injection.content)
          (raw_string_literal
            (raw_string_literal_content) @injection.content)
        ])))
]
  (#match? @_comment "^\\/\\*\\s*sql\\s*\\*\\/$")
  (#set! injection.language "sql"))

([
  (const_spec
    name: (identifier)
    "="
    (comment) @_comment
    value: (expression_list
      [
        (interpreted_string_literal
          (interpreted_string_literal_content) @injection.content)
        (raw_string_literal
          (raw_string_literal_content) @injection.content)
      ]))
  (var_spec
    name: (identifier)
    "="
    (comment) @_comment
    value: (expression_list
      [
        (interpreted_string_literal
          (interpreted_string_literal_content) @injection.content)
        (raw_string_literal
          (raw_string_literal_content) @injection.content)
      ]))
  (assignment_statement
    left: (expression_list)
    "="
    (comment) @_comment
    right: (expression_list
      [
        (interpreted_string_literal
          (interpreted_string_literal_content) @injection.content)
        (raw_string_literal
          (raw_string_literal_content) @injection.content)
      ]))
  (short_var_declaration
    left: (expression_list)
    ":="
    (comment) @_comment
    right: (expression_list
      [
        (interpreted_string_literal
          (interpreted_string_literal_content) @injection.content)
        (raw_string_literal
          (raw_string_literal_content) @injection.content)
      ]))
  (composite_literal
    body: (literal_value
      (keyed_element
        (comment) @_comment
        value: (literal_element
          [
            (interpreted_string_literal
              (interpreted_string_literal_content) @injection.content)
            (raw_string_literal
              (raw_string_literal_content) @injection.content)
          ]))))
  (expression_statement
    (call_expression
      (argument_list
        (comment) @_comment
        [
          (interpreted_string_literal
            (interpreted_string_literal_content) @injection.content)
          (raw_string_literal
            (raw_string_literal_content) @injection.content)
        ])))
]
  (#match? @_comment "^\\/\\*\\s*json\\s*\\*\\/")
  ; /* json */ or /*json*/
  (#set! injection.language "json"))

([
  (const_spec
    name: (identifier)
    "="
    (comment) @_comment
    value: (expression_list
      [
        (interpreted_string_literal
          (interpreted_string_literal_content) @injection.content)
        (raw_string_literal
          (raw_string_literal_content) @injection.content)
      ]))
  (var_spec
    name: (identifier)
    "="
    (comment) @_comment
    value: (expression_list
      [
        (interpreted_string_literal
          (interpreted_string_literal_content) @injection.content)
        (raw_string_literal
          (raw_string_literal_content) @injection.content)
      ]))
  (assignment_statement
    left: (expression_list)
    "="
    (comment) @_comment
    right: (expression_list
      [
        (interpreted_string_literal
          (interpreted_string_literal_content) @injection.content)
        (raw_string_literal
          (raw_string_literal_content) @injection.content)
      ]))
  (short_var_declaration
    left: (expression_list)
    ":="
    (comment) @_comment
    right: (expression_list
      [
        (interpreted_string_literal
          (interpreted_string_literal_content) @injection.content)
        (raw_string_literal
          (raw_string_literal_content) @injection.content)
      ]))
  (composite_literal
    body: (literal_value
      (keyed_element
        (comment) @_comment
        value: (literal_element
          [
            (interpreted_string_literal
              (interpreted_string_literal_content) @injection.content)
            (raw_string_literal
              (raw_string_literal_content) @injection.content)
          ]))))
  (expression_statement
    (call_expression
      (argument_list
        (comment) @_comment
        [
          (interpreted_string_literal
            (interpreted_string_literal_content) @injection.content)
          (raw_string_literal
            (raw_string_literal_content) @injection.content)
        ])))
]
  (#match? @_comment "^\\/\\*\\s*yaml\\s*\\*\\/")
  ; /* yaml */ or /*yaml*/
  (#set! injection.language "yaml"))

([
  (const_spec
    name: (identifier)
    "="
    (comment) @_comment
    value: (expression_list
      [
        (interpreted_string_literal
          (interpreted_string_literal_content) @injection.content)
        (raw_string_literal
          (raw_string_literal_content) @injection.content)
      ]))
  (var_spec
    name: (identifier)
    "="
    (comment) @_comment
    value: (expression_list
      [
        (interpreted_string_literal
          (interpreted_string_literal_content) @injection.content)
        (raw_string_literal
          (raw_string_literal_content) @injection.content)
      ]))
  (assignment_statement
    left: (expression_list)
    "="
    (comment) @_comment
    right: (expression_list
      [
        (interpreted_string_literal
          (interpreted_string_literal_content) @injection.content)
        (raw_string_literal
          (raw_string_literal_content) @injection.content)
      ]))
  (short_var_declaration
    left: (expression_list)
    ":="
    (comment) @_comment
    right: (expression_list
      [
        (interpreted_string_literal
          (interpreted_string_literal_content) @injection.content)
        (raw_string_literal
          (raw_string_literal_content) @injection.content)
      ]))
  (composite_literal
    body: (literal_value
      (keyed_element
        (comment) @_comment
        value: (literal_element
          [
            (interpreted_string_literal
              (interpreted_string_literal_content) @injection.content)
            (raw_string_literal
              (raw_string_literal_content) @injection.content)
          ]))))
  (expression_statement
    (call_expression
      (argument_list
        (comment) @_comment
        [
          (interpreted_string_literal
            (interpreted_string_literal_content) @injection.content)
          (raw_string_literal
            (raw_string_literal_content) @injection.content)
        ])))
]
  (#match? @_comment "^\\/\\*\\s*html\\s*\\*\\/")
  ; /* html */ or /*html*/
  (#set! injection.language "html"))

([
  (const_spec
    name: (identifier)
    "="
    (comment) @_comment
    value: (expression_list
      [
        (interpreted_string_literal
          (interpreted_string_literal_content) @injection.content)
        (raw_string_literal
          (raw_string_literal_content) @injection.content)
      ]))
  (var_spec
    name: (identifier)
    "="
    (comment) @_comment
    value: (expression_list
      [
        (interpreted_string_literal
          (interpreted_string_literal_content) @injection.content)
        (raw_string_literal
          (raw_string_literal_content) @injection.content)
      ]))
  (assignment_statement
    left: (expression_list)
    "="
    (comment) @_comment
    right: (expression_list
      [
        (interpreted_string_literal
          (interpreted_string_literal_content) @injection.content)
        (raw_string_literal
          (raw_string_literal_content) @injection.content)
      ]))
  (short_var_declaration
    left: (expression_list)
    ":="
    (comment) @_comment
    right: (expression_list
      [
        (interpreted_string_literal
          (interpreted_string_literal_content) @injection.content)
        (raw_string_literal
          (raw_string_literal_content) @injection.content)
      ]))
  (composite_literal
    body: (literal_value
      (keyed_element
        (comment) @_comment
        value: (literal_element
          [
            (interpreted_string_literal
              (interpreted_string_literal_content) @injection.content)
            (raw_string_literal
              (raw_string_literal_content) @injection.content)
          ]))))
  (expression_statement
    (call_expression
      (argument_list
        (comment) @_comment
        [
          (interpreted_string_literal
            (interpreted_string_literal_content) @injection.content)
          (raw_string_literal
            (raw_string_literal_content) @injection.content)
        ])))
]
  (#match? @_comment "^\\/\\*\\s*js\\s*\\*\\/")
  ; /* js */ or /*js*/
  (#set! injection.language "javascript"))

([
  (const_spec
    name: (identifier)
    "="
    (comment) @_comment
    value: (expression_list
      [
        (interpreted_string_literal
          (interpreted_string_literal_content) @injection.content)
        (raw_string_literal
          (raw_string_literal_content) @injection.content)
      ]))
  (var_spec
    name: (identifier)
    "="
    (comment) @_comment
    value: (expression_list
      [
        (interpreted_string_literal
          (interpreted_string_literal_content) @injection.content)
        (raw_string_literal
          (raw_string_literal_content) @injection.content)
      ]))
  (assignment_statement
    left: (expression_list)
    "="
    (comment) @_comment
    right: (expression_list
      [
        (interpreted_string_literal
          (interpreted_string_literal_content) @injection.content)
        (raw_string_literal
          (raw_string_literal_content) @injection.content)
      ]))
  (short_var_declaration
    left: (expression_list)
    ":="
    (comment) @_comment
    right: (expression_list
      [
        (interpreted_string_literal
          (interpreted_string_literal_content) @injection.content)
        (raw_string_literal
          (raw_string_literal_content) @injection.content)
      ]))
  (composite_literal
    body: (literal_value
      (keyed_element
        (comment) @_comment
        value: (literal_element
          [
            (interpreted_string_literal
              (interpreted_string_literal_content) @injection.content)
            (raw_string_literal
              (raw_string_literal_content) @injection.content)
          ]))))
  (expression_statement
    (call_expression
      (argument_list
        (comment) @_comment
        [
          (interpreted_string_literal
            (interpreted_string_literal_content) @injection.content)
          (raw_string_literal
            (raw_string_literal_content) @injection.content)
        ])))
]
  (#match? @_comment "^\\/\\*\\s*css\\s*\\*\\/")
  ; /* css */ or /*css*/
  (#set! injection.language "css"))

([
  (const_spec
    name: (identifier)
    "="
    (comment) @_comment
    value: (expression_list
      [
        (interpreted_string_literal
          (interpreted_string_literal_content) @injection.content)
        (raw_string_literal
          (raw_string_literal_content) @injection.content)
      ]))
  (var_spec
    name: (identifier)
    "="
    (comment) @_comment
    value: (expression_list
      [
        (interpreted_string_literal
          (interpreted_string_literal_content) @injection.content)
        (raw_string_literal
          (raw_string_literal_content) @injection.content)
      ]))
  (assignment_statement
    left: (expression_list)
    "="
    (comment) @_comment
    right: (expression_list
      [
        (interpreted_string_literal
          (interpreted_string_literal_content) @injection.content)
        (raw_string_literal
          (raw_string_literal_content) @injection.content)
      ]))
  (short_var_declaration
    left: (expression_list)
    ":="
    (comment) @_comment
    right: (expression_list
      [
        (interpreted_string_literal
          (interpreted_string_literal_content) @injection.content)
        (raw_string_literal
          (raw_string_literal_content) @injection.content)
      ]))
  (composite_literal
    body: (literal_value
      (keyed_element
        (comment) @_comment
        value: (literal_element
          [
            (interpreted_string_literal
              (interpreted_string_literal_content) @injection.content)
            (raw_string_literal
              (raw_string_literal_content) @injection.content)
          ]))))
  (expression_statement
    (call_expression
      (argument_list
        (comment) @_comment
        [
          (interpreted_string_literal
            (interpreted_string_literal_content) @injection.content)
          (raw_string_literal
            (raw_string_literal_content) @injection.content)
        ])))
]
  (#match? @_comment "^\\/\\*\\s*lua\\s*\\*\\/")
  ; /* lua */ or /*lua*/
  (#set! injection.language "lua"))

([
  (const_spec
    name: (identifier)
    "="
    (comment) @_comment
    value: (expression_list
      [
        (interpreted_string_literal
          (interpreted_string_literal_content) @injection.content)
        (raw_string_literal
          (raw_string_literal_content) @injection.content)
      ]))
  (var_spec
    name: (identifier)
    "="
    (comment) @_comment
    value: (expression_list
      [
        (interpreted_string_literal
          (interpreted_string_literal_content) @injection.content)
        (raw_string_literal
          (raw_string_literal_content) @injection.content)
      ]))
  (assignment_statement
    left: (expression_list)
    "="
    (comment) @_comment
    right: (expression_list
      [
        (interpreted_string_literal
          (interpreted_string_literal_content) @injection.content)
        (raw_string_literal
          (raw_string_literal_content) @injection.content)
      ]))
  (short_var_declaration
    left: (expression_list)
    ":="
    (comment) @_comment
    right: (expression_list
      [
        (interpreted_string_literal
          (interpreted_string_literal_content) @injection.content)
        (raw_string_literal
          (raw_string_literal_content) @injection.content)
      ]))
  (composite_literal
    body: (literal_value
      (keyed_element
        (comment) @_comment
        value: (literal_element
          [
            (interpreted_string_literal
              (interpreted_string_literal_content) @injection.content)
            (raw_string_literal
              (raw_string_literal_content) @injection.content)
          ]))))
  (expression_statement
    (call_expression
      (argument_list
        (comment) @_comment
        [
          (interpreted_string_literal
            (interpreted_string_literal_content) @injection.content)
          (raw_string_literal
            (raw_string_literal_content) @injection.content)
        ])))
]
  (#match? @_comment "^\\/\\*\\s*bash\\s*\\*\\/")
  ; /* bash */ or /*bash*/
  (#set! injection.language "bash"))
