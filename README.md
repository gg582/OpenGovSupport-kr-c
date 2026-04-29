# 사회복지 계산식 — 웹앱

사회복지 업무에서 자주 쓰이는 계산 16종(사적이전소득·이자소득 공제·재산상담·
상속분·긴급공제·해외체류 등)을 **C23 + Next.js** 로 구현한 웹 앱입니다.

## 실행


```bash
make run
```

원하면 따로 띄울 수도 있습니다:

```bash
make run-backend     # 백엔드만
make run-frontend    # 프런트엔드만
make loadtest        # 200 동시 / 10초 RPS 측정
make bench           # numerics 패키지 마이크로벤치
```

### Docker Compose

```bash
cp .env.example .env       # (선택) 포트·튜닝 파라미터 변경 시
make compose-up            # docker compose up -d --build
make compose-logs          # 로그 따라가기
make compose-down
```

- 기본 노출 포트: 프런트엔드 31778 / 백엔드 31777 (`docker-compose.yml` 의
  `${FRONTEND_PORT:-31778}` / `${BACKEND_PORT:-31777}` 참조).
- 백엔드 이미지: `golang:1.23-alpine` 빌드 → `distroless/static:nonroot` 런타임 (≈ 10 MB)
- 프런트엔드 이미지: Next.js standalone 출력으로 `node:20-alpine` 위에 올림 (≈ 150 MB, `node_modules` 미포함)
- 두 컨테이너는 `app` 브리지 네트워크에 합류, 프런트엔드는 `BACKEND_URL=http://backend:8080` 으로 백엔드를 호출
- `.env` 의 변수로 `POOL_WORKERS / POOL_QUEUE / GOGC_TARGET / JSON_INDENT / *_CPUS / *_MEMORY` 모두 외부에서 조정 가능

### Public 배포 (nginx + HTTPS)

번들된 nginx 리버스 프록시를 `proxy` 프로파일로 띄우면 `:80`/`:443` 한 곳에서 받아
`/api/*` 는 백엔드로 직접, 나머지는 프런트엔드로 보냅니다.

인증서 파일을 `nginx/certs/` 에 넣으면 자동으로 HTTPS 모드로 기동합니다.
인증서가 없으면 HTTP 전용으로 동작합니다.

```bash
# 1) 인증서 배치 (Let's Encrypt 등에서 발급)
cp /etc/letsencrypt/live/your.domain/fullchain.pem nginx/certs/
cp /etc/letsencrypt/live/your.domain/privkey.pem   nginx/certs/

# 2) .env 설정
echo 'PUBLIC_DOMAIN=your.domain.example.com' >> .env
echo 'BACKEND_BIND=127.0.0.1'                >> .env
echo 'FRONTEND_BIND=127.0.0.1'               >> .env

# 3) 기동
make compose-up-proxy
```

- `client_max_body_size 25m` / `proxy_read_timeout 60s` / 정확한 `X-Forwarded-*`
  헤더가 기본 세팅되어 PDF 출력 같은 큰 POST 도 안전합니다.
- `nginx/certs/` 는 `.gitignore` 처리되어 커밋되지 않습니다.
- `HTTP_PORT` / `HTTPS_PORT` 는 `.env` 에서 변경 가능 (예: 사내망에서 8080/8443).

## 디자인 원칙

- **모든 기능이 홈 화면에서 즉시 보임.** `domain.AllFeatures()` 가 단일 진실의 원천이고,
  백엔드/프런트엔드가 동일한 매니페스트를 공유합니다. 새 기능 추가 = 매니페스트 한 줄 + 핸들러 함수 하나.
- **법령 기반 공개정보를 코드에 직접 보유.** 중위소득·기초연금·차감율·법정 상속분 등은
  `domain/standards.go` 에 연도·항목별로 박혀 있어 외부에서 바로 사용 가능합니다.
  새 연도의 고시값이 나오면 이 파일만 갱신합니다.
- **클립보드 = 응답 텍스트.** 핸들러는 응답 JSON 의 `text` 필드에 결과를 담고, 프런트의
  "복사" 버튼이 `navigator.clipboard.writeText` 를 사용합니다.
- **PDF = 인쇄 미리보기.** 인쇄용 HTML 을 응답에 실어 보내고, 사용자가 브라우저의
  "PDF로 저장" 으로 직접 저장합니다.

## 엔드포인트

| 도메인 | 기능 | 엔드포인트 |
|---|---|---|
| 사적이전소득 | 계산        | `POST /api/private-income/calc` |
| 사적이전소득 | 상담기록    | `POST /api/private-income/record` |
| 사적이전소득 | 출력본(PDF) | `POST /api/private-income/pdf` |
| 이자소득     | 계산        | `POST /api/interest-income/calc` |
| 이자소득     | 상담기록    | `POST /api/interest-income/record` |
| 이자소득     | 출력본(PDF) | `POST /api/interest-income/pdf` |
| 재산상담     | 상담생성    | `POST /api/property/consult` |
| 상속분상담   | 상담생성    | `POST /api/inheritance/consult` |
| 긴급공제설명 | 설명 생성   | `POST /api/emergency/explain` |
| 해외체류     | 신규        | `POST /api/overseas/new` |
| 해외체류     | 기존        | `POST /api/overseas/existing` |
| 해외체류     | 기초/장애인 연금 | `POST /api/overseas/pension` |
| 해외체류     | 차상위 본인부담경감 | `POST /api/overseas/care` |
| 공용         | 개월수계산  | `POST /api/shared/months` |
| 공용         | 초기차감금액 | `POST /api/shared/initial-deduction` |
| 이벤트       | 재산변동 시트 | `POST /api/events/property-sheet` |

