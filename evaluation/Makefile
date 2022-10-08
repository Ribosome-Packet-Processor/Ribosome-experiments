SHELL := /bin/bash

# NPF_CLUSTER?=dut=dut-100G,nic=0 reframer=reframer-100G,nic=0+1 client=client-100G,nic=0
NPF_CLUSTER?=client=nslrack16,nic=1 nf=nslrack25 tofino=tofino server0=nslrack11 server1=nslrack12 server2=nslrack13 server3=nslrack14 tofino32=tofino32
NPF_BUILD_DIR?=/home/hamid/workspace/rdma/build

test_caida_trace:
	npf-compare "local+NF_FNT=LB:LoadBalancer" "local+NF_FNT=REF:Advanced_Scheduler"  \
	--npf gen.npf --cluster ${NPF_CLUSTER} \
	--show-all --show-cmd --show-files \
	--build-folder ${NPF_BUILD_DIR} \
	--no-graph-time \
	--no-build --no-build-deps fastclick fastclick-light \
	--graph-filename temp-results/ribosome.pdf --output \
	--variables PKTGEN_REPLAY_COUNT=100 TCO=0 \
	--tags fake gen_nolat pcap promisc trace forcedudp iterative timing caida32x \
	--variables GEN_BURST=32 GEN_BIN=click LIMIT_TIME=10 MANAGER=FlowIPManagerFuzzy NF_BIN=click \
	--show-files --config n_runs=1 \
	--graph-size 5 2.5 \
	--force-retest

test_synthetic_trace:
	npf-compare "local+NF_FNT=LB:LoadBalancer" "local+NF_FNT=REF:Advanced_Scheduler"  \
        --npf gen.npf --cluster ${NPF_CLUSTER} \
        --show-all --show-cmd --show-files \
        --build-folder ${NPF_BUILD_DIR} \
        --no-graph-time \
        --no-build --no-build-deps fastclick fastclick-light \
        --graph-filename temp-results/ribosome.pdf --output \
        --variables PKTGEN_REPLAY_COUNT=100 TCO=0 \
        --tags fake gen_nolat pcap promisc prate forcedudp iterative timing caida32x \
        --variables GEN_FLOWS=128 GEN_BURST=32 GEN_BIN=click GEN_RATE=800000 LIMIT_TIME=10 MANAGER=FlowIPManagerFuzzy FASTUDPFLOW_RATE=800000 NF_BIN=click \
        --show-files --config n_runs=1 \
        --graph-size 5 2.5 \
        --force-retest
