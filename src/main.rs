extern crate wasmi;

mod checkerboard;
mod checkers;
mod imports;
mod runtime;

use checkers::CheckersGame;
use std::error::Error;
use std::thread;
use std::time;

fn main() -> Result<(), Box<dyn Error>> {
    let mut game = CheckersGame::new("src/wat/checkers.wasm");
    game.init()?;

    let board_display = game.get_board_contents()?;
    println!("game board at start:\n{}\n", board_display);

    println!(
        "At game start, current turn is: {:?}",
        game.get_turn_owner()?
    );
    game.move_piece(&(0, 5), &(0, 4))?;
    println!(
        "After first move, current turn is {:?}",
        game.get_turn_owner()?
    );

    thread::sleep(time::Duration::from_millis(1500));

    let board_display = game.get_board_contents()?;
    println!("game board after 1 move:\n{}\n", board_display);

    Ok(())
}