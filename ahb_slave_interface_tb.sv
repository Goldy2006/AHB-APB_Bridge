`timescale 1ns/1ps

module ahb_slave_interface_tb;

    localparam logic [1:0] HTRANS_IDLE   = 2'b00;
    localparam logic [1:0] HTRANS_BUSY   = 2'b01;
    localparam logic [1:0] HTRANS_NONSEQ = 2'b10;
    localparam logic [1:0] HTRANS_SEQ    = 2'b11;

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    logic        Hclk;
    logic        Hresetn;
    logic        HSEL;
    logic        Hwrite;
    logic        Hreadyin;
    logic        apb_readyout;
    logic [1:0]  Htrans;
    logic [31:0] Haddr;
    logic [31:0] Hwdata;

    logic [1:0]  Hresp;
    logic [31:0] Hrdata;
    logic        Hreadyout;
    logic        valid;
    logic [31:0] Haddr1;
    logic [31:0] Haddr2;
    logic [31:0] Hwdata1;
    logic [31:0] Hwdata2;
    logic        Hwritereg;
    logic [2:0]  tempselx1;
    logic [2:0]  tempselx2;

    // -------------------------------------------------------------------------
    // Reference model state
    // -------------------------------------------------------------------------
    logic        exp_valid;
    logic [31:0] exp_Haddr1;
    logic [31:0] exp_Haddr2;
    logic [31:0] exp_Hwdata1;
    logic [31:0] exp_Hwdata2;
    logic        exp_Hwritereg;
    logic [2:0]  exp_tempselx1;
    logic [2:0]  exp_tempselx2;

    integer checks;
    integer errors;

    ahb_slave_interface dut (
        .Hclk      (Hclk),
        .Hresetn   (Hresetn),
        .HSEL      (HSEL),
        .Hwrite    (Hwrite),
        .Hreadyin  (Hreadyin),
        .Htrans    (Htrans),
        .Haddr     (Haddr),
        .Hwdata    (Hwdata),
        .apb_readyout(apb_readyout),
        .Hresp     (Hresp),
        .Hrdata    (Hrdata),
        .Hreadyout (Hreadyout),
        .valid     (valid),
        .Haddr1    (Haddr1),
        .Haddr2    (Haddr2),
        .Hwdata1   (Hwdata1),
        .Hwdata2   (Hwdata2),
        .Hwritereg (Hwritereg),
        .tempselx1 (tempselx1),
        .tempselx2 (tempselx2)
    );

    // -------------------------------------------------------------------------
    // Clock and waveform dump
    // -------------------------------------------------------------------------
    initial begin
        Hclk = 1'b0;
        forever #5 Hclk = ~Hclk;
    end

    initial begin
        $dumpfile("ahb_slave_interface_tb.vcd");
        $dumpvars(0, ahb_slave_interface_tb);
    end

    // -------------------------------------------------------------------------
    // Utility functions and tasks
    // -------------------------------------------------------------------------
    function automatic logic [2:0] decode_tempselx(input logic [31:0] addr);
        begin
            if ((addr >= 32'h8000_0000) && (addr <= 32'h83FF_FFFF)) begin
                decode_tempselx = 3'b001;
            end
            else if ((addr >= 32'h8400_0000) && (addr <= 32'h87FF_FFFF)) begin
                decode_tempselx = 3'b010;
            end
            else if ((addr >= 32'h8800_0000) && (addr <= 32'h8BFF_FFFF)) begin
                decode_tempselx = 3'b100;
            end
            else begin
                decode_tempselx = 3'b000;
            end
        end
    endfunction

    task automatic record_check(input bit pass, input string msg);
        begin
            checks++;
            if (!pass) begin
                errors++;
                $error("FAIL: %s", msg);
            end
        end
    endtask

    task automatic check_bit(input string name, input logic actual, input logic expected);
        begin
            record_check(actual === expected,
                         $sformatf("%s actual=%0b expected=%0b time=%0t",
                                   name, actual, expected, $time));
        end
    endtask

    task automatic check_vec2(input string name, input logic [1:0] actual, input logic [1:0] expected);
        begin
            record_check(actual === expected,
                         $sformatf("%s actual=%b expected=%b time=%0t",
                                   name, actual, expected, $time));
        end
    endtask

    task automatic check_vec3(input string name, input logic [2:0] actual, input logic [2:0] expected);
        begin
            record_check(actual === expected,
                         $sformatf("%s actual=%b expected=%b time=%0t",
                                   name, actual, expected, $time));
        end
    endtask

    task automatic check_vec32(input string name, input logic [31:0] actual, input logic [31:0] expected);
        begin
            record_check(actual === expected,
                         $sformatf("%s actual=0x%08h expected=0x%08h time=%0t",
                                   name, actual, expected, $time));
        end
    endtask

    task automatic drive_bus(input logic        sel,
                             input logic        write,
                             input logic        ready,
                             input logic [1:0]  trans,
                             input logic [31:0] addr,
                             input logic [31:0] data);
        begin
            HSEL     = sel;
            Hwrite   = write;
            Hreadyin = ready;
            apb_readyout = 1'b1;
            Htrans   = trans;
            Haddr    = addr;
            Hwdata   = data;
            #1;
        end
    endtask

    task automatic reset_reference;
        begin
            exp_valid             = 1'b0;
            exp_Haddr1            = 32'h0000_0000;
            exp_Haddr2            = 32'h0000_0000;
            exp_Hwdata1           = 32'h0000_0000;
            exp_Hwdata2           = 32'h0000_0000;
            exp_Hwritereg         = 1'b0;
            exp_tempselx1         = 3'b000;
            exp_tempselx2         = 3'b000;
        end
    endtask

    task automatic update_reference;
        logic        old_valid;
        logic        old_Hwritereg;
        logic [31:0] old_Haddr1;
        logic [31:0] old_Hwdata1;
        logic [2:0]  old_tempselx1;
        logic        exp_valid_next;
        begin
            exp_valid_next = HSEL && Hreadyin && Htrans[1];

            if (!Hresetn) begin
                reset_reference();
            end
            else begin
                old_valid     = exp_valid;
                old_Hwritereg = exp_Hwritereg;
                old_Haddr1    = exp_Haddr1;
                old_Hwdata1   = exp_Hwdata1;
                old_tempselx1 = exp_tempselx1;

                exp_valid = exp_valid_next;

                if (exp_valid_next) begin
                    exp_Haddr1    = Haddr;
                    exp_Hwritereg = Hwrite;
                    exp_tempselx1 = decode_tempselx(Haddr);
                end

                if (Hreadyin) begin
                    exp_Haddr2    = old_Haddr1;
                    exp_tempselx2 = old_tempselx1;

                    if (old_valid && old_Hwritereg) begin
                        exp_Hwdata2 = Hwdata;
                    end
                    else begin
                        exp_Hwdata2 = old_Hwdata1;
                    end
                end

                if (old_valid && old_Hwritereg) begin
                    exp_Hwdata1 = Hwdata;
                end
            end
        end
    endtask

    task automatic check_placeholders;
        begin
            check_vec2("Hresp", Hresp, 2'b00);
            check_vec32("Hrdata", Hrdata, 32'h0000_0000);
            check_bit("Hreadyout", Hreadyout, 1'b1);
        end
    endtask

    task automatic check_all_outputs(input string tag);
        begin
            check_bit({tag, " valid"}, valid, exp_valid);
            check_vec32({tag, " Haddr1"}, Haddr1, exp_Haddr1);
            check_vec32({tag, " Haddr2"}, Haddr2, exp_Haddr2);
            check_vec32({tag, " Hwdata1"}, Hwdata1, exp_Hwdata1);
            check_vec32({tag, " Hwdata2"}, Hwdata2, exp_Hwdata2);
            check_bit({tag, " Hwritereg"}, Hwritereg, exp_Hwritereg);
            check_vec3({tag, " tempselx1"}, tempselx1, exp_tempselx1);
            check_vec3({tag, " tempselx2"}, tempselx2, exp_tempselx2);
            check_placeholders();
        end
    endtask

    task automatic cycle_and_check(input string tag);
        begin
            @(posedge Hclk);
            update_reference();
            #1;
            check_all_outputs(tag);
        end
    endtask

    task automatic apply_reset;
        begin
            drive_bus(1'b0, 1'b0, 1'b1, HTRANS_IDLE, 32'h0000_0000, 32'h0000_0000);
            Hresetn = 1'b0;
            reset_reference();
            repeat (2) begin
                @(posedge Hclk);
                update_reference();
                #1;
                check_all_outputs("reset");
            end
            Hresetn = 1'b1;
            @(posedge Hclk);
            update_reference();
            #1;
            check_all_outputs("reset release");
        end
    endtask

    task automatic issue_cycle(input logic        sel,
                               input logic        write,
                               input logic        ready,
                               input logic [1:0]  trans,
                               input logic [31:0] addr,
                               input logic [31:0] data,
                               input string       tag);
        begin
            @(negedge Hclk);
            drive_bus(sel, write, ready, trans, addr, data);
            cycle_and_check(tag);
        end
    endtask

    task automatic print_test(input string name);
        begin
            $display("");
            $display("---- %s ----", name);
        end
    endtask

    // -------------------------------------------------------------------------
    // Directed and randomized tests
    // -------------------------------------------------------------------------
    integer sel_i;
    integer ready_i;
    integer trans_i;
    integer rand_i;

    initial begin
        checks = 0;
        errors = 0;
        Hresetn = 1'b1;
        reset_reference();
        drive_bus(1'b0, 1'b0, 1'b1, HTRANS_IDLE, 32'h0000_0000, 32'h0000_0000);

        print_test("TEST 1: Reset behavior");
        apply_reset();

        print_test("TEST 2: valid generation");
        for (sel_i = 0; sel_i < 2; sel_i++) begin
            for (ready_i = 0; ready_i < 2; ready_i++) begin
                for (trans_i = 0; trans_i < 4; trans_i++) begin
                    issue_cycle(sel_i[0], 1'b0, ready_i[0], trans_i[1:0],
                                32'h9000_0000 + trans_i, 32'h1111_0000 + trans_i,
                                "valid generation");
                end
            end
        end

        print_test("TEST 3: Address decode");
        issue_cycle(1'b1, 1'b0, 1'b1, HTRANS_NONSEQ, 32'h8000_1234, 32'h0000_0000, "decode interrupt");
        issue_cycle(1'b1, 1'b0, 1'b1, HTRANS_NONSEQ, 32'h8400_1234, 32'h0000_0000, "decode timer");
        issue_cycle(1'b1, 1'b0, 1'b1, HTRANS_NONSEQ, 32'h8800_1234, 32'h0000_0000, "decode remap");
        issue_cycle(1'b1, 1'b0, 1'b1, HTRANS_NONSEQ, 32'h8C00_0000, 32'h0000_0000, "decode invalid");

        print_test("TEST 4: Single write transfer");
        issue_cycle(1'b1, 1'b1, 1'b1, HTRANS_NONSEQ, 32'h8000_0100, 32'hAAAA_AAAA, "single write address");
        issue_cycle(1'b0, 1'b0, 1'b1, HTRANS_IDLE,   32'h0000_0000, 32'h1234_5678, "single write data");
        issue_cycle(1'b0, 1'b0, 1'b1, HTRANS_IDLE,   32'h0000_0000, 32'hDEAD_BEEF, "single write pipeline");

        print_test("TEST 5: Single read transfer");
        issue_cycle(1'b1, 1'b0, 1'b1, HTRANS_NONSEQ, 32'h8400_0200, 32'hCAFE_BABE, "single read address");
        issue_cycle(1'b0, 1'b0, 1'b1, HTRANS_IDLE,   32'h0000_0000, 32'hFACE_FACE, "single read idle");

        print_test("TEST 6: Back-to-back writes");
        issue_cycle(1'b1, 1'b1, 1'b1, HTRANS_NONSEQ, 32'h8000_1000, 32'h0000_0000, "btb write A0");
        issue_cycle(1'b1, 1'b1, 1'b1, HTRANS_SEQ,    32'h8400_1004, 32'hD000_0000, "btb write A1 data D0");
        issue_cycle(1'b0, 1'b0, 1'b1, HTRANS_IDLE,   32'h0000_0000, 32'hD111_1111, "btb data D1");
        issue_cycle(1'b0, 1'b0, 1'b1, HTRANS_IDLE,   32'h0000_0000, 32'h0000_0000, "btb pipeline drain");

        print_test("TEST 7: Burst-style writes");
        issue_cycle(1'b1, 1'b1, 1'b1, HTRANS_NONSEQ, 32'h8000_2000, 32'h0000_0000, "burst A0");
        issue_cycle(1'b1, 1'b1, 1'b1, HTRANS_SEQ,    32'h8000_2004, 32'hB000_0000, "burst A1 D0");
        issue_cycle(1'b1, 1'b1, 1'b1, HTRANS_SEQ,    32'h8000_2008, 32'hB111_1111, "burst A2 D1");
        issue_cycle(1'b1, 1'b1, 1'b1, HTRANS_SEQ,    32'h8000_200C, 32'hB222_2222, "burst A3 D2");
        issue_cycle(1'b0, 1'b0, 1'b1, HTRANS_IDLE,   32'h0000_0000, 32'hB333_3333, "burst D3");
        issue_cycle(1'b0, 1'b0, 1'b1, HTRANS_IDLE,   32'h0000_0000, 32'h0000_0000, "burst drain");

        print_test("TEST 8: Hreadyin stall");
        issue_cycle(1'b1, 1'b1, 1'b0, HTRANS_NONSEQ, 32'h8800_3000, 32'h9999_9999, "stall no accept");
        issue_cycle(1'b1, 1'b1, 1'b1, HTRANS_NONSEQ, 32'h8800_3000, 32'h0000_0000, "stall released address");
        issue_cycle(1'b0, 1'b0, 1'b1, HTRANS_IDLE,   32'h0000_0000, 32'h9999_9999, "stall released data");

        print_test("TEST 9: IDLE and BUSY transfers");
        issue_cycle(1'b1, 1'b1, 1'b1, HTRANS_IDLE, 32'h8000_4000, 32'h4444_0000, "idle transfer");
        issue_cycle(1'b1, 1'b1, 1'b1, HTRANS_BUSY, 32'h8400_4000, 32'h4444_1111, "busy transfer");

        print_test("TEST 10: Boundary address decode");
        issue_cycle(1'b1, 1'b0, 1'b1, HTRANS_NONSEQ, 32'h8000_0000, 32'h0000_0000, "boundary 80000000");
        issue_cycle(1'b1, 1'b0, 1'b1, HTRANS_NONSEQ, 32'h83FF_FFFF, 32'h0000_0000, "boundary 83ffffff");
        issue_cycle(1'b1, 1'b0, 1'b1, HTRANS_NONSEQ, 32'h8400_0000, 32'h0000_0000, "boundary 84000000");
        issue_cycle(1'b1, 1'b0, 1'b1, HTRANS_NONSEQ, 32'h87FF_FFFF, 32'h0000_0000, "boundary 87ffffff");
        issue_cycle(1'b1, 1'b0, 1'b1, HTRANS_NONSEQ, 32'h8800_0000, 32'h0000_0000, "boundary 88000000");
        issue_cycle(1'b1, 1'b0, 1'b1, HTRANS_NONSEQ, 32'h8BFF_FFFF, 32'h0000_0000, "boundary 8bffffff");

        print_test("TEST 11: Undefined address space");
        issue_cycle(1'b1, 1'b0, 1'b1, HTRANS_NONSEQ, 32'h7FFF_FFFF, 32'h0000_0000, "undefined below");
        issue_cycle(1'b1, 1'b0, 1'b1, HTRANS_NONSEQ, 32'h8C00_0000, 32'h0000_0000, "undefined upper start");
        issue_cycle(1'b1, 1'b0, 1'b1, HTRANS_NONSEQ, 32'hBFFF_FFFF, 32'h0000_0000, "undefined upper end");
        issue_cycle(1'b1, 1'b0, 1'b1, HTRANS_NONSEQ, 32'hC000_0000, 32'h0000_0000, "undefined above");

        print_test("TEST 12: Randomized testing");
        for (rand_i = 0; rand_i < 500; rand_i++) begin
            issue_cycle($urandom_range(0, 1),
                        $urandom_range(0, 1),
                        $urandom_range(0, 1),
                        $urandom_range(0, 3),
                        $urandom(),
                        $urandom(),
                        "random");
        end

        $display("");
        $display("========================================");
        $display("Verification summary");
        $display("Checks : %0d", checks);
        $display("Errors : %0d", errors);
        if (errors == 0) begin
            $display("RESULT : PASS");
        end
        else begin
            $display("RESULT : FAIL");
        end
        $display("========================================");

        $finish;
    end

endmodule
