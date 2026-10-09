# yabol.co.kr과 GitHub Pages 연결

가비아에서 도메인을 구매하고, 홈페이지 파일은 GitHub Pages에 배포하는 구성을 사용할 수 있습니다. 현재 사이트는 localhost 미리보기이며 GitHub 저장소·공개 배포·도메인 DNS 변경은 아직 수행하지 않았습니다.

도메인은 사이트 주소, GitHub Pages는 화면 파일을 제공하는 호스팅, Supabase는 회원·게시글 저장, Cloudinary는 사진 저장을 담당합니다. 도메인 연결 자체로 회원가입이나 저장 기능이 활성화되지는 않습니다.

1. 가비아에서 사용할 도메인을 구매합니다. 아래 절차는 가비아 네임서버를 이용할 때의 설정입니다.
2. 이 프로젝트를 GitHub 저장소에 올립니다. 저장소 Settings → Pages → Source를 GitHub Actions로 설정하고 포함된 `.github/workflows/pages.yml`로 `dist/`를 배포합니다.
3. GitHub Settings → Pages → Custom domain에 `yabol.co.kr`을 입력해 저장합니다. 가비아 DNS를 연결하기 전에 GitHub에 먼저 등록합니다.
4. 가비아 서비스 관리 → DNS 관리툴 → 대상 도메인 → DNS 설정에서 아래 레코드를 추가합니다. `@`는 구매한 도메인 자체, `www`는 www 주소입니다.

| 타입 | 호스트 | 값 |
|---|---|---|
| A | @ | 185.199.108.153 |
| A | @ | 185.199.109.153 |
| A | @ | 185.199.110.153 |
| A | @ | 185.199.111.153 |
| CNAME | www | logy55.github.io. |

CNAME은 사이트를 배포할 `logy55` 계정을 기준으로 작성했습니다. 저장소 이름이나 `https://`를 붙이지 않습니다. 가비아는 CNAME 목적지 끝의 마침표를 요구합니다. IPv6 연결을 추가하려면 GitHub 공식 문서의 AAAA 값도 사용할 수 있습니다.

5. DNS 확인과 인증서 준비가 끝나면 GitHub Pages에서 **Enforce HTTPS**를 켭니다. 가비아는 DNS 반영에 최대 48시간이 걸릴 수 있다고 안내합니다.
6. 실제 로그인·사진 업로드 연결 시 서버의 `ALLOWED_ORIGINS`에 사용할 HTTPS 도메인을 등록하고 Supabase·Cloudinary 설정을 마칩니다. 실제 Origin을 확인하기 전 설정을 추정해 넣지 않습니다.

주소를 도메인 자체로 설정하고 위 www 레코드도 구성하면 www 주소는 선택한 기본 주소로 이동합니다. 이 프로젝트는 GitHub Actions 배포이므로 GitHub가 제공하는 도메인 설정을 사용하며 별도의 CNAME 파일은 필요하지 않습니다.

절차와 DNS 값은 2026-10-10에 확인했습니다. [가비아 DNS 레코드 설정 매뉴얼](https://customer.gabia.com/manual/38/3041/3040), [GitHub Pages 도메인 연결 문서](https://docs.github.com/en/pages/configuring-a-custom-domain-for-your-github-pages-site/managing-a-custom-domain-for-your-github-pages-site)를 참고합니다.
