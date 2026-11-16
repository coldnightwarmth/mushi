-- Original-input-service oracle. This script is test infrastructure, not runtime.
local m=manager.machine
local cpu=m.devices[":maincpu"]
local s=cpu.spaces.program
local dir=assert(os.getenv("MUSHI_INPUT_TEST"))
local input=assert(io.open(dir.."/inputs.bin","rb"))
local output=assert(io.open(dir.."/original-output.bin","wb"))
local function write_bytes(address,bytes)
    for i=1,#bytes,4 do s:write_u32(address+i-1,string.unpack(">I4",bytes,i)) end
end
local running=false
local initialized=false
local frames=0
emu.register_frame_done(function()
    if not initialized then
        local file=assert(io.open(dir.."/program.bin","rb"))
        write_bytes(0x0c000000,file:read("a"));file:close()
        s:write_u16(0x0c7ff000,0xaffe);s:write_u16(0x0c7ff002,0x0009)
        initialized=true
    end
    if running then
        frames=frames+1
        if cpu.state.PC.value~=0x0c7ff000 and cpu.state.PC.value~=0x0c7ff002 then
            assert(frames<10,"Input routine failed to return")
            return
        end
        output:write(string.pack(">I4",cpu.state.R0.value))
        output:write(s:read_range(0x0c05c468,0x0c05c4ef,8))
    end
    local header=input:read(8)
    if not header then input:close();output:close();m:exit();return end
    local entry,argument=string.unpack(">I4I4",header)
    local bytes=assert(input:read(0x88));assert(#bytes==0x88)
    write_bytes(0x0c05c468,bytes)
    cpu.state.SR.value=0x700000f0
    cpu.state.R4.value=argument
    cpu.state.R15.value=0x0c7fe000
    cpu.state.PR.value=0x0c7ff000
    cpu.state.PC.value=entry
    frames=0;running=true
end,"frame")
