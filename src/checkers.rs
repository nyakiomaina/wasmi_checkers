use std::error::Error;
use std::fs::File;
use std::io::prelude::*;
use wasmi::{
    ExternVal, ImportsBuilder, Module, ModuleImportResolver, ModuleInstance, ModuleRef,
    RuntimeValue,
};

use super::imports::RuntimeModuleImportResolver;
use super::runtime::Runtime;

//use checkerboard::Checkerboard;
use crate::checkerboard::Checkerboard;

pub struct CheckersGame {
    runtime: Runtime,
    module_instance: ModuleRef,
}

#[derive(Debug)]
pub enum PieceColor {
    Red,
    Black,
}

type Result<T> = ::std::result::Result<T, Box<dyn Error>>;
type Coordinate = (i32, i32);

fn load_instance(
    import_resolver: &impl ModuleImportResolver,
    module_file: &str,
) -> Result<ModuleRef> {
    let mut buffer = Vec::new();
    let mut f = File::open(module_file)?;
    f.read_to_end(&mut buffer)?;
    let module = Module::from_buffer(buffer)?;
    let mut builder = ImportsBuilder::new();
    builder.push_resolver("events", import_resolver);

    Ok(ModuleInstance::new(&module, &builder)
        .expect("WASM module failed instantiation")
        .assert_no_start())
}

impl CheckersGame {
    pub fn new(module_file: &str) -> CheckersGame {
        let resolver = RuntimeModuleImportResolver::new();
        let instance = load_instance(&resolver, module_file).unwrap();
        let runtime = Runtime::new();

        CheckersGame {
            module_instance: instance,
            runtime,
        }
    }

    pub fn init(&mut self) -> Result<()> {
        self.module_instance
            .invoke_export("initBoard", &[], &mut self.runtime)?;
        Ok(())
    }

    pub fn move_piece(&mut self, from: &Coordinate, to: &Coordinate) -> Result<bool> {
        let res = self.module_instance.invoke_export(
            "move",
            &[
                RuntimeValue::from(from.0),
                RuntimeValue::from(from.1),
                RuntimeValue::from(to.0),
                RuntimeValue::from(to.1),
            ],
            &mut self.runtime,
        )?;

        match res {
            Some(RuntimeValue::I32(v)) => Ok(v != 0),
            _ => {
                println!("Invalid response for move");
                Ok(false)
            }
        }
    }

    pub fn get_turn_owner(&mut self) -> Result<PieceColor> {
        let res = self
            .module_instance
            .invoke_export("getTurnOwner", &[], &mut self.runtime)?;
        match res {
            Some(RuntimeValue::I32(v)) => {
                if v == 1 {
                    Ok(PieceColor::Black)
                } else {
                    Ok(PieceColor::Red)
                }
            }
            _ => Err(From::from("Bad invocation")),
        }
    }

    pub fn get_board_contents(&mut self) -> Result<String> {
        let export = self.module_instance.export_by_name("memory");
        let header = r#"
    0   1   2   3   4   5   6   7
  ,...,...,...,...,...,...,...,...,"#;
        let footer = "  `---^---^---^---^---^---^---^---^";
        let middle_string = match export {
            Some(ExternVal::Memory(mr)) => Checkerboard::gen_board(&mr),
            _ => " -- no board data found -- ".to_string(),
        };
        Ok(format!("{}\n{}{}\n", header, middle_string, footer))
    }
}