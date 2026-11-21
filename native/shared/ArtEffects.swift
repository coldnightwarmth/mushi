import Foundation

struct ArtBitmap {
    var width: Int, height: Int, pixels: [UInt32]
    init(width: Int,height: Int,pixels: [UInt32]?=nil) {
        self.width=width;self.height=height
        self.pixels=pixels ?? [UInt32](repeating:0,count:width*height)
        precondition(width>0 && height>0 && self.pixels.count==width*height)
    }
    func resized(_ w: Int,_ h: Int) -> ArtBitmap {
        if w==width && h==height { return self }
        var result=ArtBitmap(width:w,height:h)
        for y in 0..<h { for x in 0..<w { result.pixels[y*w+x]=pixels[min(height-1,y*height/h)*width+min(width-1,x*width/w)] } }
        return result
    }
}
struct ArtBloom {
    let x,y: Double
    let bitmap: ArtBitmap
    let key: Int
}
struct ArtDeath { let key: UInt64;let x,y: Double;let colors: [UInt32] }
struct ArtFrame {
    let image: ArtBitmap
    var sprites: ArtBitmap?
    var effects: ArtBitmap?
    var blooms=[ArtBloom]()
    var deaths=[ArtDeath]()
    var woven=[ArtBitmap]()
    var playerX=0.5,playerY=0.75
    var words=["ESP","1UP","INSERT COIN","GAME OVER","×16"]
    var typographyStamps=[ArtBitmap]()
}

