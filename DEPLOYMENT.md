# 배포 상태

2026-10-10에 [yabol.co.kr](https://yabol.co.kr/)로 배포했습니다. 소스 저장소는 [logy55/yabol](https://github.com/logy55/yabol)이며 GitHub Actions가 `main`의 `dist/` 변경을 GitHub Pages에 자동 배포합니다.

## 완료한 연결

- 가비아 DNS: GitHub Pages A 레코드 4개와 `www` CNAME, TTL 600. 실제 도메인의 HTTPS 접속과 Enforce HTTPS를 확인했습니다.
- Supabase: 서울 리전 프로젝트 `yiosmfdqsvnadauxcxto`, 새 DB에 026까지 포함한 `schema.sql`을 한 번 적용했습니다. 확인 시 사이트 테이블 16개 모두 RLS가 활성화돼 있었습니다.
- 서버 함수: `membership-auth`, `media-upload` 배포. 함수 내부에서 인증·승인·권한을 검사합니다. 일반 공개 Auth 가입은 껐고 아이디 가입 함수를 사용합니다.
- 서버 Origin: `https://yabol.co.kr`, `https://www.yabol.co.kr`, `https://logy55.github.io`.
- Cloudinary: 무료 Image & Video 플랜, cloud name `rvu3qaha`. `yabol_public`은 Signed/upload, `yabol_private`은 Signed/authenticated입니다. 허용 포맷은 jpg/png/webp, overwrite는 false입니다.
- 비밀 키: Cloudinary API secret과 Supabase service-role 값은 Supabase 서버 환경에만 저장했습니다. 공개 소스에는 프로젝트 URL·publishable key·cloud name만 있습니다.
- 최초 어드민: 실제 가입 신청한 `iris2you`를 승인·지정했습니다. Chrome에서 로그인, NC 로고·이다영·관악 표시, 실제 회원관리 목록과 어드민 권한을 확인했습니다.
- 샘플 회원·게시글·선수는 없습니다. 확인 당시 실제 회원은 최초 어드민 1명뿐입니다.
- 사진첩 3종과 운영진 2종의 페이지 내부 이동 버튼을 제거했고 실제 도메인에서 확인했습니다. 상단 드롭다운과 자유게시판 말머리는 유지합니다. 회원가입 창을 먼저 연 경우에도 클라이언트 연결 완료 후 제출 버튼이 활성화되도록 수정했습니다.
- 기존 `logy55/settlement/index.html`은 사용자 요청으로 Git 이력에 복구 가능한 삭제 커밋을 남겼습니다. 로컬 백업은 `work/settlement-legacy/index.html`에 있습니다.

## 수정과 재배포

화면 파일을 수정하고 필요한 검증을 마친 뒤 GitHub `main`의 `dist/`에 반영하면 자동 배포됩니다. DB 변경은 다음 번호의 마이그레이션으로 적용합니다. 운영 DB에 전체 `schema.sql`을 다시 실행하지 않습니다. 서버 함수 변경은 Supabase에 별도로 배포해야 합니다.

## 남은 운영 검증

실제 도메인의 가입·최초 승인·로그인·회원관리 조회는 확인했습니다. 실제 사진 업로드와 비공개 사진 접근, 서로 다른 실회원의 게시글·댓글·모집 참석/불참, 여러 기기의 온라인 사다리 동시 참여는 아직 운영 환경에서 검증하지 않았습니다. 샘플 데이터를 공개 DB에 생성하지 않았습니다.

로컬 PGlite에서 DB 이관·권한·제한 해제·모집 참석·백넘버 정렬·사다리 상태를 검증했고, 메모리 DB의 별도 테스트 서버에서 2인 사다리 준비·카운트다운·순차 결과를 확인했습니다. 이는 인터넷에서 여러 기기를 사용하는 검증을 대체하지 않습니다.

사진 저장·전송·변환은 Cloudinary의 공유 크레딧 한도를 사용합니다. 무료 플랜은 25크레딧이며 현재 사이트 업로드 제한은 사진당 10MiB, 게시물당 5장입니다. Cloudinary는 프리셋별 파일 크기 제한을 지원하지 않아 클라이언트와 서버의 업로드 결과 검사로 제한합니다.
