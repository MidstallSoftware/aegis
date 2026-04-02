/*
 *  Aegis FPGA viaduct micro-architecture for nextpnr-generic.
 *
 *  Models the actual Aegis routing architecture: directional routing
 *  tracks (N/E/S/W) with configurable input and output muxes per tile.
 *  Matches the Dart tile.dart implementation for bitstream compatibility.
 *
 *  Uses -o device=WxHtT to configure dimensions.
 */

#include <array>
#include <fstream>
#include <sstream>

#include "log.h"
#include "nextpnr.h"
#include "util.h"
#include "viaduct_api.h"
#include "viaduct_helpers.h"

NEXTPNR_NAMESPACE_BEGIN

namespace {

struct AegisImpl : ViaductAPI {
  ~AegisImpl() {};

  int W = 4, H = 4;
  int T = 1;
  int K = 4;

  // Cached IdStrings
  IdString id_LUT4, id_DFF, id_IOB, id_INBUF, id_OUTBUF;
  IdString id_CLK, id_D, id_Q, id_F, id_I, id_O, id_PAD, id_EN;
  IdString id_INIT, id_PIP, id_LOCAL;

  dict<std::string, std::string> device_args;

  // Per-tile wire storage
  struct TileWires {
    WireId clk;
    std::vector<WireId> lut_in; // K inputs
    WireId lut_out;             // F
    WireId ff_d, ff_q;          // DFF wires
    WireId carry_in, carry_out;
    std::vector<WireId> track_n, track_e, track_s, track_w; // T tracks per dir
    // Per-track output mux wires — one per track per direction
    std::vector<WireId> out_n, out_e, out_s, out_w;
    // IO wires (only for IO tiles)
    std::vector<WireId> pad;
    std::vector<WireId> io_in, io_out;
  };
  std::vector<std::vector<TileWires>> tile_wires;

  void init(Context *ctx) override {
    ViaductAPI::init(ctx);
    h.init(ctx);

    id_LUT4 = ctx->id("LUT4");
    id_DFF = ctx->id("DFF");
    id_IOB = ctx->id("IOB");
    id_INBUF = ctx->id("INBUF");
    id_OUTBUF = ctx->id("OUTBUF");
    id_CLK = ctx->id("CLK");
    id_D = ctx->id("D");
    id_Q = ctx->id("Q");
    id_F = ctx->id("F");
    id_I = ctx->id("I");
    id_O = ctx->id("O");
    id_PAD = ctx->id("PAD");
    id_EN = ctx->id("EN");
    id_INIT = ctx->id("INIT");
    id_PIP = ctx->id("PIP");

    if (device_args.count("device")) {
      std::string val = device_args.at("device");
      if (val.find('x') != std::string::npos) {
        sscanf(val.c_str(), "%dx%d", &W, &H);
        if (val.find('t') != std::string::npos)
          sscanf(strstr(val.c_str(), "t") + 1, "%d", &T);
      }
    }

    // Grid includes IO ring
    W += 2;
    H += 2;

    log_info("Aegis FPGA: %dx%d grid (%dx%d fabric), %d tracks\n", W, H, W - 2,
             H - 2, T);

    init_wires();
    init_bels();
    init_pips();
  }

  void pack() override {
    IdString id_lut = ctx->id("$lut");
    IdString id_dff_p = ctx->id("$_DFF_P_");
    IdString id_Y = ctx->id("Y");

    // Replace constants with proper $lut cells
    const dict<IdString, Property> vcc_params = {
        {ctx->id("LUT"), Property(0xFFFF, 16)},
        {ctx->id("WIDTH"), Property(4, 32)}};
    const dict<IdString, Property> gnd_params = {
        {ctx->id("LUT"), Property(0x0000, 16)},
        {ctx->id("WIDTH"), Property(4, 32)}};
    h.replace_constants(CellTypePort(id_lut, id_Y), CellTypePort(id_lut, id_Y),
                        vcc_params, gnd_params);

    // Constrain LUT+FF pairs
    int lutffs =
        h.constrain_cell_pairs(pool<CellTypePort>{{id_lut, id_Y}},
                               pool<CellTypePort>{{id_dff_p, id_D}}, 1);
    log_info("Constrained %d LUTFF pairs.\n", lutffs);
  }

