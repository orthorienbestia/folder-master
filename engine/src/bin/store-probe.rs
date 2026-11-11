//! Non-shipping CLI fixture for actual inter-process ownership tests.
use folder_master_engine::storage::Store;
use std::{
    io::{self, Write},
    path::PathBuf,
};
fn main() {
    let args: Vec<_> = std::env::args_os().collect();
    if args.len() != 3 {
        std::process::exit(2);
    }
    match Store::open(&PathBuf::from(&args[2])) {
        Ok(_store) => {
            println!("owned");
            io::stdout().flush().unwrap();
            if args[1] == "hold" {
                let mut line = String::new();
                let _ = io::stdin().read_line(&mut line);
            }
        }
        Err(error) => {
            println!("error:{}", error.code);
            std::process::exit(1);
        }
    }
}
