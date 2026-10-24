# Whozzie 사다리 엔진

출처: https://github.com/zeikar/whozzie

검토 버전: d8217dfef8b6fff22cdaff607c890cd2dc92b98f

`src/vendor/whozzie`의 사다리·경로 배치·난수 코드와 `dist/whozzie.js`는 Whozzie의 MIT 소스를 사용합니다. 기존 정적 사이트에 맞춰 경로를 수정했고 SQL의 사다리 생성 로직도 이 알고리즘을 적용했습니다. 온라인 대기방, 준비·카운트다운·서버 동기화와 네이비 UI는 이 사이트에서 추가했습니다. 전체 Whozzie 앱을 삽입한 것은 아닙니다.

MIT License

Copyright (c) 2025 zeikar

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.


# 정산 계산기

출처: https://github.com/logy55/settlement/blob/main/index.html

사용자가 직접 만든 본인 소스라고 밝히고 이 사이트에 적용하도록 요청했습니다. 원본 입력·차수별 지출·참여자 선택·결과 복사 흐름을 유지하고 나눔스퀘어라운드/네이비 디자인, 정수 원 단위 정산, 사이트 내 표시를 수정했습니다. 원본에는 별도 공개 라이선스가 없으므로 제3자 공개 사용 허가를 이 문서에서 부여하지 않습니다.

# Anime.js

공식 출처: https://github.com/juliangarnier/anime/tree/v3.2.2

고정 버전 3.2.2의 ESM 소스를 `dist/anime.js`에 포함했습니다. 사다리의 야구공 이동·경로 표시·결과 카드 연출에 사용합니다. MIT 라이선스 전문은 `dist/anime-LICENSE.txt`에 포함합니다.

# Marble physics and maps

Source: https://github.com/lazygyu/roulette/tree/bd237348858035c48336c3f2a0d5276008d86fb6

MIT licensed physics adapter, map definitions, original camera, progress ranking, zoom helpers and rendering constants. The site supplies its own interface, room server and renderer. The adapter uses an instance-local seeded random generator and a fixed non-SIMD Box2D WASM build for replay. Original branding, advertisements, analytics and community services are excluded. MIT text: `dist/marble-LICENSE.txt`. Box2D WASM 7.0.0 uses the zlib license, retained at `dist/marble-box2d-LICENSE.txt`. Original sources and local modifications are in `marble-source.zip` and the local `src/` tree. Unzip at the project root, run `pnpm install`, then `pnpm build:marble` to rebuild.

# Mediabunny MP4 encoder

Official source: https://github.com/Vanilagy/mediabunny

Mediabunny 1.62.1 is bundled without library source modifications in `dist/video-encoder.js` under MPL-2.0. The complete license is `dist/mediabunny-LICENSE.txt`. The exact corresponding npm source package is included as `mediabunny-source.tgz` at the project root, also available at https://github.com/logy55/yabol/blob/main/mediabunny-source.tgz . The site-specific import entry is `src/replay-video-encoder.js`; install dependencies and run `build:replay-video` to rebuild. Replay capture uses local browser WebCodecs and does not upload recordings to a server.

## 야구공 게임
Matter.js 0.20.0 (MIT), https://github.com/liabru/matter-js . 라이선스는 dist/baseball/matter-LICENSE.txt, 공식 소스는 src/vendor/matter.cjs에 포함합니다. 물리 엔진은 브라우저와 점수 검증 서버에서 동일한 버전을 사용합니다. 스포츠공 그림·게임 규칙·UI는 자체 작성했습니다.

