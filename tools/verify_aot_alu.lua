local m=manager.machine
local cpu=m.devices[":maincpu"]
local s=cpu.spaces.program
local directory=assert(os.getenv("MUSHI_ALU_TEST"))
local input=assert(io.open(directory.."/cases.bin","rb"))
local output=assert(io.open(directory.."/original.bin","wb"))
local running=false
emu.register_frame_done(function()
    if running then
        assert(cpu.state.PC.value==0x0c7ff000 or cpu.state.PC.value==0x0c7ff002,"ALU case did not return")
        for i=0,15 do output:write(string.pack(">I4",cpu.state["R"..i].value)) end
        for _,name in ipairs({"SR","MACH","MACL"}) do output:write(string.pack(">I4",cpu.state[name].value)) end
    end
    local bytes=input:read(80)
    if not bytes then input:close();output:close();m:exit();return end
    local opcode=string.unpack(">I4",bytes,1)
    s:write_u16(0x0c7fc000,opcode)
    s:write_u16(0x0c7fc002,0x000b);s:write_u16(0x0c7fc004,0x0009)
    s:write_u16(0x0c7ff000,0xaffe);s:write_u16(0x0c7ff002,0x0009)
    cpu.state.SR.value=string.unpack(">I4",bytes,69)
    for i=0,15 do cpu.state["R"..i].value=string.unpack(">I4",bytes,5+i*4) end
    cpu.state.MACH.value=string.unpack(">I4",bytes,73)
    cpu.state.MACL.value=string.unpack(">I4",bytes,77)
    cpu.state.PR.value=0x0c7ff000
    cpu.state.PC.value=0x0c7fc000
    running=true
end,"frame")
