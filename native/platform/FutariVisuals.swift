import AppKit

/// Shared art engine, fed by Futari's recovered native draw priorities.
final class FutariVisuals {
    let engine=ArtEffectEngine()
    let trails=FutariTrails()
    private var lastTick = -1
    private var context=0
    private var previousEffects: ArtBitmap?
    private struct SavedFrame {let tick,width,height:Int,memory:RewindMemory}
    private var history=[SavedFrame](),historyBytes=0
    func clear(){trails.clear();lastTick = -1;previousEffects=nil;context+=1;history=[];historyBytes=0}
    private func layer(_ game:FutariGame,_ world:UInt32,_ kind:Int,_ w:Int,_ h:Int)->ArtBitmap {
        var bytes=[UInt8](repeating:0,count:w*h*4)
        futari_layer_pixels(game,world,Int32(kind),Int32(w),Int32(h),&bytes)
        let colors=stride(from:0,to:bytes.count,by:4).map { i in UInt32(bytes[i])|UInt32(bytes[i+1])<<8|UInt32(bytes[i+2])<<16|UInt32(bytes[i+3])<<24 }
        return ArtBitmap(width:w,height:h,pixels:colors)
    }
    private func overlay(_ fg:ArtBitmap,_ bg:inout ArtBitmap) {
        for i in bg.pixels.indices where fg.pixels[i]>>24 != 0 {bg.pixels[i]=fg.pixels[i]}
    }
    func render(_ game:FutariGame,options:CustomGameOptions,hideHUD:Bool,rewinding:Bool,width:Int,height:Int)->ArtBitmap {
        let tick=Int(futari_frame_number(game)),status=futari_custom_status(game)
        let w=width,h=height
        let effectContext="futari-\(context)-\(futari_status(game).stage)"
        if tick<lastTick {previousEffects=nil}
        var scene=layer(game,0,0,w,h),background=layer(game,0,1,w,h)
        var actors=layer(game,0,2,w,h),effects=layer(game,0,4,w,h)
        let hud=layer(game,0,3,w,h)
        // Menus, loading and rewinding preserve their original completed framebuffer.
        if rewinding || futari_presentation_ready(game)==0 {
            if rewinding {_=engine.render(ArtFrame(image:scene),options:options.art,tick:tick,context:effectContext,rewinding:true)}
            if let saved=history.last(where:{$0.tick<=tick}) {
                var reader=saved.memory.reader()
                return ArtBitmap(width:saved.width,height:saved.height,pixels:reader.array(UInt32.self)).resized(w,h)
            }
            return scene
        }
        if futari_scene(game) != 3 {
            if w==240 && h==320 {
                var bytes=[UInt8](repeating:0,count:w*h*4);futari_pixels(game,&bytes)
                scene.pixels=stride(from:0,to:bytes.count,by:4).map{i in UInt32(bytes[i])|UInt32(bytes[i+1])<<8|UInt32(bytes[i+2])<<16|0xff000000}
            }
            return scene
        }
        if history.last.map({$0.tick>tick})==true {history.removeAll{$0.tick>tick};historyBytes=history.reduce(0){$0+$1.memory.data.count}}
        var woven=[ArtBitmap]()
        for world in 1..<status.worlds where futari_world_status(game,world).phase==3 {
            let peer=layer(game,world,1,w,h),sprites=layer(game,world,2,w,h),burst=layer(game,world,4,w,h)
            woven.append(peer)
            for i in scene.pixels.indices {background.pixels[i]=ArtEffectEngine.mix(background.pixels[i],peer.pixels[i],96)}
            overlay(sprites,&actors);overlay(burst,&effects)
        }
        if options.background != .art {background.pixels=[UInt32](repeating:options.background.rgba,count:w*h)}
        var trailSource=actors
        if options.trailStyle == .random {
            trailSource=layer(game,0,5,w,h)
            for world in 1..<status.worlds where futari_world_status(game,world).phase==3 {let peer=layer(game,world,5,w,h);overlay(peer,&trailSource)}
        }
        trails.render(trailSource,over:&background,tick:tick,style:options.trailStyle)
        scene=background;overlay(actors,&scene)
        var frame=ArtFrame(image:options.art.backgroundOnly ? background:scene,sprites:actors,effects:effects)
        frame.woven=woven;frame.words=["FUTARI","1UP","ORIGINAL","INSERT COIN","GAME OVER"]
        frame.playerX=Double(Int(status.player_x)+(w-240)/2)/Double(w)
        frame.playerY=Double(Int(status.player_y)+(h-320)/2)/Double(h)
        // Extract native burst fragments and HUD lettering for the shared art engine.
        // Samples are taken from their own draw layers, never from the screen background.
        for y in stride(from:0,to:h,by:24) {for x in stride(from:0,to:w,by:24) {
            let sw=min(24,w-x),sh=min(24,h-y)
            var stamp=ArtBitmap(width:sw,height:sh),colors=[UInt32](),newPixels=0
            for yy in 0..<sh {for xx in 0..<sw {
                let i=(y+yy)*w+x+xx,c=effects.pixels[i];stamp.pixels[yy*sw+xx]=c
                if c>>24>0 {colors.append(c);if previousEffects?.pixels.count != effects.pixels.count || previousEffects!.pixels[i] != c {newPixels+=1}}
            }}
            if colors.count>12 && newPixels>8 {
                let key=(tick/12)*1000+y*w+x
                frame.blooms.append(ArtBloom(x:Double(x+sw/2)/Double(w),y:Double(y+sh/2)/Double(h),bitmap:stamp,key:key))
                frame.deaths.append(ArtDeath(key:UInt64(key),x:Double(x+sw/2)/Double(w),y:Double(y+sh/2)/Double(h),colors:Array(colors.prefix(64))))
            }
            if y<48 || y>h-48 {
                var glyph=ArtBitmap(width:sw,height:sh)
                for yy in 0..<sh {for xx in 0..<sw {glyph.pixels[yy*sw+xx]=hud.pixels[(y+yy)*w+x+xx]}}
                if glyph.pixels.contains(where:{$0>>24>0}){frame.typographyStamps.append(glyph)}
            }
        }}
        if tick != lastTick {previousEffects=effects;lastTick=tick}
        var result=engine.render(frame,options:options.art,tick:tick,context:effectContext,rewinding:false)
        if options.art.backgroundOnly {overlay(actors,&result)}
        if !hideHUD {overlay(hud,&result)}
        if history.last?.tick==tick {historyBytes-=history.removeLast().memory.data.count}
        var writer=RewindWriter(capacity:w*h*4+4);writer.array(result.pixels)
        let saved=SavedFrame(tick:tick,width:w,height:h,memory:RewindMemory(writer.data));history.append(saved);historyBytes+=saved.memory.data.count
        while history.count>1 && (historyBytes>64*1024*1024 || history.count>600) {historyBytes-=history.removeFirst().memory.data.count}
        return result
    }
}
