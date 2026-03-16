FROM elasticsearch:8.13.0

# nori analyzer (한국어 형태소 분석기) 플러그인 설치
RUN elasticsearch-plugin install --batch analysis-nori

LABEL org.opencontainers.image.description="Elasticsearch 8.13.0 + analysis-nori"
