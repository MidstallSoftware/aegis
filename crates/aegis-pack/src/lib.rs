use aegis_desc::*;
use serde::Deserialize;
use serde_json::Value;
use std::collections::HashMap;

/// A placed cell from nextpnr's JSON output.
#[derive(Debug, Deserialize)]
pub struct PnrCell {
    #[serde(rename = "type")]
    pub cell_type: String,
    #[serde(default)]
    pub attributes: HashMap<String, String>,
    #[serde(default)]
    pub parameters: HashMap<String, String>,
    #[serde(default)]
    pub port_directions: HashMap<String, String>,
}

/// A net from nextpnr's JSON output.
#[derive(Debug, Deserialize)]
pub struct PnrNet {
    #[serde(default)]
    pub attributes: HashMap<String, Value>,
    #[serde(default)]
    pub bits: Vec<Value>,
}

/// Top-level nextpnr JSON output.
#[derive(Debug, Deserialize)]
pub struct PnrOutput {
    pub modules: HashMap<String, PnrModule>,
}

/// A module in the nextpnr output.
#[derive(Debug, Deserialize)]
pub struct PnrModule {
    #[serde(default)]
    pub cells: HashMap<String, PnrCell>,
    #[serde(default)]
    pub netnames: HashMap<String, PnrNet>,
}

/// Tile config bit layout constants.
///
/// These match the Dart tile implementation:
///   [17:0]  CLB config (16 LUT + 1 FF enable + 1 carry mode)
///   [20:18] sel0, [23:21] sel1, [26:24] sel2, [29:27] sel3
///   [30] enNorth, [31] enEast, [32] enSouth, [33] enWest
///   [36:34] selNorth, [39:37] selEast, [42:40] selSouth, [45:43] selWest
mod tile_bits {
    pub const LUT_INIT: usize = 0;
    pub const LUT_INIT_WIDTH: usize = 16;
    pub const FF_ENABLE: usize = 16;
    pub const CARRY_MODE: usize = 17;

    pub const SEL_BASE: usize = 18;
    pub const SEL_WIDTH: usize = 3;

    pub const EN_NORTH: usize = 30;
    pub const EN_EAST: usize = 31;
    pub const EN_SOUTH: usize = 32;
    pub const EN_WEST: usize = 33;

    pub const SEL_NORTH: usize = 34;
    pub const SEL_EAST: usize = 37;
    pub const SEL_SOUTH: usize = 40;
    pub const SEL_WEST: usize = 43;

    /// Input mux select values matching the Dart tile implementation.
    pub const MUX_NORTH: u64 = 0;
    pub const MUX_EAST: u64 = 1;
    pub const MUX_SOUTH: u64 = 2;
    pub const MUX_WEST: u64 = 3;
    pub const MUX_CLB_OUT: u64 = 4;
    pub const MUX_CONST0: u64 = 5;
    pub const MUX_CONST1: u64 = 6;
}

/// Pack a nextpnr-placed design into a bitstream.
///
/// Returns the raw bitstream bytes matching the config chain order:
/// clock tiles → IO tiles → SerDes tiles → fabric tiles (row-major).
pub fn pack(desc: &AegisFpgaDeviceDescriptor, pnr: &PnrOutput) -> Vec<u8> {
    let total_bits = desc.config.total_bits as usize;
    let mut bits = vec![0u8; (total_bits + 7) / 8];

    let module = pnr
        .modules
        .values()
        .next()
        .expect("No modules in PnR output");

    // Build tile lookup: (x, y) → config offset within the fabric section
    let tile_offsets: HashMap<(i64, i64), (usize, usize)> = desc
        .tiles
        .iter()
        .map(|t| {
            (
                (t.x, t.y),
                (t.config_offset as usize, t.config_width as usize),
            )
        })
        .collect();

    // Compute the bit offset where the fabric_tiles section starts
    let mut fabric_base = 0usize;
    for section in &desc.config.chain_order {
        if matches!(section.section, ChainSectionSection::FabricTiles) {
            break;
        }
        fabric_base += section.total_bits as usize;
    }

    // Pack cell configurations
    for (_name, cell) in &module.cells {
        let loc = cell_location(cell);
        match cell.cell_type.as_str() {
            "AEGIS_LUT4" => {
                if let Some((x, y)) = loc {
                    pack_lut4(&mut bits, cell, x, y, &tile_offsets, fabric_base);
                }
            }
            "AEGIS_DFF" => {
                if let Some((x, y)) = loc {
                    pack_dff(&mut bits, x, y, &tile_offsets, fabric_base);
                }
            }
            "AEGIS_CARRY" => {
                if let Some((x, y)) = loc {
                    pack_carry(&mut bits, x, y, &tile_offsets, fabric_base);
                }
            }
            "AEGIS_BRAM" => {
                if let Some((x, y)) = loc {
                    pack_bram(&mut bits, x, y, &tile_offsets, fabric_base);
                }
            }
            _ => {}
        }
    }

    // Pack routing from pip names
    pack_routing(&mut bits, pnr, &tile_offsets, fabric_base);

    bits
}

