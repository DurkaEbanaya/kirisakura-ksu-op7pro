# Security patches — v2.0

161 commits cherry-picked from **linux-4.14.y stable** (v4.14.244 → v4.14.336) into Kirisakura 4.14.243.

Total: **161** patches | **11** CVEs addressed | **22** patches skipped (code conflicts)

Source: `git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git` branch `linux-4.14.y`  
SHA list: `security-patches-shas.txt`

## CVEs patched

| CVE | Commit(s) | Subsystems |
|---|---|---|
| CVE-2017-6074 | 4762cd50 | net/dccp |
| CVE-2018-1000204 | ec378443 | Documentation, include, lib |
| CVE-2020-16119 | 4762cd50 | net/dccp |
| CVE-2021-20317 | 9de02b37 | include, lib |
| CVE-2021-3573 | 56b683dc | include, net/bluetooth |
| CVE-2022-0435 | fcee5776 | net/tipc |
| CVE-2022-2586 | c454810a | include, net/netfilter |
| CVE-2022-2588 | 756e08e4 | net/sched |
| CVE-2023-1989 | 8f273f8e | drivers/bluetooth |
| CVE-2023-31436 | c15a81d0 | net/sched |
| CVE-2023-3772 | 994279b3 | net/xfrm |

## Subsystem distribution

| Subsystem | Patches |
|---|---|
| include | 33 |
| kernel | 20 |
| net/sched | 17 |
| net/ipv4 | 17 |
| net/netfilter | 14 |
| mm | 10 |
| lib | 9 |
| net/core | 9 |
| arch/arm | 9 |
| net/ipv6 | 8 |
| arch/arm64 | 4 |
| net/netlink | 4 |
| net/packet | 4 |
| net/dccp | 3 |
| block | 3 |
| net/unix | 3 |
| net/bluetooth | 2 |
| net/tipc | 2 |
| net/xfrm | 2 |
| arch/mips | 2 |
| arch/powerpc | 2 |
| crypto | 2 |
| ipc | 2 |
| net/sctp | 2 |
| net/l2tp | 2 |
| drivers/android | 2 |
| Documentation | 1 |
| drivers/bluetooth | 1 |
| arch/arc | 1 |
| net/bridge | 1 |
| net/802 | 1 |
| net/nfc | 1 |
| net/caif | 1 |
| net/rxrpc | 1 |
| arch/alpha | 1 |
| arch/h8300 | 1 |
| arch/hexagon | 1 |
| arch/ia64 | 1 |
| arch/m68k | 1 |
| arch/microblaze | 1 |
| arch/nios2 | 1 |
| arch/openrisc | 1 |
| arch/parisc | 1 |
| arch/s390 | 1 |
| arch/sh | 1 |
| arch/sparc | 1 |
| arch/x86 | 1 |
| arch/xtensa | 1 |
| tools | 1 |
| drivers/usb | 1 |
| drivers/net | 1 |
| security | 1 |

## Full patch list (chronological)

