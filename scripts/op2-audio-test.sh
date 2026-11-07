#!/usr/bin/env bash
# Plays a quiet 2 s tone (440 Hz) through the loudspeaker path of a phone running a kernel with
# OP2_ADSP OP2_A_I2C OP2_AUDIO and qcom_q6v5_pas.op2_noauto=1.
#   scripts/op2-audio-test.sh <ssh_config> <host>
# The ADSP firmware (adsp.mbn from the phone's own modem partition) must be in
# /lib/firmware/qcom/msm8994/oneplus2/ on the phone; it is not part of this repository.
set -euo pipefail
S() { timeout 120 ssh -F "$1" "$2" "${@:3}"; }
S "$1" "$2" '
  [ "$(cat /sys/class/remoteproc/remoteproc0/state)" = running ] || { echo start > /sys/class/remoteproc/remoteproc0/state; sleep 5; }
  cat /sys/class/remoteproc/remoteproc0/state
  amixer -c 0 cset name="QUAT_MI2S_RX Audio Mixer MultiMedia1" on >/dev/null
  python3 -c "
import wave,struct,math
w=wave.open(\"/tmp/t.wav\",\"w\"); w.setnchannels(2); w.setsampwidth(2); w.setframerate(48000)
w.writeframes(b\"\".join(struct.pack(\"<hh\",*(int(2000*math.sin(2*math.pi*440*i/48000)),)*2) for i in range(96000)))
w.close()"
  aplay -D hw:0,0 /tmp/t.wav'
