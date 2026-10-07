module tausworthe_lfsr_tb;

    localparam int UNIFORM_SAMPLES = 16384;
    localparam int REF_WORDS       = 12;

    // Ideal count per bin if the top nibble is uniformly distributed. The
    // measured worst-case deviation over this many samples is under 5%, so a
    // 10% band checks the distribution without being flaky.
    localparam int BIN_IDEAL = UNIFORM_SAMPLES / 16;
    localparam int BIN_LO    = BIN_IDEAL - (BIN_IDEAL / 10);
    localparam int BIN_HI    = BIN_IDEAL + (BIN_IDEAL / 10);

    logic clk, rst, en;
    logic [31:0] rand_out;
    logic valid_out;

    int errors = 0;

    // Bit-exact expected stream, generated from an independent Python
    // implementation of L'Ecuyer's LFSR113 using the DUT's default seeds.
    // Checking against these rather than against a SystemVerilog copy of the
    // same recurrence is what makes this a real reference and not a tautology.
    logic [31:0] ref_words [0:REF_WORDS-1];

    // Combined word straight after reset, before any step: the XOR of the
    // four seeds.
    localparam logic [31:0] SEED_XOR = 32'h6503_A9CF;

    tausworthe_lfsr #(
        .OUT_WIDTH (32)
    ) dut (
        .clk       (clk),
        .rst       (rst),
        .en        (en),
        .rand_out  (rand_out),
        .valid_out (valid_out)
    );

    initial begin
        clk = 0;
        forever begin
            #5 clk = ~clk; // 100 MHz
        end
    end

    task automatic load_reference();
        ref_words[0]  = 32'hAE32_5728;
        ref_words[1]  = 32'h7287_C452;
        ref_words[2]  = 32'h37CB_24DB;
        ref_words[3]  = 32'h8083_41F3;
        ref_words[4]  = 32'h5147_81F8;
        ref_words[5]  = 32'h9F32_687A;
        ref_words[6]  = 32'h97E9_BC91;
        ref_words[7]  = 32'h8A60_DA89;
        ref_words[8]  = 32'h4AC4_184B;
        ref_words[9]  = 32'hEAC2_7A56;
        ref_words[10] = 32'h2ACC_6A01;
        ref_words[11] = 32'h9F25_4DF8;
    endtask

    // Hold reset for two cycles, then release, leaving en low.
    task automatic reset_dut();
        rst = 1;
        en  = 0;
        repeat (2) @(posedge clk);
        #1;
        rst = 0;
    endtask

    // rand_out is combinational off the state registers, so sampling one
    // timestep after the edge reads the value the new state produces.
    task automatic step_once();
        @(posedge clk);
        #1;
    endtask

    task automatic check_reset_state();
        int local_errors;
        local_errors = 0;

        $display("--- TEST: reset loads seeds ---");

        reset_dut();

        if (rand_out !== SEED_XOR) begin
            $error("post-reset rand_out wrong: expected %08h, got %08h",
                   SEED_XOR, rand_out);
            local_errors++;
        end

        if (valid_out !== 1'b0) begin
            $error("post-reset valid_out wrong: expected 0, got %0b", valid_out);
            local_errors++;
        end

        errors += local_errors;

        if (local_errors == 0) $display("    seeds loaded, valid_out low  PASS");
    endtask

    task automatic check_bit_exact();
        int local_errors;
        local_errors = 0;

        $display("--- TEST: bit-exact match against LFSR113 reference ---");

        reset_dut();
        en = 1;

        for (int i = 0; i < REF_WORDS; i++) begin
            step_once();

            if (valid_out !== 1'b1) begin
                $error("word %0d: valid_out wrong: expected 1, got %0b",
                       i, valid_out);
                local_errors++;
            end

            if (rand_out !== ref_words[i]) begin
                $error("word %0d wrong: expected %08h, got %08h",
                       i, ref_words[i], rand_out);
                local_errors++;
            end
        end

        en = 0;
        errors += local_errors;

        if (local_errors == 0)
            $display("    %0d words match reference  PASS", REF_WORDS);
    endtask

    // A stalled downstream consumer must see the sample held, not dropped.
    task automatic check_en_gating();
        logic [31:0] held;
        int local_errors;
        local_errors = 0;

        $display("--- TEST: en gating holds the current sample ---");

        reset_dut();
        en = 1;
        repeat (3) step_once();

        en   = 0;
        held = rand_out;

        for (int i = 0; i < 5; i++) begin
            step_once();

            if (rand_out !== held) begin
                $error("cycle %0d: rand_out advanced while en low: was %08h, now %08h",
                       i, held, rand_out);
                local_errors++;
            end

            if (valid_out !== 1'b0) begin
                $error("cycle %0d: valid_out wrong with en low: expected 0, got %0b",
                       i, valid_out);
                local_errors++;
            end
        end

        // Re-enabling must resume the stream rather than restart it.
        en = 1;
        step_once();

        if (rand_out === held) begin
            $error("rand_out did not advance after en re-asserted: still %08h", held);
            local_errors++;
        end

        en = 0;
        errors += local_errors;

        if (local_errors == 0) $display("    sample held for 5 stalled cycles  PASS");
    endtask

    // Coarse distribution check plus a lockup check on every sub-generator.
    // A component whose state reaches zero stops contributing to the XOR and
    // silently halves the generator's quality, which no bit-exact check on a
    // short prefix would catch.
    task automatic check_uniformity();
        longint unsigned sum_samples;
        int bin_count [0:15];
        real mean;
        int local_errors;

        sum_samples = 0;
        local_errors = 0;
        for (int b = 0; b < 16; b++) bin_count[b] = 0;

        $display("--- TEST: uniformity and no component lockup over %0d samples ---",
                 UNIFORM_SAMPLES);

        reset_dut();
        en = 1;

        for (int i = 0; i < UNIFORM_SAMPLES; i++) begin
            step_once();

            sum_samples += {32'd0, rand_out};
            bin_count[rand_out[31:28]]++;

            if (dut.z0 === 32'd0 || dut.z1 === 32'd0 ||
                dut.z2 === 32'd0 || dut.z3 === 32'd0) begin
                $error("sample %0d: component locked up at zero (z0=%08h z1=%08h z2=%08h z3=%08h)",
                       i, dut.z0, dut.z1, dut.z2, dut.z3);
                local_errors++;
            end
        end

        en = 0;

        mean = real'(sum_samples) / real'(UNIFORM_SAMPLES) / 4294967296.0;

        if (mean < 0.49 || mean > 0.51) begin
            $error("mean wrong: expected 0.5 +/- 0.01, got %0.6f", mean);
            local_errors++;
        end else begin
            $display("    mean = %0.6f", mean);
        end

        for (int b = 0; b < 16; b++) begin
            if (bin_count[b] < BIN_LO || bin_count[b] > BIN_HI) begin
                $error("bin %0d count %0d outside [%0d, %0d]",
                       b, bin_count[b], BIN_LO, BIN_HI);
                local_errors++;
            end
        end

        errors += local_errors;

        if (local_errors == 0)
            $display("    all 16 bins within 10%% of %0d, no lockup  PASS", BIN_IDEAL);
    endtask

    initial begin
        en = 0;

        load_reference();

        check_reset_state();
        check_bit_exact();
        check_en_gating();
        check_uniformity();

        if (errors == 0) begin
            $display("\n=== PASS ===");
        end else begin
            $display("\n=== FAIL: %0d errors ===", errors);
        end

        $finish;
    end

endmodule
