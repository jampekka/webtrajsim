#!/usr/bin/env python3
import zmq, msgpack, time
from msgpack import loads
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
    sub.setsockopt_string(zmq.SUBSCRIBE, '')

    while True:
       
        topic = sub.recv_string()
        recv_ts_mono = time.monotonic()
        recv_ts = time.time()

        msg = sub.recv()
        data = loads(msg, encoding='utf-8')
        msg = dict(
            recv_ts=recv_ts,
            recv_ts_mono=recv_ts_mono,
            topic=topic,
            data=data
        )
        json.dump(msg, sys.stdout)
        sys.stdout.write('\n')
        sys.stdout.flush()

while True: dumper()
