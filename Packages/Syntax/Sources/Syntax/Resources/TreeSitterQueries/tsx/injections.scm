(call_expression
  function: (identifier) @_name
  (#eq? @_name "css")
  arguments: (template_string
    (string_fragment) @injection.content
    (#set! injection.language "css")))

(call_expression
  function: (member_expression
    object: (identifier) @_obj
    (#eq? @_obj "styled")
    property: (property_identifier))
  arguments: (template_string
    (string_fragment) @injection.content
    (#set! injection.language "css")))

(call_expression
  function: (call_expression
    function: (identifier) @_name
    (#eq? @_name "styled"))
  arguments: (template_string
    (string_fragment) @injection.content
    (#set! injection.language "css")))

(call_expression
  function: (identifier) @_name
  (#eq? @_name "html")
  arguments: (template_string
    (string_fragment) @injection.content
    (#set! injection.language "html")))

(call_expression
  function: (identifier) @_name
  (#eq? @_name "js")
  arguments: (template_string
    (string_fragment) @injection.content
    (#set! injection.language "javascript")))

(call_expression
  function: (identifier) @_name
  (#eq? @_name "json")
  arguments: (template_string
    (string_fragment) @injection.content
    (#set! injection.language "json")))

(call_expression
  function: (identifier) @_name
  (#eq? @_name "sql")
  arguments: (template_string
    (string_fragment) @injection.content
    (#set! injection.language "sql")))

(call_expression
  function: (identifier) @_name
  (#eq? @_name "sql")
  arguments: (arguments
    (template_string
      (string_fragment) @injection.content
      (#set! injection.language "sql"))))

(call_expression
  function: (identifier) @_name
  (#eq? @_name "ts")
  arguments: (template_string
    (string_fragment) @injection.content
    (#set! injection.language "typescript")))

(call_expression
  function: (identifier) @_name
  (#match? @_name "^ya?ml$")
  arguments: (template_string
    (string_fragment) @injection.content
    (#set! injection.language "yaml")))

(((comment) @_ecma_comment
  [
    (string
      (string_fragment) @injection.content)
    (template_string
      (string_fragment) @injection.content)
  ])
  (#match? @_ecma_comment "^\\/\\*\\s*html\\s*\\*\\/")
  (#set! injection.language "html"))

(((comment) @_ecma_comment
  [
    (string
      (string_fragment) @injection.content)
    (template_string
      (string_fragment) @injection.content)
  ])
  (#match? @_ecma_comment "^\\/\\*\\s*sql\\s*\\*\\/")
  (#set! injection.language "sql"))

(((comment) @_ecma_comment
  [
    (string
      (string_fragment) @injection.content)
    (template_string
      (string_fragment) @injection.content)
  ])
  (#match? @_ecma_comment "^\\/\\*\\s*(css)\\s*\\*\\/")
  (#set! injection.language "css"))
