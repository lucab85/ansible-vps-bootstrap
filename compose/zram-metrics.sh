#!/bin/bash
set -euo pipefail

METRICS_FILE="/opt/apps/monitoring/textfile_collector/zram.prom"
METRICS_TMP="${METRICS_FILE}.tmp"
DEVICE="/sys/block/zram0"

read -r ORIG COMPR MEM_USED MEM_LIMIT MEM_MAX SAME_PAGES PAGES_COMPACTED _ _ < "$DEVICE/mm_stat"
DISKSIZE=$(cat "$DEVICE/disksize")

mkdir -p "$(dirname "$METRICS_FILE")"
{
  echo "# HELP node_zram_orig_data_bytes Uncompressed size of data currently held in zram"
  echo "# TYPE node_zram_orig_data_bytes gauge"
  echo "node_zram_orig_data_bytes ${ORIG}"

  echo "# HELP node_zram_compr_data_bytes Compressed size of data currently held in zram"
  echo "# TYPE node_zram_compr_data_bytes gauge"
  echo "node_zram_compr_data_bytes ${COMPR}"

  echo "# HELP node_zram_mem_used_total_bytes Actual RAM used by zram, including per-page metadata overhead"
  echo "# TYPE node_zram_mem_used_total_bytes gauge"
  echo "node_zram_mem_used_total_bytes ${MEM_USED}"

  echo "# HELP node_zram_mem_limit_bytes Configured max RAM zram is allowed to use (0 = no limit)"
  echo "# TYPE node_zram_mem_limit_bytes gauge"
  echo "node_zram_mem_limit_bytes ${MEM_LIMIT}"

  echo "# HELP node_zram_disksize_bytes Configured max size of the zram block device"
  echo "# TYPE node_zram_disksize_bytes gauge"
  echo "node_zram_disksize_bytes ${DISKSIZE}"

  echo "# HELP node_zram_same_pages Pages stored for free because they're identical (e.g. all-zero)"
  echo "# TYPE node_zram_same_pages gauge"
  echo "node_zram_same_pages ${SAME_PAGES}"
} > "$METRICS_TMP"
mv "$METRICS_TMP" "$METRICS_FILE"
