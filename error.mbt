///|
/// The category of a Rego engine error.
///
/// Every failure surfaced by the engine is classified, so callers can react to
/// a missing document differently from a syntax error.
pub(all) enum RegoErrorKind {
  LexError
  ParseError
  JsonError
  TypeError
  UndefinedError
  ArityError
  DivideByZero
  ConflictError
  SafetyError
  CompileError
}

///|
/// A structured engine error, optionally carrying a source position.
pub(all) struct RegoError {
  kind : RegoErrorKind
  message : String
  line : Int
  column : Int
}

///|
/// An error with no source position.
pub fn RegoError::make(kind : RegoErrorKind, message : String) -> RegoError {
  { kind, message, line: 0, column: 0 }
}

///|
/// An error located at a line/column in the policy source.
pub fn RegoError::at(
  kind : RegoErrorKind,
  message : String,
  line : Int,
  column : Int,
) -> RegoError {
  { kind, message, line, column }
}

///|
/// A short machine-friendly label for the error category.
pub fn RegoErrorKind::label(self : RegoErrorKind) -> String {
  match self {
    RegoErrorKind::LexError => "lex"
    RegoErrorKind::ParseError => "parse"
    RegoErrorKind::JsonError => "json"
    RegoErrorKind::TypeError => "type"
    RegoErrorKind::UndefinedError => "undefined"
    RegoErrorKind::ArityError => "arity"
    RegoErrorKind::DivideByZero => "divide-by-zero"
    RegoErrorKind::ConflictError => "conflict"
    RegoErrorKind::SafetyError => "safety"
    RegoErrorKind::CompileError => "compile"
  }
}

///|
/// Render an error for humans, including the position when it is known.
pub fn RegoError::render(self : RegoError) -> String {
  if self.line > 0 {
    "[" +
    self.kind.label() +
    "] " +
    self.message +
    " (line " +
    self.line.to_string() +
    ", column " +
    self.column.to_string() +
    ")"
  } else {
    "[" + self.kind.label() + "] " + self.message
  }
}