/// Extract BEL location (x, y) from cell attributes.
///
/// Looks for `"place"` or `"nextpnr_bel"` attributes with format `"X{x}/Y{y}/..."`.
fn cell_location(cell: &PnrCell) -> Option<(i64, i64)> {
    let bel = cell
        .attributes
        .get("place")
        .or_else(|| cell.attributes.get("nextpnr_bel"))?;
    parse_xy(bel)
}

/// Parse "X{x}/Y{y}/..." into (x, y).
fn parse_xy(s: &str) -> Option<(i64, i64)> {
    let parts: Vec<&str> = s.split('/').collect();
    if parts.len() < 2 {
        return None;
    }
    let x = parts[0].strip_prefix('X')?.parse().ok()?;
    let y = parts[1].strip_prefix('Y')?.parse().ok()?;
    Some((x, y))
}

/// Set a bit in the bitstream.
fn set_bit(bits: &mut [u8], offset: usize) {
    bits[offset / 8] |= 1 << (offset % 8);
}

/// Write a value into the bitstream at a given bit offset and width.
fn write_bits(bits: &mut [u8], offset: usize, value: u64, width: usize) {
    for i in 0..width {
        if value & (1 << i) != 0 {
            set_bit(bits, offset + i);
        }
    }
}

fn pack_lut4(
    bits: &mut [u8],
    cell: &PnrCell,
    x: i64,
    y: i64,
    tile_offsets: &HashMap<(i64, i64), (usize, usize)>,
    fabric_base: usize,
) {
    let Some(&(tile_offset, _)) = tile_offsets.get(&(x, y)) else {
        return;
    };

    let init = cell
        .parameters
        .get("INIT")
        .and_then(|v| parse_param(v, 16))
        .unwrap_or(0);

    write_bits(
        bits,
        fabric_base + tile_offset + tile_bits::LUT_INIT,
        init,
        tile_bits::LUT_INIT_WIDTH,
    );
}

fn pack_dff(
    bits: &mut [u8],
    x: i64,
    y: i64,
    tile_offsets: &HashMap<(i64, i64), (usize, usize)>,
    fabric_base: usize,
) {
    let Some(&(tile_offset, _)) = tile_offsets.get(&(x, y)) else {
        return;
    };
    set_bit(bits, fabric_base + tile_offset + tile_bits::FF_ENABLE);
}

fn pack_carry(
    bits: &mut [u8],
    x: i64,
    y: i64,
    tile_offsets: &HashMap<(i64, i64), (usize, usize)>,
    fabric_base: usize,
) {
    let Some(&(tile_offset, _)) = tile_offsets.get(&(x, y)) else {
        return;
    };
    set_bit(bits, fabric_base + tile_offset + tile_bits::CARRY_MODE);
}

fn pack_bram(
    bits: &mut [u8],
    x: i64,
    y: i64,
    tile_offsets: &HashMap<(i64, i64), (usize, usize)>,
    fabric_base: usize,
) {
    let Some(&(tile_offset, _)) = tile_offsets.get(&(x, y)) else {
        return;
    };
    set_bit(bits, fabric_base + tile_offset); // port A enable
    set_bit(bits, fabric_base + tile_offset + 1); // port B enable
}

