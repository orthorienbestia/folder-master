//! Filename glob grammar, compiled through the same bounded Unicode regex API.
use super::{error, CompileError};
use std::{iter::Peekable, str::Chars};

pub(super) fn regex_source(pattern: &str) -> Result<String, CompileError> {
    let mut chars = pattern.chars().peekable();
    let mut result = String::from(r"\A(?:");
    let mut depth = 0;
    while let Some(c) = chars.next() {
        match c {
            '/' | '\0' => return Err(error("invalid_glob")),
            '*' => result.push_str("[^/]*"),
            '?' => result.push_str("[^/]"),
            '[' => result.push_str(&class(&mut chars)?),
            '\\' => {
                let escaped = chars.next().ok_or_else(|| error("invalid_glob"))?;
                if escaped == '/' || escaped == '\0' {
                    return Err(error("invalid_glob"));
                };
                result.push_str(&regex::escape(&escaped.to_string()));
            }
            '{' => {
                depth += 1;
                if depth > 16 {
                    return Err(error("glob_too_deep"));
                };
                result.push_str("(?:");
            }
            '}' => {
                if depth == 0 {
                    return Err(error("invalid_glob"));
                };
                depth -= 1;
                result.push(')');
            }
            ',' if depth > 0 => result.push('|'),
            _ => result.push_str(&regex::escape(&c.to_string())),
        }
    }
    if depth != 0 {
        return Err(error("invalid_glob"));
    }
    result.push_str(r")\z");
    Ok(result)
}
fn class(chars: &mut Peekable<Chars<'_>>) -> Result<String, CompileError> {
    let mut result = String::from("[");
    if matches!(chars.peek(), Some('!' | '^')) {
        chars.next();
        result.push('^');
    }
    let mut first = true;
    let mut hyphen = false;
    while let Some(c) = chars.next() {
        if c == ']' && !first {
            result.push(']');
            return Ok(result);
        }
        match c {
            '/' | '\0' => return Err(error("invalid_glob")),
            '\\' => {
                let c = chars.next().ok_or_else(|| error("invalid_glob"))?;
                if c == '/' || c == '\0' {
                    return Err(error("invalid_glob"));
                };
                result.push_str(&regex::escape(&c.to_string()));
                hyphen = false;
            }
            '-' if !first && chars.peek() != Some(&']') => {
                if hyphen {
                    return Err(error("invalid_glob"));
                };
                result.push('-');
                hyphen = true;
            }
            _ => {
                result.push_str(&regex::escape(&c.to_string()));
                hyphen = false;
            }
        }
        first = false;
    }
    Err(error("invalid_glob"))
}
