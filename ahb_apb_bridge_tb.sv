`timescale 1ns/1ps

module ahb_apb_bridge_tb;

    localparam logic [1:0] HTRANS_IDLE   = 2'b00;
    localparam logic [1:0] HTRANS_NONSEQ = 2'b10;
    localparam logic [1:0] HTRANS_SEQ    = 2'b11;

    localparam logic [2:0] ST_IDLE     = 3'd0;
    localparam logic [2:0] ST_WWAIT    = 3'd1;
    localparam logic [2:0] ST_READ     = 3'd2;
    localparam logic [2:0] ST_WRITE    = 3'd3;
    localparam logic [2:0] ST_WRITEP   = 3'd4;
    localparam logic [2:0] ST_RENABLE  = 3'd5;
    localparam logic [2:0] ST_WENABLE  = 3'd6;
    localparam logic [2:0] ST_WENABLEP = 3'd7;

    localparam int MAX_EXPECTED = 4096;
    localparam int MAX_ERROR_PRINTS = 100;

    typedef struct packed {
        bit          write;
        logic [31:0] addr;
        logic [31:0] data;
        logic [2:0]  sel;
    } apb_item_t;

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    logic        Hclk;
    logic        Hresetn;
    logic        HSEL;
    logic        Hwrite;
    logic        Hreadyin;
    logic [1:0]  Htrans;
    logic [31:0] Haddr;
    logic [31:0] Hwdata;

    logic [1:0]  Hresp;
    logic [31:0] Hrdata;
    logic        Hreadyout;
    logic        apb_readyout;

    logic        valid;
    logic [31:0] Haddr1;
    logic [31:0] Haddr2;
    logic [31:0] Hwdata1;
    logic [31:0] Hwdata2;
    logic        Hwritereg;
    logic [2:0]  tempselx1;
    logic [2:0]  tempselx2;

    logic [31:0] Paddr;
    logic [31:0] Pwdata;
    logic        Pwrite;
    logic        Penable;
    logic [2:0]  Pselx;

    // -------------------------------------------------------------------------
    // Scoreboard and coverage helpers
    // -------------------------------------------------------------------------
    apb_item_t active_item;
    bit          exp_write_q [MAX_EXPECTED];
    logic [31:0] exp_addr_q  [MAX_EXPECTED];
    logic [31:0] exp_data_q  [MAX_EXPECTED];
    logic [2:0]  exp_sel_q   [MAX_EXPECTED];
    int exp_wr;
    int exp_rd;
    int checks;
    int errors;
    int reset_during_transfer_count;
    bit monitor_enable;
    bit access_pending;
    logic [2:0] prev_state;
    logic [31:0] setup_addr;
    logic [31:0] setup_wdata;
    logic        setup_write;
    logic [2:0]  setup_sel;
    logic [2:0]  cov_state;
    logic [2:0]  cov_prev_state;
    logic        cov_is_write;
    logic [2:0]  cov_sel;
    logic [31:0] cov_addr;

`ifndef __ICARUS__
    covergroup bridge_cg;
        option.per_instance = 1;

        cp_state: coverpoint cov_state {
            bins idle     = {ST_IDLE};
            bins wwait    = {ST_WWAIT};
            bins read     = {ST_READ};
            bins write    = {ST_WRITE};
            bins writep   = {ST_WRITEP};
            bins renable  = {ST_RENABLE};
            bins wenable  = {ST_WENABLE};
            bins wenablep = {ST_WENABLEP};
        }

        cp_transition: coverpoint {cov_prev_state, cov_state} {
            bins idle_wwait       = {{ST_IDLE, ST_WWAIT}};
            bins idle_read        = {{ST_IDLE, ST_READ}};
            bins wwait_write      = {{ST_WWAIT, ST_WRITE}};
            bins wwait_writep     = {{ST_WWAIT, ST_WRITEP}};
            bins read_renable     = {{ST_READ, ST_RENABLE}};
            bins renable_idle     = {{ST_RENABLE, ST_IDLE}};
            bins renable_read     = {{ST_RENABLE, ST_READ}};
            bins renable_wwait    = {{ST_RENABLE, ST_WWAIT}};
            bins write_wenable    = {{ST_WRITE, ST_WENABLE}};
            bins wenable_idle     = {{ST_WENABLE, ST_IDLE}};
            bins wenable_read     = {{ST_WENABLE, ST_READ}};
            bins wenable_writep   = {{ST_WENABLE, ST_WRITEP}};
            bins writep_wenablep  = {{ST_WRITEP, ST_WENABLEP}};
            bins wenablep_idle    = {{ST_WENABLEP, ST_IDLE}};
            bins wenablep_read    = {{ST_WENABLEP, ST_READ}};
            bins wenablep_writep  = {{ST_WENABLEP, ST_WRITEP}};
        }

        cp_rw: coverpoint cov_is_write {
            bins read  = {1'b0};
            bins write = {1'b1};
        }

        cp_peripheral: coverpoint cov_sel {
            bins none = {3'b000};
            bins p1   = {3'b001};
            bins p2   = {3'b010};
            bins p3   = {3'b100};
        }

        cp_boundaries: coverpoint cov_addr {
            bins p1_low  = {32'h8000_0000};
            bins p1_high = {32'h83FF_FFFF};
            bins p2_low  = {32'h8400_0000};
            bins p2_high = {32'h87FF_FFFF};
            bins p3_low  = {32'h8800_0000};
            bins p3_high = {32'h8BFF_FFFF};
            bins invalid = {32'h9000_0000};
        }

        cp_reset_during_transfer: coverpoint reset_during_transfer_count {
            bins seen = {[1:$]};
        }
    endgroup

    bridge_cg cg = new();
`endif

    // -------------------------------------------------------------------------
    // DUT instantiation: final bridge connection
    // -------------------------------------------------------------------------
    ahb_slave_interface ahb_dut (
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

    apb_controller apb_dut (
        .Hclk      (Hclk),
        .Hresetn   (Hresetn),
        .valid     (valid),
        .Haddr1    (Haddr1),
        .Haddr2    (Haddr2),
        .Hwdata1   (Hwdata1),
        .Hwdata2   (Hwdata2),
        .Hwritereg (Hwritereg),
        .tempselx1 (tempselx1),
        .tempselx2 (tempselx2),
        .Paddr     (Paddr),
        .Pwdata    (Pwdata),
        .Pwrite    (Pwrite),
        .Penable   (Penable),
        .Pselx     (Pselx),
        .Hreadyout (apb_readyout)
    );

    // -------------------------------------------------------------------------
    // Clock and helpers
    // -------------------------------------------------------------------------
    initial begin
        Hclk = 1'b0;
        forever #5 Hclk = ~Hclk;
    end

    initial begin
        $dumpfile("ahb_apb_bridge_tb.vcd");
        $dumpvars(0, ahb_apb_bridge_tb);
    end

    function automatic logic [2:0] decode_sel(input logic [31:0] addr);
        begin
            if ((addr >= 32'h8000_0000) && (addr <= 32'h83FF_FFFF)) begin
                decode_sel = 3'b001;
            end
            else if ((addr >= 32'h8400_0000) && (addr <= 32'h87FF_FFFF)) begin
                decode_sel = 3'b010;
            end
            else if ((addr >= 32'h8800_0000) && (addr <= 32'h8BFF_FFFF)) begin
                decode_sel = 3'b100;
            end
            else begin
                decode_sel = 3'b000;
            end
        end
    endfunction

    function automatic string state_name(input logic [2:0] state);
        begin
            case (state)
                ST_IDLE:     state_name = "ST_IDLE";
                ST_WWAIT:    state_name = "ST_WWAIT";
                ST_READ:     state_name = "ST_READ";
                ST_WRITE:    state_name = "ST_WRITE";
                ST_WRITEP:   state_name = "ST_WRITEP";
                ST_RENABLE:  state_name = "ST_RENABLE";
                ST_WENABLE:  state_name = "ST_WENABLE";
                ST_WENABLEP: state_name = "ST_WENABLEP";
                default:     state_name = "ILLEGAL";
            endcase
        end
    endfunction

    function automatic bit is_legal_state(input logic [2:0] state);
        begin
            case (state)
                ST_IDLE, ST_WWAIT, ST_READ, ST_WRITE, ST_WRITEP,
                ST_RENABLE, ST_WENABLE, ST_WENABLEP: is_legal_state = 1'b1;
                default: is_legal_state = 1'b0;
            endcase
        end
    endfunction

    task automatic record_check(input bit pass, input string msg);
        begin
            checks++;
            if (!pass) begin
                errors++;
                if (errors <= MAX_ERROR_PRINTS) begin
                    $error("FAIL: %s", msg);
                end
                else if (errors == (MAX_ERROR_PRINTS + 1)) begin
                    $display("Additional failures suppressed after %0d errors.", MAX_ERROR_PRINTS);
                end
            end
        end
    endtask

    task automatic reset_scoreboard();
        begin
            exp_wr         = 0;
            exp_rd         = 0;
            access_pending = 1'b0;
            monitor_enable = 1'b1;
        end
    endtask

    task automatic push_expected(input bit write,
                                 input logic [31:0] addr,
                                 input logic [31:0] data);
        logic [2:0] decoded_sel;
        begin
            decoded_sel = decode_sel(addr);
            if (decoded_sel != 3'b000) begin
                record_check(exp_wr < MAX_EXPECTED, "expected queue overflow");
                exp_write_q[exp_wr] = write;
                exp_addr_q[exp_wr]  = addr;
                exp_data_q[exp_wr]  = data;
                exp_sel_q[exp_wr]   = decoded_sel;
                exp_wr++;
            end
        end
    endtask

    task automatic check_apb_item(input apb_item_t exp, input bit access_phase);
        begin
            record_check(Pselx === exp.sel,
                         $sformatf("Pselx actual=%b expected=%b", Pselx, exp.sel));
            record_check(Paddr === exp.addr,
                         $sformatf("Paddr actual=0x%08h expected=0x%08h", Paddr, exp.addr));
            record_check(Pwrite === exp.write,
                         $sformatf("Pwrite actual=%0b expected=%0b", Pwrite, exp.write));
            record_check(Penable === access_phase,
                         $sformatf("Penable actual=%0b expected=%0b", Penable, access_phase));
            if (exp.write) begin
                record_check(Pwdata === exp.data,
                             $sformatf("Pwdata actual=0x%08h expected=0x%08h", Pwdata, exp.data));
            end
        end
    endtask

    task automatic expect_state(input logic [2:0] exp_state, input string tag);
        begin
            #1;
            record_check(apb_dut.present_state === exp_state,
                         $sformatf("%s state actual=%s expected=%s",
                                   tag,
                                   state_name(apb_dut.present_state),
                                   state_name(exp_state)));
        end
    endtask

    task automatic drive_cycle(input logic        sel,
                               input logic        write,
                               input logic [1:0]  trans,
                               input logic [31:0] addr,
                               input logic [31:0] data);
        begin
            @(negedge Hclk);
            HSEL     = sel;
            Hwrite   = write;
            Hreadyin = 1'b1;
            Htrans   = trans;
            Haddr    = addr;
            Hwdata   = data;
            do begin
                @(posedge Hclk);
            end while (Hreadyout !== 1'b1);
        end
    endtask

    task automatic ahb_idle();
        begin
            drive_cycle(1'b0, 1'b0, HTRANS_IDLE, 32'h0000_0000, 32'h0000_0000);
        end
    endtask

    task automatic ahb_write(input [31:0] addr,
                             input [31:0] data);
        begin
            push_expected(1'b1, addr, data);
            drive_cycle(1'b1, 1'b1, HTRANS_NONSEQ, addr, 32'h0000_0000);
            drive_cycle(1'b0, 1'b0, HTRANS_IDLE, 32'h0000_0000, data);
        end
    endtask

    task automatic ahb_read(input [31:0] addr);
        begin
            push_expected(1'b0, addr, 32'h0000_0000);
            drive_cycle(1'b1, 1'b0, HTRANS_NONSEQ, addr, 32'h0000_0000);
        end
    endtask

    task automatic apply_reset(input int cycles);
        begin
            @(negedge Hclk);
            Hresetn  = 1'b0;
            HSEL     = 1'b0;
            Hwrite   = 1'b0;
            Hreadyin = 1'b1;
            Htrans   = HTRANS_IDLE;
            Haddr    = 32'h0000_0000;
            Hwdata   = 32'h0000_0000;
            repeat (cycles) @(posedge Hclk);
            #1;
            record_check(apb_dut.present_state === ST_IDLE, "reset state is ST_IDLE");
            record_check(Haddr1 === 32'h0000_0000, "reset Haddr1");
            record_check(Haddr2 === 32'h0000_0000, "reset Haddr2");
            record_check(Hwdata1 === 32'h0000_0000, "reset Hwdata1");
            record_check(Hwdata2 === 32'h0000_0000, "reset Hwdata2");
            record_check(Hwritereg === 1'b0, "reset Hwritereg");
            record_check(tempselx1 === 3'b000, "reset tempselx1");
            record_check(tempselx2 === 3'b000, "reset tempselx2");
            record_check(Pselx === 3'b000, "reset Pselx inactive");
            record_check(Penable === 1'b0, "reset Penable inactive");
            record_check(Pwrite === 1'b0, "reset Pwrite inactive");
            @(negedge Hclk);
            Hresetn = 1'b1;
        end
    endtask

    task automatic finish_pending(int max_cycles);
        int i;
        begin
            for (i = 0; i < max_cycles; i++) begin
                ahb_idle();
                if ((apb_dut.present_state === ST_IDLE) && (exp_rd == exp_wr) && !access_pending) begin
                    i = max_cycles;
                end
            end
        end
    endtask

    task automatic check_no_x_outputs(input string tag);
        begin
            record_check(!$isunknown({Paddr, Pwdata, Pwrite, Penable, Pselx}),
                         {tag, " APB outputs contain no X/Z"});
        end
    endtask

    task automatic reset_during_state(input logic [2:0] target_state, input string tag);
        int guard;
        bit found;
        begin
            reset_scoreboard();
            monitor_enable = 1'b0;
            found = 1'b0;
            drive_cycle(1'b1, 1'b1, HTRANS_NONSEQ, 32'h8000_0100, 32'h0000_0000);
            @(negedge Hclk);
            HSEL     = 1'b0;
            Hwrite   = 1'b0;
            Hreadyin = 1'b1;
            Htrans   = HTRANS_IDLE;
            Haddr    = 32'h0000_0000;
            Hwdata   = 32'hCAFE_0000 | target_state;
            for (guard = 0; guard < 12; guard++) begin
                @(posedge Hclk);
                #1;
                if (apb_dut.present_state === target_state) begin
                    found = 1'b1;
                    reset_during_transfer_count++;
                    @(negedge Hclk);
                    Hresetn = 1'b0;
                    @(posedge Hclk);
                    #1;
                    record_check(apb_dut.present_state === ST_IDLE, {tag, " reset returns FSM to IDLE"});
                    record_check(Pselx === 3'b000, {tag, " reset clears Pselx"});
                    record_check(Penable === 1'b0, {tag, " reset clears Penable"});
                    record_check(Pwrite === 1'b0, {tag, " reset clears Pwrite"});
                    @(negedge Hclk);
                    Hresetn = 1'b1;
                    reset_scoreboard();
                    guard = 12;
                end
            end
            if (!found) begin
                record_check(1'b0, {tag, " target state was not reached"});
            end
        end
    endtask

    // -------------------------------------------------------------------------
    // Runtime monitor and assertions
    // -------------------------------------------------------------------------
    always @(posedge Hclk or negedge Hresetn) begin
        if (!Hresetn) begin
            access_pending <= 1'b0;
            prev_state     <= ST_IDLE;
        end
        else begin
            #1;

            cov_prev_state = prev_state;
            cov_state      = apb_dut.present_state;
            cov_is_write   = Pwrite;
            cov_sel        = Pselx;
            cov_addr       = Paddr;
`ifndef __ICARUS__
            cg.sample();
`endif

            record_check(!$isunknown(apb_dut.present_state), "FSM state is known");
            record_check(is_legal_state(apb_dut.present_state),
                         $sformatf("FSM illegal state %0d", apb_dut.present_state));

            if (Penable && (Pselx == 3'b000)) begin
                record_check(1'b0, "PENABLE asserted while Pselx is zero");
            end

            if (Penable) begin
                record_check(access_pending, "ACCESS phase occurred without previous SETUP phase");
                record_check(Paddr === setup_addr, "Paddr changed from SETUP to ACCESS");
                record_check(Pwrite === setup_write, "Pwrite changed from SETUP to ACCESS");
                record_check(Pselx === setup_sel, "Pselx changed from SETUP to ACCESS");
                if (Pwrite) begin
                    record_check(Pwdata === setup_wdata, "Pwdata changed from SETUP to ACCESS");
                end
                if (monitor_enable && access_pending) begin
                    check_apb_item(active_item, 1'b1);
                    exp_rd++;
                end
                access_pending <= 1'b0;
            end
            else if (Pselx != 3'b000) begin
                record_check(!access_pending, "new SETUP phase before previous ACCESS phase");
                if (monitor_enable) begin
                    record_check(exp_rd < exp_wr, "unexpected APB SETUP transfer");
                    active_item.write = exp_write_q[exp_rd];
                    active_item.addr  = exp_addr_q[exp_rd];
                    active_item.data  = exp_data_q[exp_rd];
                    active_item.sel   = exp_sel_q[exp_rd];
                    check_apb_item(active_item, 1'b0);
                end
                setup_addr    <= Paddr;
                setup_wdata   <= Pwdata;
                setup_write   <= Pwrite;
                setup_sel     <= Pselx;
                access_pending <= 1'b1;
            end
            else begin
                record_check(!access_pending, "APB SETUP was not followed by ACCESS");
            end

            prev_state <= apb_dut.present_state;
        end
    end

    // -------------------------------------------------------------------------
    // Directed tests
    // -------------------------------------------------------------------------
    task automatic test_reset_behavior();
        begin
            $display("TEST 1: Reset Behavior");
            reset_scoreboard();
            apply_reset(4);
            finish_pending(3);
        end
    endtask

    task automatic test_single_write();
        begin
            $display("TEST 2: Single Write Transfer");
            reset_scoreboard();
            ahb_write(32'h8000_0010, 32'hDEAD_BEEF);
            finish_pending(4);
        end
    endtask

    task automatic test_single_read();
        begin
            $display("TEST 3: Single Read Transfer");
            reset_scoreboard();
            ahb_read(32'h8400_0020);
            ahb_idle();
            finish_pending(4);
        end
    endtask

    task automatic test_back_to_back_writes();
        begin
            $display("TEST 4: Back-to-Back Writes");
            reset_scoreboard();
            push_expected(1'b1, 32'h8000_0100, 32'hAAAA_0001);
            push_expected(1'b1, 32'h8400_0104, 32'hBBBB_0002);
            push_expected(1'b1, 32'h8800_0108, 32'hCCCC_0003);
            drive_cycle(1'b1, 1'b1, HTRANS_NONSEQ, 32'h8000_0100, 32'h0000_0000);
            drive_cycle(1'b1, 1'b1, HTRANS_SEQ,    32'h8400_0104, 32'hAAAA_0001);
            drive_cycle(1'b1, 1'b1, HTRANS_SEQ,    32'h8800_0108, 32'hBBBB_0002);
            drive_cycle(1'b0, 1'b0, HTRANS_IDLE,   32'h0000_0000, 32'hCCCC_0003);
            finish_pending(12);
        end
    endtask

    task automatic test_back_to_back_reads();
        begin
            $display("TEST 5: Back-to-Back Reads");
            reset_scoreboard();
            push_expected(1'b0, 32'h8000_0200, 32'h0000_0000);
            push_expected(1'b0, 32'h8400_0204, 32'h0000_0000);
            push_expected(1'b0, 32'h8800_0208, 32'h0000_0000);
            drive_cycle(1'b1, 1'b0, HTRANS_NONSEQ, 32'h8000_0200, 32'h0000_0000);
            drive_cycle(1'b1, 1'b0, HTRANS_SEQ,    32'h8400_0204, 32'h0000_0000);
            drive_cycle(1'b1, 1'b0, HTRANS_SEQ,    32'h8800_0208, 32'h0000_0000);
            ahb_idle();
            finish_pending(12);
        end
    endtask

    task automatic test_write_read_transition();
        begin
            $display("TEST 6: Write -> Read Transition");
            reset_scoreboard();
            push_expected(1'b1, 32'h8000_0300, 32'h1234_5678);
            push_expected(1'b0, 32'h8400_0304, 32'h0000_0000);
            drive_cycle(1'b1, 1'b1, HTRANS_NONSEQ, 32'h8000_0300, 32'h0000_0000);
            drive_cycle(1'b1, 1'b0, HTRANS_SEQ,    32'h8400_0304, 32'h1234_5678);
            ahb_idle();
            finish_pending(12);
        end
    endtask

    task automatic test_read_write_transition();
        begin
            $display("TEST 7: Read -> Write Transition");
            reset_scoreboard();
            push_expected(1'b0, 32'h8400_0400, 32'h0000_0000);
            push_expected(1'b1, 32'h8800_0404, 32'hFACE_CAFE);
            drive_cycle(1'b1, 1'b0, HTRANS_NONSEQ, 32'h8400_0400, 32'h0000_0000);
            drive_cycle(1'b1, 1'b1, HTRANS_SEQ,    32'h8800_0404, 32'h0000_0000);
            drive_cycle(1'b0, 1'b0, HTRANS_IDLE,   32'h0000_0000, 32'hFACE_CAFE);
            finish_pending(12);
        end
    endtask

    task automatic test_peripheral_switching();
        begin
            $display("TEST 8: Peripheral Switching");
            reset_scoreboard();
            ahb_read(32'h8000_0000);
            ahb_read(32'h8400_0000);
            ahb_read(32'h8800_0000);
            ahb_idle();
            finish_pending(16);
        end
    endtask

    task automatic test_invalid_address();
        begin
            $display("TEST 9: Invalid Address");
            reset_scoreboard();
            ahb_read(32'h9000_0000);
            ahb_idle();
            repeat (4) begin
                @(posedge Hclk);
                #1;
                record_check(Pselx === 3'b000, "invalid address keeps Pselx deasserted");
            end
            finish_pending(4);
        end
    endtask

    task automatic test_reset_during_active_transfer();
        begin
            $display("TEST 10: Reset During Active Transfer");
            reset_during_state(ST_WRITE,   "reset during WRITE");
            reset_during_state(ST_WENABLE, "reset during WENABLE");
            reset_scoreboard();
            monitor_enable = 1'b0;
            drive_cycle(1'b1, 1'b0, HTRANS_NONSEQ, 32'h8400_0500, 32'h0000_0000);
            for (int guard = 0; guard < 8; guard++) begin
                @(posedge Hclk);
                #1;
                if (apb_dut.present_state === ST_READ) begin
                    reset_during_transfer_count++;
                    @(negedge Hclk);
                    Hresetn = 1'b0;
                    HSEL     = 1'b0;
                    Hwrite   = 1'b0;
                    Htrans   = HTRANS_IDLE;
                    Haddr    = 32'h0000_0000;
                    Hwdata   = 32'h0000_0000;
                    @(posedge Hclk);
                    #1;
                    record_check(apb_dut.present_state === ST_IDLE, "reset during READ returns FSM to IDLE");
                    @(negedge Hclk);
                    Hresetn = 1'b1;
                    reset_scoreboard();
                    guard = 8;
                end
            end
            reset_scoreboard();
            monitor_enable = 1'b0;
            drive_cycle(1'b1, 1'b0, HTRANS_NONSEQ, 32'h8400_0504, 32'h0000_0000);
            for (int guard = 0; guard < 8; guard++) begin
                @(posedge Hclk);
                #1;
                if (apb_dut.present_state === ST_RENABLE) begin
                    reset_during_transfer_count++;
                    @(negedge Hclk);
                    Hresetn = 1'b0;
                    HSEL     = 1'b0;
                    Hwrite   = 1'b0;
                    Htrans   = HTRANS_IDLE;
                    Haddr    = 32'h0000_0000;
                    Hwdata   = 32'h0000_0000;
                    @(posedge Hclk);
                    #1;
                    record_check(apb_dut.present_state === ST_IDLE, "reset during RENABLE returns FSM to IDLE");
                    @(negedge Hclk);
                    Hresetn = 1'b1;
                    reset_scoreboard();
                    guard = 8;
                end
            end
            finish_pending(4);
        end
    endtask

    task automatic test_edge_writes_different_peripherals();
        begin
            $display("EDGE: Consecutive writes to different peripherals");
            reset_scoreboard();
            push_expected(1'b1, 32'h8000_1000, 32'h1111_1111);
            push_expected(1'b1, 32'h8400_1004, 32'h2222_2222);
            push_expected(1'b1, 32'h8800_1008, 32'h3333_3333);
            push_expected(1'b1, 32'h8000_100C, 32'h4444_4444);
            drive_cycle(1'b1, 1'b1, HTRANS_NONSEQ, 32'h8000_1000, 32'h0000_0000);
            drive_cycle(1'b1, 1'b1, HTRANS_SEQ,    32'h8400_1004, 32'h1111_1111);
            drive_cycle(1'b1, 1'b1, HTRANS_SEQ,    32'h8800_1008, 32'h2222_2222);
            drive_cycle(1'b1, 1'b1, HTRANS_SEQ,    32'h8000_100C, 32'h3333_3333);
            drive_cycle(1'b0, 1'b0, HTRANS_IDLE,   32'h0000_0000, 32'h4444_4444);
            finish_pending(16);
        end
    endtask

    task automatic test_boundary_addresses();
        logic [31:0] boundaries [0:6];
        begin
            $display("EDGE: Address boundary coverage");
            boundaries[0] = 32'h8000_0000;
            boundaries[1] = 32'h83FF_FFFF;
            boundaries[2] = 32'h8400_0000;
            boundaries[3] = 32'h87FF_FFFF;
            boundaries[4] = 32'h8800_0000;
            boundaries[5] = 32'h8BFF_FFFF;
            boundaries[6] = 32'h9000_0000;
            reset_scoreboard();
            foreach (boundaries[i]) begin
                ahb_read(boundaries[i]);
            end
            ahb_idle();
            finish_pending(24);
        end
    endtask

    task automatic test_random_traffic();
        logic [31:0] addr_pool [0:6];
        logic [31:0] rand_addr;
        logic [31:0] rand_data;
        bit          rand_write;
        int          i;
        begin
            $display("RANDOM: 750 mixed transactions");
            addr_pool[0] = 32'h8000_0000;
            addr_pool[1] = 32'h8000_1234;
            addr_pool[2] = 32'h8400_0000;
            addr_pool[3] = 32'h8400_5678;
            addr_pool[4] = 32'h8800_0000;
            addr_pool[5] = 32'h8800_9ABC;
            addr_pool[6] = 32'h9000_0000;
            reset_scoreboard();
            for (i = 0; i < 750; i++) begin
                rand_write = $urandom_range(0, 1);
                rand_addr  = addr_pool[$urandom_range(0, 6)] + ($urandom() & 32'h0000_00FC);
                rand_data  = $urandom();
                if (rand_write) begin
                    ahb_write(rand_addr, rand_data);
                end
                else begin
                    ahb_read(rand_addr);
                end
                if (($urandom_range(0, 4)) == 0) begin
                    ahb_idle();
                end
            end
            finish_pending(64);
        end
    endtask

    // -------------------------------------------------------------------------
    // Test sequence
    // -------------------------------------------------------------------------
    initial begin
        checks = 0;
        errors = 0;
        reset_during_transfer_count = 0;
        monitor_enable = 1'b1;
        access_pending = 1'b0;
        prev_state = ST_IDLE;

        Hresetn  = 1'b1;
        HSEL     = 1'b0;
        Hwrite   = 1'b0;
        Hreadyin = 1'b1;
        Htrans   = HTRANS_IDLE;
        Haddr    = 32'h0000_0000;
        Hwdata   = 32'h0000_0000;

        test_reset_behavior();
        test_single_write();
        test_single_read();
        test_back_to_back_writes();
        test_back_to_back_reads();
        test_write_read_transition();
        test_read_write_transition();
        test_peripheral_switching();
        test_invalid_address();
        test_reset_during_active_transfer();
        test_edge_writes_different_peripherals();
        test_boundary_addresses();
        test_random_traffic();

        repeat (5) begin
            ahb_idle();
            @(posedge Hclk);
        end

        $display("");
        $display("========================================");
        $display("AHB-to-APB bridge verification summary");
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
