// Known entry seeds only. SH4 big-endian is used as a SH3 instruction superset.
// @category Mushi
import ghidra.app.script.GhidraScript;
import ghidra.program.model.symbol.SourceType;
import ghidra.program.model.mem.MemoryBlock;

public class SeedFutari extends GhidraScript {
    public void run() throws Exception {
        setAnalysisOption(currentProgram, "Function ID", "false");
        MemoryBlock text=currentProgram.getMemory().getBlock(toAddr(0x0c000000));
        text.setExecute(true);
        long end=text.getEnd().getOffset()+1;
        MemoryBlock ram=currentProgram.getMemory().createUninitializedBlock("work_ram",toAddr(end),0x0c800000-end,false);
        ram.setRead(true);ram.setWrite(true);ram.setExecute(false);
        long[] entry={0x0c000000,0x0c002ac4,0x0c051614,0x0c05dbd0,0x0c062fa0};
        String[] names={"boot_entry","decode_lz","graphics_init_candidate","clear_runtime_state","main_loop"};
        for(int i=0;i<entry.length;i++) {
            createLabel(toAddr(entry[i]),names[i],true,SourceType.USER_DEFINED);
            disassemble(toAddr(entry[i]));
            createFunction(toAddr(entry[i]),names[i]);
        }
        setPlateComment(toAddr(0x0c051000),"Decompressed U4 payload from physical offset 0x51000. Initial writable data precedes executable code. Original game CPU: SH7709S (SH3), not SH4. Pseudocode requires manual review.");
    }
}
