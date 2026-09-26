// =============================================================================
// File:    tausworthe_lfsr.sv
//
// Module Description:
//   Combined Tausworthe uniform random number generator (L'Ecuyer LFSR113).
//   Four parallel LFSR sub-generators, each with its own tap set and state
//   width, XOR-combined into a single output stream. One uniform word per
//   enabled clock cycle. Shifts and XORs only -- no multipliers, so this
//   costs LUTs and 128 flops rather than any of the Cyclone V DSP blocks.
//
//   The four component state widths (k = 31, 29, 28, 25) have coprime
//   periods, so XOR-combining them yields a period of roughly 2^113 -- far
//   longer and more equidistributed than any single LFSR of the same cost.
//   A plain 32-bit LFSR would repeat after 2^32 draws, which is not enough
//   headroom for a Monte Carlo run that wants millions of paths.
//
// Interface:
//   en gates the state update, so a stalled downstream consumer holds the
//   current sample rather than dropping draws.
//   valid_out is high on any cycle where rand_out carries a freshly
//   generated word, matching the valid_in/valid_out style used by fma.
//   rand_out is the top OUT_WIDTH bits of the combined word, read
//   downstream as an unsigned fraction in [0, 1). The generator is
//   maximally equidistributed, so slicing from the MSB side keeps the
//   uniformity guarantee at any width.
// =============================================================================
module tausworthe_lfsr #(
    parameter OUT_WIDTH = 32,

    // Per-component seeds. Each must have at least one bit set inside its
    // component mask (see SEED*_SAFE below); the defaults do.
    parameter logic [31:0] SEED0 = 32'h1234_5678,
    parameter logic [31:0] SEED1 = 32'h9ABC_DEF0,
    parameter logic [31:0] SEED2 = 32'hFEDC_BA98,
    parameter logic [31:0] SEED3 = 32'h1357_9BDF
)(
    input logic clk, rst, en,

    output logic [OUT_WIDTH-1:0] rand_out,
    output logic valid_out
);

    // Component parameters (k, q, s) from L'Ecuyer's tables of maximally
    // equidistributed combined LFSR generators. MASK clears the low 32-k
    // bits, which are the part of the word this component's shorter state
    // does not occupy. SHR is k-s.
    localparam logic [31:0] MASK0 = 32'hFFFF_FFFE;  // k=31, q=6,  s=18
    localparam logic [31:0] MASK1 = 32'hFFFF_FFF8;  // k=29, q=2,  s=2
    localparam logic [31:0] MASK2 = 32'hFFFF_FFF0;  // k=28, q=13, s=7
    localparam logic [31:0] MASK3 = 32'hFFFF_FF80;  // k=25, q=3,  s=13

    // A component whose state has no bits inside its mask is a lockup state:
    // the recurrence would return zero forever and that component would stop
    // contributing to the XOR. Sanitize at elaboration so a bad seed
    // parameter cannot silently degrade the generator on the board. This
    // costs no hardware -- it resolves to a constant before synthesis.
    localparam logic [31:0] SEED0_SAFE = ((SEED0 & MASK0) != 0) ? SEED0 : (SEED0 | 32'd2);
    localparam logic [31:0] SEED1_SAFE = ((SEED1 & MASK1) != 0) ? SEED1 : (SEED1 | 32'd8);
    localparam logic [31:0] SEED2_SAFE = ((SEED2 & MASK2) != 0) ? SEED2 : (SEED2 | 32'd16);
    localparam logic [31:0] SEED3_SAFE = ((SEED3 & MASK3) != 0) ? SEED3 : (SEED3 | 32'd128);

    logic [31:0] z0, z1, z2, z3;
    logic [31:0] combined;

    // One Tausworthe step for a component with parameters (k, q, s):
    //   b = ((z << q) ^ z) >> (k - s)
    //   z = ((z & mask) << s) ^ b
    // Every call site passes constants, so this synthesises to fixed wiring
    // rather than any shifter logic.
    function automatic logic [31:0] taus_step(
        input logic [31:0] z,
        input logic [31:0] mask,
        input int          q,
        input int          s,
        input int          shr
    );
        logic [31:0] b;
        begin
            b         = ((z << q) ^ z) >> shr;
            taus_step = ((z & mask) << s) ^ b;
        end
    endfunction

    // The four sub-generators advance independently on the same cycle, then
    // XOR into one stream.
    assign combined = z0 ^ z1 ^ z2 ^ z3;
    assign rand_out = combined[31 -: OUT_WIDTH];

    always_ff @(posedge clk) begin
        if (rst) begin
            z0        <= SEED0_SAFE;
            z1        <= SEED1_SAFE;
            z2        <= SEED2_SAFE;
            z3        <= SEED3_SAFE;
            valid_out <= 0;
        end else begin
            valid_out <= en;
            if (en) begin
                z0 <= taus_step(z0, MASK0, 6,  18, 13);
                z1 <= taus_step(z1, MASK1, 2,  2,  27);
                z2 <= taus_step(z2, MASK2, 13, 7,  21);
                z3 <= taus_step(z3, MASK3, 3,  13, 12);
            end
        end
    end

endmodule