  void prePlace() override {
    assign_cell_info();

    // Apply PCF constraints if provided via -o pcf=<file>
    if (device_args.count("pcf")) {
      std::string pcf_path = device_args.at("pcf");
      std::ifstream pcf(pcf_path);
      if (!pcf.is_open()) {
        log_error("Cannot open PCF file: %s\n", pcf_path.c_str());
      }
      log_info("Reading PCF constraints from %s\n", pcf_path.c_str());
      std::string line;
      int count = 0;
      while (std::getline(pcf, line)) {
        // Strip comments and whitespace
        auto comment_pos = line.find('#');
        if (comment_pos != std::string::npos)
          line = line.substr(0, comment_pos);
        std::istringstream iss(line);
        std::string cmd, signal, bel;
        if (!(iss >> cmd >> signal >> bel))
          continue;
        if (cmd != "set_io")
          continue;

        // Find cell by name and constrain to BEL
        IdString sig_id = ctx->id(signal);
        bool found = false;
        for (auto &cell : ctx->cells) {
          if (cell.first == sig_id) {
            BelId target = ctx->getBelByName(IdStringList::parse(ctx, bel));
            if (target != BelId()) {
              cell.second->attrs[ctx->id("BEL")] = bel;
              log_info("  Constrained '%s' to BEL '%s'\n", signal.c_str(),
                       bel.c_str());
              count++;
            } else {
              log_warning("  BEL '%s' not found for signal '%s'\n", bel.c_str(),
                          signal.c_str());
            }
            found = true;
            break;
          }
        }
        if (!found)
          log_warning("  Signal '%s' not found in design\n", signal.c_str());
      }
      log_info("Applied %d PCF constraints.\n", count);
    }
  }

  bool isBelLocationValid(BelId bel, bool explain_invalid) const override {
    Loc l = ctx->getBelLocation(bel);
    if (is_io(l.x, l.y))
      return true;
    return slice_valid(l.x, l.y, l.z / 2);
  }

private:
  ViaductHelpers h;

  bool is_io(int x, int y) const {
    return (x == 0) || (x == (W - 1)) || (y == 0) || (y == (H - 1));
  }

  PipId add_pip(Loc loc, WireId src, WireId dst, delay_t delay = 0.05) {
    IdStringList name =
        IdStringList::concat(ctx->getWireName(dst), ctx->getWireName(src));
    return ctx->addPip(name, id_PIP, src, dst, delay, loc);
  }

  void init_wires() {
    log_info("Creating wires...\n");
    tile_wires.resize(H);
    for (int y = 0; y < H; y++) {
      tile_wires[y].resize(W);
      for (int x = 0; x < W; x++) {
        auto &tw = tile_wires[y][x];

        if (!is_io(x, y)) {
          // Logic tile wires
          tw.clk = ctx->addWire(h.xy_id(x, y, ctx->id("CLK")), id_CLK, x, y);
          tw.lut_out = ctx->addWire(h.xy_id(x, y, ctx->id("CLB_O")),
                                    ctx->id("CLB_OUTPUT"), x, y);
          tw.ff_d = ctx->addWire(h.xy_id(x, y, ctx->id("FF_D")), id_D, x, y);
          tw.ff_q = ctx->addWire(h.xy_id(x, y, ctx->id("CLB_Q")), id_Q, x, y);
          tw.carry_in = ctx->addWire(h.xy_id(x, y, ctx->id("CARRY_IN")),
                                     ctx->id("CARRY"), x, y);
          tw.carry_out = ctx->addWire(h.xy_id(x, y, ctx->id("CARRY_OUT")),
                                      ctx->id("CARRY"), x, y);

          // Per-track output mux wires — each track has its own independent mux
          for (int t = 0; t < T; t++) {
            tw.out_n.push_back(
                ctx->addWire(h.xy_id(x, y, ctx->idf("OUT_N%d", t)),
                             ctx->id("OUTPUT_MUX"), x, y));
            tw.out_e.push_back(
                ctx->addWire(h.xy_id(x, y, ctx->idf("OUT_E%d", t)),
                             ctx->id("OUTPUT_MUX"), x, y));
            tw.out_s.push_back(
                ctx->addWire(h.xy_id(x, y, ctx->idf("OUT_S%d", t)),
                             ctx->id("OUTPUT_MUX"), x, y));
            tw.out_w.push_back(
                ctx->addWire(h.xy_id(x, y, ctx->idf("OUT_W%d", t)),
                             ctx->id("OUTPUT_MUX"), x, y));
          }

          for (int k = 0; k < K; k++)
            tw.lut_in.push_back(
                ctx->addWire(h.xy_id(x, y, ctx->idf("CLB_I%d", k)),
                             ctx->id("CLB_INPUT"), x, y));

          // Directional routing tracks
          for (int t = 0; t < T; t++) {
            tw.track_n.push_back(ctx->addWire(h.xy_id(x, y, ctx->idf("N%d", t)),
                                              ctx->id("ROUTING"), x, y));
            tw.track_e.push_back(ctx->addWire(h.xy_id(x, y, ctx->idf("E%d", t)),
                                              ctx->id("ROUTING"), x, y));
            tw.track_s.push_back(ctx->addWire(h.xy_id(x, y, ctx->idf("S%d", t)),
                                              ctx->id("ROUTING"), x, y));
            tw.track_w.push_back(ctx->addWire(h.xy_id(x, y, ctx->idf("W%d", t)),
                                              ctx->id("ROUTING"), x, y));
          }
        } else if (x != y) {
          // IO tile wires
          for (int z = 0; z < 2; z++) {
            tw.pad.push_back(ctx->addWire(h.xy_id(x, y, ctx->idf("PAD%d", z)),
                                          id_PAD, x, y));
            tw.io_in.push_back(
                ctx->addWire(h.xy_id(x, y, ctx->idf("IO_I%d", z)), id_I, x, y));
            tw.io_out.push_back(
                ctx->addWire(h.xy_id(x, y, ctx->idf("IO_O%d", z)), id_O, x, y));
          }
          // IO tiles also have routing tracks for fabric connection
          for (int t = 0; t < T; t++) {
            tw.track_n.push_back(ctx->addWire(h.xy_id(x, y, ctx->idf("N%d", t)),
                                              ctx->id("ROUTING"), x, y));
            tw.track_e.push_back(ctx->addWire(h.xy_id(x, y, ctx->idf("E%d", t)),
                                              ctx->id("ROUTING"), x, y));
            tw.track_s.push_back(ctx->addWire(h.xy_id(x, y, ctx->idf("S%d", t)),
                                              ctx->id("ROUTING"), x, y));
            tw.track_w.push_back(ctx->addWire(h.xy_id(x, y, ctx->idf("W%d", t)),
                                              ctx->id("ROUTING"), x, y));
          }
        }
      }
    }
  }

