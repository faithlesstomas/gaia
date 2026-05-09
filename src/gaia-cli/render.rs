use lexpr::Value;
use pulldown_cmark::{Parser, Event, Tag, TagEnd};

pub const BOLD: &str = "\x1b[1m";
pub const DIM: &str = "\x1b[2m";
pub const RED: &str = "\x1b[31m";
pub const GREEN: &str = "\x1b[32m";
pub const YELLOW: &str = "\x1b[33m";
pub const CYAN: &str = "\x1b[36m";
pub const RESET: &str = "\x1b[0m";

pub fn print_status(msg: &str) {
    eprint!("\r{}{}{}{}", DIM, msg, " ".repeat(10), RESET);
}

pub fn print_result(msg: &str) {
    println!("{}{}{}", GREEN, msg, RESET);
}

pub fn print_error(msg: &str) {
    println!("{}{}{}", RED, msg, RESET);
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

                println!("{}[{}]{} ", color, role.to_uppercase(), RESET);
                print_markdown(&content);
                println!("{}", "-".repeat(40));

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
