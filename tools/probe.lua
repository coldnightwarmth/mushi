-- Read-only reference-machine inspection and scheduled input replay.
local m = manager.machine
local out = assert(os.getenv("MUSHI_CAPTURE"), "MUSHI_CAPTURE is required")
local cpu = m.devices[":maincpu"]
local space = cpu.spaces.program
local frame = 0
local limit = tonumber(os.getenv("MUSHI_FRAMES") or "1800")
local log = assert(io.open(out .. "/machine.txt", "w"))
for tag,dev in pairs(m.devices) do
    log:write(tag, "\n")
    for name,index in pairs(dev.items) do log:write("  ", name, " ", tostring(index), "\n") end
end
for tag,port in pairs(m.ioport.ports) do
    log:write("port ", tag, "\n")
    for name,field in pairs(port.fields) do log:write("  ", name, "\n") end
end
log:close()
local screen = m.screens[":screen"]
local frame_log = assert(io.open(out .. "/frames.tsv", "w"))
frame_log:write("frame\tpc\n");frame_log:setvbuf("line")
local snapshots = {}
for n in (os.getenv("MUSHI_SNAPSHOTS") or "300,600,900,1200,1500,1800"):gmatch("%d+") do snapshots[tonumber(n)] = true end
local replay = os.getenv("MUSHI_REPLAY")
local events = replay and dofile(replay) or {}
local gfx = m.devices[":blitter"].items
local gfx_addr = emu.item(gfx["0/m_gfx_addr"])
local scroll_x = emu.item(gfx["0/m_gfx_scroll_x"])
local scroll_y = emu.item(gfx["0/m_gfx_scroll_y"])
local vram = emu.item(gfx["0/m_bitmaps"])
local capture_gfx = os.getenv("MUSHI_GFX") == "1"
local captures = assert(io.open(out .. "/graphics.tsv", "w"))
captures:write("frame\tlist_address\tscroll_x\tscroll_y\tvram_element_size\tvram_count\n")
emu.register_frame_done(function()
    frame = frame + 1
    if frame % 60 == 0 then frame_log:write(frame, "\t", string.format("%08x", cpu.state.PC.value), "\n") end
    for _,e in ipairs(events) do
        if frame == e[1] then m.ioport.ports[e[2]].fields[e[3]]:set_value(e[4]) end
    end
    if snapshots[frame] then
        screen:snapshot(out .. string.format("/frame-%05d.png",frame))
        local f=assert(io.open(out .. string.format("/ram-%05d.bin",frame),"wb"))
        f:write(space:read_range(0x0c000000,0x0c7fffff,8));f:close()
        local addr = gfx_addr:read(0) & 0x1fffffff
        captures:write(string.format("%d\t%08x\t%d\t%d\t%d\t%d\n",frame,addr,scroll_x:read(0),scroll_y:read(0),vram.size,vram.count));captures:flush()
        if capture_gfx then
            local v=assert(io.open(out .. string.format("/vram-%05d.bin",frame),"wb"))
            v:write(vram:read_block(0,vram.size*vram.count));v:close()
        end
    end
    if frame >= limit then frame_log:close();captures:close();m:exit() end
end, "frame")