  void init_bels() {
    log_info("Creating bels...\n");
    for (int y = 0; y < H; y++) {
      for (int x = 0; x < W; x++) {
        if (is_io(x, y)) {
          if (x == y)
            continue;
          add_io_bels(x, y);
        } else {
          add_logic_bels(x, y);
        }
      }
    }
  }

  void add_io_bels(int x, int y) {
    auto &tw = tile_wires[y][x];
    for (int z = 0; z < 2; z++) {
      BelId b = ctx->addBel(h.xy_id(x, y, ctx->idf("IO%d", z)), id_IOB,
                            Loc(x, y, z), false, false);
      ctx->addBelInout(b, id_PAD, tw.pad[z]);
      ctx->addBelInput(b, id_I, tw.io_in[z]);
      ctx->addBelInput(b, ctx->id("A"), tw.io_in[z]); // $nextpnr_obuf alias
      ctx->addBelInput(b, id_EN,
                       tw.io_in[std::min(z * 2 + 1, (int)tw.io_in.size() - 1)]);
      ctx->addBelOutput(b, id_O, tw.io_out[z]);
    }
  }

  void add_logic_bels(int x, int y) {
    auto &tw = tile_wires[y][x];

    // LUT4 BEL — pins match $lut cell ports: A[0]-A[3], Y
    BelId lut = ctx->addBel(h.xy_id(x, y, ctx->id("SLICE0_LUT")), id_LUT4,
                            Loc(x, y, 0), false, false);
    for (int k = 0; k < K; k++)
      ctx->addBelInput(lut, ctx->idf("A[%d]", k), tw.lut_in[k]);
    ctx->addBelInput(lut, ctx->id("A"), tw.lut_in[0]); // constant LUT alias
    ctx->addBelOutput(lut, ctx->id("Y"), tw.lut_out);

    // LUT output -> FF D pip
    add_pip(Loc(x, y, 0), tw.lut_out, tw.ff_d);

    // DFF BEL — pins match $_DFF_P_ cell ports: C, D, Q
    BelId dff = ctx->addBel(h.xy_id(x, y, ctx->id("SLICE0_FF")), id_DFF,
                            Loc(x, y, 1), false, false);
    ctx->addBelInput(dff, ctx->id("C"), tw.clk);
    ctx->addBelInput(dff, id_D, tw.ff_d);
    ctx->addBelOutput(dff, id_Q, tw.ff_q);
  }

