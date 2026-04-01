/*
 *  Aegis FPGA viaduct micro-architecture for nextpnr-generic.
 *
 *  Defines the Aegis routing architecture natively in C++ for fast
 *  chipdb construction. Uses -o device=WxHtT to configure dimensions.
 *
 *  Based on nextpnr's example viaduct uarch.
 */

#include "log.h"
#include "nextpnr.h"
#include "util.h"
#include "viaduct_api.h"
#include "viaduct_helpers.h"

// Use runtime ctx->id() instead of compile-time constids
// to avoid IdString table conflicts

NEXTPNR_NAMESPACE_BEGIN

namespace {

struct AegisImpl : ViaductAPI {
  ~AegisImpl() {};

  // Device parameters
  int W = 4, H = 4;
  int T = 1;
  int N = 1;
  int K = 4;
  int Wl;
  int Si = 4, Sq = 4, Sl = 8;

  dict<std::string, std::string> device_args;

  // Cached IdStrings — initialized in init()
  IdString id_LUT4, id_DFF, id_IOB, id_INBUF, id_OUTBUF;
  IdString id_CLK, id_D, id_Q, id_F, id_I, id_O, id_PAD, id_EN;
  IdString id_INIT, id_PIP, id_LOCAL;

  void init(Context *ctx) override {
    ViaductAPI::init(ctx);
    h.init(ctx);

    // Initialize IdStrings
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
    id_LOCAL = ctx->id("LOCAL");

    // Parse device parameters from vopt args
    if (device_args.count("device")) {
      std::string val = device_args.at("device");
      if (val.find('x') != std::string::npos) {
        sscanf(val.c_str(), "%dx%d", &W, &H);
        if (val.find('t') != std::string::npos) {
          sscanf(strstr(val.c_str(), "t") + 1, "%d", &T);
        }
      }
    }

    // Include IO ring
    W += 2;
    H += 2;
    Wl = N * (K + 1) + T * 4;

    log_info(
        "Aegis FPGA: %dx%d grid (%dx%d fabric), %d tracks, %d local wires\n", W,
        H, W - 2, H - 2, T, Wl);

    init_wires();
    init_bels();
    init_pips();
  }

  void pack() override {
    IdString id_lut = ctx->id("$lut");
    IdString id_dff_p = ctx->id("$_DFF_P_");
    IdString id_Y = ctx->id("Y");
    IdString id_C = ctx->id("C");

    // Replace constants with $lut cells using proper parameter names
    // $lut uses LUT (not INIT) and WIDTH parameters
    const dict<IdString, Property> vcc_params = {
        {ctx->id("LUT"), Property(0xFFFF, 16)},
        {ctx->id("WIDTH"), Property(4, 32)}};
    const dict<IdString, Property> gnd_params = {
        {ctx->id("LUT"), Property(0x0000, 16)},
        {ctx->id("WIDTH"), Property(4, 32)}};
    h.replace_constants(CellTypePort(id_lut, id_Y), CellTypePort(id_lut, id_Y),
                        vcc_params, gnd_params);

    // Constrain LUT+FF pairs for shared placement
    int lutffs =
        h.constrain_cell_pairs(pool<CellTypePort>{{id_lut, id_Y}},
                               pool<CellTypePort>{{id_dff_p, id_D}}, 1);
    log_info("Constrained %d LUTFF pairs.\n", lutffs);
  }

  void prePlace() override { assign_cell_info(); }

  bool isBelLocationValid(BelId bel, bool explain_invalid) const override {
    Loc l = ctx->getBelLocation(bel);
    if (is_io(l.x, l.y))
      return true;
    return slice_valid(l.x, l.y, l.z / 2);
  }

private:
  ViaductHelpers h;

  struct TileWires {
    std::vector<WireId> clk, q, f, d, i;
    std::vector<WireId> l;
    std::vector<WireId> pad;
  };

