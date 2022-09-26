/* -*- P4_16 -*- */

#include <core.p4>
#include <tna.p4>

#define PKTGEN_PORT 52
#define PKTGEN_IP 0x0a1b3cd6

const bit<9> RECIRCULATION_PORT = 196;

/* INGRESS */
/* Types */
enum bit<16> ether_type_t {
    IPV4 = 0x0800,
    IPV6 = 0x86DD
}

/* IPv4 protocol type */
enum bit<8> ipv4_protocol_t {
    TCP = 0x06,
    UDP = 0x11
}

typedef bit<48> mac_addr_t;

typedef bit<32> ipv4_addr_t;

/* Standard headers */
header ethernet_h {
    bit<16> dst_addr_1;
    bit<32> dst_addr_2;
    mac_addr_t src_addr;
    ether_type_t ether_type;
}

header ipv4_h {
    bit<4> version;
    bit<4> ihl;
    bit<6> dscp;
    bit<2> ecn;
    bit<16> total_len;
    bit<16> identification;
    bit<3> flags;
    bit<13> frag_offset;
    bit<8> ttl;
    ipv4_protocol_t protocol;
    bit<16> hdr_checksum;
    ipv4_addr_t src_addr;
    ipv4_addr_t dst_addr;
}

header tcp_h {
    bit<16> src_port;
    bit<16> dst_port;
    bit<32> seq_n;
    bit<32> ack_n;
    bit<4> data_offset;
    bit<4> res;
    bit<1> cwr;
    bit<1> ece;
    bit<1> urg;
    bit<1> ack;
    bit<1> psh;
    bit<1> rst;
    bit<1> syn;
    bit<1> fin;
    bit<16> window;
    bit<16> checksum;
    bit<16> urgent_ptr;
}

header udp_h {
    bit<16> src_port;
    bit<16> dst_port;
    bit<16> length;
    bit<16> checksum;
}

struct my_ingress_headers_t {
    ethernet_h ethernet;
    ipv4_h ipv4;
    tcp_h tcp;
    udp_h udp;
}

struct my_ingress_metadata_t {}

parser IngressParser(packet_in pkt, out my_ingress_headers_t hdr, out my_ingress_metadata_t meta, out ingress_intrinsic_metadata_t ig_intr_md) {
    /* This is a mandatory state, required by Tofino Architecture */
    state start {
        pkt.extract(ig_intr_md);
        pkt.advance(PORT_METADATA_SIZE);
        transition parse_ethernet;
    }

    state parse_ethernet {
        pkt.extract(hdr.ethernet);
        transition select(hdr.ethernet.ether_type) {
            ether_type_t.IPV4: parse_ipv4;
            default: accept;
        }
    }

    state parse_ipv4 {
        pkt.extract(hdr.ipv4);
        transition select(hdr.ipv4.protocol) {
            ipv4_protocol_t.TCP: parse_tcp;
            ipv4_protocol_t.UDP: parse_udp;
            default: accept;
        }
    }

    state parse_tcp {
        pkt.extract(hdr.tcp);
        transition accept;
    }

    state parse_udp {
        pkt.extract(hdr.udp);
        transition accept;
    }
}