/// Render-owned, bounded visual history. Gameplay RAM, hitboxes and clocks are
/// never changed. A single lock also makes offscreen/worker rendering safe.
final class ArtEffectEngine {
    private let lock=NSLock()
    private struct Grain { var x,y,vx,vy: Double;let color: UInt32;var age: Int }
    private struct Pulse { let x,y: Double,birth: Int,key: UInt64 }
    private struct Flower { let x,y: Double,stamp: ArtBitmap,birth,key: Int }
    private struct Sample { let tick: Int,image: ArtBitmap,backgroundOnly: Bool }
    private struct Entry {
        let tick,width,height: Int,memory: RewindMemory,flowers: [Flower],grains: [Grain]
        let options: ArtOptions
        let pulses: [Pulse],seenDeaths: [UInt64]
        var bytes: Int { memory.data.count+flowers.count*96+grains.count*64 }
    }
    private var key="",lastTick = -1,width=0,height=0
    private var lastOptions=ArtOptions(),rewound=false
    private var samples=[Sample](),entries=[Entry](),entryBytes=0,sampleBytes=0
    private var previous=[UInt32](),sand=[UInt32](),lastEffects=[UInt32]()
    private var sandAge=[UInt16](),grains=[Grain](),flowers=[Flower]()
    private var pulses=[Pulse](),seenDeaths=[UInt64]()
    private var polarRadius=[Float](),polarAngle=[Int](),polarWidth=0,polarHeight=0
    private static let trig=(0..<4096).map{(Float(cos(Double($0)*Double.pi*2/4096)),Float(sin(Double($0)*Double.pi*2/4096)))}
    private(set) var lastRenderMS=0.0
    private(set) var processedFrames=0
    var particleCounts: (flying:Int,settled:Int,unsupported:Int) {
        lock.lock();defer{lock.unlock()}
        let count=sand.filter{$0 != 0}.count
        let unsupported=height>1 ? (0..<max(0,sand.count-width)).filter{sand[$0] != 0 && sand[$0+width]==0}.count:0
        return (grains.count,count,unsupported)
    }
    var retainedBytes: Int { lock.lock();defer{lock.unlock()};return entryBytes+sampleBytes }
    private static func hash(_ n: Int) -> UInt32 {
        var x=UInt32(truncatingIfNeeded:n);x ^= x>>16;x &*= 0x7feb352d;x ^= x>>15;x &*= 0x846ca68b;return x^(x>>16)
    }
    @inline(__always) static func mix(_ a: UInt32,_ b: UInt32,_ weight: Int) -> UInt32 {
        let k=UInt32(max(0,min(255,weight))),j=255-k
        // Two independent 16-bit lanes; exact /255 rounding as before.
        let rb=(a&0x00ff00ff)&*j &+ (b&0x00ff00ff)&*k
        let rb8=((rb &+ 0x00010001 &+ ((rb>>8)&0x00ff00ff))>>8)&0x00ff00ff
        let g=((a>>8)&255)&*j &+ ((b>>8)&255)&*k
        let g8=(g &+ 1 &+ (g>>8))>>8
        return 0xff000000|rb8|(g8<<8)
    }
    private static func difference(_ a: UInt32,_ b: UInt32)->Int {
        abs(Int(a&255)-Int(b&255))+abs(Int(a>>8&255)-Int(b>>8&255))+abs(Int(a>>16&255)-Int(b>>16&255))
    }
    private static func color(_ phase: Int)->UInt32 {
        let colors:[UInt32]=[0xff4040ff,0xff20b0ff,0xff40ffff,0xff80ff40,0xffffff40,0xffff8040,0xffff40d0]
        return colors[((phase%colors.count)+colors.count)%colors.count]
    }
    private func clear() {
        lastTick = -1;width=0;height=0;previous=[];sand=[];sandAge=[];lastEffects=[]
        grains=[];flowers=[];pulses=[];seenDeaths=[];samples=[];entries=[];entryBytes=0;sampleBytes=0;rewound=false
    }
    private func resize(_ w: Int,_ h: Int) {
        guard w != width || h != height else { return }
        if width>0 && height>0 {
            func scale<T>(_ values:[T])->[T] {
                var out=[T]();out.reserveCapacity(w*h)
                for y in 0..<h { for x in 0..<w { out.append(values[min(height-1,y*height/h)*width+min(width-1,x*width/w)]) } }
                return out
            }
            previous=scale(previous);sand=scale(sand);sandAge=scale(sandAge);lastEffects=scale(lastEffects)
            for i in grains.indices { grains[i].x *= Double(w)/Double(width);grains[i].y *= Double(h)/Double(height)
                grains[i].vx *= Double(w)/Double(width);grains[i].vy *= Double(h)/Double(height) }
        } else {
            previous=[UInt32](repeating:0,count:w*h);sand=previous;lastEffects=previous
            sandAge=[UInt16](repeating:0,count:w*h)
        }
        width=w;height=h
    }
    private func restore(_ e: Entry) -> ArtBitmap {
        var reader=e.memory.reader();previous=reader.array(UInt32.self);sand=reader.array(UInt32.self)
        sandAge=reader.array(UInt16.self);lastEffects=reader.array(UInt32.self)
        width=e.width;height=e.height;lastTick=e.tick;lastOptions=e.options;flowers=e.flowers;grains=e.grains;pulses=e.pulses;seenDeaths=e.seenDeaths
        return ArtBitmap(width:width,height:height,pixels:previous)
    }
    func render(_ frame: ArtFrame,options: ArtOptions,tick: Int,context: String,rewinding: Bool=false) -> ArtBitmap {
        let started=ProcessInfo.processInfo.systemUptime
        lock.lock();defer{lastRenderMS=(ProcessInfo.processInfo.systemUptime-started)*1000;lock.unlock()}
        if context != key { clear();key=context }
        guard options.active else { return frame.image }
        let w=frame.image.width,h=frame.image.height
        if rewinding {
            rewound=true
            if let e=entries.last(where:{$0.tick<=tick && $0.options.backgroundOnly==options.backgroundOnly}) {
                return restore(e).resized(w,h)
            }
            return frame.image
        }
        if rewound || tick<lastTick {
            if let e=entries.last(where:{$0.tick<=tick}) { _=restore(e) }
            else { clear() } // Never borrow visual state from a discarded future.
            entries.removeAll{$0.tick>tick};samples.removeAll{$0.tick>tick}
            entryBytes=entries.reduce(0){$0+$1.bytes};sampleBytes=samples.reduce(0){$0+$1.image.pixels.count*4};rewound=false
        }
        if tick==lastTick && options==lastOptions && w==width && h==height { return ArtBitmap(width:w,height:h,pixels:previous) }
        let dt=lastTick<0 ? 1:max(0,min(12,tick-lastTick))
        resize(w,h)
        let input=frame.image.pixels,mask=frame.sprites?.pixels
        if lastTick<0 || options.backgroundOnly != lastOptions.backgroundOnly {
            previous=input
            // Accumulation from On can contain live actors too. Keep retained
            // rewind entries, but start the new scope with a clean canvas.
            sand=[UInt32](repeating:0,count:w*h);lastEffects=sand
            sandAge=[UInt16](repeating:0,count:w*h)
            grains=[];flowers=[];pulses=[];seenDeaths=[]
        }
        // The longest delay must still fit on a wide exploration canvas.
        let sampleInterval=max(3,(options.memoryTicks*input.count*4+48*1024*1024-1)/(48*1024*1024))
        if samples.isEmpty || samples.last?.backgroundOnly != options.backgroundOnly || tick-(samples.last?.tick ?? tick)>=sampleInterval {
            samples.append(Sample(tick:tick,image:frame.image,backgroundOnly:options.backgroundOnly));sampleBytes+=input.count*4
        }
        while samples.count>2 && (tick-samples[0].tick>580 || sampleBytes>48*1024*1024) {
            sampleBytes-=samples.removeFirst().image.pixels.count*4
        }
        var delayed=[Int:[UInt32]]()
        func past(_ age: Int)->[UInt32] {
            let index=samples.lastIndex(where:{$0.backgroundOnly==options.backgroundOnly && $0.tick<=tick-age}) ?? samples.firstIndex(where:{$0.backgroundOnly==options.backgroundOnly})!
            if let cached=delayed[index] { return cached }
            let result=samples[index].image.resized(w,h).pixels;delayed[index]=result;return result
        }
        var out=input
        let deaths=frame.deaths.filter{!seenDeaths.contains($0.key)}
        seenDeaths.append(contentsOf:deaths.map{$0.key})
        if seenDeaths.count>512 { seenDeaths.removeFirst(seenDeaths.count-512) }
        if options[.tileShuffle]==3 {
            pulses.removeAll{tick-$0.birth>80}
            pulses.append(contentsOf:deaths.map{Pulse(x:$0.x,y:$0.y,birth:tick,key:$0.key)})
            if pulses.count>32 { pulses.removeFirst(pulses.count-32) }
        } else { pulses=[] }
        if options[.pixelSediment] != lastOptions[.pixelSediment] {
            grains=[]
            if options[.pixelSediment]==3 || lastOptions[.pixelSediment]==3 { sand=[UInt32](repeating:0,count:w*h);sandAge=[UInt16](repeating:0,count:w*h) }
        }
        let memory=options.memoryTicks
        if options[.slitScan]>0 {
            let mode=options[.slitScan],vertical=mode%2==1
            let extent=vertical ? w:h,bands=mode>=5 ? max(1,extent/2):24
            let depth=mode>=3 ? max(6,memory/4):memory
            for band in 0..<bands {
                let age=(band*depth/bands+(mode>=3 ? tick*3:0))%max(1,depth)
                let source=past(age)
                let a=band*extent/bands,b=(band+1)*extent/bands
                if vertical { for y in 0..<h { for x in a..<b { out[y*w+x]=source[y*w+x] } } }
                else { for y in a..<b { out.replaceSubrange(y*w..<(y+1)*w,with:source[y*w..<(y+1)*w]) } }
            }
        }
        if options[.timeBands]>0 {
            let bands=10
            for band in 0..<bands {
                // An age increasing twice as fast as the clock moves the
                // sampled source time backward, until this band wraps.
                let age=options[.timeBands]==2 && band%2==1 ? (tick*2+band*13)%memory:(band*memory/bands+tick/3)%memory
                let source=past(age)
                for y in band*h/bands..<(band+1)*h/bands { for x in 0..<w { let i=y*w+x;out[i]=Self.mix(out[i],source[i],210) } }
            }
        }
        if options[.scanlineWeaving]>0 {
            let layers=frame.woven.isEmpty ? [past(memory/3),past(memory*2/3)]:frame.woven.map{$0.resized(w,h).pixels}
            let stripe=options[.scanlineWeaving]==1 ? 1:3
            for y in 0..<h {
                let which=(y/stripe+tick/24)%(layers.count+1)
                if which>0 { let layer=layers[which-1];for x in 0..<w {
                    let i=y*w+x;out[i]=Self.mix(out[i],layer[i],options[.scanlineWeaving]==1 ? 96:128)
                } }
            }
        }
        if options[.videoFeedback]>0 {
            let source=out,cx=Double(w-1)/2,cy=Double(h-1)/2
            let angle=options[.videoFeedback]==2 ? 0.009*Double(max(1,dt)):0
            let c=cos(angle)*0.986,s=sin(angle)*0.986
            for y in 0..<h { for x in 0..<w {
                let dx=Double(x)-cx,dy=Double(y)-cy
                let sx=max(0,min(w-1,Int(cx+dx*c-dy*s))),sy=max(0,min(h-1,Int(cy+dx*s+dy*c)))
                out[y*w+x]=Self.mix(source[y*w+x],previous[sy*w+sx],options[.videoFeedback]==2 ? 170:145)
            } }
        }
        if options[.datamosh]>0 {
            let mode=options[.datamosh],old=past(4),block=[12,20,12,8][mode-1],source=out
            for by in stride(from:0,to:h,by:block) { for bx in stride(from:0,to:w,by:block) {
                var best=Int.max,mx=0,my=0
                for dy in stride(from:-4,through:4,by:4) { for dx in stride(from:-4,through:4,by:4) {
                    var error=0
                    for k in 0..<4 {
                        let x=min(w-1,bx+(k%2)*block/2),y=min(h-1,by+(k/2)*block/2)
                        error+=Self.difference(input[y*w+x],old[max(0,min(h-1,y+dy))*w+max(0,min(w-1,x+dx))])
                    }
                    if error<best { best=error;mx=dx;my=dy }
                } }
                let seed=Self.hash(bx+by*w+tick/(mode==4 ? 5:18))
                let hold=seed%7 < (mode==1 ? 3:5)
                guard hold && (mx != 0 || my != 0 || mode==2 || mode==4) else { continue }
                if mode==3 { mx *= 3;my *= 3 }
                if mode==4 { mx += (Int(seed>>8&7)-3)*4;my += (Int(seed>>12&7)-3)*4 }
                for y in by..<min(h,by+block) { for x in bx..<min(w,bx+block) {
                    let p=previous[max(0,min(h-1,y+my))*w+max(0,min(w-1,x+mx))]
                    out[y*w+x]=Self.mix(source[y*w+x],p,mode==2 ? 160:(mode==3 ? 144:112))
                } }
            } }
        }
        if options[.negativeSpace]>0,let mask=mask {
            let old=past(memory)
            for i in out.indices where mask[i]>>24>0 {
                let color=options[.negativeSpace]==1 ? old[i]:Self.color(i/w/12+i%w/18+tick/8)
                out[i]=Self.mix(out[i],color,Int(mask[i]>>24))
            }
        }
        if options[.inkBleed]>0,w>2,h>2,let mask=mask {
            var ink=mask
            for pass in 0..<(options[.inkBleed]==1 ? 2:5) {
                let source=ink
                for y in 1..<h-1 { for x in 1..<w-1 {
                    let i=y*w+x
                    if source[i]>>24==0 {
                        var color=source[i-1]
                        if source[i+1]>>24>color>>24 { color=source[i+1] }
                        if source[i-w]>>24>color>>24 { color=source[i-w] }
                        if source[i+w]>>24>color>>24 { color=source[i+w] }
                        if color>>24>24 {
                            ink[i]=(color&0xffffff)|((max(1,(color>>24)-UInt32(20+pass*2)))<<24)
                        }
                    }
                } }
            }
            for i in out.indices where mask[i]>>24==0 && ink[i]>>24>0 { out[i]=Self.mix(out[i],ink[i],Int(ink[i]>>24)) }
        }
        if options[.pixelSediment]>0 { sediment(frame,deaths:deaths,tick:tick,dt:dt,density:options[.pixelSediment],into:&out) }
        if options[.flowers]>0 { garden(frame,tick:tick,advance:dt>0,density:options[.flowers],into:&out) }
        if options[.typography]>0 { typography(frame.typographyStamps,tick:tick,mode:options[.typography],into:&out) }
        // A short live explosion must not vanish because delayed imagery or a
        // persistent flower covered the frame in which it happened. Restore
        // only currently visible native FX, then apply geometric effects once.
        if [.slitScan,.timeBands,.videoFeedback,.datamosh,.scanlineWeaving,.flowers,.typography].contains(where:{options[$0]>0}),let effects=frame.effects?.pixels {
            for i in out.indices where effects[i]>>24>0 { out[i]=Self.mix(out[i],effects[i],Int(effects[i]>>24)) }
        }
        if options[.rasterFabric]>0 {
            let source=out,strength=options[.rasterFabric]==1 ? 4:18
            for y in 0..<h {
                let shift=Int(sin(Double(y)/11+Double(tick)/17)*Double(strength))+(options[.rasterFabric]==2 ? Int(Self.hash(y/4+tick/12)%13)-6:0)
                for x in 0..<w { out[y*w+x]=source[y*w+((x+shift)%w+w)%w] }
            }
        }
        if options[.tileShuffle]>0 {
            let source=out,tile=options[.tileShuffle]==2 ? 32:12,cols=(w+tile-1)/tile,rows=(h+tile-1)/tile
            let phase=Double(tick%90)/90,slide=phase*phase*(3-2*phase)
            // Each tile shares one displacement. Do the hashing/ring tests
            // once per tile rather than once for every pixel inside it.
            for by in stride(from:0,to:h,by:tile) { for bx in stride(from:0,to:w,by:tile) {
                let col=bx/tile,row=by/tile
                var dx=0,dy=0
                if options[.tileShuffle]==3 {
                    for pulse in pulses {
                        let age=tick-pulse.birth,radius=Double(age)*4.5,thickness=18.0
                        let px=Double(bx+tile/2)-pulse.x*Double(w),py=Double(by+tile/2)-pulse.y*Double(h)
                        let distance2=px*px+py*py
                        if distance2<max(0,radius-thickness)*max(0,radius-thickness) || distance2>(radius+thickness)*(radius+thickness) { continue }
                        let seed=Self.hash(col+row*cols+Int(truncatingIfNeeded:pulse.key)*31)
                        dx=(Int(seed%7)-3)*tile;dy=(Int(seed>>8&7)-3)*tile
                    }
                    if dx==0 && dy==0 { continue }
                } else {
                    dx=Int(Self.hash(row+tick/90*19)%UInt32(max(1,cols)))*tile+(row%2==0 ? 1:-1)*Int(Double(tile)*slide)
                    dy=Int(Self.hash(col+tick/120*7)%UInt32(max(1,rows)))*tile
                }
                for y in by..<min(h,by+tile) { let sy=((y+dy)%h+h)%h
                    for x in bx..<min(w,bx+tile) { let sx=((x+dx)%w+w)%w;out[y*w+x]=source[sy*w+sx] }
                }
            } }
        }
        if options[.misregistration]>0 {
            let source=out,phase=Double(tick)/23
            let dx=options[.misregistration]==1 ? 3:Int(cos(phase)*8),dy=options[.misregistration]==1 ? 0:Int(sin(phase)*5)
            for y in 0..<h { for x in 0..<w {
                let i=y*w+x,a=source[max(0,min(h-1,y+dy))*w+max(0,min(w-1,x+dx))]
                let b=source[max(0,min(h-1,y-dy))*w+max(0,min(w-1,x-dx))]
                out[i]=0xff000000|(a&255)|(source[i]&0xff00)|(b&0xff0000)
            } }
        }
        if options[.foldedStage]>0 { fold(options[.foldedStage],tick:tick,into:&out) }
        previous=out;lastTick=tick;lastOptions=options;processedFrames+=1
        var writer=RewindWriter(capacity:out.count*12)
        writer.array(out);writer.array(sand);writer.array(sandAge);writer.array(lastEffects)
        let entry=Entry(tick:tick,width:w,height:h,memory:RewindMemory(writer.data),flowers:flowers,grains:grains,options:options,pulses:pulses,seenDeaths:seenDeaths)
        if entries.last?.tick==tick { entryBytes-=entries.removeLast().bytes }
        entries.append(entry);entryBytes+=entry.bytes
        while entries.count>1 && (tick-entries[0].tick>580 || entryBytes>96*1024*1024) { entryBytes-=entries.removeFirst().bytes }
        return ArtBitmap(width:w,height:h,pixels:out)
    }
    private func fold(_ mode: Int,tick: Int,into out: inout [UInt32]) {
        let w=width,h=height,source=out,cx=Float(w-1)/2,cy=Float(h-1)/2
        if mode==2 || mode==5 || mode==6 {
            if polarWidth != w || polarHeight != h {
                polarWidth=w;polarHeight=h;polarRadius=[];polarAngle=[]
                polarRadius.reserveCapacity(w*h);polarAngle.reserveCapacity(w*h)
                for y in 0..<h { for x in 0..<w {
                    let dx=Double(Float(x)-cx),dy=Double(Float(y)-cy)
                    polarRadius.append(Float(hypot(dx,dy)));polarAngle.append(Int(atan2(dy,dx)*4096/(Double.pi*2)))
                } }
            }
        }
        let phase=tick*4
        for y in 0..<h { for x in 0..<w {
            let i=y*w+x,sx: Int,sy: Int
            switch mode {
            case 1:sx=min(x,w-1-x)*2;sy=min(y,h-1-y)*2
            case 3:sx=min(x,w-1-x)*2;sy=y
            case 4:sx=x;sy=min(y,h-1-y)*2
            default:
                let radius=polarRadius[i]
                var angle=polarAngle[i]+phase,r=radius*0.75
                if mode==2 { angle=((angle%683)+683)%683;angle=min(angle,683-angle) }
                if mode==5 { angle=(angle*4+Int(radius)*3)&4095 }
                if mode==6 { r=Float((Int(radius)+tick)%96);r=abs(r-48)*2.5;angle &= 4095 }
                let trig=Self.trig[angle&4095]
                sx=Int(cx+trig.0*r);sy=Int(cy+trig.1*r)
            }
            out[i]=source[max(0,min(h-1,sy))*w+max(0,min(w-1,sx))]
        } }
    }
    private func sediment(_ frame: ArtFrame,deaths: [ArtDeath],tick: Int,dt: Int,density: Int,into out: inout [UInt32]) {
        let w=width,h=height,burst=density==3,effects=frame.effects?.pixels
        if dt>0 {
            let limit=density==1 ? 2400:4800
            for death in deaths {
                let count=density==1 ? 180:360
                for n in 0..<min(count,max(0,limit-grains.count)) {
                    let hash=Self.hash(n+Int(UInt32(truncatingIfNeeded:death.key^(death.key>>32)))*373)
                    let direction=Self.trig[Int(hash&4095)],speed=2.5+Double(hash>>12&255)/40
                    let color=death.colors[n%death.colors.count]
                    grains.append(Grain(x:death.x*Double(w),y:death.y*Double(h),vx:Double(direction.0)*speed,
                        vy:Double(direction.1)*speed-2.0,color:color,age:0))
                }
            }
            // Live explosion sprites also shed pixels; this retains the small
            // effects that do not pass through an enemy death award.
            if !burst,let effects=effects {
                let step=density==1 ? 29:13
                for i in stride(from:tick%step,to:effects.count,by:step) where grains.count<limit {
                    let lost=lastEffects[i]>>24>0 && effects[i]>>24==0
                    if lost || (tick%5==0 && effects[i]>>24>0) {
                        let hash=Self.hash(i+tick*17),direction=Self.trig[Int(hash&4095)]
                        grains.append(Grain(x:Double(i%w),y:Double(i/w),vx:Double(direction.0)*2.8,
                            vy:Double(direction.1)*2.8-1.8,color:lost ? lastEffects[i]:effects[i],age:0))
                    }
                }
                lastEffects=effects
            }
            var live=[Grain]();live.reserveCapacity(grains.count)
            for var grain in grains {
                grain.age+=dt;var settled=false
                for _ in 0..<dt {
                    grain.vy=min(6,grain.vy+0.13);grain.vx *= 0.994
                    // Sweep in <=1px increments so fast grains cannot tunnel
                    // through a pile and leave unsupported pockets above it.
                    let steps=max(1,Int(ceil(max(abs(grain.vx),abs(grain.vy)))))
                    for _ in 0..<steps {
                        let nx=grain.x+grain.vx/Double(steps),ny=grain.y+grain.vy/Double(steps)
                        let x=Int(floor(nx)),y=Int(floor(ny))
                        if !burst && grain.vy>0 && x>=0 && x<w && y>=0 && (y>=h || sand[y*w+x] != 0) {
                            let px=max(0,min(w-1,Int(grain.x))),py=max(0,min(h-1,Int(grain.y))),at=py*w+px
                            if sand[at]==0 { sand[at]=grain.color;sandAge[at]=0 };settled=true;break
                        }
                        grain.x=nx;grain.y=ny
                    }
                    if settled { break }
                }
                if !settled && grain.age<(burst ? 110:420) && grain.x>=0 && grain.x<Double(w) && grain.y<Double(h)+2 { live.append(grain) }
            }
            grains=live
            if !burst {
                // Bottom-up gravity fills holes first; alternate the diagonal
                // bias so particles roll into stable slopes rather than towers.
                for _ in 0..<min(4,dt) {
                    // A porous floor releases older grains. The pile above
                    // drops into the vacated cells instead of fading in place.
                    for x in 0..<w {
                        let i=(h-1)*w+x
                        if sand[i] != 0 && sandAge[i]>90+UInt16(Self.hash(x)%45) { sand[i]=0;sandAge[i]=0 }
                    }
                    if h>1 { for y in stride(from:h-2,through:0,by:-1) {
                        for n in 0..<w {
                            let x=tick&1==0 ? n:w-1-n,i=y*w+x
                            if sand[i]==0 { continue }
                            let below=i+w,bias=(x+y+tick)&1==0 ? -1:1
                            var to = sand[below]==0 ? below:-1
                            if to<0 { for dx in [bias,-bias] where x+dx>=0 && x+dx<w {
                                if sand[below+dx]==0 && sand[i+dx]==0 { to=below+dx;break }
                            } }
                            if to>=0 { sand[to]=sand[i];sandAge[to]=sandAge[i];sand[i]=0;sandAge[i]=0 }
                        }
                    } }
                }
                for i in sand.indices where sand[i] != 0 {
                    sandAge[i]=UInt16(min(600,Int(sandAge[i])+dt));if sandAge[i]>540 { sand[i]=0 }
                }
            }
        }
        if !burst { for i in sand.indices where sand[i] != 0 { out[i]=Self.mix(out[i],sand[i],255) } }
        for grain in grains {
            let x=Int(grain.x),y=Int(grain.y),alpha=burst ? min(255,max(0,(110-grain.age)*6)):255
            let size=grain.age<18 ? 2:1
            for dy in 0..<size { for dx in 0..<size {
                let xx=x+dx,yy=y+dy
                if xx>=0 && xx<w && yy>=0 && yy<h { let i=yy*w+xx;out[i]=Self.mix(out[i],grain.color,alpha) }
            } }
        }
    }
    private func garden(_ frame: ArtFrame,tick: Int,advance: Bool,density: Int,into out: inout [UInt32]) {
        let lifetime=density==1 ? 900:1500,limit=density==1 ? 48:96
        if advance {
            flowers.removeAll{tick-$0.birth>lifetime}
            if tick/8 != (lastTick<0 ? -1:lastTick/8) {
                for bloom in frame.blooms.prefix(density==1 ? 1:3) where !flowers.suffix(12).contains(where:{$0.key==bloom.key}) {
                    flowers.append(Flower(x:bloom.x,y:bloom.y,stamp:bloom.bitmap,birth:tick,key:bloom.key))
                }
            }
            if flowers.count>limit { flowers.removeFirst(flowers.count-limit) }
        }
        guard !flowers.isEmpty else { return }
        // Accumulate from the newest bloom backwards. Once the remaining
        // contribution rounds to zero, skip older petals at that pixel.
        // Full 8x8 blocks skip affine sampling altogether in dense gardens.
        let w=width,h=height,columns=(w+7)/8,rows=(h+7)/8
        var remaining=[UInt8](repeating:255,count:w*h),sum=[UInt64](repeating:0,count:w*h)
        var covered=[Int](repeating:0,count:columns*rows),capacity=covered
        for row in 0..<rows { for col in 0..<columns { capacity[row*columns+col]=min(8,w-col*8)*min(8,h-row*8) } }
        var touched=[Int]();touched.reserveCapacity(w*h)
        for flower in flowers.reversed() {
            let age=max(0,tick-flower.birth),angle=Double(age)/180,growth=1+min(2.5,Double(age)/220)
            let co=cos(angle)/growth,si=sin(angle)/growth,stamp=flower.stamp
            let cx=flower.x*Double(w),cy=flower.y*Double(h)
            let radius=Int(ceil(hypot(Double(stamp.width),Double(stamp.height))*growth/2)),opacity=min(245,max(0,(lifetime-age)*2))
            let left=max(0,Int(cx)-radius),right=min(w,Int(cx)+radius+1),top=max(0,Int(cy)-radius),bottom=min(h,Int(cy)+radius+1)
            guard left<right && top<bottom && opacity>0 else { continue }
            for y in top..<bottom {
                var x=left
                var sx=(Double(left)-cx)*co+(Double(y)-cy)*si+Double(stamp.width)/2
                var sy = -(Double(left)-cx)*si+(Double(y)-cy)*co+Double(stamp.height)/2
                while x<right {
                    let block=y/8*columns+x/8,end=min(right,(x/8+1)*8)
                    if covered[block]==capacity[block] { let count=Double(end-x);sx+=co*count;sy-=si*count;x=end;continue }
                    while x<end {
                        let at=y*w+x
                        if remaining[at]>0 && sx>=0 && sx<Double(stamp.width) && sy>=0 && sy<Double(stamp.height) {
                            let color=stamp.pixels[Int(sy)*stamp.width+Int(sx)]
                            if color>>24>0 {
                                let alpha=opacity*Int(color>>24)/255,weight=(Int(remaining[at])*alpha+127)/255
                                if weight>0 {
                                    if remaining[at]==255 { touched.append(at) }
                                    let packed=UInt64(color&255)|(UInt64(color>>8&255)<<16)|(UInt64(color>>16&255)<<32)
                                    sum[at] &+= packed &* UInt64(weight)
                                    remaining[at]-=UInt8(weight)
                                    if remaining[at]==0 { covered[block]+=1 }
                                }
                            }
                        }
                        sx+=co;sy-=si;x+=1
                    }
                }
            }
        }
        for at in touched {
            let base=out[at],packed=UInt64(base&255)|(UInt64(base>>8&255)<<16)|(UInt64(base>>16&255)<<32)
            let total=sum[at] &+ packed &* UInt64(remaining[at])
            let rgb=((total &+ 0x000100010001 &+ ((total>>8)&0x00ff00ff00ff))>>8)&0x00ff00ff00ff
            out[at]=0xff000000|UInt32(rgb&255)|UInt32(rgb>>16&255)<<8|UInt32(rgb>>32&255)<<16
        }
    }

