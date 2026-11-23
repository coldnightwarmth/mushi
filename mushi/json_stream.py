"""Bounded JSON iteration for the large generated evidence manifests."""
import json


class Reader:
    def __init__(self, stream):
        self.stream=stream;self.buffer='';self.offset=0;self.eof=False
        self.decoder=json.JSONDecoder()

    def more(self):
        self.buffer=self.buffer[self.offset:];self.offset=0
        chunk=self.stream.read(65536)
        if not chunk:self.eof=True
        self.buffer+=chunk
        return bool(chunk)

    def peek(self):
        while True:
            while self.offset<len(self.buffer) and self.buffer[self.offset].isspace():self.offset+=1
            if self.offset<len(self.buffer):return self.buffer[self.offset]
            if self.eof or not self.more():return ''

    def expect(self, token):
        if self.peek()!=token:raise ValueError(f'Expected JSON delimiter {token!r}')
        self.offset+=1

    def value(self):
        if not self.peek():raise ValueError('Truncated JSON value')
        while True:
            try:
                value,end=self.decoder.raw_decode(self.buffer,self.offset)
                # A number may end exactly on a read boundary, before its next
                # digit arrives. Require a delimiter or EOF before yielding.
                if end==len(self.buffer) and not self.eof:
                    self.more();continue
                if end<len(self.buffer) and self.buffer[end] not in ',]}: \r\n\t':
                    if self.eof:raise ValueError('Invalid character after JSON value')
                    self.more();continue
                self.offset=end;return value
            except json.JSONDecodeError:
                if self.eof:raise
                self.more()

    def array(self):
        self.expect('[')
        if self.peek()!=']':
            while True:
                yield self.value()
                if self.peek()==']':break
                self.expect(',')
        self.expect(']')

    def finish(self):
        if self.peek():raise ValueError('Trailing data after JSON document')


def array_records(stream):
    reader=Reader(stream)
    yield from reader.array()
    reader.finish()


def manifest_records(stream):
    """Yield ordinary top-level fields and one observed entry at a time."""
    reader=Reader(stream);reader.expect('{')
    if reader.peek()!='}':
        while True:
            key=reader.value()
            if not isinstance(key,str):raise ValueError('JSON object key is not a string')
            reader.expect(':')
            if key=='observed':
                for record in reader.array():yield 'observed_record',record
            else:yield key,reader.value()
            if reader.peek()=='}':break
            reader.expect(',')
    reader.expect('}');reader.finish()
