use std::process::Command;

fn main() {
    let output = Command::new("git")
        .args(&["describe", "--tags", "--always", "--dirty"])
        .output();

    let version = match output {
        Ok(o) if o.status.success() => {
            String::from_utf8(o.stdout).unwrap_or_else(|_| "X.Y.Z".to_string())
        }
        _ => "X.Y.Z".to_string(),
    };

    println!("cargo:rustc-env=GAIA_VERSION={}", version.trim());
}
