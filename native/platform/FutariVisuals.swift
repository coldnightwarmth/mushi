import AppKit

/// Shared art engine, fed by Futari's recovered native draw priorities.
final class FutariVisuals {
    let engine=ArtEffectEngine()
    let trails=FutariTrails()
    private let groupTrails=(0..<4).map{_ in FutariTrails()}
    private var lastTick = -1
    private var context=0
    private var previousEffects: ArtBitmap?
    private struct SavedFrame {let tick,width,height:Int,memory:RewindMemory}
    private var history=[SavedFrame](),historyBytes=0
    func clear(){trails.clear();groupTrails.forEach{$0.clear()};lastTick = -1;previousEffects=nil;context+=1;history=[];historyBytes=0}
    private func layer(_ game:FutariGame,_ world:UInt32,_ kind:Int,_ w:Int,_ h:Int)->ArtBitmap {
        var bytes=[UInt8](repeating:0,count:w*h*4)
        futari_layer_pixels(game,world,Int32(kind),Int32(w),Int32(h),&bytes)
        let colors=stride(from:0,to:bytes.count,by:4).map { i in UInt32(bytes[i])|UInt32(bytes[i+1])<<8|UInt32(bytes[i+2])<<16|UInt32(bytes[i+3])<<24 }
        return ArtBitmap(width:w,height:h,pixels:colors)
    }
    private func overlay(_ fg:ArtBitmap,_ bg:inout ArtBitmap) {
        for i in bg.pixels.indices where fg.pixels[i]>>24 != 0 {
            let a=fg.pixels[i],b=bg.pixels[i],aa=Int(a>>24),ba=Int(b>>24)
            if aa==255 {bg.pixels[i]=a;continue}
            let bw=ba*(255-aa)/255,alpha=aa+bw
            var pixel=UInt32(alpha)<<24
            for shift in [0,8,16] {pixel |= UInt32((Int(a>>shift&255)*aa+Int(b>>shift&255)*bw)/alpha)<<shift}
            bg.pixels[i]=pixel
        }
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
            if rewinding {
                for plan in options.artScopes.plans where plan.options.active {
                    let target=options.artScopes.plans.count==1 ? engine:engine.layerEngine(plan.groups.rawValue)
                    _=target.render(ArtFrame(image:scene),options:plan.options,tick:tick,context:effectContext,rewinding:true)
                }
            }
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
        var groups=(6..<10).map{layer(game,0,$0,w,h)}
        var randomGroups=options.trailStyle == .random ? (10..<14).map{layer(game,0,$0,w,h)}:[]
        var woven=[ArtBitmap]()
        for world in 1..<status.worlds where futari_world_status(game,world).phase==3 {
            let peer=layer(game,world,1,w,h),sprites=layer(game,world,2,w,h),burst=layer(game,world,4,w,h)
            woven.append(peer)
            for i in scene.pixels.indices {background.pixels[i]=ArtEffectEngine.mix(background.pixels[i],peer.pixels[i],96)}
            overlay(sprites,&actors);overlay(burst,&effects)
            for group in 0..<4 {
                let peerGroup=layer(game,world,6+group,w,h)
                // A visible peer actor owns its destination even when its group differs.
                for i in groups[group].pixels.indices where sprites.pixels[i]>>24>0 {groups[group].pixels[i]=peerGroup.pixels[i]}
                if !randomGroups.isEmpty {let random=layer(game,world,10+group,w,h);overlay(random,&randomGroups[group])}
            }
        }
        if options.background != .art {background.pixels=[UInt32](repeating:options.background.rgba,count:w*h)}
        var groupImages=[ArtBitmap]()
        for group in 0..<4 {
            var echoes=ArtBitmap(width:w,height:h)
            groupTrails[group].render(randomGroups.isEmpty ? groups[group]:randomGroups[group],over:&echoes,tick:tick,style:options.trailStyle)
            // Echoes stay behind all live sprites, including different target groups.
            for i in echoes.pixels.indices where actors.pixels[i]>>24>0 {echoes.pixels[i]=0}
            var image=group==0 ? background:ArtBitmap(width:w,height:h)
            overlay(echoes,&image);overlay(groups[group],&image);groupImages.append(image)
        }
        scene=groupImages[0]
        for group in 1..<4 {overlay(groupImages[group],&scene)}
        var frame=ArtFrame(image:scene,sprites:actors,effects:effects)
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
        let plans=options.artScopes.plans
        var result:ArtBitmap
        if !options.artScopes.active {
            engine.retainLayerEngines([]);result=scene
        } else if plans.count==1 {
            engine.retainLayerEngines([])
            result=engine.render(frame,options:plans[0].options,tick:tick,context:effectContext,rewinding:false)
        } else {
            engine.retainLayerEngines(Set(plans.filter{$0.options.active}.map{$0.groups.rawValue}))
            result=ArtBitmap(width:w,height:h)
            var deathOwners=[ArtEffect:UInt8](),typographyModes=Set<Int>()
            for effect in [ArtEffect.pixelSediment,.tileShuffle] {
                for group:ArtGroup in [.enemies,.background,.otherActors,.player] {
                    if let plan=plans.first(where:{$0.groups.contains(group.mask) && $0.options[effect]>0}) {deathOwners[effect]=plan.groups.rawValue;break}
                }
            }
            for plan in plans {
                var input=ArtBitmap(width:w,height:h),sprites=input
                for (index,group) in ArtGroup.allCases.enumerated() where plan.groups.contains(group.mask) {
                    overlay(groupImages[index],&input);overlay(groups[index],&sprites)
                }
                var scoped=ArtFrame(image:input)
                scoped.transparent = !plan.groups.contains(.background)
                scoped.sprites=sprites
                if plan.groups.contains(.background) {scoped.effects=effects;scoped.blooms=frame.blooms;scoped.woven=woven}
                scoped.deaths=frame.deaths
                scoped.deathEffects=Set(deathOwners.compactMap{$0.value==plan.groups.rawValue ? $0.key:nil})
                scoped.playerX=frame.playerX;scoped.playerY=frame.playerY;scoped.words=frame.words
                let typography=plan.options[.typography]
                if typography>0 && typographyModes.insert(typography).inserted {scoped.typographyStamps=frame.typographyStamps}
                let output=plan.options.active ? engine.layerEngine(plan.groups.rawValue).render(scoped,options:plan.options,tick:tick,context:effectContext):input
                overlay(output,&result)
            }
            // A protected live actor must stay clear even when another group's
            // spatial effect moves pixels across its original silhouette.
            for plan in plans where !plan.options.active {
                for (index,group) in ArtGroup.allCases.enumerated() where index>0 && plan.groups.contains(group.mask) {
                    overlay(groupImages[index],&result)
                }
            }
        }
        if !hideHUD {overlay(hud,&result)}
        if history.last?.tick==tick {historyBytes-=history.removeLast().memory.data.count}
        var writer=RewindWriter(capacity:w*h*4+4);writer.array(result.pixels)
        let saved=SavedFrame(tick:tick,width:w,height:h,memory:RewindMemory(writer.data));history.append(saved);historyBytes+=saved.memory.data.count
        while history.count>1 && (historyBytes>64*1024*1024 || history.count>600) {historyBytes-=history.removeFirst().memory.data.count}
        return result
    }
}
