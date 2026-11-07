# Sourced. xvfb WxHxD starts a virtual display of that screen, exported as DISPLAY, the server's pid in $xvfb_pid for
# the caller to kill on exit. desktop_icd is the Vulkan driver the desktop renderer runs on: CAIRNFOLD_ICD, by default
# the NVIDIA one.
# shellcheck shell=bash disable=SC2034
xvfb() {
  local display=:$((100 + RANDOM % 800))
  Xvfb "$display" -screen 0 "$1" -nolisten tcp &
  xvfb_pid=$!
  for _ in $(seq 50); do [ -e "/tmp/.X11-unix/X${display#:}" ] && break; sleep 0.1; done
  export DISPLAY=$display
}
desktop_icd=${CAIRNFOLD_ICD:-/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.json}