/// Pack routing configuration by parsing pip names from routed nets.
///
/// Pip naming convention from the chipdb emitter:
///   CLB input mux:  `X{x}/Y{y}/MUX_I{i}_{src}` where src = N/E/S/W/FB/Q
///   Output route:   `X{x}/Y{y}/RT_{dir}{t}_{src}` where src = CLB/Q
///   Inter-tile:     `X{x}/Y{y}/{dir}{t}_{movement}` (no config bits needed)
///   Clock:          `X{x}/Y{y}/GLB_CLK` (no config bits needed)
fn pack_routing(
    bits: &mut [u8],
    pnr: &PnrOutput,
    tile_offsets: &HashMap<(i64, i64), (usize, usize)>,
    fabric_base: usize,
) {
    let module = match pnr.modules.values().next() {
        Some(m) => m,
        None => return,
    };

    // Collect all pip names from the routed nets.
    // nextpnr stores routing in the "route" attribute of netnames,
    // or we can scan cell attributes for routed pips.
    // The exact format depends on the nextpnr version, so we also
    // accept a flat list approach where pip names appear in net attributes.
    let mut pips: Vec<String> = Vec::new();

    for (_name, net) in &module.netnames {
        if let Some(route) = net.attributes.get("route") {
            collect_pips_from_route(route, &mut pips);
        }
    }

    // Process each pip
    for pip in &pips {
        pack_pip(bits, pip, tile_offsets, fabric_base);
    }
}

/// Extract pip names from a nextpnr route attribute.
///
/// The route attribute can be a string of space-separated pip names,
/// or a more complex structure. We extract anything that looks like
/// a pip name (X{n}/Y{n}/...).
fn collect_pips_from_route(route: &Value, pips: &mut Vec<String>) {
    match route {
        Value::String(s) => {
            for part in s.split_whitespace() {
                if part.starts_with('X') && part.contains('/') {
                    pips.push(part.to_string());
                }
            }
        }
        Value::Array(arr) => {
            for item in arr {
                collect_pips_from_route(item, pips);
            }
        }
        Value::Object(obj) => {
            for (_key, val) in obj {
                collect_pips_from_route(val, pips);
            }
        }
        _ => {}
    }
}

/// Pack a single pip's configuration into the bitstream.
fn pack_pip(
    bits: &mut [u8],
    pip: &str,
    tile_offsets: &HashMap<(i64, i64), (usize, usize)>,
    fabric_base: usize,
) {
    let Some((x, y)) = parse_xy(pip) else {
        return;
    };
    let Some(&(tile_offset, _)) = tile_offsets.get(&(x, y)) else {
        return;
    };

    let base = fabric_base + tile_offset;

    // Extract the pip type from the name (after X{x}/Y{y}/)
    let pip_suffix = match pip.splitn(3, '/').nth(2) {
        Some(s) => s,
        None => return,
    };

    // CLB input mux: MUX_I{i}_{source}
    if let Some(rest) = pip_suffix.strip_prefix("MUX_I") {
        if let Some((idx_str, source)) = rest.split_once('_') {
            if let Ok(idx) = idx_str.parse::<usize>() {
                if idx < 4 {
                    let sel_offset = base + tile_bits::SEL_BASE + idx * tile_bits::SEL_WIDTH;
                    let sel_val = match source {
                        "N" => tile_bits::MUX_NORTH,
                        "E" => tile_bits::MUX_EAST,
                        "S" => tile_bits::MUX_SOUTH,
                        "W" => tile_bits::MUX_WEST,
                        "FB" | "Q" => tile_bits::MUX_CLB_OUT,
                        _ => return,
                    };
                    write_bits(bits, sel_offset, sel_val, tile_bits::SEL_WIDTH);
                }
            }
        }
        return;
    }

    // Output route mux: RT_{dir}{track}_{source}
    if let Some(rest) = pip_suffix.strip_prefix("RT_") {
        // Parse direction (first char) and source (after last _)
        let dir = &rest[..1];
        if let Some((_track_and_more, source)) = rest[1..].rsplit_once('_') {
            // Enable the output direction
            let en_bit = match dir {
                "N" => tile_bits::EN_NORTH,
                "E" => tile_bits::EN_EAST,
                "S" => tile_bits::EN_SOUTH,
                "W" => tile_bits::EN_WEST,
                _ => return,
            };
            set_bit(bits, base + en_bit);

            // Set the route source select
            let sel_offset = match dir {
                "N" => tile_bits::SEL_NORTH,
                "E" => tile_bits::SEL_EAST,
                "S" => tile_bits::SEL_SOUTH,
                "W" => tile_bits::SEL_WEST,
                _ => return,
            };
            let sel_val = match source {
                "CLB" | "Q" => tile_bits::MUX_CLB_OUT,
                _ => return,
            };
            write_bits(bits, base + sel_offset, sel_val, tile_bits::SEL_WIDTH);
        }
        return;
    }

    // Inter-tile pips and clock pips don't need config bits
}

