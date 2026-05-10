([
  (call
    [
      (attribute
        attribute: (identifier))
      (identifier)
    ]
    arguments: (argument_list
      (comment) @_comment
      (string
        (string_content) @injection.content)))
  ((comment) @_comment
    .
    (expression_statement
      (assignment
        right: (string
          (string_content) @injection.content))))
]
  (#match? @_comment "^(#|#\\s+)(?i:sql)\\s*$")
  (#set! injection.language "sql"))
