// Windows EXE Agent - No console window
#![cfg_attr(windows, windows_subsystem = "windows")]

mod agent;

fn main() {
    agent::run_agent();
}
