# Ribosome-experiments
Ribosome is a system that extends programmable switches with external memory (to store packets) and external general-purpose packet processing devices such as CPUs or FPGAs (to perform stateful operations). It leverages spare bandwidth from any directly connected servers to store the incoming payloads through RDMA.

This repository contains multiple experiments implemented by [FastClick][Fastclick] and [NPF][NPF] to measure the benefits of Ribosome on the performance of Network Functions (NFs).

Please check out our paper at NSDI '23 for more information.

## Download

```
git clone --recursive https://github.com/Ribosome-Packet-Processor/Ribosome-experiments.git
```

## Repository Organization

This repository contains information, experiment setups, and some of the results presented in our NSDI'23 paper. More specifically:

## Testbed

**NOTE: Before running the experiments, you need to prepare your testbed according to the following guidelines.**

All the experiments mainly require [Fastclick][Fastclick] and [NPF][NPF] tools!

### Network Performance Framework (NPF) Tool
You can install [NPF][NPF] via the following command:

```bash
python3 -m pip install --user npf
```

**Do not forget to add `export PATH=$PATH:~/.local/bin` to `~/.bashrc` or `~/.zshrc`. Otherwise, you cannot run `npf-compare` and `npf-run` commands.** 

NPF will look for `cluster/` and `repo/` in your current working/testie directory. We have included the required `repo` for our experiments and a sample `cluster` template, available at `experiment/`. For more information about how to setup your cluster please check the [NPF guidelines][NPF-cluster].

NPF automatically clone and build FastClick for the experiments based on the testie/npf files.

### Data Plane Development Kit (DPDK)
We use DPDK to bypass kernel network stack in order to achieve line rate in our tests. To build DPDK, you can run the following commands:

```
git clone https://github.com/DPDK/dpdk.git
cd dpdk
git checkout v20.02
make install T=x86_64-native-linux-gcc
```
In case you want to use a newer (or different) version of DPDK, please check [DPDK documentation][dpdk-doc].

After building DPDK, you have to define `RTE_SDK` and `RTE_TARGET` by running the following commands:

```
export RTE_SDK=<your DPDK root directory>
export RTE_TARGET=x86_64-native-linux-gcc
```
Also, do not forget to setup hugepages. To do so, you can modify `GRUB_CMDLINE_LINUX` variable in `/etc/default/grub` file similar to the following configuration:

```
GRUB_CMDLINE_LINUX="isolcpus=0,1,2,3,4,5,6,7,8,9 iommu=pt intel_iommu=on default_hugepagesz=1G hugepagesz=1G hugepages=32 acpi=on selinux=0 audit=0 nosoftlockup processor.max_cstate=1 intel_idle.max_cstate=0 intel_pstate=on nopti nospec_store_bypass_disable nospectre_v2 nospectre_v1 nospec l1tf=off netcfg/do_not_use_netplan=true mitigations=off"
```



[FastClick]: https://github.com/tbarbette/fastclick
[NPF]: https://github.com/tbarbette/npf
[NPF-cluster]: https://github.com/tbarbette/npf/blob/master/cluster/README.md
[dpdk-doc]: https://doc.dpdk.org/guides/linux_gsg/index.html
