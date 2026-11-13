# Sourced. xvfb WxHxD starts a virtual display of that screen, exported as DISPLAY, the server's pid in $xvfb_pid for
# the caller to kill on exit. The server picks the display: a number chosen here can be another server's, whose exit
# then ends this caller's clients. desktop_icd is the Vulkan driver the desktop renderer runs on: CAIRNFOLD_ICD, by
# default the NVIDIA one.
# shellcheck shell=bash disable=SC2034
xvfb() {
  local fd number
  exec {fd}< <(exec Xvfb -displayfd 1 -screen 0 "$1" -nolisten tcp)
  xvfb_pid=$!
  read -r number <&"$fd" || { echo "xvfb: Xvfb started no display" >&2; return 1; }
  exec {fd}<&-
  export DISPLAY=:$number
}
desktop_icd=${CAIRNFOLD_ICD:-/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.json}
