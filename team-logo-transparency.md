# 구단 로고 투명 배경 처리

NC 다이노스는 기존 투명 SVG를 유지합니다. 나머지 9개 구단은 원본을 보존하고 내장 image_gen 도구의 배경 추출 편집으로 투명 PNG를 적용했습니다. 완성 파일은 `dist/assets/teams/{구단 id}-transparent.png`에 저장했습니다. 사이트의 로고 이미지와 감싸는 영역 배경도 투명하게 유지합니다.

9개 PNG의 RGBA 알파 범위가 0~255이고 네 모서리 알파가 0임을 확인했습니다. 10개 구단 모두 실제 회원 표시 크기로 흰색·네이비 배경에서 확인했습니다. KT는 모든 배경에서 검정색으로 표시하며 밝은 외곽선은 제거했습니다. 투명 알파는 유지합니다. 이 편집 결과는 회원 배지 표시용이며, 원본 구단 파일도 그대로 보관합니다.

각 입력 파일은 편집 전에 화면으로 확인했습니다. 입력은 각 구단의 기존 이미지 한 장이며 새 로고를 생성하기 위한 참고 이미지가 아닙니다.

최종 프롬프트는 아래 템플릿을 구단별로 적용합니다. LG는 black, 다른 구단은 white 배경을 제거합니다.

```text
Use case: background-extraction.
Asset type: {team name} team insignia used as a tiny website member badge.
Input image 1 is the edit target, not a loose design reference.
Remove the flat {background color} rectangular background and the background visible in open gaps around or through the insignia. Output an actual transparent PNG with alpha, not a drawn checkerboard.
Preserve the exact original emblem geometry, all letterforms, proportions, colors, shades, border widths and any intentional white keylines or white/light-gray fills INSIDE the emblem. Do not redesign or reinterpret any detail. Change only the background transparency.
Center the complete original emblem with about 5% transparent padding around its visible bounds, preserving the emblem aspect ratio. Use clean anti-aliased edges, no white or dark background fringe. Do not clip the insignia, add text, cast shadows, glow, or introduce new shapes.
```

| id | team name | input | background color |
| --- | --- | --- | --- |
| kia | KIA Tigers | kia.png | white |
| samsung | Samsung Lions | samsung.jpg | white |
| lg | LG Twins | lg.webp | black |
| doosan | Doosan Bears | doosan.jpg | white |
| kt | KT Wiz | kt.jpg | white |
| ssg | SSG Landers | ssg.png | white |
| lotte | Lotte Giants | lotte.png | white |
| hanwha | Hanwha Eagles | hanwha.jpg | white |
| kiwoom | Kiwoom Heroes | kiwoom.png | white |

## 적용 파일

- [kia-transparent.png](C:/Users/이다영/Documents/Codex/2026-10-07/df/outputs/community-site/dist/assets/teams/kia-transparent.png)
- [samsung-transparent.png](C:/Users/이다영/Documents/Codex/2026-10-07/df/outputs/community-site/dist/assets/teams/samsung-transparent.png)
- [lg-transparent.png](C:/Users/이다영/Documents/Codex/2026-10-07/df/outputs/community-site/dist/assets/teams/lg-transparent.png)
- [doosan-transparent.png](C:/Users/이다영/Documents/Codex/2026-10-07/df/outputs/community-site/dist/assets/teams/doosan-transparent.png)
- [kt-transparent.png](C:/Users/이다영/Documents/Codex/2026-10-07/df/outputs/community-site/dist/assets/teams/kt-transparent.png)
- [ssg-transparent.png](C:/Users/이다영/Documents/Codex/2026-10-07/df/outputs/community-site/dist/assets/teams/ssg-transparent.png)
- [lotte-transparent.png](C:/Users/이다영/Documents/Codex/2026-10-07/df/outputs/community-site/dist/assets/teams/lotte-transparent.png)
- [hanwha-transparent.png](C:/Users/이다영/Documents/Codex/2026-10-07/df/outputs/community-site/dist/assets/teams/hanwha-transparent.png)
- [kiwoom-transparent.png](C:/Users/이다영/Documents/Codex/2026-10-07/df/outputs/community-site/dist/assets/teams/kiwoom-transparent.png)
- [nc.svg](C:/Users/이다영/Documents/Codex/2026-10-07/df/outputs/community-site/dist/assets/teams/nc.svg)
