module ahb_slave_interface (
    // -------------------------------------------------------------------------
    // Module ports
    // -------------------------------------------------------------------------
    input  logic        Hclk,
    input  logic        Hresetn,
    input  logic        HSEL,
    input  logic        Hwrite,
    input  logic        Hreadyin,
    input  logic [1:0]  Htrans,
    input  logic [31:0] Haddr,
    input  logic [31:0] Hwdata,
    input  logic        apb_readyout,

    output logic [1:0]  Hresp,
    output logic [31:0] Hrdata,
    output logic        Hreadyout,

    output logic        valid,
    output logic [31:0] Haddr1,
    output logic [31:0] Haddr2,
    output logic [31:0] Hwdata1,
    output logic [31:0] Hwdata2,
    output logic        Hwritereg,
    output logic [2:0]  tempselx1,
    output logic [2:0]  tempselx2
);

    // -------------------------------------------------------------------------
    // Internal registers
    // -------------------------------------------------------------------------
    logic       valid_next;
    logic       htrans_active;
    logic [2:0] tempselx_next;

    assign htrans_active = Htrans[1];

    // -------------------------------------------------------------------------
    // Combinational logic
    // -------------------------------------------------------------------------
    always_comb begin
        valid_next = HSEL && Hreadyin && apb_readyout && htrans_active;

        Hresp     = 2'b00;
        Hrdata    = 32'h0000_0000;
        Hreadyout = apb_readyout;

        tempselx_next = 3'b000;

        if ((Haddr >= 32'h8000_0000) && (Haddr <= 32'h83FF_FFFF)) begin
            tempselx_next = 3'b001;
        end
        else if ((Haddr >= 32'h8400_0000) && (Haddr <= 32'h87FF_FFFF)) begin
            tempselx_next = 3'b010;
        end
        else if ((Haddr >= 32'h8800_0000) && (Haddr <= 32'h8BFF_FFFF)) begin
            tempselx_next = 3'b100;
        end
    end

    // -------------------------------------------------------------------------
    // Sequential logic
    // -------------------------------------------------------------------------
    always_ff @(posedge Hclk or negedge Hresetn) begin
        if (!Hresetn) begin
            valid             <= 1'b0;
            Haddr1            <= 32'h0000_0000;
            Haddr2            <= 32'h0000_0000;
            Hwdata1           <= 32'h0000_0000;
            Hwdata2           <= 32'h0000_0000;
            Hwritereg         <= 1'b0;
            tempselx1         <= 3'b000;
            tempselx2         <= 3'b000;
        end
        else begin
            valid             <= valid_next;

            if (valid_next) begin
                Haddr1    <= Haddr;
                Hwritereg <= Hwrite;
                tempselx1 <= tempselx_next;
            end

            if (Hreadyin) begin
                Haddr2    <= Haddr1;
                tempselx2 <= tempselx1;

                if (valid && Hwritereg) begin
                    Hwdata2 <= Hwdata;
                end
                else begin
                    Hwdata2 <= Hwdata1;
                end
            end

            if (valid && Hwritereg) begin
                Hwdata1 <= Hwdata;
            end
        end
    end

endmodule
