(macro_invocation
  macro: [
    (identifier) @_macro_name
    (scoped_identifier
      (identifier) @_macro_name .)
  ]
  (#not-any-of? @_macro_name "view" "html")
  (token_tree) @injection.content
  (#set! injection.language "rust"))

(macro_invocation
  macro: [
    (identifier) @_macro_name
    (scoped_identifier
      (identifier) @_macro_name .)
  ]
  (#any-of? @_macro_name "sql")
  (_) @injection.content
  (#set! injection.language "sql"))