control Ingress(inout my_ingress_headers_t hdr, inout my_ingress_metadata_t meta,
                in ingress_intrinsic_metadata_t ig_intr_md, in ingress_intrinsic_metadata_from_parser_t ig_prsr_md,
                inout ingress_intrinsic_metadata_for_deparser_t ig_dprsr_md, inout ingress_intrinsic_metadata_for_tm_t ig_tm_md) {
    Register<bit<32>, _>(1) received_packet_number_lo;
    Register<bit<32>, _>(1) received_packet_number_hi;

    RegisterAction<bit<32>, _, bit<32>>(received_packet_number_lo) received_packet_number_lo_increment = {
        void apply(inout bit<32> value, out bit<32> read_value) {
            value = value + 1;
            read_value = value;
        }
    };

    RegisterAction<bit<32>, _, bit<32>>(received_packet_number_hi) received_packet_number_hi_increment = {
        void apply(inout bit<32> value, out bit<32> read_value) {
            value = value + 1;
        }
    };

    bit<64> rx_packet_size;
    bit<32> rx_packet_size_inv;
    bit<32> hi_carry;
    Register<bit<32>, _>(1) received_packet_size_lo;
    Register<bit<32>, _>(1) received_packet_size_lo_carry;
    Register<bit<32>, _>(1) received_packet_size_hi;
    RegisterAction<bit<32>, _, bit<32>>(received_packet_size_lo) received_packet_size_lo_write = {
        void apply(inout bit<32> value, out bit<32> read_value) {
            value = value + rx_packet_size[31:0];
            read_value = value;
        }
    };

    RegisterAction<bit<32>, _, bit<32>>(received_packet_size_lo_carry) received_packet_size_lo_carry_write = {
        void apply(inout bit<32> value, out bit<32> read_value) {
            if (rx_packet_size_inv < value) {
                read_value = 1;
            } else {
                read_value = 0;
            }

            value = value + rx_packet_size[31:0];
        }
    };
    
    RegisterAction<bit<32>, _, bit<32>>(received_packet_size_hi) received_packet_size_hi_write = {
        void apply(inout bit<32> value, out bit<32> read_value) {
            value = value + hi_carry;
        }
    };

    Register<bit<8>, _>(1) enable_recirculation;
    RegisterAction<bit<8>, _, bit<8>>(enable_recirculation) enable_recirculation_read = {
        void apply(inout bit<8> value, out bit<8> read_value) {
            read_value = value;
        }
    };

    Register<bit<32>, _>(1) drop_counter;
    Register<bit<32>, _>(1) drop_threshold;
    bit<32> drop_thresh = 0;
    RegisterAction<bit<32>, _, bit<32>>(drop_counter) drop_counter_increment = {
        void apply(inout bit<32> value, out bit<32> read_value) {
            read_value = value;
            if (value + 1 == drop_thresh) {
                value = 0;
            } else {
                value = value + 1;
            }
        }
    };

    RegisterAction<bit<32>, _, bit<32>>(drop_threshold) drop_threshold_read = {
        void apply(inout bit<32> value, out bit<32> read_value) {
            read_value = value;
        }
    };

    apply {
        if (hdr.ipv4.isValid()) {
            bit<8> is_recirculation_enabled = 0;
            if (ig_intr_md.ingress_port == PKTGEN_PORT) {
                drop_thresh = drop_threshold_read.execute(0);
                if (drop_thresh == 0) {
                    ig_tm_md.mcast_grp_a = 100;
                } else {
                    bit<32> d_counter = drop_counter_increment.execute(0);
                    if (d_counter == 0) {
                        ig_tm_md.mcast_grp_a = 100;
                    } else {
                        ig_dprsr_md.drop_ctl = 1;
                    }
                }


            } else if (ig_intr_md.ingress_port == RECIRCULATION_PORT) {
                is_recirculation_enabled = enable_recirculation_read.execute(0);

                if (is_recirculation_enabled == 1) {
                    ig_tm_md.mcast_grp_a = 200;
                    hdr.ipv4.identification = 0xabcd;
                } else {
                    ig_dprsr_md.drop_ctl = 1;
                }
            } else {
                bit<32> read_pkt_count = received_packet_number_lo_increment.execute(0);
                if (read_pkt_count == 0x0) {
                    received_packet_number_hi_increment.execute(0);
                }

                bit<32> total_len = 16w0x0 ++ hdr.ipv4.total_len;
                rx_packet_size = 32w0x0 ++ (20 + total_len);
                rx_packet_size_inv = ~rx_packet_size[31:0];

                received_packet_size_lo_write.execute(0);
                hi_carry = rx_packet_size[63:32] + received_packet_size_lo_carry_write.execute(0);
                received_packet_size_hi_write.execute(0);

                if (hdr.ipv4.identification == 0xffff) {
                    hdr.ipv4.identification = 0x0;
                    ig_tm_md.ucast_egress_port = PKTGEN_PORT;
                } else {
                    ig_dprsr_md.drop_ctl = 1;
                }
            }
        }

    }
}

control IngressDeparser(packet_out pkt, inout my_ingress_headers_t hdr,
                        in my_ingress_metadata_t meta, in ingress_intrinsic_metadata_for_deparser_t ig_dprsr_md) {
    apply {
        pkt.emit(hdr);
    }
}


/* EGRESS */
struct my_egress_headers_t {
    ethernet_h ethernet;
    ipv4_h ipv4;
    tcp_h tcp;
    udp_h udp;
}

struct my_egress_metadata_t {}

parser EgressParser(packet_in pkt, out my_egress_headers_t hdr, out my_egress_metadata_t meta,
                    out egress_intrinsic_metadata_t eg_intr_md) {
    /* This is a mandatory state, required by Tofino Architecture */
    state start {
        pkt.extract(eg_intr_md);
        transition parse_ethernet;
    }

    state parse_ethernet {
        pkt.extract(hdr.ethernet);
        transition select(hdr.ethernet.ether_type) {
            ether_type_t.IPV4: parse_ipv4;
            default: accept;
        }
    }

    state parse_ipv4 {
        pkt.extract(hdr.ipv4);
        transition select(hdr.ipv4.protocol) {
            ipv4_protocol_t.TCP: parse_tcp;
            ipv4_protocol_t.UDP: parse_udp;
            default: accept;
        }
    }

    state parse_tcp {
        pkt.extract(hdr.tcp);
        transition accept;
    }

    state parse_udp {
        pkt.extract(hdr.udp);
        transition accept;
    }
}

