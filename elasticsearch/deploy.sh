#!/bin/bash

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()   { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# ── 1. 부팅 자동 시작 설정 ──────────────────────────────────
log "Docker 부팅 자동 시작 활성화..."
sudo systemctl enable docker 2>/dev/null || true

# ── 2. 커널 설정 (부팅 시 영구 적용) ────────────────────────
log "vm.max_map_count 설정 중..."
CURRENT_MAP=$(sysctl -n vm.max_map_count)
if [ "$CURRENT_MAP" -lt 262144 ]; then
    sudo sysctl -w vm.max_map_count=262144
fi
if ! grep -q "vm.max_map_count" /etc/sysctl.conf 2>/dev/null; then
    echo "vm.max_map_count = 262144" | sudo tee -a /etc/sysctl.conf > /dev/null
fi
log "vm.max_map_count=$(sysctl -n vm.max_map_count)"

# ── 3. Docker 이미지 빌드 (nori 포함) ───────────────────────
log "Elasticsearch 이미지 빌드 중 (nori 포함)..."
docker build -t es-nori:8.13.0 .

# ── 4. 기존 컨테이너 정리 및 시작 ──────────────────────────
log "기존 컨테이너 정리 중..."
docker compose down 2>/dev/null || true

log "Elasticsearch 클러스터 & Kibana 시작 중..."
docker compose up -d

# ── 5. ES 클러스터 green + 2노드 대기 ──────────────────────
log "Elasticsearch 클러스터 준비 대기 중 (green, 2 nodes)..."
for i in $(seq 1 60); do
    HEALTH=$(curl -sf http://localhost:9200/_cluster/health 2>/dev/null || true)
    STATUS=$(echo "$HEALTH" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['status'])" 2>/dev/null || true)
    NODES=$(echo "$HEALTH"  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['number_of_nodes'])" 2>/dev/null || true)
    if [ "$STATUS" = "green" ] && [ "$NODES" = "2" ]; then
        echo ""
        log "클러스터 준비 완료! (green, ${NODES} nodes)"
        break
    fi
    if [ "$i" -eq 60 ]; then
        echo ""
        error "Elasticsearch 클러스터가 green 상태가 되지 않았습니다. 로그 확인: docker compose logs es01"
    fi
    echo -n "."
    sleep 3
done

# ── 6. nori-test 인덱스 생성 (nori_analyzer 포함) ──────────
log "nori-test 인덱스 설정 중..."
INDEX_STATUS=$(curl -sf -o /dev/null -w "%{http_code}" http://localhost:9200/nori-test 2>/dev/null || echo "000")
if [ "$INDEX_STATUS" = "200" ]; then
    log "nori-test 인덱스가 이미 존재합니다."
else
    curl -sf -X PUT "http://localhost:9200/nori-test" \
      -H "Content-Type: application/json" \
      -d '{
        "settings": {
          "analysis": {
            "tokenizer": {
              "nori_user_dict": {
                "type": "nori_tokenizer",
                "decompound_mode": "mixed",
                "discard_punctuation": true
              }
            },
            "filter": {
              "nori_posfilter": {
                "type": "nori_part_of_speech",
                "stoptags": ["E","IC","J","MAG","MAJ","MM","SP","SSC","SSO","SC","SE","XPN","XSA","XSN","XSV","UNA","NA","VSV"]
              }
            },
            "analyzer": {
              "nori_analyzer": {
                "type": "custom",
                "tokenizer": "nori_user_dict",
                "filter": ["nori_posfilter", "lowercase", "trim"]
              }
            }
          }
        },
        "mappings": {
          "properties": {
            "content": {
              "type": "text",
              "analyzer": "nori_analyzer"
            }
          }
        }
      }' > /dev/null
    log "nori-test 인덱스 생성 완료"
fi

# ── 7. Kibana 준비 대기 ─────────────────────────────────────
log "Kibana 준비 대기 중..."
for i in $(seq 1 60); do
    CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:5601/api/status 2>/dev/null || echo "000")
    if [ "$CODE" = "200" ]; then
        echo ""
        log "Kibana 준비 완료!"
        break
    fi
    if [ "$i" -eq 60 ]; then
        echo ""
        warn "Kibana가 응답하지 않습니다. 나중에 수동으로 확인하세요."
        break
    fi
    echo -n "."
    sleep 3
done

# ── 8. Kibana 데이터 뷰 & 노드 헬스 대시보드 생성 ──────────
log "Kibana 데이터 뷰 및 노드 헬스 대시보드 생성 중..."
python3 << 'PYEOF'
import json, urllib.request, urllib.error, sys

KIBANA  = "http://localhost:5601"
HEADERS = {"Content-Type": "application/json", "kbn-xsrf": "true"}

def request(method, path, data=None):
    req = urllib.request.Request(
        f"{KIBANA}{path}",
        data=json.dumps(data).encode() if data is not None else None,
        headers=HEADERS,
        method=method
    )
    try:
        with urllib.request.urlopen(req) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        return json.loads(e.read())

# 데이터 뷰 재생성
request("DELETE", "/api/data_views/data_view/monitoring-es-nodes")
result = request("POST", "/api/data_views/data_view", {
    "data_view": {
        "id":            "monitoring-es-nodes",
        "title":         ".monitoring-es-*",
        "timeFieldName": "timestamp",
        "name":          "ES Monitoring"
    },
    "override": True
})
field_count = len(result.get("data_view", {}).get("fields", {}))
print(f"  데이터 뷰  : OK ({field_count} fields)")

# Lens 시각화 4종 + 대시보드 정의
def lens_xy(vis_id, title, metric_field, metric_label, series_type="line"):
    return {
        "id": vis_id, "type": "lens",
        "attributes": {
            "title": title,
            "visualizationType": "lnsXY",
            "state": {
                "datasourceStates": {"formBased": {"layers": {"l1": {
                    "columnOrder": ["col-time", "col-node", "col-val"],
                    "columns": {
                        "col-time": {
                            "dataType": "date", "isBucketed": True, "label": "time",
                            "operationType": "date_histogram",
                            "params": {"interval": "auto"},
                            "sourceField": "timestamp"
                        },
                        "col-node": {
                            "dataType": "string", "isBucketed": True, "label": "Node",
                            "operationType": "terms",
                            "params": {"size": 10, "orderBy": {"type": "alphabetical"},
                                       "orderDirection": "asc", "otherBucket": False, "missingBucket": False},
                            "sourceField": "source_node.name"
                        },
                        "col-val": {
                            "dataType": "number", "isBucketed": False, "label": metric_label,
                            "operationType": "average",
                            "sourceField": metric_field
                        }
                    },
                    "indexPatternId": "monitoring-es-nodes"
                }}}},
                "visualization": {
                    "legend": {"isVisible": True, "position": "bottom"},
                    "valueLabels": "hide", "fittingFunction": "None",
                    "layers": [{"layerId": "l1", "layerType": "data",
                                "xAccessor": "col-time", "splitAccessor": "col-node",
                                "accessors": ["col-val"], "seriesType": series_type}]
                },
                "query": {"query": "type:node_stats", "language": "kuery"},
                "filters": []
            }
        },
        "references": [{"id": "monitoring-es-nodes",
                         "name": "indexpattern-datasource-layer-l1",
                         "type": "index-pattern"}]
    }

objects = [
    lens_xy("node-cpu-vis",  "노드 CPU 사용률 (%)",        "node_stats.process.cpu.percent",            "CPU %",       "line"),
    lens_xy("node-heap-vis", "노드 Heap 사용률 (%)",        "node_stats.jvm.mem.heap_used_percent",      "Heap %",      "line"),
    lens_xy("node-load-vis", "노드 Load Average (1m)",      "node_stats.os.cpu.load_average.1m",         "Load 1m",     "area"),
    lens_xy("node-disk-vis", "노드 디스크 여유 공간 (bytes)", "node_stats.fs.total.available_in_bytes",   "Available",   "area"),
    {
        "id": "es-node-health-dashboard", "type": "dashboard",
        "attributes": {
            "title":       "Elasticsearch 노드 헬스",
            "description": "ES 클러스터 노드 CPU / Heap / Load / Disk 모니터링",
            "panelsJSON": json.dumps([
                {"version":"8.13.0","type":"lens","gridData":{"x":0, "y":0, "w":24,"h":15,"i":"p1"},"panelIndex":"p1","embeddableConfig":{"enhancements":{}},"panelRefName":"panel_p1"},
                {"version":"8.13.0","type":"lens","gridData":{"x":24,"y":0, "w":24,"h":15,"i":"p2"},"panelIndex":"p2","embeddableConfig":{"enhancements":{}},"panelRefName":"panel_p2"},
                {"version":"8.13.0","type":"lens","gridData":{"x":0, "y":15,"w":24,"h":15,"i":"p3"},"panelIndex":"p3","embeddableConfig":{"enhancements":{}},"panelRefName":"panel_p3"},
                {"version":"8.13.0","type":"lens","gridData":{"x":24,"y":15,"w":24,"h":15,"i":"p4"},"panelIndex":"p4","embeddableConfig":{"enhancements":{}},"panelRefName":"panel_p4"},
            ]),
            "optionsJSON": json.dumps({"useMargins": True, "syncColors": False, "hidePanelTitles": False}),
            "timeRestore": False,
            "kibanaSavedObjectMeta": {"searchSourceJSON": json.dumps({"query":{"query":"","language":"kuery"},"filter":[]})}
        },
        "references": [
            {"id": "node-cpu-vis",  "name": "panel_p1", "type": "lens"},
            {"id": "node-heap-vis", "name": "panel_p2", "type": "lens"},
            {"id": "node-load-vis", "name": "panel_p3", "type": "lens"},
            {"id": "node-disk-vis", "name": "panel_p4", "type": "lens"},
        ]
    }
]

result = request("POST", "/api/saved_objects/_bulk_create?overwrite=true", objects)
for item in result.get("saved_objects", []):
    err = item.get("error")
    print(f"  {item['type']:12s} : {'OK' if not err else err}")
PYEOF

# ── 9. 검증 ─────────────────────────────────────────────────
echo ""
log "=== 배포 검증 ==="
echo ""

echo "[클러스터 헬스]"
curl -s http://localhost:9200/_cluster/health | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(f'  상태    : {d[\"status\"]}')
print(f'  노드 수 : {d[\"number_of_nodes\"]}')
print(f'  샤드    : active={d[\"active_shards\"]}, unassigned={d[\"unassigned_shards\"]}')
"

echo ""
echo "[노드 목록]"
curl -s "http://localhost:9200/_cat/nodes?v&h=name,ip,heap.percent,cpu,master" | sed 's/^/  /'

echo ""
echo "[플러그인]"
echo "  es01: $(docker exec es01 elasticsearch-plugin list)"
echo "  es02: $(docker exec es02 elasticsearch-plugin list)"

echo ""
echo "[nori 분석 테스트]"
curl -s -X POST "http://localhost:9200/nori-test/_analyze" \
  -H "Content-Type: application/json" \
  -d '{"analyzer":"nori_analyzer","text":"한국어 검색 테스트"}' | \
  python3 -c "import sys,json; print('  토큰:', [t['token'] for t in json.load(sys.stdin)['tokens']])"

echo ""
echo "[Kibana]"
curl -s -o /dev/null -w "  상태 코드: %{http_code}\n" http://localhost:5601/api/status

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  배포 완료!${NC}"
echo -e "${GREEN}============================================${NC}"
echo "  Elasticsearch (node1) : http://localhost:9200"
echo "  Elasticsearch (node2) : http://localhost:9201"
echo "  Kibana                : http://localhost:5601"
echo "  노드 헬스 대시보드    : http://localhost:5601/app/dashboards#/view/es-node-health-dashboard"
echo ""