  void init_pips() {
    log_info("Creating pips...\n");
    for (int y = 0; y < H; y++) {
      for (int x = 0; x < W; x++) {
        if (is_io(x, y)) {
          if (x != y)
            add_io_pips(x, y);
        } else {
          add_logic_pips(x, y);
        }
        add_inter_tile_pips(x, y);
      }
    }
  }

  void add_logic_pips(int x, int y) {
    auto &tw = tile_wires[y][x];
    Loc loc(x, y, 0);

    // CLB input muxes: each input reads from track 0 of each direction
    // Hardware sel values: 0=N0, 1=E0, 2=S0, 3=W0, 4=CLB_OUT
    for (int i = 0; i < K; i++) {
      WireId dst = tw.lut_in[i];
      for (int t = 0; t < T; t++) {
        add_pip(loc, tw.track_n[t], dst, 0.05);
        add_pip(loc, tw.track_e[t], dst, 0.05);
        add_pip(loc, tw.track_s[t], dst, 0.05);
        add_pip(loc, tw.track_w[t], dst, 0.05);
      }
      add_pip(loc, tw.lut_out, dst, 0.05); // feedback
      add_pip(loc, tw.ff_q, dst, 0.05);    // FF output
    }

    // Clock: any track from any direction can drive clock
    for (int t = 0; t < T; t++) {
      add_pip(loc, tw.track_n[t], tw.clk, 0.05);
      add_pip(loc, tw.track_e[t], tw.clk, 0.05);
      add_pip(loc, tw.track_s[t], tw.clk, 0.05);
      add_pip(loc, tw.track_w[t], tw.clk, 0.05);
    }

    // Per-track output routing. Each track in each direction has its own
    // independent output mux, selecting from CLB_O, CLB_Q, or the same
    // track index from any other direction (pass-through).
    std::array<std::vector<WireId> *, 4> out_vecs = {&tw.out_n, &tw.out_e,
                                                     &tw.out_s, &tw.out_w};
    std::array<std::vector<WireId> *, 4> trk_vecs = {&tw.track_n, &tw.track_e,
                                                     &tw.track_s, &tw.track_w};
    for (int d = 0; d < 4; d++) {
      for (int t = 0; t < T; t++) {
        WireId out_wire = (*out_vecs[d])[t];
        // CLB sources
        add_pip(loc, tw.lut_out, out_wire, 0.05);
        add_pip(loc, tw.ff_q, out_wire, 0.05);
        // Pass-through from same track of other directions
        for (int s = 0; s < 4; s++) {
          if (s != d)
            add_pip(loc, (*trk_vecs[s])[t], out_wire, 0.05);
        }
        // Output mux wire → track (1:1, not configurable)
        add_pip(loc, out_wire, (*trk_vecs[d])[t], 0.01);
      }
    }
  }

  void add_io_pips(int x, int y) {
    auto &tw = tile_wires[y][x];
    Loc loc(x, y, 0);

    // IO input -> routing tracks (pad input drives into fabric)
    for (size_t z = 0; z < tw.io_out.size(); z++) {
      for (int t = 0; t < T; t++) {
        if (!tw.track_n.empty())
          add_pip(loc, tw.io_out[z], tw.track_n[t], 0.05);
        if (!tw.track_e.empty())
          add_pip(loc, tw.io_out[z], tw.track_e[t], 0.05);
        if (!tw.track_s.empty())
          add_pip(loc, tw.io_out[z], tw.track_s[t], 0.05);
        if (!tw.track_w.empty())
          add_pip(loc, tw.io_out[z], tw.track_w[t], 0.05);
      }
    }

    // Routing tracks -> IO output (fabric drives out to pad)
    for (size_t z = 0; z < tw.io_in.size(); z++) {
      for (int t = 0; t < T; t++) {
        if (!tw.track_n.empty())
          add_pip(loc, tw.track_n[t], tw.io_in[z], 0.05);
        if (!tw.track_e.empty())
          add_pip(loc, tw.track_e[t], tw.io_in[z], 0.05);
        if (!tw.track_s.empty())
          add_pip(loc, tw.track_s[t], tw.io_in[z], 0.05);
        if (!tw.track_w.empty())
          add_pip(loc, tw.track_w[t], tw.io_in[z], 0.05);
      }
    }

    // No pass-through pips within IO tiles. The sim models IO tiles
    // as simple pass-through (one value per direction), so per-track
    // direction changes are not supported. Routing through the IO ring
    // must use fabric tiles for direction changes.
  }

