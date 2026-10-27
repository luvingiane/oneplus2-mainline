#!/bin/sh
# smmu-glob.sh: read the GPU SMMU global registers (base 0xfdb10000, CAF
# msm_iommu_hw-v1.h offsets) ONE at a time, syncing the log after each, so if
# a read resets the phone the log shows which one. GPU must be powered.
# Log: /root/smmu-glob.log
L=/root/smmu-glob.log
: > $L; sync
for r in IDR0:0x20 IDR1:0x24 CR0:0x0 SCR1:0x4 ACR:0x10 NSCR0:0x400 \
         SMR0:0x800 SMR1:0x804 SMR2:0x808 SMR3:0x80c \
         S2CR0:0xc00 S2CR1:0xc04 S2CR2:0xc08 S2CR3:0xc0c \
         CBAR0:0x1000 CBAR1:0x1004 CBAR2:0x1008; do
	n=${r%%:*}; o=${r#*:}
	echo "reading $n ($o)" >> $L; sync
	v=$(python3 -c "
import mmap,os,struct
f=os.open('/dev/mem',os.O_RDONLY|os.O_SYNC); m=mmap.mmap(f,0x2000,mmap.MAP_SHARED,mmap.PROT_READ,offset=0xfdb10000)
print(hex(struct.unpack('<I',m[$o:$o+4])[0]))")
	echo "$n = $v" >> $L; sync
done
echo end >> $L; sync
