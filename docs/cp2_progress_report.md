# CP2 Progress Report

For this checkpoint, we focused on implementing the core framework of the Tomasulo out-of-order (OoO) processor, including all essential backend structures and functional units necessary for out-of-order execution.

Implementation
-  Completed the RAT, ARF, Reorder Buffer (ROB), and Free List modules,     for register renaming.
-  Integrated and verified the ALU and Multiply functional units, both capable of issuing and writing results out-of-order and to the cdb. 
-  Integrated sequential multiply and sequential divide units from Synopsys DesignWare IP blocks.
- Added back pressure stall logic across pipeline.
    

### **Testing**

-   Verified out-of-order execution behavior using the provided benchmark, observing correct commit ordering through the ROB.
-   Validated multiply/divide correctness as well as tested for edge cases. 

### **Next Steps**

-  Integrate the branch predictor, branch functional unit with the rename and ROB stages for full control-flow speculation support.
- Connect the load/store functional units. 