  void add_inter_tile_pips(int x, int y) {
    auto &tw = tile_wires[y][x];
    Loc loc(x, y, 0);

    if (tw.track_n.empty())
      return;

    // IO ring tiles only get span-1 connections (no multi-span routing
    // through the IO ring — the sim models IO tiles as simple pass-through)
    int max_span = is_io(x, y) ? 1 : 4;
    int spans[] = {1, 2, 4};
    for (int span : spans) {
      if (span > max_span)
        break;
      delay_t delay = 0.1 * span;
      for (int t = 0; t < T; t++) {
        // North
        if (y - span >= 0 && !tile_wires[y - span][x].track_s.empty())
          add_pip(loc, tw.track_n[t], tile_wires[y - span][x].track_s[t],
                  delay);
        // South
        if (y + span < H && !tile_wires[y + span][x].track_n.empty())
          add_pip(loc, tw.track_s[t], tile_wires[y + span][x].track_n[t],
                  delay);
        // East
        if (x + span < W && !tile_wires[y][x + span].track_w.empty())
          add_pip(loc, tw.track_e[t], tile_wires[y][x + span].track_w[t],
                  delay);
        // West
        if (x - span >= 0 && !tile_wires[y][x - span].track_e.empty())
          add_pip(loc, tw.track_w[t], tile_wires[y][x - span].track_e[t],
                  delay);
      }
    }
  }

  // Validity checking
  struct AegisCellInfo {
    const NetInfo *lut_f = nullptr, *ff_d = nullptr;
    bool lut_i3_used = false;
  };
  std::vector<AegisCellInfo> fast_cell_info;

  void assign_cell_info() {
    fast_cell_info.resize(ctx->cells.size());
    for (auto &cell : ctx->cells) {
      CellInfo *ci = cell.second.get();
      auto &fc = fast_cell_info.at(ci->flat_index);
      if (ci->type == id_LUT4 || ci->type == ctx->id("$lut")) {
        fc.lut_f = ci->getPort(ctx->id("Y"));
        fc.lut_i3_used = (ci->getPort(ctx->idf("A[%d]", K - 1)) != nullptr);
      } else if (ci->type == id_DFF || ci->type == ctx->id("$_DFF_P_")) {
        fc.ff_d = ci->getPort(id_D);
      }
    }
  }

  bool slice_valid(int x, int y, int z) const {
    const CellInfo *lut =
        ctx->getBoundBelCell(ctx->getBelByLocation(Loc(x, y, z * 2)));
    const CellInfo *ff =
        ctx->getBoundBelCell(ctx->getBelByLocation(Loc(x, y, z * 2 + 1)));
    if (!lut || !ff)
      return true;
    const auto &lut_data = fast_cell_info.at(lut->flat_index);
    const auto &ff_data = fast_cell_info.at(ff->flat_index);
    if (ff_data.ff_d == lut_data.lut_f)
      return true;
    if (lut_data.lut_i3_used)
      return false;
    return true;
  }

  IdString getBelBucketForCellType(IdString cell_type) const override {
    if (cell_type.in(id_INBUF, id_OUTBUF, ctx->id("$nextpnr_ibuf"),
                     ctx->id("$nextpnr_obuf")))
      return id_IOB;
    if (cell_type == ctx->id("$_DFF_P_"))
      return id_DFF;
    if (cell_type == ctx->id("$lut"))
      return id_LUT4;
    return cell_type;
  }

  bool isValidBelForCellType(IdString cell_type, BelId bel) const override {
    IdString bel_type = ctx->getBelType(bel);
    if (bel_type == id_IOB)
      return cell_type.in(id_INBUF, id_OUTBUF, ctx->id("$nextpnr_ibuf"),
                          ctx->id("$nextpnr_obuf"));
    if (bel_type == id_DFF)
      return cell_type.in(id_DFF, ctx->id("$_DFF_P_"));
    if (bel_type == id_LUT4)
      return cell_type.in(id_LUT4, ctx->id("$lut"));
    return (bel_type == cell_type);
  }
};

struct AegisArch : ViaductArch {
  AegisArch() : ViaductArch("aegis") {};
  std::unique_ptr<ViaductAPI>
  create(const dict<std::string, std::string> &args) {
    auto impl = std::make_unique<AegisImpl>();
    impl->device_args = args;
    return impl;
  }
} aegisArch;

} // namespace

NEXTPNR_NAMESPACE_END