  std::vector<std::vector<TileWires>> wires_by_tile;

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
    wires_by_tile.resize(H);
    for (int y = 0; y < H; y++) {
      auto &row = wires_by_tile.at(y);
      row.resize(W);
      for (int x = 0; x < W; x++) {
        auto &w = row.at(x);
        if (!is_io(x, y)) {
          // Logic tile wires
          for (int z = 0; z < N; z++) {
            w.clk.push_back(ctx->addWire(h.xy_id(x, y, ctx->idf("CLK%d", z)),
                                         id_CLK, x, y));
            w.d.push_back(
                ctx->addWire(h.xy_id(x, y, ctx->idf("D%d", z)), id_D, x, y));
            w.q.push_back(
                ctx->addWire(h.xy_id(x, y, ctx->idf("Q%d", z)), id_Q, x, y));
            w.f.push_back(
                ctx->addWire(h.xy_id(x, y, ctx->idf("F%d", z)), id_F, x, y));
            for (int k = 0; k < K; k++)
              w.i.push_back(ctx->addWire(
                  h.xy_id(x, y, ctx->idf("L%dI%d", z, k)), id_I, x, y));
          }
        } else if (x != y) {
          // IO tile wires — dedicated pad and IO wires
          for (int z = 0; z < 2; z++) {
            w.pad.push_back(ctx->addWire(h.xy_id(x, y, ctx->idf("PAD%d", z)),
                                         id_PAD, x, y));
            // IO input/output/enable wires
            w.i.push_back(
                ctx->addWire(h.xy_id(x, y, ctx->idf("IO_I%d", z)), id_I, x, y));
            w.i.push_back(ctx->addWire(h.xy_id(x, y, ctx->idf("IO_EN%d", z)),
                                       id_I, x, y));
            w.q.push_back(
                ctx->addWire(h.xy_id(x, y, ctx->idf("IO_O%d", z)), id_O, x, y));
          }
        }
        // Local wires for routing
        for (int l = 0; l < Wl; l++)
          w.l.push_back(ctx->addWire(h.xy_id(x, y, ctx->idf("LOCAL%d", l)),
                                     id_LOCAL, x, y));
      }
    }
  }

  void add_io_bels(int x, int y) {
    auto &w = wires_by_tile.at(y).at(x);
    for (int z = 0; z < 2; z++) {
      BelId b = ctx->addBel(h.xy_id(x, y, ctx->idf("IO%d", z)), id_IOB,
                            Loc(x, y, z), false, false);
      ctx->addBelInout(b, id_PAD, w.pad.at(z));
      ctx->addBelInput(b, id_I, w.i.at(z * 2)); // $nextpnr_ibuf.I
      ctx->addBelInput(b, ctx->id("A"),
                       w.i.at(z * 2)); // $nextpnr_obuf.A (alias)
      ctx->addBelInput(b, id_EN, w.i.at(z * 2 + 1));
      ctx->addBelOutput(b, id_O, w.q.at(z));
    }
  }

  void add_slice_bels(int x, int y) {
    auto &w = wires_by_tile.at(y).at(x);
    for (int z = 0; z < N; z++) {
      BelId lut = ctx->addBel(h.xy_id(x, y, ctx->idf("SLICE%d_LUT", z)),
                              id_LUT4, Loc(x, y, z * 2), false, false);
      // Pin names match $lut cell: A[0]-A[3], Y
      // Also add unindexed 'A' for constant LUTs created by replace_constants
      for (int k = 0; k < K; k++)
        ctx->addBelInput(lut, ctx->idf("A[%d]", k), w.i.at(z * K + k));
      ctx->addBelInput(lut, ctx->id("A"), w.i.at(z * K));
      ctx->addBelOutput(lut, ctx->id("Y"), w.f.at(z));

      add_pip(Loc(x, y, 0), w.f.at(z), w.d.at(z));
      add_pip(Loc(x, y, 0), w.i.at(z * K + (K - 1)), w.d.at(z));

      // Pin names match $_DFF_P_ cell: C, D, Q
      BelId dff = ctx->addBel(h.xy_id(x, y, ctx->idf("SLICE%d_FF", z)), id_DFF,
                              Loc(x, y, z * 2 + 1), false, false);
      ctx->addBelInput(dff, ctx->id("C"), w.clk.at(z));
      ctx->addBelInput(dff, id_D, w.d.at(z));
      ctx->addBelOutput(dff, id_Q, w.q.at(z));
    }
  }

