
## CP1 Progress Report

For this checkpoint, we implemented part of the front-end of our Tomasulo out-of-order CPU and the base of the fetch stage. We built a line-buffered instruction cache using the cache from mp_cache (with write functionality removed) and connected it to a cacheline adapter that interfaces with the burst memory model.

### Implementation
1) Added a 256-bit linebuffered icache to store/serve repeated fetches for an average IPC of 1.
2) Added a parameterizable FIFO instruction queue to buffer fetched instructions being read from icache.
3) Implemented a fetch stage that signals instruction requests and pushes/pops instructions to/from fifo queue. 

### Testing
-   Verified correct linebuffer fetch and fifo behaviour through test bench + spike.
    
### Next Steps
-  Integrate cacheline adapter with dcache + arbiter.
-  Begin decode stage implementation.