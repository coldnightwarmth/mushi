import Foundation
import Compression

/// Lossless packed arrays used by the bounded visual frame history.
struct RewindWriter {
    var data=Data()
    init(capacity: Int=1_048_576) { data.reserveCapacity(capacity) }
    mutating func array<T: FixedWidthInteger>(_ values: [T],paddedCount: Int?=nil) {
        let length=paddedCount ?? values.count
        precondition(length>=values.count)
        var count=UInt32(length).littleEndian
        withUnsafeBytes(of:&count) { data.append(contentsOf:$0) }
        values.withUnsafeBytes { data.append(contentsOf:$0) }
        // Data initializes only the newly appended padding; no temporary audio
        // array or second copy of the real samples is needed.
        data.count+=(length-values.count)*MemoryLayout<T>.stride
    }
}
struct RewindReader {
    let data: Data
    var offset=0
    mutating func array<T: FixedWidthInteger>(_ type: T.Type) -> [T] {
        precondition(offset+4<=data.count)
        let count=(0..<4).reduce(0) { $0 | Int(data[offset+$1])<<($1*8) }
        offset+=4
        let bytes=count*MemoryLayout<T>.stride
        precondition(offset+bytes<=data.count)
        var values=[T](repeating:0,count:count)
        if bytes != 0 {
            values.withUnsafeMutableBytes { target in
                data.withUnsafeBytes { source in
                    target.baseAddress!.copyMemory(from:source.baseAddress!.advanced(by:offset),byteCount:bytes)
                }
            }
        }
        offset+=bytes;return values
    }
}
struct RewindMemory {
    let data: Data,originalCount: Int,compressed: Bool
    fileprivate init(data: Data,originalCount: Int,compressed: Bool) {
        self.data=data;self.originalCount=originalCount;self.compressed=compressed
    }
    init(_ raw: Data,compress: Bool=true) {
        originalCount=raw.count
        if !compress || raw.isEmpty { data=raw;compressed=false;return }
        // The encoder initializes only its result. Clearing a worst-case
        // full-level trail buffer first writes megabytes that are never used.
        let output=[UInt8](unsafeUninitializedCapacity:raw.count+raw.count/255+64) { destination,initialized in
            initialized=raw.withUnsafeBytes { source in
                compression_encode_buffer(destination.baseAddress!,destination.count,
                    source.bindMemory(to:UInt8.self).baseAddress!,raw.count,nil,COMPRESSION_LZ4)
            }
        }
        compressed = !output.isEmpty && output.count<raw.count
        data=compressed ? Data(output):raw
    }
    func reader() -> RewindReader {
        guard compressed else { return RewindReader(data:data) }
        var output=Data(count:originalCount)
        let count=output.withUnsafeMutableBytes { destination in
            data.withUnsafeBytes { source in
                compression_decode_buffer(destination.bindMemory(to:UInt8.self).baseAddress!,originalCount,
                    source.bindMemory(to:UInt8.self).baseAddress!,data.count,nil,COMPRESSION_LZ4)
            }
        }
        precondition(count==originalCount,"Corrupt rewind memory")
        return RewindReader(data:output)
    }
}
