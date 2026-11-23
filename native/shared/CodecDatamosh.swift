import Foundation

/// A small, deterministic predictive-video model, not a bitstream encoder.
/// Keep the encoder's clean reference separate from the decoder's damaged one:
/// P = motion(previous) + quantized residual. Dropped intra refreshes never
/// repair the decoder. Bloom repeats a P packet against its own decoded output.
/// This is deliberately not an alpha blend with the current game image.
/// Coding model: https://www.rfc-editor.org/rfc/rfc9328.html#section-1.1.1
struct CodecDatamosh {
    private var width=0,height=0,lastTick = -1,mode=0,anchorTick=0,packetTick = -1,packetStep=1
    private var clean=[UInt32](),decoded=[UInt32](),residual=[UInt32]()
    private var motionX=[Int16](),motionY=[Int16]() // half-pixel, backward vectors

    mutating func reset() { self=CodecDatamosh() }
    func write(to writer: inout RewindWriter) {
        writer.array([width,height,lastTick,mode,anchorTick,packetTick,packetStep].map{Int64($0)})
        writer.array(clean);writer.array(decoded);writer.array(residual)
        writer.array(motionX);writer.array(motionY)
    }
    mutating func read(from reader: inout RewindReader) {
        let header=reader.array(Int64.self).map{Int($0)}
        width=header[0];height=header[1];lastTick=header[2];mode=header[3]
        anchorTick=header[4];packetTick=header[5];packetStep=header[6]
        clean=reader.array(UInt32.self);decoded=reader.array(UInt32.self);residual=reader.array(UInt32.self)
        motionX=reader.array(Int16.self);motionY=reader.array(Int16.self)
    }
    @inline(__always) private static func clamp(_ x: Int)->Int { max(0,min(255,x)) }
    /// Full-range YCbCr with 4:2:0 color sampling, like a low-bitrate video.
    private static func encode(_ pixels: [UInt32],_ w: Int,_ h: Int)->[UInt32] {
        var out=[UInt32](repeating:0,count:pixels.count)
        for i in pixels.indices {
            let p=pixels[i],r=Int(p&255),g=Int(p>>8&255),b=Int(p>>16&255)
            let y=(77*r+150*g+29*b+128)>>8
            let cb=clamp(((-43*r-85*g+128*b+128)>>8)+128)
            let cr=clamp(((128*r-107*g-21*b+128)>>8)+128)
            out[i]=UInt32(y|cb<<8|cr<<16)|(p&0xff000000)
        }
        for y in stride(from:0,to:h,by:2) { for x in stride(from:0,to:w,by:2) {
            let right=min(w,x+2),bottom=min(h,y+2),count=(right-x)*(bottom-y)
            var cb=0,cr=0
            for yy in y..<bottom { for xx in x..<right { let p=out[yy*w+xx];cb+=Int(p>>8&255);cr+=Int(p>>16&255) } }
            let chroma=UInt32((cb+count/2)/count)<<8|UInt32((cr+count/2)/count)<<16
            for yy in y..<bottom { for xx in x..<right { let i=yy*w+xx;out[i]=(out[i]&0xff0000ff)|chroma } }
        } }
        return out
    }
    private static func rgb(_ pixels: [UInt32])->[UInt32] {
        pixels.map { p in
            let y=Int(p&255),cb=Int(p>>8&255)-128,cr=Int(p>>16&255)-128
            let r=clamp(y+((359*cr+128)>>8)),g=clamp(y-((88*cb+183*cr+128)>>8)),b=clamp(y+((454*cb+128)>>8))
            return (p&0xff000000)|UInt32(r)|UInt32(g)<<8|UInt32(b)<<16
        }
    }
    @inline(__always) private static func sample(_ pixels: [UInt32],_ x2: Int,_ y2: Int,_ w: Int,_ h: Int)->UInt32 {
        let xx=max(0,min((w-1)*2,x2)),yy=max(0,min((h-1)*2,y2)),x=xx>>1,y=yy>>1
        let at=y*w+x,a=pixels[at],fx=xx&1,fy=yy&1
        if fx==0 && fy==0 { return a }
        let b=pixels[at+fx],c=pixels[at+fy*w],d=pixels[at+fx+fy*w]
        // Average separate 16-bit lanes; all three channels round identically.
        let yc=(((a&0x00ff00ff)+(b&0x00ff00ff)+(c&0x00ff00ff)+(d&0x00ff00ff)+0x00020002)>>2)&0x00ff00ff
        let cb=(((a>>8&255)+(b>>8&255)+(c>>8&255)+(d>>8&255)+2)>>2)<<8
        let alpha=((a>>24)+(b>>24)+(c>>24)+(d>>24)+2)>>2
        return yc|cb|alpha<<24
    }
    private mutating func packet(_ current: [UInt32],tick: Int,step: Int)->[UInt32] {
        let w=width,h=height,cols=(w+15)/16,rows=(h+15)/16,oldX=motionX,oldY=motionY
        var reconstructed=current
        motionX=[Int16](repeating:0,count:cols*rows);motionY=motionX
        residual=[UInt32](repeating:0x80808080,count:w*h)
        let radius=min(32,max(8,step*8))*2
        for row in 0..<rows { for col in 0..<cols {
            let bx=col*16,by=row*16,index=row*cols+col,bw=min(16,w-bx),bh=min(16,h-by)
            // Sparse 4x4 SAD grid plus a small vector cost prevents drifting
            // on flat colors. Neighbor predictors keep coherent pans cheap.
            func score(_ dx: Int,_ dy: Int)->Int {
                var sum=(abs(dx)+abs(dy))/2
                for gy in 0..<4 { for gx in 0..<4 {
                    let x=bx+min(bw-1,(gx*2+1)*bw/8),y=by+min(bh-1,(gy*2+1)*bh/8)
                    let a=current[y*w+x],b=Self.sample(clean,x*2+dx,y*2+dy,w,h)
                    sum+=abs(Int(a&255)-Int(b&255))
                    sum+=(abs(Int(a>>8&255)-Int(b>>8&255))+abs(Int(a>>16&255)-Int(b>>16&255)))/4
                } }
                return sum
            }
            var dx=0,dy=0,best=score(0,0)
            func consider(_ x: Int,_ y: Int) {
                guard abs(x)<=radius && abs(y)<=radius else { return }
                let error=score(x,y)
                if error<best { best=error;dx=x;dy=y }
            }
            if best>16 {
                if oldX.count==cols*rows { consider(Int(oldX[index]),Int(oldY[index])) }
                if col>0 { consider(Int(motionX[index-1]),Int(motionY[index-1])) }
                if row>0 { consider(Int(motionX[index-cols]),Int(motionY[index-cols])) }
                // Try ordinary two-pixel game motion before the wide search:
                // repeated textures can otherwise trap coarse search far away.
                for sy in -1...1 { for sx in -1...1 where sx != 0 || sy != 0 { consider(sx*4,sy*4) } }
                // Coarse-to-fine search followed by half-pixel refinement.
                for distance in [16,8,4,2,1] where best>16 {
                    let cx=dx,cy=dy
                    for sy in -1...1 { for sx in -1...1 where sx != 0 || sy != 0 {
                        consider(cx+sx*distance,cy+sy*distance)
                    } }
                    if best<=16 { break }
                }
            }
            // An unmatched block would need intra refresh. Drop that refresh
            // and conceal with its existing pixels, rather than invent motion.
            guard best<16*30 else { continue }
            motionX[index]=Int16(dx);motionY[index]=Int16(dy)
            for y in by..<by+bh { for x in bx..<bx+bw {
                let at=y*w+x,a=current[at],b=Self.sample(clean,x*2+dx,y*2+dy,w,h)
                // Quantized P-frame correction. These are signed component
                // errors against the CLEAN reference, never the damaged one.
                let ry=(Int(a&255)-Int(b&255))/4+128
                let cb=(Int(a>>8&255)-Int(b>>8&255))/8+128
                let cr=(Int(a>>16&255)-Int(b>>16&255))/8+128
                let ra=(Int(a>>24)-Int(b>>24))/4+128
                residual[at]=UInt32(ry|cb<<8|cr<<16|ra<<24)
                // The healthy encoder also uses its reconstructed reference.
                // Otherwise rounding alone would accumulate unintended drift,
                // even before any refresh packets were deliberately removed.
                let yy=Int(b&255)+(ry-128)*4,cbb=Int(b>>8&255)+(cb-128)*8,crr=Int(b>>16&255)+(cr-128)*8
                let aa=Int(b>>24)+(ra-128)*4
                reconstructed[at]=UInt32(yy|cbb<<8|crr<<16|aa<<24)
            } }
        } }
        packetTick=tick;packetStep=step
        return reconstructed
    }
    mutating func render(_ image: ArtBitmap,mode selected: Int,tick: Int,memory: Int)->[UInt32] {
        let w=image.width,h=image.height
        if lastTick<0 || selected != mode {
            width=w;height=h;mode=selected;lastTick=tick;anchorTick=tick;packetTick = -1
            clean=Self.encode(image.pixels,w,h);decoded=clean;residual=[];motionX=[];motionY=[]
            return Self.rgb(decoded)
        }
        if w != width || h != height {
            clean=ArtBitmap(width:width,height:height,pixels:clean).resized(w,h).pixels
            decoded=ArtBitmap(width:width,height:height,pixels:decoded).resized(w,h).pixels
            width=w;height=h;packetTick = -1;residual=[];motionX=[];motionY=[]
        }
        guard tick>lastTick else { return Self.rgb(decoded) }
        let step=max(1,min(12,tick-lastTick)),current=Self.encode(image.pixels,w,h)
        var nextClean=current
        defer { clean=nextClean;lastTick=tick }
        // Simulate removing scheduled I frames. Encoder advances; decoder
        // retains the wrong reference. Real scene cuts also fail the intra
        // block test above and do not silently reseed the damaged canvas.
        if selected==1 && tick-anchorTick>=memory {
            anchorTick=tick;return Self.rgb(decoded)
        }
        if selected==1 || packetTick<0 || tick-packetTick>=max(6,memory/4) {
            nextClean=packet(current,tick:tick,step:step)
        }
        let source=decoded,cols=(w+15)/16
        var out=[UInt32](repeating:0,count:w*h)
        for by in stride(from:0,to:h,by:16) { for bx in stride(from:0,to:w,by:16) {
            let i=by/16*cols+bx/16
            let dx=Int(motionX[i])*step/packetStep,dy=Int(motionY[i])*step/packetStep
            for y in by..<min(h,by+16) { for x in bx..<min(w,bx+16) {
                let at=y*w+x,p=Self.sample(source,x*2+dx,y*2+dy,w,h),r=residual[at]
                let yy=Self.clamp(Int(p&255)+(Int(r&255)-128)*4*step/packetStep)
                let cb=Self.clamp(Int(p>>8&255)+(Int(r>>8&255)-128)*8*step/packetStep)
                let cr=Self.clamp(Int(p>>16&255)+(Int(r>>16&255)-128)*8*step/packetStep)
                let alpha=Self.clamp(Int(p>>24)+(Int(r>>24)-128)*4*step/packetStep)
                out[at]=UInt32(yy|cb<<8|cr<<16|alpha<<24)
            } }
        } }
        decoded=out;return Self.rgb(out)
    }
}