/// Parse a nextpnr parameter value.
///
/// Handles formats like "16'b0000000000000000", "16'h1234", or plain integers.
fn parse_param(value: &str, width: usize) -> Option<u64> {
    if let Some(rest) = value.strip_prefix(&format!("{width}'b")) {
        u64::from_str_radix(rest, 2).ok()
    } else if let Some(rest) = value.strip_prefix(&format!("{width}'h")) {
        u64::from_str_radix(rest, 16).ok()
    } else {
        value.parse().ok()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_binary_param() {
        assert_eq!(parse_param("16'b1010101010101010", 16), Some(0xAAAA));
    }

    #[test]
    fn parse_hex_param() {
        assert_eq!(parse_param("16'hDEAD", 16), Some(0xDEAD));
    }

    #[test]
    fn parse_integer_param() {
        assert_eq!(parse_param("42", 16), Some(42));
    }

    #[test]
    fn write_bits_at_offset_zero() {
        let mut bits = vec![0u8; 4];
        write_bits(&mut bits, 0, 0xABCD, 16);
        assert_eq!(bits[0], 0xCD);
        assert_eq!(bits[1], 0xAB);
    }

    #[test]
    fn write_bits_at_offset() {
        let mut bits = vec![0u8; 4];
        write_bits(&mut bits, 8, 0xFF, 8);
        assert_eq!(bits[0], 0x00);
        assert_eq!(bits[1], 0xFF);
    }

    #[test]
    fn set_individual_bit() {
        let mut bits = vec![0u8; 2];
        set_bit(&mut bits, 0);
        set_bit(&mut bits, 7);
        set_bit(&mut bits, 8);
        assert_eq!(bits[0], 0x81);
        assert_eq!(bits[1], 0x01);
    }

    /// Build a minimal descriptor for testing.
    fn test_descriptor() -> AegisFpgaDeviceDescriptor {
        serde_json::from_str(
            r#"{
            "device": "test",
            "fabric": {
                "width": 2, "height": 2, "tracks": 1,
                "tile_config_width": 46,
                "bram": { "column_interval": 0, "columns": [],
                          "data_width": null, "addr_width": null,
                          "depth": null, "tile_config_width": 8 },
                "dsp": { "column_interval": 0, "columns": [],
                         "a_width": null, "b_width": null,
                         "result_width": null, "tile_config_width": 16 },
                "carry_chain": { "direction": "south_to_north", "per_column": true }
            },
            "io": { "total_pads": 8, "tile_config_width": 8, "pads": [] },
            "serdes": { "count": 0, "tile_config_width": 32, "edge_assignment": [] },
            "clock": { "tile_count": 0, "tile_config_width": 49,
                       "outputs_per_tile": 4, "total_outputs": 0 },
            "config": {
                "total_bits": 248,
                "chain_order": [
                    { "section": "io_tiles", "count": 8,
                      "bits_per_tile": 8, "total_bits": 64 },
                    { "section": "fabric_tiles", "count": 4,
                      "total_bits": 184 }
                ]
            },
            "tiles": [
                { "x": 0, "y": 0, "type": "lut", "config_width": 46, "config_offset": 0 },
                { "x": 1, "y": 0, "type": "lut", "config_width": 46, "config_offset": 46 },
                { "x": 0, "y": 1, "type": "lut", "config_width": 46, "config_offset": 92 },
                { "x": 1, "y": 1, "type": "lut", "config_width": 46, "config_offset": 138 }
            ]
        }"#,
        )
        .unwrap()
    }

    fn test_pnr_with_lut(x: i64, y: i64, init: &str) -> PnrOutput {
        let mut cells = HashMap::new();
        let mut attrs = HashMap::new();
        attrs.insert("place".to_string(), format!("X{x}/Y{y}/LUT4"));
        let mut params = HashMap::new();
        params.insert("INIT".to_string(), init.to_string());
        cells.insert(
            "lut0".to_string(),
            PnrCell {
                cell_type: "AEGIS_LUT4".to_string(),
                attributes: attrs,
                parameters: params,
                port_directions: HashMap::new(),
            },
        );
        let mut modules = HashMap::new();
        modules.insert(
            "top".to_string(),
            PnrModule {
                cells,
                netnames: HashMap::new(),
            },
        );
        PnrOutput { modules }
    }

    fn test_pnr_with_routing(pips: &[&str]) -> PnrOutput {
        let mut netnames = HashMap::new();
        let route_str = pips.join(" ");
        let mut attrs = HashMap::new();
        attrs.insert("route".to_string(), Value::String(route_str));
        netnames.insert(
            "net0".to_string(),
            PnrNet {
                attributes: attrs,
                bits: vec![],
            },
        );
        let mut modules = HashMap::new();
        modules.insert(
            "top".to_string(),
            PnrModule {
                cells: HashMap::new(),
                netnames,
            },
        );
        PnrOutput { modules }
    }

    fn read_bits(bits: &[u8], offset: usize, width: usize) -> u64 {
        let mut val = 0u64;
        for i in 0..width {
            if bits[(offset + i) / 8] & (1 << ((offset + i) % 8)) != 0 {
                val |= 1 << i;
            }
        }
        val
    }

    #[test]
    fn pack_lut4_at_origin() {
        let desc = test_descriptor();
        let pnr = test_pnr_with_lut(0, 0, "16'hAAAA");
        let bits = pack(&desc, &pnr);

        let init = read_bits(&bits, 64, 16); // fabric_base=64, tile_offset=0
        assert_eq!(init, 0xAAAA);
    }

    #[test]
    fn pack_lut4_at_offset_tile() {
        let desc = test_descriptor();
        let pnr = test_pnr_with_lut(1, 0, "16'h1234");
        let bits = pack(&desc, &pnr);

        let init = read_bits(&bits, 64 + 46, 16); // tile (1,0) offset=46
        assert_eq!(init, 0x1234);
    }

    #[test]
    fn pack_dff_sets_ff_enable() {
        let desc = test_descriptor();
        let mut cells = HashMap::new();
        let mut attrs = HashMap::new();
        attrs.insert("place".to_string(), "X0/Y0/DFF".to_string());
        cells.insert(
            "dff0".to_string(),
            PnrCell {
                cell_type: "AEGIS_DFF".to_string(),
                attributes: attrs,
                parameters: HashMap::new(),
                port_directions: HashMap::new(),
            },
        );
        let mut modules = HashMap::new();
        modules.insert(
            "top".to_string(),
            PnrModule {
                cells,
                netnames: HashMap::new(),
            },
        );
        let bits = pack(&desc, &PnrOutput { modules });

        assert_ne!(read_bits(&bits, 64 + tile_bits::FF_ENABLE, 1), 0);
    }

    #[test]
    fn pack_carry_sets_carry_mode() {
        let desc = test_descriptor();
        let mut cells = HashMap::new();
        let mut attrs = HashMap::new();
        attrs.insert("place".to_string(), "X1/Y1/CARRY".to_string());
        cells.insert(
            "carry0".to_string(),
            PnrCell {
                cell_type: "AEGIS_CARRY".to_string(),
                attributes: attrs,
                parameters: HashMap::new(),
                port_directions: HashMap::new(),
            },
        );
        let mut modules = HashMap::new();
        modules.insert(
            "top".to_string(),
            PnrModule {
                cells,
                netnames: HashMap::new(),
            },
        );
        let bits = pack(&desc, &PnrOutput { modules });

        // tile (1,1) offset=138
        assert_ne!(read_bits(&bits, 64 + 138 + tile_bits::CARRY_MODE, 1), 0);
    }

    #[test]
    fn pack_routing_input_mux_north() {
        let desc = test_descriptor();
        let pnr = test_pnr_with_routing(&["X0/Y0/MUX_I0_N"]);
        let bits = pack(&desc, &pnr);

        // sel0 is at bits [20:18] of tile config
        let sel = read_bits(&bits, 64 + tile_bits::SEL_BASE, tile_bits::SEL_WIDTH);
        assert_eq!(sel, tile_bits::MUX_NORTH);
    }

    #[test]
    fn pack_routing_input_mux_east() {
        let desc = test_descriptor();
        let pnr = test_pnr_with_routing(&["X1/Y0/MUX_I2_E"]);
        let bits = pack(&desc, &pnr);

        // sel2 at tile (1,0): offset 46, sel2 starts at 18 + 2*3 = 24
        let sel = read_bits(
            &bits,
            64 + 46 + tile_bits::SEL_BASE + 2 * tile_bits::SEL_WIDTH,
            tile_bits::SEL_WIDTH,
        );
        assert_eq!(sel, tile_bits::MUX_EAST);
    }

    #[test]
    fn pack_routing_input_mux_feedback() {
        let desc = test_descriptor();
        let pnr = test_pnr_with_routing(&["X0/Y0/MUX_I1_FB"]);
        let bits = pack(&desc, &pnr);

        let sel = read_bits(
            &bits,
            64 + tile_bits::SEL_BASE + 1 * tile_bits::SEL_WIDTH,
            tile_bits::SEL_WIDTH,
        );
        assert_eq!(sel, tile_bits::MUX_CLB_OUT);
    }

    #[test]
    fn pack_routing_output_north() {
        let desc = test_descriptor();
        let pnr = test_pnr_with_routing(&["X0/Y0/RT_N0_CLB"]);
        let bits = pack(&desc, &pnr);

        // enNorth should be set
        assert_ne!(read_bits(&bits, 64 + tile_bits::EN_NORTH, 1), 0);
        // selNorth should be MUX_CLB_OUT
        let sel = read_bits(&bits, 64 + tile_bits::SEL_NORTH, tile_bits::SEL_WIDTH);
        assert_eq!(sel, tile_bits::MUX_CLB_OUT);
    }

    #[test]
    fn pack_routing_output_west() {
        let desc = test_descriptor();
        let pnr = test_pnr_with_routing(&["X1/Y1/RT_W0_Q"]);
        let bits = pack(&desc, &pnr);

        // tile (1,1) offset=138
        assert_ne!(read_bits(&bits, 64 + 138 + tile_bits::EN_WEST, 1), 0);
        let sel = read_bits(&bits, 64 + 138 + tile_bits::SEL_WEST, tile_bits::SEL_WIDTH);
        assert_eq!(sel, tile_bits::MUX_CLB_OUT);
    }

    #[test]
    fn pack_multiple_pips_same_tile() {
        let desc = test_descriptor();
        let pnr = test_pnr_with_routing(&["X0/Y0/MUX_I0_N", "X0/Y0/MUX_I1_E", "X0/Y0/RT_S0_CLB"]);
        let bits = pack(&desc, &pnr);

        let sel0 = read_bits(&bits, 64 + tile_bits::SEL_BASE, tile_bits::SEL_WIDTH);
        let sel1 = read_bits(
            &bits,
            64 + tile_bits::SEL_BASE + tile_bits::SEL_WIDTH,
            tile_bits::SEL_WIDTH,
        );
        assert_eq!(sel0, tile_bits::MUX_NORTH);
        assert_eq!(sel1, tile_bits::MUX_EAST);
        assert_ne!(read_bits(&bits, 64 + tile_bits::EN_SOUTH, 1), 0);
    }

    #[test]
    fn pack_bitstream_length_matches_descriptor() {
        let desc = test_descriptor();
        let pnr = test_pnr_with_lut(0, 0, "0");
        let bits = pack(&desc, &pnr);
        assert_eq!(bits.len(), (desc.config.total_bits as usize + 7) / 8);
    }

    #[test]
    fn empty_design_produces_zero_bitstream() {
        let desc = test_descriptor();
        let pnr: PnrOutput =
            serde_json::from_str(r#"{"modules":{"top":{"cells":{},"netnames":{}}}}"#).unwrap();
        let bits = pack(&desc, &pnr);
        assert!(bits.iter().all(|&b| b == 0));
    }

    #[test]
    fn inter_tile_pips_dont_set_bits() {
        let desc = test_descriptor();
        let pnr = test_pnr_with_routing(&["X0/Y0/NORTH0_UP", "X0/Y0/GLB_CLK"]);
        let bits = pack(&desc, &pnr);
        // These pips are physical connections, no config bits
        assert!(bits.iter().all(|&b| b == 0));
    }
}
