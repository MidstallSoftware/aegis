use std::fs;
use std::path::PathBuf;

use clap::Parser;

/// Aegis FPGA bitstream packer.
///
/// Reads a device descriptor JSON and a nextpnr placed/routed JSON,
/// packs cell parameters and routing into a binary bitstream matching
/// the config chain layout.
#[derive(Parser)]
#[command(name = "aegis-pack")]
struct Args {
    /// Path to the device descriptor JSON
    #[arg(short, long)]
    descriptor: PathBuf,

    /// Path to the nextpnr placed/routed JSON output
    #[arg(short, long)]
    pnr: PathBuf,

    /// Output bitstream file path
    #[arg(short, long, default_value = "bitstream.bin")]
    output: PathBuf,
}

fn main() {
    let args = Args::parse();

    let desc_json = fs::read_to_string(&args.descriptor)
        .unwrap_or_else(|e| panic!("Failed to read descriptor: {e}"));
    let desc: aegis_desc::AegisFpgaDeviceDescriptor = serde_json::from_str(&desc_json)
        .unwrap_or_else(|e| panic!("Failed to parse descriptor: {e}"));

    let pnr_json =
        fs::read_to_string(&args.pnr).unwrap_or_else(|e| panic!("Failed to read PnR output: {e}"));
    let pnr: aegis_pack::PnrOutput = serde_json::from_str(&pnr_json)
        .unwrap_or_else(|e| panic!("Failed to parse PnR output: {e}"));

    let total_bits = desc.config.total_bits as usize;
    eprintln!(
        "Packing {} for {} ({} config bits)",
        args.descriptor.display(),
        desc.device,
        total_bits
    );

    let bitstream = aegis_pack::pack(&desc, &pnr);

    fs::write(&args.output, &bitstream)
        .unwrap_or_else(|e| panic!("Failed to write bitstream: {e}"));

    eprintln!(
        "Wrote {} bytes to {}",
        bitstream.len(),
        args.output.display()
    );
}
