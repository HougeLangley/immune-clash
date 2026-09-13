#!/usr/bin/env bash
# 安装 APK 到小米手机（push+pm install 绕过 MIUI USB 安装确认弹窗）
# 用法: miui-install.sh <apk路径>
set -u
ADB=/home/houge/Android/Sdk/platform-tools/adb
APK="$1"
[ -f "$APK" ] || { echo "APK 不存在: $APK"; exit 1; }

TMP="/data/local/tmp/_install.apk"
$ADB push "$APK" "$TMP" >/dev/null 2>&1
RESULT=$($ADB shell pm install -r -t "$TMP" 2>&1)
$ADB shell rm "$TMP" >/dev/null 2>&1

if echo "$RESULT" | grep -q "Success"; then
  echo "[miui-install] ✅ 安装成功（无弹窗直装）"
  exit 0
else
  echo "[miui-install] ❌ pm install 失败: $RESULT"
  echo "[miui-install] 尝试备用方案（标准 install+自动点弹窗）..."
  $ADB install -r "$APK" > /tmp/inst.log 2>&1 &
  IPID=$!
  for i in $(seq 1 10); do
    sleep 1
    $ADB shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1
    NODE=$($ADB shell cat /sdcard/ui.xml 2>/dev/null | grep -o '<node[^>]*继续安装[^>]*>')
    B=$(echo "$NODE" | grep -o 'bounds="\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]"')
    if [ -n "$B" ]; then
      XY=$(echo "$B" | grep -oE '[0-9]+' | awk '{a[NR]=$1} END{print int((a[1]+a[3])/2), int((a[2]+a[4])/2)}')
      set -- $XY
      $ADB shell input tap $1 $2
      break
    fi
  done
  wait $IPID
  RC=$?
  RESULT=$(tail -1 /tmp/inst.log)
  if echo "$RESULT" | grep -q "Success\|complete"; then
    echo "[miui-install] ✅ 备用方案成功: $RESULT"
    exit 0
  else
    echo "[miui-install] ❌ 安装失败(rc=$RC): $RESULT"
    exit 1
  fi
fi
