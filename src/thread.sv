// Thread: computes one output element C[i][j] via index/address generation and FMA accumulation
module thread #(
    parameter DATA_WIDTH = 16,
    parameter ADDR_WIDTH = 16
)(
    input logic clk, rst, en,
    input logic [7:0] N, k,
    input logic [15:0] thread_id,
    input logic [ADDR_WIDTH-1:0] base_addr_A, base_addr_B, base_addr_C,
    
    // Data from memory (valid/ready handshake)
    input logic data_valid,
    input logic [DATA_WIDTH-1:0] a_val, b_val,
    output logic data_ready,

    // Address generation
    output logic [ADDR_WIDTH-1:0] addr_A, addr_B, addr_C,

    // Accumulated result
    output logic [DATA_WIDTH-1:0] result
);
    // calculate row and col of matrix c[i][j] = i and j from thread_id
    logic [7:0] i, j;
    assign i = thread_id[7:0] / N;
    assign j = thread_id[7:0] % N;

    // calculating i/o addresses
    logic [ADDR_WIDTH-1:0] iN, kN;
    assign iN = ADDR_WIDTH'(i) * ADDR_WIDTH'(N);
    assign kN = ADDR_WIDTH'(k) * ADDR_WIDTH'(N);
    assign addr_A = base_addr_A + iN + ADDR_WIDTH'(k);
    assign addr_B = base_addr_B + kN + ADDR_WIDTH'(j);
    assign addr_C = base_addr_C + iN + ADDR_WIDTH'(j);

    // fma takes 1 cycle
    assign data_ready = 1'b1;

    // k=0: FMA computes (a*b) + 0; k>0: FMA computes (a*b) + result
    // c_in gets result when data_valid and en
    logic [DATA_WIDTH-1:0] c_in;
    logic fma_valid_in, fma_valid_out;
    assign c_in = (k == 8'd0) ? 0 : result;
    assign fma_valid_in = en && data_valid;

    fma #(
        .DATA_WIDTH(DATA_WIDTH)
    ) u_fma (
        .clk       (clk),
        .rst       (rst),
        .a         (a_val),
        .b         (b_val),
        .c         (c_in),
        .valid_in  (fma_valid_in),
        .result    (result),
        .valid_out (fma_valid_out)
    );

endmodule
