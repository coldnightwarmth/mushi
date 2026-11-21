import Foundation

/// Bounded presentation history. Connected native sprite pieces grow around
/// their own centers; sparse pixels keep ordinary trails cheap to composite.
final class FutariTrails {
    struct Dot {let at:Int;let color:UInt32}
    struct Stamp {let x,y:Int;let bitmap:ArtBitmap}
    struct Echo {let tick:Int,dots:[Dot],stamps:[Stamp]}
    private var echoes=[Echo](),size=(0,0),lastTick = -1,style=TrailStyle.off
    func clear(){echoes=[];lastTick = -1;size=(0,0)}
    private func stamps(_ image:ArtBitmap)->[Stamp] {
        let w=image.width,h=image.height
        var visited=[Bool](repeating:false,count:w*h),result=[Stamp]()
        for start in image.pixels.indices where !visited[start] && image.pixels[start]>>24>0 {
            var queue=[start],cursor=0,left=start%w,right=left,top=start/w,bottom=top
            visited[start]=true
            while cursor<queue.count {
                let i=queue[cursor],x=i%w,y=i/w;cursor+=1
                left=min(left,x);right=max(right,x);top=min(top,y);bottom=max(bottom,y)
                for p in [x>0 ? i-1:-1,x+1<w ? i+1:-1,y>0 ? i-w:-1,y+1<h ? i+w:-1] where p>=0 && !visited[p] && image.pixels[p]>>24>0 {
                    visited[p]=true;queue.append(p)
                }
            }
            var bitmap=ArtBitmap(width:right-left+1,height:bottom-top+1)
            for i in queue {bitmap.pixels[(i/w-top)*bitmap.width+i%w-left]=image.pixels[i]}
            result.append(Stamp(x:left,y:top,bitmap:bitmap))
        }
        return result
    }
    func render(_ source:ArtBitmap,over background:inout ArtBitmap,tick:Int,style:TrailStyle) {
        if self.style != style || size != (source.width,source.height) {clear();self.style=style;size=(source.width,source.height)}
        guard style != .off else{return}
        if tick<lastTick {echoes.removeAll{$0.tick>tick}}
        if tick != lastTick && tick%Int(style.captureInterval)==0 {
            let dots=source.pixels.indices.compactMap{source.pixels[$0]>>24>0 ? Dot(at:$0,color:source.pixels[$0]):nil}
            echoes.append(Echo(tick:tick,dots:dots,stamps:style.scaleRate>0 ? stamps(source):[]))
        }
        lastTick=tick;echoes.removeAll{tick-$0.tick>180}
        if echoes.count>120 {echoes.removeFirst(echoes.count-120)}
        let w=background.width,h=background.height
        for echo in echoes where echo.tick<tick {
            let age=tick-echo.tick
            if style == .loop && (age/30)%2==1 {continue}
            let hash=UInt64(echo.tick) &* 0x9e3779b97f4a7c15
            if style == .flash && (tick/(3+Int((hash^(hash>>31))%11)))%2==1 {continue}
            let alpha=style == .fade ? max(0,255-age*255/180):255
            if style.scaleRate==0 {
                for dot in echo.dots {background.pixels[dot.at]=alpha==255 ? dot.color:ArtEffectEngine.mix(background.pixels[dot.at],dot.color,alpha)}
            } else {
                let scale=1+Double(age)*style.scaleRate/600
                for stamp in echo.stamps {
                    let sw=stamp.bitmap.width,sh=stamp.bitmap.height,cx=Double(stamp.x)+Double(sw)/2,cy=Double(stamp.y)+Double(sh)/2
                    let x0=max(0,Int(floor(cx-Double(sw)*scale/2))),x1=min(w,Int(ceil(cx+Double(sw)*scale/2)))
                    let y0=max(0,Int(floor(cy-Double(sh)*scale/2))),y1=min(h,Int(ceil(cy+Double(sh)*scale/2)))
                    guard x0<x1 && y0<y1 else{continue}
                    let columns=(x0..<x1).map{Int((Double($0)+0.5-cx)/scale+Double(sw)/2)}
                    for y in y0..<y1 {
                        let sy=Int((Double(y)+0.5-cy)/scale+Double(sh)/2);if sy<0 || sy>=sh {continue}
                        for (column,sx) in columns.enumerated() where sx>=0 && sx<sw {
                            let c=stamp.bitmap.pixels[sy*sw+sx];if c>>24>0 {background.pixels[y*w+x0+column]=c}
                    }}
                }
            }
        }
    }
}
