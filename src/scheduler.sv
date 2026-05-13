// =============================================================================
// scheduler.sv  (1-cycle BRAM latency)
//
// Main FSM for one core. 
//
//   for k = 0..N-1:
//       for t = 0..thread_count-1:
//           ISSUE  → drive thread t's addr_A and addr_B (via MUX in core.sv)
//           FMA    → BRAM data is on the bus; pulse data_valid[t] + fma_en[t]
//   for t = 0..thread_count-1:
//           WRITE  → drive thread t's addr_C and result, pulse mem_write_en
//
// Threads compute their own addresses (addr_A/B/C). Scheduler picks which
// thread's address bus reaches the BRAM via t_select.
// =============================================================================
module scheduler #(
    parameter THREADS_PER_CORE = 2,
    parameter TSEL            = (THREADS_PER_CORE == 1) ? 1 : $clog2(THREADS_PER_CORE)
)(
    input  logic                              clk,
    input  logic                              rst,
    input  logic                              start,

    // Kernel parameters
    input  logic [7:0]                        N,
    input  logic [7:0]                        thread_count,

    // To core: which thread's address bus drives the BRAM port this cycle
    output logic [TSEL-1:0]                   t_select,

    // To threads: per-thread one-hot pulses
    output logic [THREADS_PER_CORE-1:0]       data_valid,
    output logic [THREADS_PER_CORE-1:0]       fma_en,
    output logic [7:0]                        k,

    // To core: memory phase signals
    output logic                              mem_read_a_en,   // drive addr_A this cycle
    output logic                              mem_read_b_en,   // drive addr_B this cycle
    output logic                              mem_write_en,    // drive addr_C / result this cycle

    output logic [3:0]                        state,           // exposed for debug / TB
    output logic                              done
);

    typedef enum logic [3:0] {
        IDLE,
        INIT,
        ISSUE_A,
        ISSUE_B,
        FMA,
        NEXT_T,
        NEXT_K,
        WRITE,
        NEXT_W,
        DONE_S
    } state_t;

    state_t state_r;

    // Counters
    logic [7:0] t_cnt;
    logic [7:0] k_cnt;

    logic is_last_thread = (t_cnt == thread_count - 8'd1); //used to terminate the loop  
    logic is_last_k      = (k_cnt == N - 8'd1);

    // FSM
    always_ff @(posedge clk) begin
        if (rst) begin
            state_r <= IDLE;
            t_cnt <= 0;
            k_cnt <= 0;
        end else begin
            case (state_r)
                IDLE: begin
                    if (start) state_r <= INIT;
                end

                INIT: begin
                    t_cnt   <= '0;
                    k_cnt   <= '0;
                    state_r <= ISSUE_A;
                end

                ISSUE_A: state_r <= ISSUE_B;
                ISSUE_B: state_r <= FMA;
                FMA:     state_r <= NEXT_T;

                NEXT_T: begin
                    if (is_last_thread) begin
                        t_cnt   <= '0;
                        state_r <= NEXT_K;
                    end else begin
                        t_cnt   <= t_cnt + 8'd1;
                        state_r <= ISSUE_A;
                    end
                end

                NEXT_K: begin
                    if (is_last_k) begin
                        t_cnt   <= '0;
                        state_r <= WRITE;
                    end else begin
                        k_cnt   <= k_cnt + 8'd1;
                        state_r <= ISSUE_A;
                    end
                end

                WRITE: state_r <= NEXT_W;

                NEXT_W: begin
                    if (is_last_thread) begin
                        state_r <= DONE_S;
                    end else begin
                        t_cnt   <= t_cnt + 8'd1;
                        state_r <= WRITE;
                    end
                end

                DONE_S:  state_r <= IDLE;
                default: state_r <= IDLE;
            endcase
        end
    end

    // Mealy outputs (combinational from `state_r` + `t_cnt`)
    always_comb begin
        data_valid = '0;
        fma_en     = '0;
        if (state_r == FMA) begin
            data_valid[t_cnt[TSEL-1:0]] = 1'b1;
            fma_en    [t_cnt[TSEL-1:0]] = 1'b1;
        end
        t_select      = t_cnt[TSEL-1:0];
        k             = k_cnt;
        mem_read_a_en = (state_r == ISSUE_A);
        mem_read_b_en = (state_r == ISSUE_B);
        mem_write_en  = (state_r == WRITE);
        done          = (state_r == DONE_S);
        state         = state_r;
    end
endmodule