| # | SHA | Subject | CVEs | Subsystems |
|---|---|---|---|---|
| 1 | `56b683dce71f` | Bluetooth: defer cleanup of resources in hci_unregister_dev() | CVE-2021-3573 | include, net/bluetooth |
| 2 | `4762cd5050e7` | dccp: don't duplicate ccid when cloning dccp sock | CVE-2017-6074, CVE-2020-16119 | net/dccp |
| 3 | `9de02b373e88` | lib/timerqueue: Rely on rbtree semantics for next timer | CVE-2021-20317 | include, lib |
| 4 | `fcee5776018a` | tipc: improve size validations for received domain records | CVE-2022-0435 | net/tipc |
| 5 | `ec37844336ee` | swiotlb: fix info leak with DMA_FROM_DEVICE | CVE-2018-1000204 | Documentation, include, lib |
| 6 | `756e08e4b2bd` | net_sched: cls_route: remove from list when handle is 0 | CVE-2022-2588 | net/sched |
| 7 | `c454810add06` | netfilter: nf_tables: do not allow SET_ID to refer to another tab | CVE-2022-2586 | include, net/netfilter |
| 8 | `c15a81d0e5da` | net/sched: sch_qfq: account for stab overhead in qfq_enqueue | CVE-2023-31436 | net/sched |
| 9 | `994279b30b90` | xfrm: add NULL check in xfrm_update_ae_params | CVE-2023-3772 | net/xfrm |
| 10 | `8f273f8ee80f` | Bluetooth: btsdio: fix use after free bug in btsdio_remove due to | CVE-2023-1989 | drivers/bluetooth |
| 11 | `e8a19fc61eb6` | lib/test: use after free in register_test_dev_kmod() | — | lib |
| 12 | `7eb2ef6d2198` | crypto: lib/mpi - avoid null pointer deref in mpi_cmp_ui() | — | lib |
| 13 | `8de8a2ec6c4d` | net: Fix load-tearing on sk->sk_stamp in sock_recv_cmsgs(). | — | include |
| 14 | `04d4c996e2cc` | net/sched: cls_fw: Fix improper refcount update leads to use-afte | — | net/sched |
| 15 | `60fdc1d39242` | perf/core: Fix data race between perf_event_set_output() and perf | — | kernel |
| 16 | `a9e1fd4cce2e` | netfilter: nf_queue: fix socket leak | — | net/netfilter |
| 17 | `6cc242140fe1` | bpf: Fix integer overflow in prealloc_elems_and_freelist() | — | kernel |
| 18 | `9a4270b43b07` | net: add missing data-race annotation for sk_ll_usec | — | net/core |
| 19 | `d1832a54c82d` | net/sched: cls_u32: No longer copy tcf_result on update to avoid  | — | net/sched |
| 20 | `5b7aaf29fc21` | arch: pgtable: define MAX_POSSIBLE_PHYSMEM_BITS where needed | — | arch/arc, arch/arm, arch/mips |
| 21 | `a1deb2836326` | netfilter: nf_queue: fix possible use-after-free | — | include, net/netfilter |
| 22 | `4d2c27ac01df` | net: ieee802154: handle iftypes as u32 | — | include |
| 23 | `9a5337de544f` | arm64: entry.S: Add ventry overflow sanity checks | — | arch/arm64 |
| 24 | `43704c5251ca` | netfilter: xt_u32: validate user space input | — | net/netfilter |
| 25 | `97709e881881` | tcp: annotate data races in __tcp_oow_rate_limited() | — | net/ipv4 |
| 26 | `37a52c9a3900` | netfilter: ipset: Fix overflow before widen in the bitmap_ip_crea | — | net/netfilter |
| 27 | `d0797063cac1` | net: udp: annotate data race around udp_sk(sk)->corkflag | — | net/ipv4, net/ipv6 |
| 28 | `fedb770d95c0` | ARM: 9105/1: atags_to_fdt: don't warn about stack size | — | arch/arm |
| 29 | `84c90c622a15` | ipv6: sr: fix out-of-bounds read when setting HMAC data. | — | net/ipv6 |
| 30 | `93da1aee5792` | af_unix: Fix data-races around sk->sk_shutdown. | — | net/core |
| 31 | `9896655a7b68` | net: sched: sch_qfq: Fix UAF in qfq_dequeue() | — | net/sched |
| 32 | `30751898c6bc` | shmem: fix a race between shmem_unused_huge_shrink and shmem_evic | — | mm |
| 33 | `bec0db0ac0fc` | mm/slub: add missing TID updates on slab deactivation | — | mm |
| 34 | `1f119806a65d` | sch_qfq: prevent shift-out-of-bounds in qfq_init_qdisc | — | net/sched |
| 35 | `062e428f962d` | blktrace: Fix uaf in blk_trace access after removing by sysfs | — | kernel |
| 36 | `17554af0ef80` | crypto: pcrypt - Delay write to padata->info | — | crypto |
| 37 | `81ea28f45546` | netfilter: nf_tables: incorrect error path handling with NFT_MSG_ | — | net/netfilter |
| 38 | `9b714e539184` | acct: fix potential integer overflow in encode_comp_t() | — | kernel |
| 39 | `39bd483f950a` | crypto: seqiv - Handle EBUSY correctly | — | crypto |
| 40 | `b2b63eb52b46` | netlink: annotate data races around nlk->bound | — | net/netlink |
| 41 | `8f423698c665` | llc: fix out-of-bound array index in llc_sk_dev_hash() | — | include |
| 42 | `2a7a72e7f057` | ipc: WARN if trying to remove ipc object which is absent | — | ipc |
| 43 | `c9c9fe5c6430` | net: sched: cbq: dont intepret cls results when asked to drop | — | net/sched |
| 44 | `aeabf741edcb` | block: unhash blkdev part inode when the part is deleted | — | block |
| 45 | `d0558a3426b1` | ipv4: igmp: fix refcnt uaf issue when receiving igmp query packet | — | net/ipv4 |
| 46 | `bb33a3f20a4d` | netlink: annotate data races around dst_portid and dst_group | — | net/netlink |
| 47 | `8a0ce2a46eca` | netfilter: xt_sctp: validate the flag_info count | — | net/netfilter |
| 48 | `7224b1f9571c` | pwm: Fix double shift bug | — | include |
| 49 | `96eeaf2666a5` | cred: allow get_cred() and put_cred() to be given NULL. | — | include |
| 50 | `f59c26bd6448` | memcg: fix possible use-after-free in memcg_write_event_control() | — | include, kernel, mm |
| 51 | `7659cdcc11eb` | net/ulp: prevent ULP without clone op from entering the LISTEN st | — | net/ipv4 |
| 52 | `e35edc772220` | kobject: Fix slab-out-of-bounds in fill_kobj_path() | — | lib |
| 53 | `1b8d6a0aaa8f` | ipv6: avoid use-after-free in ip6_fragment() | — | net/ipv6 |
| 54 | `1e57e3d26ebd` | net/packet: fix slab-out-of-bounds access in packet_recvmsg() | — | net/packet |
| 55 | `213d08aa3ab1` | seg6: fix the iif in the IPv6 socket control block | — | net/ipv6 |
| 56 | `a9b558e3d97f` | ALSA: seq: fix undefined behavior in bit shift for SNDRV_SEQ_FILT | — | include |
| 57 | `e457d68e1987` | igmp: limit igmpv3_newpack() packet size to IP_MAX_MTU | — | net/ipv4 |
| 58 | `348d3a70acf8` | netfilter: ebtables: reject blobs that don't provide all entry po | — | include, net/bridge |
| 59 | `20fb5a51f81b` | block: bio-integrity: Copy flags when bio_integrity_payload is cl | — | block |
| 60 | `01af40bdbd2c` | af_netlink: Fix shift out of bounds in group mask calculation | — | net/netlink |
| 61 | `f44d3d8d362f` | tipc: Fix potential OOB in tipc_link_proto_rcv() | — | net/tipc |
| 62 | `516e79605d89` | mrp: introduce active flags to prevent UAF when applicant uninit | — | include, net/802 |
| 63 | `0cc4f95502a0` | net/packet: rx_owner_map depends on pg_vec | — | net/packet |
| 64 | `1dc9d1bc1102` | net/sched: cls_u32: Fix reference counter leak leading to overflo | — | net/sched |
| 65 | `caede47995c2` | sch_sfb: Don't assume the skb is still around after enqueueing to | — | net/sched |
| 66 | `2062f0399d78` | net: sched: Fix use after free in red_enqueue() | — | net/sched |
| 67 | `6400782c80a9` | ARM: davinci: da850-evm: Avoid NULL pointer dereference | — | arch/arm |
| 68 | `cbb106587b80` | netfilter: nfnetlink_queue: fix OOB when mac header was cleared | — | net/netfilter |
| 69 | `de86f3e6536a` | arm64: fix oops in concurrently setting insn_emulation sysctls | — | arch/arm64 |
| 70 | `f05cbd3ea8b8` | lib: cpu_rmap: Avoid use after free on rmap->obj array entries | — | lib |
| 71 | `aede080bef0d` | audit: fix undefined behavior in bit shift for AUDIT_BIT | — | include |
| 72 | `cdcfb30dfd05` | PM: hibernate: Use __get_safe_page() rather than touching the lis | — | kernel |
| 73 | `16e6e253e1be` | inet: fully convert sk->sk_rx_dst to RCU rules | — | include, net/ipv4, net/ipv6 |
| 74 | `6aba59adb667` | tcp: fix race condition when creating child sockets from syncooki | — | include, net/dccp, net/ipv4 |
| 75 | `ef826d911fab` | flow_dissector: Fix out-of-bounds warnings | — | net/core |
| 76 | `cda1cb2f947c` | mm: prevent page_frag_alloc() from corrupting the memory | — | mm |
| 77 | `9a87734b9a01` | tcp: Fix potential use-after-free due to double kfree() | — | net/ipv4 |
| 78 | `64fe6d57fb93` | NFC: add NCI_UNREG flag to eliminate the race | — | include, net/nfc |
| 79 | `c903a0bc50b4` | sctp: use call_rcu to free endpoint | — | include, net/sctp |
| 80 | `5e60a68e08f8` | watchdog/perf: more properly prevent false positives with turbo m | — | kernel |
| 81 | `713f7717d417` | shm: extend forced shm destroy to support objects from several IP | — | include, ipc |
| 82 | `6aa60f2c2b43` | ARM: findbit: fix overflowing offset | — | arch/arm |
| 83 | `5eaf30821327` | net/tunnel: wait until all sk_user_data reader finish before rele | — | net/ipv4 |
| 84 | `746286bd9bbb` | ip_vti: fix potential slab-use-after-free in decode_session6 | — | net/ipv4 |
| 85 | `bf5f12c9e247` | profiling: fix shift too large makes kernel panic | — | kernel |
| 86 | `4e753f736964` | af_unix: Fix data race around sk->sk_err. | — | net/core |
| 87 | `a64cdb4b5699` | rtnetlink: make sure to refresh master_dev/m_ops in __rtnl_newlin | — | net/core |
| 88 | `47f97700f5cc` | igmp: Add ip_mc_list lock in ip_check_mc_rcu | — | net/ipv4 |
| 89 | `a397e4585cba` | test_firmware: prevent race conditions by a correct implementatio | — | lib |
| 90 | `3912fe79209d` | tracing: Fix infinite loop in tracing_read_pipe on overflowed pri | — | kernel |
| 91 | `3a54da026576` | block: change all __u32 annotations to __be32 in affs_hardblocks. | — | include |
| 92 | `1e1b83eac67f` | net: caif: Fix use-after-free in cfusbl_device_notify() | — | net/caif |
| 93 | `19b0b36299db` | udp6: Fix race condition in udp6_sendmsg & connect | — | net/core |
| 94 | `c0cf6954ad21` | ftrace: Fix null pointer dereference in ftrace_add_mod() | — | kernel |
| 95 | `2c9973d2e968` | capabilities: fix undefined behavior in bit shift for CAP_TO_MASK | — | include |
| 96 | `28dce3844c1c` | mm/zsmalloc.c: close race window between zs_pool_dec_isolated() a | — | mm |
| 97 | `a8b98cdfe557` | af_unix: Fix a data race of sk->sk_receive_queue->qlen. | — | net/unix |
| 98 | `5ffc7ff69dfa` | sched/core: Mitigate race cpus_share_cache()/update_top_cache_dom | — | kernel |
| 99 | `bb1d5c014b8c` | rxrpc: Fix listen() setting the bar too high for the prealloc rin | — | net/rxrpc |
| 100 | `b56157d34068` | exit: Add and use make_task_dead. | — | arch/alpha, arch/arm, arch/arm64 |
| 101 | `04f44833037f` | net: fix use-after-free in tw_timer_handler | — | net/ipv4 |
| 102 | `176722ac0aae` | Bluetooth: L2CAP: Fix use-after-free caused by l2cap_chan_put | — | include, net/bluetooth |
| 103 | `03c4bdec9da5` | netfilter: nf_tables: disallow non-stateful expression in sets ea | — | net/netfilter |
| 104 | `2c5dc91efe33` | ipv6: Fix out-of-bounds access in ipv6_find_tlv() | — | net/ipv6 |
| 105 | `363fd958f633` | lib: cpu_rmap: Fix potential use-after-free in irq_cpu_rmap_relea | — | lib |
| 106 | `3b32c69f8ee3` | sched/fair: sanitize vruntime of entity being placed | — | kernel |
| 107 | `71a88812d27d` | net/sched: cls_fw: No longer copy tcf_result on update to avoid u | — | net/sched |
| 108 | `0b07cdf35966` | proc: avoid integer type confusion in get_proc_long | — | kernel |
| 109 | `1ac75ed0edda` | netfilter: conntrack: Avoid nf_ct_helper_hash uses after free | — | net/netfilter |
| 110 | `2b28e8f976f1` | mm/pages_alloc.c: don't create ZONE_MOVABLE beyond the end of a n | — | mm |
| 111 | `ae68e605234a` | ftrace: Fix NULL pointer dereference in is_ftrace_trampoline when | — | kernel |
| 112 | `e3193a206c0a` | netfilter: nf_tables: fix null deref due to zeroed list head | — | net/netfilter |
| 113 | `90f21a9c9936` | netfilter: nft_dynset: restore set element counter when failing t | — | net/netfilter |
| 114 | `c6933ec94d9f` | net: sched: disallow noqueue for qdisc classes | — | net/sched |
| 115 | `9cbea14f606c` | net: sched: fix race condition in qdisc_graft() | — | net/sched |
| 116 | `d325afab22b0` | tcp: fix tcp_mtup_probe_success vs wrong snd_cwnd | — | net/ipv4 |
| 117 | `85f48000cd62` | audit: fix potential double free on error path from fsnotify_add_ | — | kernel |
| 118 | `4fde73b01f0d` | hw_breakpoint: fix single-stepping when using bpf_overflow_handle | — | arch/arm, arch/arm64, include |
| 119 | `46bb969d0b2c` | af_packet: Fix data-races of pkt_sk(sk)->num. | — | net/packet |
| 120 | `a909d14eba0f` | tcp: cdg: allow tcp_cdg_release() to be called multiple times | — | net/ipv4 |
| 121 | `3e0007ea934f` | net/sched: sch_hfsc: Ensure inner classes have fsc curve | — | net/sched |
| 122 | `cf50820e8970` | net: do not keep the dst cache when uncloning an skb dst and its  | — | include |
| 123 | `924d807f5454` | ring-buffer: Sync IRQ works before buffer destruction | — | kernel |
| 124 | `8c701036cc90` | zsmalloc: fix races between asynchronous zspage free and page mig | — | mm |
| 125 | `1b1e1a3e1017` | profiling: fix shift-out-of-bounds bugs | — | kernel |
| 126 | `b14651773dea` | dccp: Fix out of bounds access in DCCP error handler | — | net/dccp |
| 127 | `966109ebc578` | l2tp: don't use inet_shutdown on ppp session destroy | — | net/l2tp |
| 128 | `558d3d43224a` | timerqueue: Use rb_entry_safe() in timerqueue_getnext() | — | include |
| 129 | `2b3a4c64cc77` | ARM: exynos: Fix refcount leak in exynos_map_pmu | — | arch/arm |
| 130 | `d03dd18f9cad` | net: igmp: respect RCU rules in ip_mc_source() and ip_mc_msfilter | — | net/ipv4 |
| 131 | `53c4c8326c59` | af_unix: Fix null-ptr-deref in unix_stream_sendpage(). | — | net/unix |
| 132 | `9306551920f6` | ftrace: Fix invalid address access in lookup_rec() when index is  | — | kernel |
| 133 | `3271153b46f3` | net: Catch invalid index in XPS mapping | — | net/core |
| 134 | `9a090a6afdba` | net/af_unix: fix a data-race in unix_dgram_poll | — | include, net/unix |
| 135 | `e5a3df79782c` | ARM: OMAP2+: Fix null pointer dereference and memory leak in omap | — | arch/arm |
| 136 | `ba85a42f9b99` | net_sched: fix NULL deref in fifo_set_limit() | — | net/sched |
| 137 | `24130afc3496` | ARM: socfpga: Fix crash with CONFIG_FORTIRY_SOURCE | — | arch/arm |
| 138 | `8dd48f39b59a` | sctp: check asoc strreset_chunk in sctp_generate_reconf_event | — | net/sctp |
| 139 | `1aed0e1804d4` | net/sched: cls_route: No longer copy tcf_result on update to avoi | — | net/sched |
| 140 | `6024aef9ca56` | net: If sock is dead don't access sock's sk_wq in sk_stream_wait_ | — | net/core |
| 141 | `d4108547648d` | usb: otg-fsm: Fix hrtimer list corruption | — | drivers/usb, include |
| 142 | `7b8fb4243b27` | netfilter: nf_tables: prevent OOB access in nft_byteorder_eval | — | net/netfilter |
| 143 | `b14450d5089c` | kobject: Add sanity check for kset->kobj.ktype in kset_register() | — | lib |
| 144 | `2fb621da2d09` | team: fix null-ptr-deref when team device type is changed | — | drivers/net, include |
| 145 | `bbc9e1890b41` | packet: Move reference count in packet_sock to atomic_long_t | — | net/packet |
| 146 | `1f42c83b9a7a` | netlink: annotate data races around sk_state | — | net/netlink |
| 147 | `a29c2ad53d08` | mm/swap: fix swap_info_struct race between swapoff and get_swap_p | — | mm |
| 148 | `1403bc1c9472` | mm: fix race between MADV_FREE reclaim and blkdev direct IO read | — | mm |
| 149 | `d8e4cc336a5a` | blk-throttle: fix UAF by deleteing timer in blk_throtl_exit() | — | block |
| 150 | `af98ddb90646` | ip6_vti: fix slab-use-after-free in decode_session6 | — | net/ipv6 |
| 151 | `177d1c5d81c5` | ipv6: Fix signed integer overflow in l2tp_ip6_sendmsg | — | net/l2tp |
| 152 | `81d99076f93a` | net: xfrm: Fix xfrm_address_filter OOB read | — | net/xfrm |
| 153 | `0802c30caeec` | ipv4: ip_output.c: Fix out-of-bounds warning in ip_copy_addrs() | — | net/ipv4 |
| 154 | `9ef200827254` | ipv4: fix null-deref in ipv4_link_failure | — | net/ipv4 |
| 155 | `3ff31f2bfbfe` | net-sysfs: add check for netdevice being present to speed_show | — | net/core |
| 156 | `acf182764afa` | net: sched: sch_qfq: prevent slab-out-of-bounds in qfq_activate_a | — | net/sched |
| 157 | `c54bd030e7e4` | netfilter: fix use-after-free in __nf_register_net_hook() | — | net/netfilter |
| 158 | `83df4cf54370` | cgroup: Use separate src/dst nodes when preloading css_sets for m | — | include, kernel |
| 159 | `05b0b816a05f` | mm/page_alloc: fix race condition between build_all_zonelists and | — | mm |
| 160 | `2f94a1ba9365` | binder: use cred instead of task for selinux checks | — | drivers/android, include, security |
| 161 | `7983fc816081` | binder: use euid from cred instead of using task | — | drivers/android |

