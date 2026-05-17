module core #(
    parameter DATA_WIDTH      = 16,
    parameter ADDR_WIDTH      = 16,
    parameter THREADS_PER_CORE = 2
)(
    input logic clk, rst, start, //start should be sufficient when wired
    input logic [7:0] N,
    input logic [15:0] thread_id_start, thread_count, //comes from dispatcher
    input logic [ADDR_WIDTH-1:0] base_addr_A, base_addr_B, base_addr_C,

    output logic dispatch_ready, done, //dispatcher ready and one is core_ready to dispatcher

    // Memory read bus (valid/ready handshake)
    input logic [DATA_WIDTH-1:0] mem_read_data,

    output logic mem_read_valid,
    output logic [ADDR_WIDTH-1:0] mem_read_addr,

    output logic mem_write_valid,
    output logic [ADDR_WIDTH-1:0] mem_write_addr, mem_write_data
);

    parameter TSEL = (THREADS_PER_CORE == 1) ? 1 : $clog2(THREADS_PER_CORE);
    typedef enum logic { C_IDLE, C_BUSY } core_state_t;
    core_state_t core_state;

    logic [15:0] thread_id_start_r;
    logic [15:0] thread_count_r;

    // Per-thread outputs (each thread emits its own addr_A/B/C and result)
    logic [ADDR_WIDTH-1:0] t_addr_A [THREADS_PER_CORE-1:0];
    logic [ADDR_WIDTH-1:0] t_addr_B [THREADS_PER_CORE-1:0]; 
    logic [ADDR_WIDTH-1:0] t_addr_C [THREADS_PER_CORE-1:0];
    logic [DATA_WIDTH-1:0] t_result [THREADS_PER_CORE-1:0];

    // Scheduler outputs
    logic [TSEL-1:0] sched_t_select;
    logic [THREADS_PER_CORE-1:0] sched_data_valid, sched_fma_en;
    logic [7:0] sched_k;
    logic [3:0] sched_state;
    logic sched_mem_read_a_en, sched_mem_read_b_en, sched_mem_write_en, sched_done;
    
    // A-side latch: captures BRAM read data during ISSUE_B so the FMA cycle
    // sees a_val = a_buf (A operand) and b_val = mem_read_data (B operand).
    logic [DATA_WIDTH-1:0] a_buf;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            core_state <= C_IDLE;
            done <= 0;
            thread_id_start_r <= 0;
            thread_count_r <= 0;
            a_buf <= 0;
        end else begin
            done <= 0;
            if (sched_mem_read_b_en)  a_buf <= mem_read_data;
            case (core_state)
                C_IDLE: begin
                    if (start) begin
                        thread_id_start_r <= thread_id_start;
                        thread_count_r    <= thread_count;
                        core_state        <= C_BUSY;
                    end
                end

                C_BUSY: begin
                    if (sched_done) begin
                        done       <= 1'b1;
                        core_state <= C_IDLE;
                    end
                end

                default: core_state <= C_IDLE;
            endcase
            
        end
    end

    always_ff @(posedge clk) begin
        if (rst)                       
        else 
    end
    
    assign dispatch_ready  = (core_state == C_IDLE);
    assign mem_read_addr   = sched_mem_read_b_en ? t_addr_B[sched_t_select]
                                                 : t_addr_A[sched_t_select];
    assign mem_read_valid  = sched_mem_read_a_en || sched_mem_read_b_en;
    assign mem_write_addr  = t_addr_C[sched_t_select];
    assign mem_write_data  = t_result[sched_t_select];
    assign mem_write_valid = sched_mem_write_en;

    scheduler #(
        .THREADS_PER_CORE(THREADS_PER_CORE)
    ) u_scheduler (
        .clk           (clk),
        .rst           (rst),
        .start         (start),
        .N             (N),
        .thread_count  (thread_count_r[7:0]),

        .t_select      (sched_t_select),
        .data_valid    (sched_data_valid),
        .fma_en        (sched_fma_en),
        .k             (sched_k),

        .mem_read_a_en (sched_mem_read_a_en),
        .mem_read_b_en (sched_mem_read_b_en),
        .mem_write_en  (sched_mem_write_en),

        .state         (sched_state),
        .done          (sched_done)
    );

    for (genvar gi = 0; gi < THREADS_PER_CORE; gi++) begin : gen_threads
        thread #(
            .DATA_WIDTH(DATA_WIDTH),
            .ADDR_WIDTH(ADDR_WIDTH)
        ) u_thread (
            .clk        (clk),
            .rst        (rst),
            .en         (sched_fma_en[gi]),
            .N          (N),
            .k          (sched_k),
            .thread_id  (thread_id_start_r + 16'(gi)),
            .base_addr_A(base_addr_A),
            .base_addr_B(base_addr_B),
            .base_addr_C(base_addr_C),

            .data_valid (sched_data_valid[gi]),
            .a_val      (a_buf),
            .b_val      (mem_read_data),
            .data_ready (),

            .addr_A     (t_addr_A[gi]),
            .addr_B     (t_addr_B[gi]),
            .addr_C     (t_addr_C[gi]),

            .result     (t_result[gi])
        );
    end

endmodule