control Egress(inout my_egress_headers_t hdr, inout my_egress_metadata_t meta,
               in egress_intrinsic_metadata_t eg_intr_md, in egress_intrinsic_metadata_from_parser_t eg_prsr_md,
               inout egress_intrinsic_metadata_for_deparser_t eg_dprsr_md, inout egress_intrinsic_metadata_for_output_port_t eg_oport_md) {
    Register<bit<32>, _>(1) sent_packet_number_lo;
    Register<bit<32>, _>(1) sent_packet_number_hi;

    RegisterAction<bit<32>, _, bit<32>>(sent_packet_number_lo) sent_packet_number_lo_increment = {
        void apply(inout bit<32> value, out bit<32> read_value) {
            value = value + 1;
            read_value = value;
        }
    };

    RegisterAction<bit<32>, _, bit<32>>(sent_packet_number_hi) sent_packet_number_hi_increment = {
        void apply(inout bit<32> value, out bit<32> read_value) {
            value = value + 1;
        }
    };

    bit<64> tx_packet_size;
    bit<32> tx_packet_size_inv;
    bit<32> hi_carry;
    Register<bit<32>, _>(1) sent_packet_size_lo;
    Register<bit<32>, _>(1) sent_packet_size_lo_carry;
    Register<bit<32>, _>(1) sent_packet_size_hi;
    RegisterAction<bit<32>, _, bit<32>>(sent_packet_size_lo) sent_packet_size_lo_write = {
        void apply(inout bit<32> value, out bit<32> read_value) {
            value = value + tx_packet_size[31:0];
            read_value = value;
        }
    };

    RegisterAction<bit<32>, _, bit<32>>(sent_packet_size_lo_carry) sent_packet_size_lo_carry_write = {
        void apply(inout bit<32> value, out bit<32> read_value) {
            if (tx_packet_size_inv < value) {
                read_value = 1;
            } else {
                read_value = 0;
            }

            value = value + tx_packet_size[31:0];
        }
    };

    RegisterAction<bit<32>, _, bit<32>>(sent_packet_size_hi) sent_packet_size_hi_write = {
        void apply(inout bit<32> value, out bit<32> read_value) {
            value = value + hi_carry;
        }
    };

    apply {
        if(hdr.ipv4.isValid()) {
            if (hdr.ipv4.identification != 0xabcd) {
                if (eg_intr_md.egress_port == 188) {
                    hdr.ipv4.identification = 0xffff;
                } if (eg_intr_md.egress_port == 180) {
                    hdr.ipv4.src_addr = hdr.ipv4.src_addr + 1;
                } else if (eg_intr_md.egress_port == 172) {
                    hdr.ipv4.src_addr = hdr.ipv4.src_addr + 2;
                } else if (eg_intr_md.egress_port == 164) {
                    hdr.ipv4.src_addr = hdr.ipv4.src_addr + 3;
                }
            } else {
                if (eg_intr_md.egress_port == 188) {
                    hdr.ipv4.src_addr = hdr.ipv4.src_addr + 4;
                } if (eg_intr_md.egress_port == 180) {
                    hdr.ipv4.src_addr = hdr.ipv4.src_addr + 5;
                } else if (eg_intr_md.egress_port == 172) {
                    hdr.ipv4.src_addr = hdr.ipv4.src_addr + 6;
                } else if (eg_intr_md.egress_port == 164) {
                    hdr.ipv4.src_addr = hdr.ipv4.src_addr + 7;
                }
            }

            bit<32> sent_pkt_count = sent_packet_number_lo_increment.execute(0);
            if (sent_pkt_count == 0x0) {
                sent_packet_number_hi_increment.execute(0);
            }

            bit<32> total_len = 16w0x0 ++ hdr.ipv4.total_len;
            tx_packet_size = 32w0x0 ++ (20 + total_len);
            tx_packet_size_inv = ~tx_packet_size[31:0];

            sent_packet_size_lo_write.execute(0);
            hi_carry = tx_packet_size[63:32] + sent_packet_size_lo_carry_write.execute(0);
            sent_packet_size_hi_write.execute(0);
        }
    }
}

control EgressDeparser(packet_out pkt, inout my_egress_headers_t hdr, in my_egress_metadata_t meta,
                       in egress_intrinsic_metadata_for_deparser_t  eg_dprsr_md) {
    apply {
        pkt.emit(hdr);
    }
}

Pipeline(
    IngressParser(),
    Ingress(),
    IngressDeparser(),
    EgressParser(),
    Egress(),
    EgressDeparser()
) pipe;

Switch(pipe) main;