## Skipped patches (22, code conflicts)

These could not be cherry-picked due to conflicts with Qualcomm/OnePlus custom code:

- net/ax25/* — ax25 reference count leaks
- include/linux/cred.h — cred NULL handling (empty after auto-merge)
- kernel/events/core.c — perf race condition
- mm/khugepaged.c — khugepaged MMU notifier UAF
- include/linux/printk.h — printk deferred annotation
- net/netfilter/nfnetlink_queue.c — nf_queue UAF
- include/net/ax25.h — ax25 header changes
- include/net/netfilter/nf_tables.h — nf_tables set binding
- drivers/android/binder.c — binder cred (manually resolved, see below)
- kernel/trace/trace.c — tracing race condition
- kernel/sched/fair.c — sched/fair vruntime (Kirisakura EAS conflicts)
- mm/page_alloc.c — page_alloc race (applied via different patch)
- net/netfilter/nf_tables_api.c — nf_tables API (2 patches)
- net/netfilter/ipvs/ip_vs_ctl.c — ipvs race
- kernel/exit.c — make_task_dead (manually resolved)
- kernel/cgroup/cgroup.c — cgroup namespace migration
- net/dccp/ipv4.c — dccp error handler (applied via different patch)
- arch/arm/kernel/stacktrace.c — ARM stacktrace KASAN
- include/net/sock.h + net/ipv4/esp4.c + net/ipv6/esp6.c — ESP buffer overflow (3 patches)
- kernel/cgroup/cgroup-internal.h — cgroup preload

### Manually resolved: binder cred patch

The binder security patch (`binder: use cred instead of task for selinux checks`) required manual conflict resolution:
- `drivers/android/binder.c`: OnePlus `CONFIG_OP_FREEZER` code merged with upstream `proc->cred` change
- `security/selinux/hooks.c`: Upstream `cred_sid()` merged with 4.14 `&selinux_state` API
- Prerequisite patch `binder: use euid from cred instead of using task` applied first

## Build fixes required by security patches

| # | Fix | Reason |
|---|---|---|
| 7 | `drivers/soc/qcom/event_timer.c`: `.head = RB_ROOT` → `.rb_root = RB_ROOT_CACHED` | CVE-2021-20317 changed `struct timerqueue_head` members |
| 8 | `init/Kconfig`: `KALLSYMS_BASE_RELATIVE` default → `n` | Kernel image too large with 161 patches + WiFi built-in; relative kallsyms overflow |
