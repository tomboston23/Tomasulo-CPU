module cache_adapter_tb
import cache_types::*;();

    logic clk;
    logic rst;
    
    // bmem signals
    logic [31:0] bmem_addr;
    logic bmem_read;
    logic [63:0] bmem_rdata;
    logic bmem_rvalid;
    
    // cache signals
    logic dfp_resp;
    logic [255:0] dfp_rdata;
    logic [31:0] dfp_addr;
    logic dfp_read;
    
    // Test variables
    logic [255:0] expected;
    int i;

    // Instantiate DUT
    cache_adapter dut (.*);

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Test stimulus
    initial begin
        // Initialize
        rst = 1;
        dfp_addr = 32'hDEADBEEF;
        dfp_read = 0;
        bmem_rdata = 64'h0;
        bmem_rvalid = 0;
        
        // Reset
        repeat(2) @(posedge clk);
        rst = 0;
        @(posedge clk);
        
        $display("=== Test 1: Single cache line read ===");
        // Initiate read
        dfp_read = 1;
        @(posedge clk);
        dfp_read = 0;
        
        // Check bmem_read pulse
        @(posedge clk);
        if (bmem_read) 
            $display("✓ bmem_read asserted");
        else
            $display("✗ ERROR: bmem_read not asserted");
            
        if (bmem_addr == 32'hDEADBEEF)
            $display("✓ bmem_addr correct: 0x%h", bmem_addr);
        else
            $display("✗ ERROR: bmem_addr = 0x%h, expected 0xDEADBEEF", bmem_addr);
        
        // Simulate bmem responses (with some delay)
        repeat(2) @(posedge clk);
        
        // Send 4 chunks of data
        for (i = 0; i < 4; i++) begin
            bmem_rvalid = 1;
            bmem_rdata = 64'h0000_0000_0000_0000 + (i << 32) + i;  // Pattern: upper=i, lower=i
            @(posedge clk);
            bmem_rvalid = 0;
            $display("  Sent chunk %0d: 0x%h", i, bmem_rdata);
            repeat(1) @(posedge clk);  // Gap between chunks
        end
        
        // Check response
        while(!dfp_resp) @(posedge clk);
        
        if (dfp_resp) begin
            $display("✓ dfp_resp asserted");
            $display("  dfp_rdata = 0x%h", dfp_rdata);
            // Check if data matches expected pattern
            expected = {64'h0000_0003_0000_0003, 
                        64'h0000_0002_0000_0002,
                        64'h0000_0001_0000_0001,
                        64'h0000_0000_0000_0000};
            if (dfp_rdata == expected)
                $display("✓ Data correct!");
            else
                $display("✗ ERROR: Data mismatch!\n  Expected: 0x%h\n  Got:      0x%h", 
                         expected, dfp_rdata);
        end else
            $display("✗ ERROR: dfp_resp not asserted");
        
        @(posedge clk);
        
        // Test 2: Back-to-back reads
        $display("\n=== Test 2: Back-to-back reads ===");
        dfp_addr = 32'hCAFEBABE;
        dfp_read = 1;
        @(posedge clk);
        dfp_read = 0;
        
        repeat(2) @(posedge clk);
        for (i = 0; i < 4; i++) begin
            bmem_rvalid = 1;
            bmem_rdata = 64'hAAAA_AAAA_AAAA_AAAA + i;
            @(posedge clk);
            bmem_rvalid = 0;
            repeat(1) @(posedge clk);
        end
        
        while(!dfp_resp) @(posedge clk);
        if (dfp_resp && bmem_addr == 32'hCAFEBABE)
            $display("✓ Second read successful");
        else
            $display("✗ ERROR: Second read failed");
        
        repeat(5) @(posedge clk);
        
        // Test 3: Variable latency responses
        $display("\n=== Test 3: Variable latency responses ===");
        dfp_addr = 32'h1234_5678;
        dfp_read = 1;
        @(posedge clk);
        dfp_read = 0;
        
        repeat(2) @(posedge clk);
        for (i = 0; i < 4; i++) begin
            // Varying delays between responses
            repeat(i + 1) @(posedge clk);
            bmem_rvalid = 1;
            bmem_rdata = 64'h1111_1111_1111_1111 * (i + 1);
            @(posedge clk);
            bmem_rvalid = 0;
            $display("  Sent chunk %0d with %0d cycle delay", i, i+1);
        end
        
        while(!dfp_resp) @(posedge clk);
        
        expected = {64'h4444_4444_4444_4444,
                    64'h3333_3333_3333_3333,
                    64'h2222_2222_2222_2222,
                    64'h1111_1111_1111_1111};
        if (dfp_rdata == expected)
            $display("✓ Variable latency test passed!");
        else
            $display("✗ ERROR: Expected 0x%h, got 0x%h", expected, dfp_rdata);
        
        @(posedge clk);
        
        // Test 4: Immediate back-to-back (no idle cycles)
        $display("\n=== Test 4: Immediate back-to-back reads ===");
        dfp_addr = 32'hBEEF_CAFE;
        dfp_read = 1;
        @(posedge clk);
        dfp_read = 0;
        
        repeat(2) @(posedge clk);
        for (i = 0; i < 4; i++) begin
            bmem_rvalid = 1;
            bmem_rdata = 64'hF0F0_F0F0_0F0F_0F0F + (i << 8);
            @(posedge clk);
            bmem_rvalid = 0;
        end
        
        while(!dfp_resp) @(posedge clk);
        $display("✓ First immediate read complete");
        
        // Start second read immediately
        @(posedge clk);
        dfp_addr = 32'hDEAD_BEEF;
        dfp_read = 1;
        @(posedge clk);
        dfp_read = 0;
        
        repeat(2) @(posedge clk);
        for (i = 0; i < 4; i++) begin
            bmem_rvalid = 1;
            bmem_rdata = 64'hCCCC_CCCC_CCCC_CCCC;
            @(posedge clk);
            bmem_rvalid = 0;
        end
        
        while(!dfp_resp) @(posedge clk);
        if (dfp_rdata == {4{64'hCCCC_CCCC_CCCC_CCCC}})
            $display("✓ Immediate back-to-back reads passed!");
        else
            $display("✗ ERROR: Back-to-back failed");
        
        @(posedge clk);
        
        // Test 5: All zeros and all ones
        $display("\n=== Test 5: Edge cases (all 0s, all 1s) ===");
        dfp_addr = 32'h0000_0000;
        dfp_read = 1;
        @(posedge clk);
        dfp_read = 0;
        
        repeat(2) @(posedge clk);
        for (i = 0; i < 4; i++) begin
            bmem_rvalid = 1;
            bmem_rdata = 64'h0;
            @(posedge clk);
            bmem_rvalid = 0;
            repeat(1) @(posedge clk);
        end
        
        while(!dfp_resp) @(posedge clk);
        if (dfp_rdata == 256'h0)
            $display("✓ All zeros test passed!");
        else
            $display("✗ ERROR: Expected all zeros, got 0x%h", dfp_rdata);
        
        @(posedge clk);
        
        dfp_addr = 32'hFFFF_FFFF;
        dfp_read = 1;
        @(posedge clk);
        dfp_read = 0;
        
        repeat(2) @(posedge clk);
        for (i = 0; i < 4; i++) begin
            bmem_rvalid = 1;
            bmem_rdata = 64'hFFFF_FFFF_FFFF_FFFF;
            @(posedge clk);
            bmem_rvalid = 0;
            repeat(1) @(posedge clk);
        end
        
        while(!dfp_resp) @(posedge clk);
        if (dfp_rdata == {256{1'b1}})
            $display("✓ All ones test passed!");
        else
            $display("✗ ERROR: Expected all ones, got 0x%h", dfp_rdata);
        
        repeat(5) @(posedge clk);
        $display("\n=== All Tests Complete ===");
        $finish;
    end
    
    // Timeout
    initial begin
        #10000;
        $display("ERROR: Timeout!");
        $finish;
    end
    
    // Waveform dump (for GTKWave or similar)
    initial begin
        $dumpfile("cache_adapter.vcd");
        $dumpvars(0, cache_adapter_tb);
    end

endmodule