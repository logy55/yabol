# 배포 준비

현재 코드는 로컬에서 검증했으며 공개 배포와 실제 Supabase·Cloudinary 연결은 아직 하지 않았습니다. 사이트에 샘플 회원·선수·게시글이 들어 있지 않습니다. 기본 접속 상태는 비로그인입니다.

## 확인한 배포 대상

- 도메인: `yabol.co.kr`
- GitHub 계정: `logy55`
- 기존 `logy55/settlement`의 예전 계산기 파일 정리는 사용자 요청에 따라 진행합니다. 현재 원격 파일은 `index.html` 하나이며, 삭제 작업과 공개 배포는 아직 수행하지 않았습니다.
- 실제 GitHub 인증 연결과 Supabase·Cloudinary 프로젝트 연결이 남아 있습니다.

## 필요한 정보

- 사이트를 올릴 GitHub 저장소 이름 또는 URL
- 새 Supabase 프로젝트의 URL과 공개 publishable key
- Cloudinary cloud name와 업로드 프리셋 설정
- 최초 어드민으로 사용할 로그인 아이디

비밀번호와 service-role 키, Cloudinary API secret은 채팅에 보내지 않고 서비스의 비밀 설정 화면에서 입력합니다. 최초 어드민은 실제 회원가입을 마친 계정을 `MEMBERSHIP.md`의 SQL로 지정합니다.

## 연결 순서

1. GitHub 저장소를 정하고 Supabase·Cloudinary 프로젝트를 준비합니다.
2. **새 DB는 `supabase/schema.sql`을 한 번 실행**합니다. 이미 019까지 적용한 DB는 020 → 021 → 022 → 023 → 024 → 025 → 026 순서로 적용합니다. 기존 DB에 전체 schema를 다시 실행하지 않습니다.
3. Supabase에서 `membership-auth`와 `media-upload` Edge Function을 배포합니다. 두 함수의 `ALLOWED_ORIGINS`에 배포할 HTTPS origin을 설정합니다. 개발 검증 시에만 `http://127.0.0.1:8768`을 추가합니다.
4. Cloudinary 공개 signed 프리셋과 비공개 authenticated 프리셋을 설정하고 API secret을 Edge Function의 서버 비밀에 저장합니다. 정확한 설정은 `README.md`를 따릅니다.
5. `dist/config.js`에 Supabase URL·공개 키·Cloudinary cloud name만 입력합니다.
6. 실제 계정으로 가입 신청 → 어드민 승인 → 로그인 → 구단·지역·소속 표시를 확인합니다. YB 체크는 가입 요청이며 관리자 확인을 거쳐 권한을 부여합니다.
7. 별도 승인 계정 두 개로 글·댓글·사진과 모집 참석/불참을 확인하고, 온라인 사다리 방에 동시에 입장해 모두 준비 → 카운트다운 → 순차 결과 공개를 확인합니다.
8. GitHub 저장소에 소스를 올립니다. Settings → Pages → Source를 **GitHub Actions**로 설정합니다. 포함된 워크플로는 `dist/`만 배포합니다.
9. GitHub Pages에서 custom domain을 설정하고 가비아 DNS를 연결합니다. `DOMAIN.md`의 공식 가이드를 참고하고 HTTPS가 준비되면 활성화합니다.
10. 실제 도메인에서 회원가입·로그인·권한·업로드·사다리를 다시 확인합니다.

사다리 상태는 1.5초 간격으로 서버 RPC를 조회하므로 Supabase Realtime 테이블 구독 설정은 필요하지 않습니다. 방을 만든 회원이 방장이며 시작 전 참여 인원과 꽝 인원을 설정합니다. 결과는 서버에서 생성하고 모든 참여자가 같은 게임과 시작 시각을 받습니다.

## 배포 전 PC 테스트

개발용 별도 서버 `http://127.0.0.1:8769/`는 메모리 DB와 테스트 회원 2명을 사용합니다. 실제 사이트나 공개 DB에 테스트 회원을 만들지 않습니다.

1. `http://127.0.0.1:8769/?player=1`에서 참여 인원 2명·꽝 1명으로 방을 만듭니다.
2. `http://127.0.0.1:8769/?player=2`에서 대기방 목록의 입장을 누릅니다.
3. 두 창에서 각각 준비를 누릅니다. 5초 후 1번 경로·결과, 2번 경로·결과 순서로 공개됩니다.
4. 다시 테스트할 때 방장이 나가서 새 방을 만듭니다. 서버를 종료하면 테스트 데이터는 없어집니다.

이 검증은 PC 내부에서 SQL과 브라우저가 연결되는 흐름을 확인하며, 실제 Supabase 인증·인터넷 지연·서로 다른 기기에서의 검증은 서비스 연결 후 수행합니다.
