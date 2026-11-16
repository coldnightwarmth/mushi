// Analysis artifacts are not compilable decompiled gameplay.
// @category Mushi
import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.*;
import ghidra.program.model.listing.*;
import java.nio.file.*;
import java.io.*;

public class ExportFutari extends GhidraScript {
    public void run() throws Exception {
        Path out=Paths.get(getScriptArgs()[0]);Files.createDirectories(out.resolve("functions"));
        // These are script-owned generated exports. Remove stale function files
        // when analysis boundaries change, so they cannot masquerade as current.
        try(var files=Files.list(out.resolve("functions"))) {
            for(Path path:files.toList()) {
                if(path.getFileName().toString().matches("[0-9a-fA-F]{8}\\.c"))Files.delete(path);
            }
        }
        DecompInterface decomp=new DecompInterface();decomp.openProgram(currentProgram);
        try(BufferedWriter index=Files.newBufferedWriter(out.resolve("functions.tsv"));
            BufferedWriter listing=Files.newBufferedWriter(out.resolve("listing.asm"))) {
            index.write("address\tname\tstatus\tbytes\n");
            for(Instruction ins:currentProgram.getListing().getInstructions(true)) listing.write(ins.getAddress()+"  "+ins.toString()+"\n");
            for(Function f:currentProgram.getFunctionManager().getFunctions(true)) {
                if(f.isExternal())continue;
                DecompileResults r=decomp.decompileFunction(f,15,monitor);
                boolean ok=r.decompileCompleted()&&r.getDecompiledFunction()!=null;
                String body=ok?r.getDecompiledFunction().getC():r.getErrorMessage();
                String address=f.getEntryPoint().toString();
                Files.writeString(out.resolve("functions/"+address+".c"),"/* UNREVIEWED GHIDRA PSEUDOCODE. Not original source or a native port. */\n"+body);
                index.write(address+"\t"+f.getName()+"\t"+(ok?"pseudocode":"failed")+"\t"+f.getBody().getNumAddresses()+"\n");
            }
        } finally {decomp.dispose();}
    }
}
