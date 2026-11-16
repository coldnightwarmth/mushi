-- Isolated execution of the original 0x0c002ac4 decoder, with interrupts masked.
-- No game state is used as a test result; caller inputs and output ranges are explicit.
local m=manager.machine
local cpu=m.devices[":maincpu"]
local s=cpu.spaces.program
local dir=assert(os.getenv("MUSHI_DECODER_TEST"))
local input=assert(io.open(dir.."/inputs.bin","rb"))
local output=assert(io.open(dir.."/original-output.bin","wb"))
local log=assert(io.open(dir.."/original.tsv","w"));log:setvbuf("line")
log:write("case\tframes\treturn_size\tdestination_end\tsource_end\n")
local routine=assert(io.open(dir.."/routine.bin","rb")):read("a")
local function write_bytes(address,bytes)
    local i=1
    while i+3<=#bytes do s:write_u32(address+i-1,string.unpack(">I4",bytes,i));i=i+4 end
    while i<=#bytes do s:write_u8(address+i-1,bytes:byte(i));i=i+1 end
end
local running=false
local frame,start,index,expected=0,0,0,0
emu.register_frame_done(function()
    frame=frame+1
    if running then
        if cpu.state.PC.value~=0x0c7ff000 and cpu.state.PC.value~=0x0c7ff002 then
            if frame-start>600 then error("Original decoder did not return") end
            return
        end
        output:write(s:read_range(0x0c300000,0x0c300000+expected-1,8))
        log:write(string.format("%d\t%d\t%d\t%08x\t%08x\n",index,frame-start,cpu.state.R0.value,cpu.state.R4.value,cpu.state.R12.value))
        if index%50==0 then print("Verified original decoder case "..index) end
    end
    local header=input:read(8)
    if not header then input:close();output:close();log:close();m:exit();return end
    local length
    length,expected=string.unpack(">I4I4",header)
    assert(length<=0x1f0000 and expected<=0x300000)
    local bytes=assert(input:read(length));assert(#bytes==length)
    write_bytes(0x0c600000,bytes)
    write_bytes(0x0c002ac4,routine)
    -- A branch-to-self return sentinel outside source and destination buffers.
    s:write_u16(0x0c7ff000,0xaffe);s:write_u16(0x0c7ff002,0x0009)
    cpu.state.SR.value=0x700000f0
    cpu.state.R4.value=0x0c300000
    cpu.state.R5.value=0x0c600000
    cpu.state.PR.value=0x0c7ff000
    cpu.state.PC.value=0x0c002ac4
    start=frame;running=true;index=index+1
end,"frame")