  void init_bels() {
    log_info("Creating bels...\n");
    for (int y = 0; y < H; y++)
      for (int x = 0; x < W; x++) {
        if (is_io(x, y)) {
          if (x == y)
            continue;
          add_io_bels(x, y);
        } else {
          add_slice_bels(x, y);
        }
      }
  }

  void add_tile_pips(int x, int y) {
    auto &w = wires_by_tile.at(y).at(x);
    Loc loc(x, y, 0);

    if (!is_io(x, y)) {
      // Logic tile pips
      auto create_input_pips = [&](WireId dst, int offset, int skip) {
        for (int i = (offset % skip); i < Wl; i += skip)
          add_pip(loc, w.l.at(i), dst, 0.05);
      };
      for (int z = 0; z < N; z++) {
        create_input_pips(w.clk.at(z), 0, Si);
        for (int k = 0; k < K; k++)
          create_input_pips(w.i.at(z * K + k), k, Si);
      }
    } else if (x != y) {
      // IO tile — connect IO wires to local routing
      for (size_t z = 0; z < w.i.size(); z++) {
        for (int l = (z % Si); l < Wl; l += Si)
          add_pip(loc, w.l.at(l), w.i.at(z), 0.05);
      }
      for (size_t z = 0; z < w.q.size(); z++) {
        for (int l = (z % Sq); l < Wl; l += Sq)
          add_pip(loc, w.q.at(z), w.l.at(l), 0.05);
      }
    }

    auto create_output_pips = [&](WireId dst, int offset, int skip) {
      if (is_io(x, y))
        return;
      for (int z = (offset % skip); z < N; z += skip) {
        add_pip(loc, w.f.at(z), dst, 0.05);
        add_pip(loc, w.q.at(z), dst, 0.05);
      }
    };
    auto create_neighbour_pips = [&](WireId dst, int nx, int ny, int offset,
                                     int skip) {
      if (nx < 0 || nx >= W || ny < 0 || ny >= H)
        return;
      auto &nw = wires_by_tile.at(ny).at(nx);
      for (int i = (offset % skip); i < Wl; i += skip)
        add_pip(loc, dst, nw.l.at(i), 0.1);
    };

    for (int i = 0; i < Wl; i++) {
      WireId dst = w.l.at(i);
      create_output_pips(dst, i % Sq, Sq);
      create_neighbour_pips(dst, x - 1, y - 1, (i + 1) % Sl, Sl);
      create_neighbour_pips(dst, x - 1, y, (i + 2) % Sl, Sl);
      create_neighbour_pips(dst, x - 1, y + 1, (i + 3) % Sl, Sl);
      create_neighbour_pips(dst, x, y - 1, (i + 4) % Sl, Sl);
      create_neighbour_pips(dst, x, y + 1, (i + 5) % Sl, Sl);
      create_neighbour_pips(dst, x + 1, y - 1, (i + 6) % Sl, Sl);
      create_neighbour_pips(dst, x + 1, y, (i + 7) % Sl, Sl);
      create_neighbour_pips(dst, x + 1, y + 1, (i + 8) % Sl, Sl);
    }
  }

  void init_pips() {
    log_info("Creating pips...\n");
    for (int y = 0; y < H; y++)
      for (int x = 0; x < W; x++)
        add_tile_pips(x, y);
  }

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
