import Foundation

/// Check predictive behavior rather than just whether a filter changed pixels.
func verifyCodecDatamosh() {
    func check(_ value: @autoclosure ()->Bool,_ message: String) {
        if !value() { fputs("FAIL Datamosh: "+message+"\n",stderr);exit(1) }
    }
    func gray(_ value: Int,_ w: Int=64,_ h: Int=64)->ArtBitmap {
        ArtBitmap(width:w,height:h,pixels:[UInt32](repeating:0xff000000|UInt32(value*0x010101),count:w*h))
    }
    func texture(_ base: Int,shift: Int=0)->ArtBitmap {
        var image=gray(base,96,64)
        for y in 0..<64 { for x in 0..<96 {
            let xx=max(0,x-shift),v=base+((xx*17+y*11+(xx/7)*13+(y/5)*19)%48)
            image.pixels[y*96+x]=0xff000000|UInt32(v*0x010101)
        } }
        return image
    }
    var melt=CodecDatamosh()
    let anchor=melt.render(texture(20),mode:1,tick:0,memory:116)
    let cut=melt.render(texture(170),mode:1,tick:1,memory:116)
    check(anchor==cut,"a scene cut repaired a dropped intra reference")
    let moving=melt.render(texture(170,shift:2),mode:1,tick:2,memory:116)
    var matches=0,total=0
    for y in 16..<48 { for x in 16..<80 {
        total+=1;if moving[y*96+x]==anchor[y*96+x-2] { matches+=1 }
    } }
    check(matches*100/total>90,"wrong reference did not follow measured motion (\(matches)/\(total))")
    print("PASS Datamosh: missing scene refresh retains old pixels; new motion moves the damaged reference (\(matches)/\(total)).")

    var bloom=CodecDatamosh()
    _=bloom.render(gray(80),mode:2,tick:0,memory:232)
    let p=bloom.render(gray(88),mode:2,tick:1,memory:232)
    let repeated=bloom.render(gray(88),mode:2,tick:2,memory:232)
    check(p[0]&255==88 && repeated[0]&255==96,"Bloom did not repeat a signed residual packet")
    check(bloom.render(gray(10),mode:2,tick:2,memory:232)==repeated,"paused repaint advanced Bloom")
    var writer=RewindWriter();bloom.write(to:&writer)
    let next=bloom.render(gray(88),mode:2,tick:3,memory:232)
    var restored=CodecDatamosh(),reader=RewindMemory(writer.data).reader();restored.read(from:&reader)
    check(restored.render(gray(88),mode:2,tick:3,memory:232)==next,"restored packet diverged")

    var keyframes=CodecDatamosh()
    for tick in 0...5 {
        let output=keyframes.render(gray(80+tick*4),mode:1,tick:tick,memory:4)
        check(output[0]&255==UInt32(tick<4 ? 80+tick*4:80+(tick-1)*4),"dropped keyframe lost predictive error at \(tick)")
    }
    print("PASS Datamosh: repeated P-packet corrections, scheduled refresh loss, pause and serialized decoder state.")

    for mode in 1...2 {
        let engine=ArtEffectEngine();var options=ArtOptions();options[.codecDatamosh]=mode
        var images=[[UInt32]]()
        for tick in 0..<40 {
            images.append(engine.render(ArtFrame(image:texture(tick<10 ? 20:170,shift:tick%10)),options:options,tick:tick,context:"codec").pixels)
        }
        check(engine.render(ArtFrame(image:gray(0,96,64)),options:options,tick:22,context:"codec",rewinding:true).pixels==images[22],"retained rewind pixels changed")
        check(engine.render(ArtFrame(image:texture(170,shift:3)),options:options,tick:23,context:"codec").pixels==images[23],"rewind branch lost decoder reference")
        // Scope changes and Clear canvas must never import actor pixels from
        // the old scope. Canvas resize preserves feedback without invalid MVs.
        options.scope = .background
        let source=ArtFrame(image:gray(80,96,64))
        check(engine.render(source,options:options,tick:24,context:"codec").pixels==source.image.pixels,"Bkg inherited On history")
        for (w,h) in [(1,1),(3,97),(97,3),(160,240)] {
            let frame=ArtFrame(image:gray(90,w,h))
            _=engine.render(frame,options:options,tick:25,context:"codec")
            let output=engine.render(frame,options:options,tick:26,context:"codec")
            check(output.pixels.allSatisfy{$0>>24==255},"resize generated transparency")
        }
        check(engine.render(source,options:options,tick:27,context:"new-canvas").pixels==source.image.pixels,"Clear canvas retained corruption")
    }
    print("PASS Datamosh: both modes rewind/branch exactly, resize safely and isolate On/Bkg/Clear canvas.");fflush(stdout)
}
