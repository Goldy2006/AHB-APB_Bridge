module apb_controller (
    // -------------------------------------------------------------------------
    // Module ports
    // -------------------------------------------------------------------------
    input  logic        Hclk,
    input  logic        Hresetn,

    input  logic        valid,
    input  logic [31:0] Haddr1,
    input  logic [31:0] Haddr2,
    input  logic [31:0] Hwdata1,
    input  logic [31:0] Hwdata2,
    input  logic        Hwritereg,
    input  logic [2:0]  tempselx1,
    input  logic [2:0]  tempselx2,

    output logic [31:0] Paddr,
    output logic [31:0] Pwdata,
    output logic        Pwrite,
    output logic        Penable,
    output logic [2:0]  Pselx,
    output logic        Hreadyout
);

    // -------------------------------------------------------------------------
    // FSM state encoding
    // -------------------------------------------------------------------------
    typedef enum logic [2:0] {
        ST_IDLE,
        ST_WWAIT,
        ST_READ,
        ST_WRITE,
        ST_WRITEP,
        ST_RENABLE,
        ST_WENABLE,
        ST_WENABLEP
    } state_t;

    state_t present_state;
    state_t next_state;

    logic [31:0] paddr_hold;
    logic [31:0] pwdata_hold;
    logic        pwrite_hold;
    logic [2:0]  pselx_hold;

    logic [31:0] setup_paddr;
    logic [31:0] setup_pwdata;
    logic        setup_pwrite;
    logic [2:0]  setup_pselx;

    logic        setup_phase;

    assign setup_phase = (present_state == ST_READ)   ||
                         (present_state == ST_WRITE)  ||
                         (present_state == ST_WRITEP);

    // -------------------------------------------------------------------------
    // Sequential state register
    // -------------------------------------------------------------------------
    always_ff @(posedge Hclk or negedge Hresetn) begin
        if (!Hresetn) begin
            present_state <= ST_IDLE;
            paddr_hold    <= 32'h0000_0000;
            pwdata_hold   <= 32'h0000_0000;
            pwrite_hold   <= 1'b0;
            pselx_hold    <= 3'b000;
        end
        else begin
            present_state <= next_state;

            // Capture the APB setup values so the following access phase holds
            // address, data, select, and control stable while Penable is high.
            if (setup_phase) begin
                paddr_hold  <= setup_paddr;
                pwdata_hold <= setup_pwdata;
                pwrite_hold <= setup_pwrite;
                pselx_hold  <= setup_pselx;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Next-state combinational logic
    // -------------------------------------------------------------------------
    always_comb begin
        next_state = present_state;

        unique case (present_state)
            ST_IDLE: begin
                // Start a new APB sequence only when the AHB side has a valid
                // decoded transfer available.
                if (valid && Hwritereg) begin
                    next_state = ST_WWAIT;
                end
                else if (valid && !Hwritereg) begin
                    next_state = ST_READ;
                end
            end

            ST_WWAIT: begin
                // Insert one wait cycle before the write setup phase. If a new
                // transfer is already pending, use the pipelined write path.
                if (valid) begin
                    next_state = ST_WRITEP;
                end
                else begin
                    next_state = ST_WRITE;
                end
            end

            ST_READ: begin
                // Read setup phase is followed by the APB access phase.
                next_state = ST_RENABLE;
            end

            ST_RENABLE: begin
                // After the read access phase, immediately sequence the next
                // pending transfer or return to idle when there is none.
                if (valid && Hwritereg) begin
                    next_state = ST_WWAIT;
                end
                else if (valid && !Hwritereg) begin
                    next_state = ST_READ;
                end
                else begin
                    next_state = ST_IDLE;
                end
            end

            ST_WRITE: begin
                // Write setup phase is followed by the APB access phase.
                next_state = ST_WENABLE;
            end

            ST_WENABLE: begin
                // Complete the write access phase, then continue with any
                // pending transfer from the AHB pipeline.
                if (valid && Hwritereg) begin
                    next_state = ST_WRITEP;
                end
                else if (valid && !Hwritereg) begin
                    next_state = ST_READ;
                end
                else begin
                    next_state = ST_IDLE;
                end
            end

            ST_WRITEP: begin
                // Pipelined write setup uses the write data currently aligned
                // with the second-stage address.
                next_state = ST_WENABLEP;
            end

            ST_WENABLEP: begin
                // Complete the pipelined write access phase, then keep taking
                // pending transfers without returning to idle.
                if (valid && Hwritereg) begin
                    next_state = ST_WRITEP;
                end
                else if (valid && !Hwritereg) begin
                    next_state = ST_READ;
                end
                else begin
                    next_state = ST_IDLE;
                end
            end

            default: begin
                next_state = ST_IDLE;
            end
        endcase
    end

    // -------------------------------------------------------------------------
    // Output combinational logic
    // -------------------------------------------------------------------------
    always_comb begin
        // Defaults keep APB outputs inactive and avoid inferred latches.
        setup_paddr  = 32'h0000_0000;
        setup_pwdata = 32'h0000_0000;
        setup_pwrite = 1'b0;
        setup_pselx  = 3'b000;

        Paddr   = 32'h0000_0000;
        Pwdata  = 32'h0000_0000;
        Pwrite  = 1'b0;
        Penable = 1'b0;
        Pselx   = 3'b000;
        Hreadyout = 1'b0;

        unique case (present_state)
            ST_IDLE: begin
                // Ready for a new AHB address phase only when no registered
                // transfer is waiting to be sequenced into APB setup/access.
                Hreadyout = !valid;
            end

            ST_READ: begin
                // APB read setup phase: assert select and address with
                // Penable low for one cycle.
                setup_pselx  = tempselx1;
                setup_paddr  = Haddr1;
                setup_pwrite = 1'b0;

                Pselx        = setup_pselx;
                Paddr        = setup_paddr;
                Pwrite       = setup_pwrite;
                Penable      = 1'b0;
                Hreadyout    = 1'b0;
            end

            ST_RENABLE: begin
                // APB read access phase: use captured setup values so the
                // transfer remains stable while Penable is asserted.
                Pselx   = pselx_hold;
                Paddr   = paddr_hold;
                Pwdata  = pwdata_hold;
                Pwrite  = pwrite_hold;
                Penable = (pselx_hold != 3'b000);
                Hreadyout = 1'b0;
            end

            ST_WRITE: begin
                // APB write setup phase for a non-pipelined write transfer.
                setup_pselx  = tempselx2;
                setup_paddr  = Haddr2;
                setup_pwdata = Hwdata2;
                setup_pwrite = 1'b1;

                Pselx        = setup_pselx;
                Paddr        = setup_paddr;
                Pwdata       = setup_pwdata;
                Pwrite       = setup_pwrite;
                Penable      = 1'b0;
                Hreadyout    = 1'b0;
            end

            ST_WENABLE: begin
                // APB write access phase: drive only the captured setup values.
                Pselx   = pselx_hold;
                Paddr   = paddr_hold;
                Pwdata  = pwdata_hold;
                Pwrite  = pwrite_hold;
                Penable = (pselx_hold != 3'b000);
                Hreadyout = 1'b0;
            end

            ST_WRITEP: begin
                // APB setup phase for a pipelined write.
                setup_pselx  = tempselx2;
                setup_paddr  = Haddr2;
                setup_pwdata = Hwdata2;
                setup_pwrite = 1'b1;

                Pselx        = setup_pselx;
                Paddr        = setup_paddr;
                Pwdata       = setup_pwdata;
                Pwrite       = setup_pwrite;
                Penable      = 1'b0;
                Hreadyout    = 1'b0;
            end

            ST_WENABLEP: begin
                // APB access phase for a pipelined write: hold captured setup.
                Pselx   = pselx_hold;
                Paddr   = paddr_hold;
                Pwdata  = pwdata_hold;
                Pwrite  = pwrite_hold;
                Penable = (pselx_hold != 3'b000);
                Hreadyout = 1'b0;
            end

            default: begin
                // ST_IDLE and ST_WWAIT keep the APB bus inactive.
            end
        endcase
    end

endmodule