    private func typography(_ stamps: [ArtBitmap],tick: Int,mode: Int,into out: inout [UInt32]) {
        guard !stamps.isEmpty else { return }
        let count=[10,28,20,16,12][mode-1]
        for i in 0..<count {
            let seed=Self.hash(i*197)
            // The atlas ends with colorful HUD fragments. Give these a third
            // of the slots so operator-menu text cannot overwhelm the icons.
            let index=i%3==0 ? stamps.count-1-(i/3)%min(10,stamps.count):(i*13+Int(seed%97))%stamps.count
            let stamp=stamps[index]
            let scale=(mode==2 && i%4==0) ? 2:1
            let sw=stamp.width*scale,sh=stamp.height*scale
            let x:Int,y:Int
            switch mode {
            case 3:
                x=Int(seed%UInt32(max(1,width)))-sw/2
                y=(Int(seed>>12)%max(1,height+sh)+tick*(1+i%3))%(height+sh)-sh
            case 4:
                let angle=Double(tick)/70+Double(i)*2.39996
                x=Int(Double(width)/2+cos(angle)*Double(width)*0.38)-sw/2
                y=Int(Double(height)/2+sin(angle)*Double(height)*0.38)-sh/2
            case 5:
                let travel=(Int(seed%UInt32(width+sw))+tick*(1+i%2))%(width+sw)
                x=i%2==0 ? travel-sw:width-travel
                y=(i*max(16,height/count))%height
            default:
                x=(Int(seed%UInt32(width+sw))+tick/(mode==2 ? 1:2+i%4))%(width+sw)-sw
                y=(Int(seed>>12)%max(1,height+sh)+tick/(mode==2 ? 1:3+i%5))%(height+sh)-sh
            }
            let left=max(0,x),right=min(width,x+sw),top=max(0,y),bottom=min(height,y+sh)
            guard left<right && top<bottom else { continue }
            for yy in top..<bottom { for xx in left..<right {
                let color=stamp.pixels[((yy-y)/scale)*stamp.width+(xx-x)/scale]
                if color>>24>0 { let at=yy*width+xx;out[at]=Self.mix(out[at],color,220) }
            } }
        }
    }
}
