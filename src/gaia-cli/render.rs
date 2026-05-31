use lexpr::Value;
use pulldown_cmark::{Parser, Event, Tag, TagEnd};
use regex::Regex;

pub const BOLD: &str = "\x1b[1m";
pub const DIM: &str = "\x1b[2m";
pub const RED: &str = "\x1b[31m";
pub const GREEN: &str = "\x1b[32m";
pub const YELLOW: &str = "\x1b[33m";
pub const CYAN: &str = "\x1b[36m";
pub const MAGENTA: &str = "\x1b[35m";
pub const BLUE: &str = "\x1b[34m";
pub const RESET: &str = "\x1b[0m";

const SCHEME_KEYWORDS: &[&str] = &[
    "define", "define*", "lambda", "let", "let*", "letrec", "if", "cond", "else",
    "when", "unless", "begin", "do", "case", "match", "and", "or", "not",
    "set!", "quote", "quasiquote", "unquote", "display", "format", "newline",
    "car", "cdr", "cons", "list", "map", "filter", "for-each", "apply",
    "string-append", "string-length", "substring", "number->string",
    "use-modules", "catch", "throw", "with-exception-handler",
    "#t", "#f",
];

/// Print Scheme code with syntax highlighting
pub fn print_scheme(code: &str) {
    for line in code.lines() {
        let trimmed = line.trim();
        if trimmed.starts_with(";;") || trimmed.starts_with(";") {
            // Comment line
            println!("  {DIM}{CYAN}{}{RESET}", line);
        } else {
            print!("  ");
            print_scheme_line(line);
            println!();
        }
    }
}

fn print_scheme_line(line: &str) {
    let mut chars = line.chars().peekable();
    while let Some(&ch) = chars.peek() {
        match ch {
            '(' | ')' => {
                print!("{YELLOW}{}{RESET}", ch);
                chars.next();
            }
            '"' => {
                // String literal
                let mut s = String::new();
                s.push(ch);
                chars.next();
                let mut escaped = false;
                while let Some(&c) = chars.peek() {
                    s.push(c);
                    chars.next();
                    if escaped { escaped = false; continue; }
                    if c == '\\' { escaped = true; continue; }
                    if c == '"' { break; }
                }
                print!("{GREEN}{}{RESET}", s);
            }
            ';' => {
                // Inline comment — rest of line
                let rest: String = chars.collect();
                print!("{DIM}{CYAN}{}{RESET}", rest);
                return;
            }
            ' ' | '\t' => {
                print!("{}", ch);
                chars.next();
            }
            _ => {
                // Collect a token
                let mut token = String::new();
                while let Some(&c) = chars.peek() {
                    if c == '(' || c == ')' || c == ' ' || c == '\t' || c == '"' || c == ';' {
                        break;
                    }
                    token.push(c);
                    chars.next();
                }
                if SCHEME_KEYWORDS.contains(&token.as_str()) {
                    print!("{MAGENTA}{BOLD}{}{RESET}", token);
                } else if token.starts_with('#') || token.starts_with('\'') {
                    print!("{BLUE}{}{RESET}", token);
                } else if token.parse::<f64>().is_ok() {
                    print!("{BLUE}{}{RESET}", token);
                } else {
                    print!("{}", token);
                }
            }
        }
    }
}


pub fn print_status(msg: &str) {
    eprint!("\r{}{}{}{}", DIM, msg, " ".repeat(10), RESET);
}

pub fn print_result(msg: &str) {
    println!("{}{}{}", GREEN, msg, RESET);
}

pub fn print_error(msg: &str) {
    println!("{}{}{}", RED, msg, RESET);
}

