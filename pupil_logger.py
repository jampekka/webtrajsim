#!/usr/bin/env python3
import zmq, msgpack, time
from msgpack import unpackb
import json
import sys


def dumper():
    ctx = zmq.Context()
    req = ctx.socket(zmq.REQ)

    req.connect('tcp://0.0.0.0:50020')
    req.send_string('SUB_PORT')
    sub_port = req.recv_string()
    sub = ctx.socket(zmq.SUB)
    sub.connect("tcp://0.0.0.0:{}".format(sub_port))
    sub.setsockopt(zmq.SUBSCRIBE, b'')



    while True:
        #topic = sub.recv_string()
        topic, *data = sub.recv_multipart()
        if topic.startswith(b'frame.'):
            # Skip frames. zmq.INVERT_MATCHING doesn't seem to work :(
            continue
        recv_ts_mono = time.monotonic()
        recv_ts = time.time()

        msg = data[0]
        data = unpackb(msg, raw=False)
        
        print(data)
        msg = dict(
            recv_ts=recv_ts,
            recv_ts_mono=recv_ts_mono,
            topic=topic.decode('utf-8'),
            data=data
        )
        json.dump(msg, sys.stdout)
        sys.stdout.write('\n')
        sys.stdout.flush()

while True: dumper()
