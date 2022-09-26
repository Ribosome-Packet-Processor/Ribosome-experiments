import json
import time
import os

p4 = bfrt.ribosome_mcast

PIPE_NUM = 1

ENABLE_RECIRCULATION = 0
DROP_THRESHOLD = 0  # If set, only 1/DROP_THRESHOLD packets are sent out the switch

previous_pkts_count = 0
previous_bytes_count = 0

start_ts = time.time()


def run_pd_rpc(cmd_or_code, no_print=False):
    """
    This function invokes run_pd_rpc.py tool. It has a single string argument
    cmd_or_code that works as follows:
       If it is a string:
            * if the string starts with os.sep, then it is a filename
            * otherwise it is a piece of code (passed via "--eval"
       Else it is a list/tuple and it is passed "as-is"

    Note: do not attempt to run the tool in the interactive mode!
    """
    import subprocess

    path = os.path.join("/home", "tofino", "tools", "run_pd_rpc.py")

    command = [path]
    if isinstance(cmd_or_code, str):
        if cmd_or_code.startswith(os.sep):
            command.extend(["--no-wait", cmd_or_code])
        else:
            command.extend(["--no-wait", "--eval", cmd_or_code])
    else:
        command.extend(cmd_or_code)

    result = subprocess.check_output(command).decode("utf-8")[:-1]
    if not no_print:
        print(result)

    return result


def port_stats():
    import struct

    global p4, previous_pkts_count, previous_bytes_count, time, start_ts, PIPE_NUM

    received_pkts_reg_lo = p4.pipe.Ingress.received_packet_number_lo.dump(from_hw=1, json=1)
    received_pkts_lo = json.loads(received_pkts_reg_lo)
    received_pkts_reg_hi = p4.pipe.Ingress.received_packet_number_hi.dump(from_hw=1, json=1)
    received_pkts_hi = json.loads(received_pkts_reg_hi)
    received_bytes_reg_lo = p4.pipe.Ingress.received_packet_size_lo.dump(from_hw=1, json=1)
    received_bytes_lo = json.loads(received_bytes_reg_lo)
    received_bytes_reg_hi = p4.pipe.Ingress.received_packet_size_hi.dump(from_hw=1, json=1)
    received_bytes_hi = json.loads(received_bytes_reg_hi)

    total_pkts_received = struct.pack('>II',
                                      received_pkts_hi[0]['data']['Ingress.received_packet_number_hi.f1'][PIPE_NUM],
                                      received_pkts_lo[0]['data']['Ingress.received_packet_number_lo.f1'][PIPE_NUM]
                                      )

    total_bytes_received = struct.pack('>II',
                                       received_bytes_hi[0]['data']['Ingress.received_packet_size_hi.f1'][PIPE_NUM],
                                       received_bytes_lo[0]['data']['Ingress.received_packet_size_lo.f1'][PIPE_NUM]
                                       )

    total_pkts_received = struct.unpack('>Q', total_pkts_received)[0]
    total_bytes_received = struct.unpack('>Q', total_bytes_received)[0]

    dbytes = total_bytes_received - previous_bytes_count
    dpkts = total_pkts_received - previous_pkts_count

    ts = time.time() - start_ts
    print("MCAST-%f-RESULT-MC_PPS %f pps" % (ts, dpkts))
    print("Total : %d packets" % total_pkts_received)
    print("MCAST-%f-RESULT-MC_BPS %f bps" % (ts, dbytes * 8))
    print("Link Rate: %f b/s" % ((dbytes + (dpkts * 24)) * 8))
    print("Total Bytes: %f" % total_bytes_received)
    previous_pkts_count = total_pkts_received
    previous_bytes_count = total_bytes_received

    sent_pkts_reg_lo = p4.pipe.Egress.sent_packet_number_lo.dump(from_hw=1, json=1)
    sent_pkts_lo = json.loads(sent_pkts_reg_lo)
    sent_pkts_reg_hi = p4.pipe.Egress.sent_packet_number_hi.dump(from_hw=1, json=1)
    sent_pkts_hi = json.loads(sent_pkts_reg_hi)
    sent_bytes_reg_lo = p4.pipe.Egress.sent_packet_size_lo.dump(from_hw=1, json=1)
    sent_bytes_lo = json.loads(sent_bytes_reg_lo)
    sent_bytes_reg_hi = p4.pipe.Egress.sent_packet_size_hi.dump(from_hw=1, json=1)
    sent_bytes_hi = json.loads(sent_bytes_reg_hi)

    total_pkts_sent = struct.pack('>II',
                                  sent_pkts_hi[0]['data']['Egress.sent_packet_number_hi.f1'][PIPE_NUM],
                                  sent_pkts_lo[0]['data']['Egress.sent_packet_number_lo.f1'][PIPE_NUM]
                                  )

    total_bytes_sent = struct.pack('>II',
                                   sent_bytes_hi[0]['data']['Egress.sent_packet_size_hi.f1'][PIPE_NUM],
                                   sent_bytes_lo[0]['data']['Egress.sent_packet_size_lo.f1'][PIPE_NUM]
                                   )

    total_pkts_sent = struct.unpack('>Q', total_pkts_sent)[0]
    total_bytes_sent = struct.unpack('>Q', total_bytes_sent)[0]

    print("Total Packets Sent: %f" % total_pkts_sent)
    print("Total Bytes Sent: %f" % total_bytes_sent)


def port_stats_timer():
    import threading

    global port_stats_timer, port_stats
    port_stats()
    threading.Timer(1, port_stats_timer).start()


run_pd_rpc(os.path.join(os.environ['HOME'], "labs/multicast_tofino/run_pd_rpc/setup.py"))

p4.pipe.Ingress.enable_recirculation.add(f1=ENABLE_RECIRCULATION, REGISTER_INDEX=0)
p4.pipe.Ingress.drop_threshold.add(f1=DROP_THRESHOLD, REGISTER_INDEX=0)

port_stats_timer()