fn clean_assistant_content(text: &str) -> String {
    let mut cleaned = text.to_string();

    // 1. Strip <confidence>...</confidence> and CONFIDENCE(...)
    if let Ok(re) = Regex::new(r"(?s)<confidence>\d+</confidence>") {
        cleaned = re.replace_all(&cleaned, "").to_string();
    }
    if let Ok(re) = Regex::new(r"CONFIDENCE\(\d+\)") {
        cleaned = re.replace_all(&cleaned, "").to_string();
    }

    // 2. Strip FINAL(...) and FINAL_VAR(...)
    if let Ok(re) = Regex::new(r"(?s)FINAL\([^)]*\)") {
        cleaned = re.replace_all(&cleaned, "").to_string();
    }
    if let Ok(re) = Regex::new(r"(?s)FINAL_VAR\([^)]*\)") {
        cleaned = re.replace_all(&cleaned, "").to_string();
    }

    // 3. Strip Scheme code blocks entirely to keep conversation clean
    if let Ok(re) = Regex::new(r"(?s)```repl.*?```") {
        cleaned = re.replace_all(&cleaned, "").to_string();
    }
    if let Ok(re) = Regex::new(r"(?s)```scheme.*?```") {
        cleaned = re.replace_all(&cleaned, "").to_string();
    }

    // 4. Strip <|think|>...</|think|> blocks
    if let Ok(re) = Regex::new(r"(?s)<\|think\|>.*?</\|think\|>") {
        cleaned = re.replace_all(&cleaned, "").to_string();
    }

    let trimmed = cleaned.trim().to_string();
    if trimmed.is_empty() {
        format!("{DIM}[State Update / Internal Execution]{RESET}")
    } else {
        trimmed
    }
}

pub fn print_history(val: &Value) {
    match val {
        Value::Null => println!("  (no history)"),
        Value::Cons(cons) => {
            let mut current = Value::Cons(cons.clone());
            while let Value::Cons(pair) = current {
                let turn = pair.car();
                let mut role = "unknown".to_string();
                let mut content = "".to_string();

                // turn is an alist: (("content" . "...") ("role" . "..."))
                if let Value::Cons(alist) = turn {
                    let mut items = Value::Cons(alist.clone());
                    while let Value::Cons(item_pair) = items {
                        if let Value::Cons(kv) = item_pair.car() {
                            let k = kv.car().as_str().unwrap_or("");
                            let v = kv.cdr().as_str().unwrap_or("");
                            if k == "role" { role = v.to_string(); }
                            if k == "content" { content = v.to_string(); }
                        }
                        items = item_pair.cdr().clone();
                    }
                }

                let color = match role.as_str() {
                    "user" => GREEN,
                    "assistant" => YELLOW,
                    _ => DIM,
                };
                let display_name = match role.as_str() {
                    "user" => "👤 User",
                    "assistant" => "🤖 GAIA",
                    _ => "❓ Unknown",
                };

                println!("{}{} >{} ", color, display_name, RESET);
                let cleaned = if role == "assistant" {
                    clean_assistant_content(&content)
                } else {
                    content
                };
                print_markdown(&cleaned);
                println!("{}", "—".repeat(40));

                current = pair.cdr().clone();
            }
        }
        _ => println!("  {}", val),
    }
}

pub fn print_markdown(text: &str) {
    let parser = Parser::new(text);
    for event in parser {
        match event {
            Event::Text(t) => print!("{}", t),
            Event::Code(c) => print!("{}{}{}", CYAN, c, RESET),
            Event::Start(Tag::Strong) => print!("{}", BOLD),
            Event::End(TagEnd::Strong) => print!("{}", RESET),
            Event::Start(Tag::Emphasis) => print!("\x1b[3m"),
            Event::End(TagEnd::Emphasis) => print!("{}", RESET),
            Event::Start(Tag::Heading { .. }) => print!("\n{}", BOLD),
            Event::End(TagEnd::Heading { .. }) => print!("{}\n", RESET),
            Event::SoftBreak | Event::HardBreak => println!(),
            _ => {}
        }
    }
    println!();
}

pub fn print_env_bindings(val: &Value) {
    match val {
        Value::Null => {
            println!("  {}(empty){}", DIM, RESET);
        }
        Value::Cons(cons) => {
            let mut current = Value::Cons(cons.clone());
            while let Value::Cons(pair) = current {
                let entry = pair.car();
                if let Value::Cons(kv) = entry {
                    let key = kv.car();
                    let val = kv.cdr();
                    println!("  {} = {}", key, val);
                }
                current = pair.cdr().clone();
            }
        }
        _ => {
            println!("  {}", val);
        }
    }
}

pub fn print_list(val: &Value) {
    match val {
        Value::Null => {
            println!("  {}(none){}", DIM, RESET);
        }
        Value::Cons(cons) => {
            let mut current = Value::Cons(cons.clone());
            while let Value::Cons(pair) = current {
                println!("  - {}", pair.car());
                current = pair.cdr().clone();
            }
        }
        _ => {
            println!("  {}", val);
        }
    }
}
