# 야구보러갈래? 커뮤니티

침하하의 상단 메뉴·공지·인기글·게시판별 글 목록 구성을 참고한 커뮤니티입니다. 사용자가 제공한 야구보러갈래? 로고와 구단 로고를 사용합니다. 침하하의 로고, 콘텐츠, 사진, 코드는 복제하지 않았습니다.

2026-10-10에 [yabol.co.kr](https://yabol.co.kr/)로 배포하고 Supabase·Cloudinary를 연결했습니다. 샘플 회원·가입 대기 회원·선수·게시글은 없습니다. 최초 어드민 `iris2you`의 가입 신청·승인·로그인·실제 회원관리 조회를 Chrome에서 확인했습니다. 로그인 후 어드민·운영진·부운영진에게 회원관리와 로그아웃, 일반회원에게 로그아웃을 표시합니다. 배포 상태는 [DEPLOYMENT.md](DEPLOYMENT.md), 회원관리는 [ADMIN.md](ADMIN.md)를 참고합니다.

메뉴는 공지사항·인기글·게시판·사진첩·도구·운영진 게시판·YB Holics입니다. 게시판 아래에는 자유게시판·유머게시판·모집게시판, 사진첩에는 벙개 사진·직관 사진·정모 사진, 운영진에는 작당모의·회의록, YB에는 선수단·경기 일정·홀릭스 게시판이 있습니다. 서브메뉴 12개 항목의 접근 불가·읽기·읽기/쓰기를 각각 관리합니다. 선수단은 기본적으로 누구나 읽을 수 있고, 홀릭스 게시판은 YB 소속 회원과 운영진·부운영진이 이용합니다. 가입 대기에는 승인·거절 버튼, 승인 회원에는 기간 지정 이용 제한·즉시 해제 버튼을 제공합니다. 제한 계정은 시작·해제 일시와 사유 안내를 보며 기간 종료 후 기존 권한으로 자동 복귀합니다. 접근할 수 없는 페이지는 권한 안내를 표시합니다.

선수단은 감독·코칭스태프·매니저·투수·포수·내야수·외야수 순서, 200×200 사진 아래 백넘버와 이름입니다. 어드민·운영진·부운영진·YB 감독·매니저는 **편집** 버튼을 켜면 선수 등록·수정·사진 변경·삭제를 사용할 수 있습니다. 편집 종료 시 버튼을 숨깁니다. 경기 일정은 비회원과 YB 미소속 회원도 보는 월별 달력과 날짜별 목록이며, 쓰기 권한으로 등록·수정·삭제합니다. 회원관리에서 응원 구단을 변경하면 회원·게시글 작성자 로고가 함께 갱신됩니다. 공개 선수단 사진과 비공개 게시글 사진의 접근 방식을 구분합니다.

10개 구단 로고와 운영진 금색 왕관·부운영진 은색 왕관·YB 소속 아이콘을 표시하는 코드를 유지합니다. 샘플 회원 데이터는 없습니다. KT 로고는 검정색이며 배경은 투명합니다. 작성자 열은 오른쪽 기준으로 정렬하며 게시글 목록에는 추천 마크와 추천 수가 없습니다.

자유게시판은 잡담 → 정보 → 질문 순서의 파스텔 말머리를 사용하며 기본값은 잡담입니다. 유머는 별도 게시판에 있습니다. 도구는 온라인 사다리 게임·차수별 정산 계산기·매직넘버 계산기입니다. 두 줄 네이비 헤더는 고정하고 화면 길이에 따라 메뉴가 좌우로 움직이지 않도록 스크롤 공간을 확보합니다.

소스는 [logy55/yabol](https://github.com/logy55/yabol)에 있으며 GitHub Actions가 `dist/`를 GitHub Pages에 배포합니다. HTTPS, DB 스키마, 두 서버 함수와 서버 비밀 설정을 완료했습니다. 실제 사진 업로드·서로 다른 회원의 게시글/댓글·여러 기기의 사다리 동시 참여는 아직 운영 환경에서 검증하지 않았습니다.

## 구성

| 역할 | 서비스 | 소스 |
|---|---|---|
| 화면과 주소 | GitHub Pages | `dist/`, `.github/workflows/pages.yml` |
| 회원 인증·글·댓글·추천 | Supabase | `supabase/schema.sql` |
| 사진 파일 | Cloudinary | 서버용 `supabase/functions/media-upload/index.ts` |

`dist/config.js`에는 사이트 이름, Supabase 프로젝트 URL·공개 키, Cloudinary cloud name만 넣습니다. Cloudinary API secret과 Supabase service-role 키는 절대로 `dist/`나 GitHub에 넣지 않습니다.

## 로컬 미리보기

Python이 설치된 PC에서 프로젝트 폴더를 열고 실행합니다.

```powershell
python -m http.server 8768 --bind 127.0.0.1 --directory dist
```

그다음 `http://127.0.0.1:8768/`를 엽니다. `file://`로 직접 여는 방식은 모듈 스크립트 때문에 지원하지 않습니다.

## 실제 서비스 연결 순서

1. 새 Supabase 프로젝트를 만들고 SQL Editor에서 `supabase/schema.sql`을 **한 번** 실행합니다. 기존 데이터가 있는 프로젝트에는 그대로 적용하지 않습니다.
2. 이메일 없는 아이디 가입과 관리자 승인 방식은 `MEMBERSHIP.md`에 따라 연결합니다. `membership-auth` 서버 함수와 003 SQL이 필요하며 운영진·YB 표시는 004·005 SQL, 자유게시판 말머리 통합은 006 SQL, 사진첩 직관 분류는 007 SQL, 에디터 본문은 008 SQL, 회원 관리·읽기/쓰기 권한은 009, 운영진 관리 접근은 010, 운영진 하위 게시판·선수단은 011, 유머게시판·일정은 012, 서브메뉴 권한은 013, 선수 편집은 014, 선수 편집 역할과 YB 직책은 015, 기간 지정 이용 제한은 016, 운영진의 홀릭스 접근은 017, 경기 일정 공개 조회는 018, 회원관리 구단 변경은 019, 모집게시판은 020, 백넘버 정렬은 021, 사다리 방은 022, 메인 공지 선택은 023, YB 가입 신청은 024, 방장 설정은 025, 자유게시판 말머리는 026 SQL을 순서대로 적용합니다. 갱신된 두 Edge Function도 함께 배포합니다. 새 프로젝트용 `schema.sql`에는 모두 포함되어 있습니다. 가입 신청은 관리자 승인 후 이용할 수 있으며, 구단 로고 닉네임 · 지역 형식으로 표시합니다.
3. Cloudinary에서 **Signed** 업로드 프리셋을 만듭니다. 허용 포맷은 `jpg,png,webp`, overwrite는 `false`, 공개 사진은 전달 유형 `upload`, 운영진·YB 사진은 별도의 인증된 `authenticated` 프리셋으로 설정합니다. 공개 unsigned 프리셋은 이 구현에서 사용하지 않습니다. Cloudinary는 프리셋별 파일 크기 제한을 지원하지 않으므로 10MiB 제한은 사이트 업로드 전 검사와 서버의 업로드 결과 검증에서 적용합니다.
4. Supabase Edge Function Secrets에 다음 값을 설정합니다. 비밀 값은 채팅에 붙여넣거나 저장소에 커밋하지 않습니다.

   | 변수 | 값 |
   |---|---|
   | `CLOUDINARY_CLOUD_NAME` | Cloudinary cloud name |
   | `CLOUDINARY_API_KEY` | Cloudinary API key |
   | `CLOUDINARY_API_SECRET` | Cloudinary API secret |
   | `CLOUDINARY_SIGNED_PRESET` | 공개 사진 signed 프리셋 이름 |
   | `CLOUDINARY_PRIVATE_SIGNED_PRESET` | 비공개 사진 authenticated signed 프리셋 이름 |
   | `ALLOWED_ORIGINS` | GitHub Pages의 origin, 예: `https://사용자명.github.io` |

   `SUPABASE_URL`, `SUPABASE_ANON_KEY`와 `SUPABASE_SERVICE_ROLE_KEY`는 Edge Function 서버 환경에서 제공합니다. 로컬에서 테스트할 때만 별도 비공개 환경 파일에 설정합니다. origins는 경로 없이 지정하며, 로컬 테스트를 허용할 때는 쉼표로 `http://127.0.0.1:8768`을 추가합니다.
5. Supabase CLI로 `media-upload`와 `membership-auth` 함수를 배포합니다. `supabase/config.toml`은 각 함수가 요청을 검증하도록 구성합니다. 사진 함수는 회원 JWT와 승인·게시판 접근 권한을 확인하고, 가입·로그인 함수는 입력값과 관리자 승인 여부를 확인합니다.
6. `dist/config.js`의 공개 설정 세 항목을 채웁니다. URL과 키가 설정되면 Supabase 데이터를 불러옵니다.
7. GitHub 저장소에 소스를 올리고 Settings → Pages → Source를 GitHub Actions로 설정합니다. 워크플로가 `dist/`만 게시합니다. `main` 브랜치를 사용하는 구성입니다.
8. 별도 계정 2개와 로그아웃 브라우저로 아래 운영 검증을 수행한 뒤 공개합니다.

## 공개 전 운영 검증

- 아이디 가입 신청 → 관리자 승인 → 로그인 → 로그아웃 → 다시 로그인
- 승인 전 로그인·글쓰기·댓글·추천 제한, 승인 후 선택 구단 로고·닉네임·지역 표시 확인
- 가입 거절, 제한 예약·시작·자동 만료·중도 해제와 제한 계정의 해제 예정일 안내 확인
- YB 미소속 운영진·부운영진의 홀릭스 글·댓글·사진 접근과 선수 편집 다섯 역할 확인
- 계정 A의 글·사진·댓글이 계정 B와 로그아웃 브라우저에서 새로고침 후 보이는지 확인
- 계정 B 및 비회원이 A의 글을 수정하거나 A의 이름으로 작성할 수 없는지 API 요청으로 확인
- 비회원의 사진 업로드와 임의 이미지 URL 등록이 거절되는지 확인
- 같은 회원의 같은 글 추천 중복 등록이 불가능한지 확인
- 정상 사진 1~5장 업로드와 10MB 초과·허용되지 않은 포맷 거절 확인
- 네트워크 오류 시 작성 중인 본문이 사라지지 않는지 확인

## 운영 범위와 아직 남은 작업

현재 연결용 코드는 회원가입·로그인, 공개 글 조회, 본인 글 수정, 댓글 작성, 추천·취소, 사진 업로드에 해당합니다. 사진은 서버가 Cloudinary에서 확인한 URL만 게시글에 첨부할 수 있습니다. 회원 이메일을 가입 항목으로 수집하지 않습니다. 승인 운영과 내부 인증 식별자는 `MEMBERSHIP.md`를 참고합니다.

이번 시안에는 신고 처리·비밀번호 재설정·탈퇴 화면·게시글 삭제 화면이 들어 있지 않습니다. 공지는 해당 게시판 쓰기 권한이 있는 회원이 글쓰기 화면에서 등록할 수 있습니다. 회원 승인·거절·기간 지정 이용 제한·중도 해제·등급·서브메뉴별 읽기/쓰기·YB 소속과 직책·어드민 권한·변경 기록은 ADMIN.md의 관리자 화면으로 관리합니다. 공개 커뮤니티 운영을 결정하면 필요한 관리 기능과 사이트 이용약관·개인정보 안내를 주제와 운영 방식에 맞춰 추가해야 합니다.

피드는 최신 500개를 불러오는 초기 구현이며, 장기간 운영할 사이트는 서버 검색과 페이지네이션으로 확장해야 합니다. 사진을 업로드한 뒤 글 등록을 취소한 경우 Cloudinary에 미사용 파일이 남을 수 있어 정리 정책이 필요합니다. 업로드 서명은 회원당 시간당 30회·하루 100회로 제한합니다. 실제 서비스의 요금·용량·발송 한도는 각 계정의 플랜을 확인합니다.

## 공식 문서

- [GitHub Pages Actions 배포](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages)
- [Supabase 공개 키와 서버 비밀 키](https://supabase.com/docs/guides/getting-started/api-keys)
- [Supabase Row Level Security](https://supabase.com/docs/guides/database/postgres/row-level-security)
- [Cloudinary 인증된 브라우저 업로드](https://cloudinary.com/documentation/client_side_uploading)
- [Cloudinary 업로드 서명](https://cloudinary.com/documentation/authentication_signatures)

온라인 사다리·모집 참석·메인 공지는 [TOOLS.md](TOOLS.md), 배포에 필요한 계정과 설정은 [DEPLOYMENT.md](DEPLOYMENT.md)를 참고합니다. 메인에는 공지와 전체 인기글만 표시하고 향후 배너를 위한 숨겨진 슬롯을 두었습니다.
