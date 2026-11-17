-- Synthetic original-blitter oracle; strictly headless test infrastructure.
local m=manager.machine
local cpu=m.devices[":maincpu"]
local s=cpu.spaces.program
local out=assert(os.getenv("MUSHI_GRAPHICS_TEST"))
local frame=0
emu.register_frame_done(function()
    frame=frame+1
    if frame==1 then
        cpu.state.SR.value=0x700000f0
        s:write_u16(0x0c7ff000,0xaffe);s:write_u16(0x0c7ff002,0x0009)
        cpu.state.PC.value=0x0c7ff000
        local f=assert(io.open(out.."/commands.bin","rb"));local bytes=f:read("a");f:close()
        s:write_u32(0x18000040,string.unpack(">I4",bytes,1))
        s:write_u32(0x18000044,string.unpack(">I4",bytes,5))
        for i=9,#bytes do s:write_u8(0x0c100000+i-9,bytes:byte(i)) end
        s:write_u32(0x18000008,0x0c100000)
        s:write_u32(0x18000004,1)
    elseif frame==4 then
        local item=emu.item(m.devices[":blitter"].items["0/m_bitmaps"])
        local f=assert(io.open(out.."/original.bin","wb"));f:write(item:read_block(0,item.size*item.count));f:close()
        m:exit()
    end
end,"frame")
