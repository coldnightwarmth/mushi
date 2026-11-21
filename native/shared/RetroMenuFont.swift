import AppKit

/// Small bitmap alphabet: no installed font, smoothing, or platform font metrics.
/// Coordinates are snapped to backing pixels before each solid pixel is drawn.
enum RetroMenuFont {
    private static let patterns: [Character:[UInt8]] = [
        "A":[14,17,17,31,17,17,17],"B":[30,17,17,30,17,17,30],
        "C":[14,17,16,16,16,17,14],"D":[30,17,17,17,17,17,30],
        "E":[31,16,16,30,16,16,31],"F":[31,16,16,30,16,16,16],
        "G":[14,17,16,23,17,17,15],"H":[17,17,17,31,17,17,17],
        "I":[14,4,4,4,4,4,14],"J":[7,2,2,2,18,18,12],
        "K":[17,18,20,24,20,18,17],"L":[16,16,16,16,16,16,31],
        "M":[17,27,21,21,17,17,17],"N":[17,25,21,19,17,17,17],
        "O":[14,17,17,17,17,17,14],"P":[30,17,17,30,16,16,16],
        "Q":[14,17,17,17,21,18,13],"R":[30,17,17,30,20,18,17],
        "S":[15,16,16,14,1,1,30],"T":[31,4,4,4,4,4,4],
        "U":[17,17,17,17,17,17,14],"V":[17,17,17,17,17,10,4],
        "W":[17,17,17,21,21,21,10],"X":[17,17,10,4,10,17,17],
        "Y":[17,17,10,4,4,4,4],"Z":[31,1,2,4,8,16,31],
        // Lowercase shares the capital baseline. Descenders use the two spare
        // rows inside the existing ten-pixel line spacing.
        "a":[0,0,14,1,15,17,15],"b":[16,16,30,17,17,17,30],
        "c":[0,0,14,16,16,17,14],"d":[1,1,15,17,17,17,15],
        "e":[0,0,14,17,31,16,14],"f":[6,9,8,28,8,8,8],
        "g":[0,0,15,17,17,17,15,1,14],"h":[16,16,30,17,17,17,17],
        "i":[4,0,12,4,4,4,14],"j":[2,0,6,2,2,2,2,18,12],
        "k":[16,16,18,20,24,20,18],"l":[12,4,4,4,4,4,14],
        "m":[0,0,26,21,21,21,21],"n":[0,0,30,17,17,17,17],
        "o":[0,0,14,17,17,17,14],"p":[0,0,30,17,17,17,30,16,16],
        "q":[0,0,15,17,17,17,15,1,1],"r":[0,0,22,25,16,16,16],
        "s":[0,0,15,16,14,1,30],"t":[8,8,28,8,8,9,6],
        "u":[0,0,17,17,17,17,15],"v":[0,0,17,17,17,10,4],
        "w":[0,0,17,17,21,21,10],"x":[0,0,17,10,4,10,17],
        "y":[0,0,17,17,17,17,15,1,14],"z":[0,0,31,2,4,8,31],
        "0":[14,17,19,21,25,17,14],"1":[4,12,4,4,4,4,14],
        "2":[14,17,1,2,4,8,31],"3":[30,1,1,14,1,1,30],
        "4":[2,6,10,18,31,2,2],"5":[31,16,16,30,1,1,30],
        "6":[14,16,16,30,17,17,14],"7":[31,1,2,4,8,8,8],
        "8":[14,17,17,14,17,17,14],"9":[14,17,17,15,1,1,14],
        ".":[0,0,0,0,0,12,12],", ".first!:[0,0,0,0,4,4,8],
        ":":[0,12,12,0,12,12,0],"; ".first!:[0,12,12,0,4,4,8],
        "- ".first!:[0,0,0,31,0,0,0],"+ ".first!:[0,4,4,31,4,4,0],
        "/":[1,2,2,4,8,8,16],"\\":[16,8,8,4,2,2,1],
        "(":[2,4,8,8,8,4,2],")":[8,4,2,2,2,4,8],
        "' ".first!:[4,4,8,0,0,0,0],"| ".first!:[4,4,4,4,4,4,4],
        "? ".first!:[14,17,1,2,4,0,4],"#":[10,31,10,10,31,10,0],
        "! ".first!:[4,4,4,4,4,0,4],"= ".first!:[0,0,31,0,31,0,0],
        "&":[12,18,20,8,21,18,13],"% ".first!:[25,25,2,4,8,19,19],
        "<":[2,4,8,16,8,4,2],">":[8,4,2,1,2,4,8],
        "↓":[4,4,4,4,21,14,4],"↑":[4,14,21,4,4,4,4],
        "·":[0,0,0,4,0,0,0],"×":[0,17,10,4,10,17,0],"−":[0,0,0,31,0,0,0]
    ]
    static func rows(_ character: Character) -> [UInt8] { patterns[character] ?? [] }
    static func draw(_ value: String,in rect: NSRect,scale requested: CGFloat,color: NSColor,right: Bool=false,wrapWords: Bool=false) {
        var value=value
        if wrapWords {
            let columns=max(1,Int((rect.width+requested)/(requested*6)))
            var lines=[String]()
            for paragraph in value.components(separatedBy:"\n") {
                var line=""
                for word in paragraph.split(whereSeparator: { $0.isWhitespace }) {
                    if !line.isEmpty && line.count+1+word.count>columns {
                        lines.append(line);line=""
                    }
                    if !line.isEmpty { line+=" " }
                    line+=String(word)
                }
                lines.append(line)
            }
            value=lines.joined(separator:"\n")
        }
        let chars=Array(value)
        let requested=rect.height<=22 && CGFloat(chars.count)*requested*6>rect.width ? min(requested,1):requested
        let step=requested*6,line=requested*10
        var x=right ? max(rect.minX,rect.maxX-CGFloat(chars.count)*step):rect.minX,y=rect.minY
        guard let context=NSGraphicsContext.current?.cgContext else { return }
        context.saveGState();context.setShouldAntialias(false);context.clip(to:rect)
        color.setFill()
        let path=NSBezierPath()
        for c in chars {
            if c=="\n" || x+5*requested>rect.maxX {
                x=rect.minX;y+=line
                if c=="\n" { continue }
            }
            if y+7*requested>rect.maxY { break }
            if let rows=patterns[c] {
                for (row,bits) in rows.enumerated() { for column in 0..<5 where bits & (1<<(4-column)) != 0 {
                    let a=context.convertToDeviceSpace(CGPoint(x:x+CGFloat(column)*requested,y:y+CGFloat(row)*requested))
                    let b=context.convertToDeviceSpace(CGPoint(x:x+CGFloat(column+1)*requested,y:y+CGFloat(row+1)*requested))
                    let p=context.convertToUserSpace(CGPoint(x:a.x.rounded(),y:a.y.rounded()))
                    let q=context.convertToUserSpace(CGPoint(x:b.x.rounded(),y:b.y.rounded()))
                    path.appendRect(NSRect(x:min(p.x,q.x),y:min(p.y,q.y),width:abs(q.x-p.x),height:abs(q.y-p.y)))
                } }
            }
            x+=step
        }
        path.fill();context.restoreGState()
    }
}
