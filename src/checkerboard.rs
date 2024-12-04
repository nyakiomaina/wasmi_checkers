use wasmi::MemoryRef;

pub struct Checkerboard {}

impl Checkerboard {
    fn to_u32(bytes: &[u8]) -> u32 {
        bytes.iter().rev().fold(0, |acc, &b| acc * 2 + b as u32)
    }

    fn calc_offset(x: usize, y: usize) -> u32 {
        ((x + y * 8) * 4) as u32
    }
    fn value_label(v: u32) -> String {
        match v {
            0 => "   ",
            1 => " B ",
            2 => " R ",
            5 => " B*",
            6 => " R*",
            _ => "???",
        }
            .into()
    }

    pub fn gen_board(memory: &MemoryRef) -> String {
        let mut vals = Vec::<String>::new();

        for y in 0..8 {
            vals.push(format!("{} ", y));
            for x in 0..8 {
                let offset = Checkerboard::calc_offset(x, y);
                let bytevec: Vec<u8> = memory.get(offset, 4).unwrap();
                let value = Checkerboard::to_u32(&bytevec[..]);

                vals.push(format!("|{}", Checkerboard::value_label(value)));
            }
            vals.push("|\n".into());
        }
        vals.join("")
    }
}