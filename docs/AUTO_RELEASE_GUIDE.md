# ClaudePet 자동 릴리즈 시스템 구축 가이드

> 현재의 수동 8단계 릴리즈를 **`git tag` 한 번**으로 줄이는 자동화 계획입니다.

---

## 현재 vs 목표

| 항목 | 현재 (수동) | 목표 (자동화) |
|------|------------|--------------|
| 릴리즈 단계 | 8단계 | 1단계 (태그 푸시) |
| 소요 시간 | ~15분 | ~3분 (CI 대기) |
| 실수 가능성 | 높음 (복붙, 경로, 서명) | 거의 없음 |
| appcast.xml | 수동 편집 | 자동 생성 |
| ZIP 서명 | 터미널에서 수동 | CI에서 자동 |

---

## 전체 흐름 요약

```
충남이 할 일                          GitHub Actions가 할 일
─────────────                        ─────────────────────
1. 코드 수정                          
2. Xcode에서 버전 올리기              
3. git tag v1.0.7 && git push --tags  →  4. xcodebuild로 앱 빌드
                                         5. ditto로 ZIP 생성
                                         6. sign_update로 EdDSA 서명
                                         7. appcast.xml 자동 갱신
                                         8. GitHub Release 생성 + ZIP 업로드
                                         9. appcast.xml 커밋 & 푸시
```

---

## Phase 1: 사전 준비 (충남이 할 일)

이 단계는 한 번만 하면 됩니다.

### 1-1. Sparkle EdDSA 서명 키를 GitHub Secret에 등록

Sparkle은 EdDSA 키 쌍으로 업데이트를 서명합니다. 현재 로컬에만 있는 이 비밀키를 GitHub에 안전하게 저장해야 해요.

**비밀키 찾기:**

```bash
cat ~/Library/Sparkle/ed25519/sparkle_private_key
```

만약 이 경로에 없다면, Sparkle이 키를 저장한 다른 위치를 찾아야 합니다:

```bash
# Keychain에서 찾기
security find-generic-password -s "ed25519" -g 2>&1
```

**GitHub Secret 등록:**

1. GitHub 저장소 → Settings → Secrets and variables → Actions
2. "New repository secret" 클릭
3. Name: `SPARKLE_PRIVATE_KEY`
4. Value: 위에서 찾은 비밀키 전체 내용 붙여넣기
5. "Add secret" 클릭

### 1-2. sign_update 바이너리를 저장소에 포함

현재 DerivedData 경로에 의존하고 있어서 불안정합니다. 두 가지 방법이 있어요:

**방법 A (추천): CI에서 Sparkle SPM 빌드 시 자동으로 가져오기**

GitHub Actions 워크플로우에서 Xcode 빌드를 하면 SPM이 Sparkle을 자동으로 받아오고, 그 안에 `sign_update`가 포함됩니다. 별도 작업 불필요.

**방법 B: 저장소에 직접 포함**

```bash
# 현재 sign_update 바이너리를 저장소에 복사
mkdir -p scripts
cp "/Users/main/Library/Developer/Xcode/DerivedData/ClaudePet-bjpbajhvsnfemrhigrxsgbgaqkeq/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update" scripts/
git add scripts/sign_update
git commit -m "chore: add sign_update binary for CI"
git push
```

### 1-3. Xcode 프로젝트 빌드 설정 확인

CI에서 빌드하려면 코드 서명 설정이 맞아야 합니다.

```
Signing & Capabilities:
  ☐ Automatically manage signing → 체크 해제
  ☐ Code Signing Identity → "Sign to Run Locally" 또는 "-" (Ad Hoc)
  ☐ Provisioning Profile → 없음
```

> Apple Developer 계정이 없으므로 Ad Hoc 서명으로 충분합니다.

---

## Phase 2: GitHub Actions 워크플로우 작성 (Claude가 도와줄 일)

아래 파일을 `.github/workflows/release.yml`에 만들면 됩니다. Claude에게 요청하면 프로젝트에 맞게 작성해줄 수 있어요.

### 워크플로우 핵심 구조

```yaml
name: Release

on:
  push:
    tags:
      - 'v*'   # v1.0.7 같은 태그가 푸시되면 실행

jobs:
  build-and-release:
    runs-on: macos-15    # Xcode가 필요하므로 macOS 러너 사용
    
    steps:
      # 1. 코드 체크아웃
      - uses: actions/checkout@v4

      # 2. Xcode 버전 선택
      - uses: maxim-lobanov/setup-xcode@v1
        with:
          xcode-version: latest-stable

      # 3. 앱 빌드
      - name: Build
        run: |
          xcodebuild -project ClaudePet.xcodeproj \
            -scheme ClaudePet \
            -configuration Release \
            -derivedDataPath build \
            CODE_SIGN_IDENTITY="-" \
            CODE_SIGNING_ALLOWED=NO

      # 4. ZIP 생성 (ditto 사용 — Finder 압축 X)
      - name: Create ZIP
        run: |
          ditto -c -k --keepParent \
            "build/Build/Products/Release/ClaudePet.app" \
            "ClaudePet.zip"

      # 5. EdDSA 서명
      - name: Sign ZIP
        env:
          SPARKLE_PRIVATE_KEY: ${{ secrets.SPARKLE_PRIVATE_KEY }}
        run: |
          # SPM에서 sign_update 경로 찾기
          SIGN_UPDATE=$(find build -name "sign_update" -type f | head -1)
          
          # 서명 실행
          SIGN_OUTPUT=$($SIGN_UPDATE "ClaudePet.zip" \
            --ed-key-file <(echo "$SPARKLE_PRIVATE_KEY"))
          
          # 결과 파싱
          ED_SIGNATURE=$(echo "$SIGN_OUTPUT" | grep -o 'edSignature="[^"]*"' | cut -d'"' -f2)
          FILE_LENGTH=$(stat -f%z "ClaudePet.zip")
          
          echo "ED_SIGNATURE=$ED_SIGNATURE" >> $GITHUB_ENV
          echo "FILE_LENGTH=$FILE_LENGTH" >> $GITHUB_ENV

      # 6. appcast.xml 업데이트
      - name: Update appcast.xml
        run: |
          VERSION=${GITHUB_REF_NAME#v}   # v1.0.7 → 1.0.7
          # Python 스크립트로 appcast.xml에 새 <item> 삽입
          python3 scripts/update_appcast.py \
            --version "$VERSION" \
            --signature "$ED_SIGNATURE" \
            --length "$FILE_LENGTH"

      # 7. GitHub Release 생성 + ZIP 업로드
      - name: Create Release
        uses: softprops/action-gh-release@v2
        with:
          files: ClaudePet.zip
          generate_release_notes: true

      # 8. appcast.xml 변경사항 커밋 & 푸시
      - name: Commit appcast
        run: |
          git config user.name "github-actions"
          git config user.email "actions@github.com"
          git add docs/appcast.xml
          git commit -m "chore: update appcast for ${{ github.ref_name }}"
          git push origin HEAD:main
```

### 필요한 보조 스크립트: `scripts/update_appcast.py`

appcast.xml을 자동으로 갱신하는 Python 스크립트도 필요합니다. Claude에게 요청하면 만들어줄 수 있어요.

이 스크립트가 하는 일:
- 태그에서 버전 번호 추출
- 현재 날짜로 pubDate 생성
- EdDSA 서명과 파일 크기로 `<item>` 블록 생성
- appcast.xml의 맨 위에 새 항목 삽입

---

## Phase 3: SparkleManager 에러 핸들링 강화 (Claude가 할 일)

현재 SparkleManager는 에러 처리가 전혀 없습니다. 아래를 추가하면 사용자 경험이 개선돼요:

```swift
extension SparkleManager: SPUUpdaterDelegate {
    // 기존: feedURL 제공
    func feedURLString(for updater: SPUUpdater) -> String? {
        return "https://cchh494.github.io/claude-pet/appcast.xml"
    }
    
    // 추가: 업데이트 에러 시 사용자에게 안내
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        // 에러 종류별 사용자 친화적 메시지 표시
        // 예: 네트워크 오류, 서명 불일치, 다운로드 실패 등
    }
    
    // 추가: 업데이트 찾을 수 없을 때
    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        // "이미 최신 버전입니다" 안내
    }
}
```

---

## Phase 4: 기존 문제 정리 (Claude가 할 일)

### 4-1. appcast.xml의 v1.0.0 깨진 항목 수정

현재 v1.0.0 항목에 `SIGNATURE_HERE`와 `length="0"`이 남아있어서, 이전 버전 사용자가 업데이트 체크 시 오류가 날 수 있습니다.

처리 방법:
- v1.0.0 사용자가 없다면 → 해당 `<item>` 삭제
- 있다면 → 올바른 서명값으로 교체

### 4-2. RELEASE_GUIDE.md 업데이트

자동화 완료 후 기존 릴리즈 가이드를 새 프로세스에 맞게 수정합니다.

---

## 실행 순서 체크리스트

아래 순서대로 진행하면 됩니다. ✋ = 충남이 직접, 🤖 = Claude가 도와줌

| # | 작업 | 담당 | 예상 시간 |
|---|------|------|----------|
| 1 | Sparkle 비밀키 찾아서 GitHub Secret 등록 | ✋ | 5분 |
| 2 | Xcode 코드 서명 설정 확인 | ✋ | 3분 |
| 3 | `.github/workflows/release.yml` 작성 | 🤖 | Claude에게 요청 |
| 4 | `scripts/update_appcast.py` 작성 | 🤖 | Claude에게 요청 |
| 5 | SparkleManager 에러 핸들링 추가 | 🤖 | Claude에게 요청 |
| 6 | appcast.xml v1.0.0 항목 정리 | 🤖 | Claude에게 요청 |
| 7 | 전체 커밋 & 푸시 | ✋ | 2분 |
| 8 | 테스트 릴리즈 (v1.0.7 태그 푸시해서 CI 확인) | ✋+🤖 | 10분 |

---

## 새로운 릴리즈 프로세스 (자동화 완료 후)

자동화가 끝나면 릴리즈는 이렇게 간단해집니다:

```bash
# 1. 코드 수정 & Xcode에서 버전 올리기 (충남)

# 2. 커밋
git add -A
git commit -m "feat: 새 기능 설명"

# 3. 태그 & 푸시 — 이것만 하면 끝!
git tag v1.0.7
git push origin main --tags

# 4. 기다리기 (~3분)
# GitHub Actions가 빌드 → ZIP → 서명 → appcast → Release 전부 처리

# 5. 확인
# https://github.com/cchh494/claude-pet/releases 에서 확인
```

---

## 문제가 생기면?

| 상황 | 해결 방법 |
|------|----------|
| CI 빌드 실패 | GitHub Actions 탭에서 로그 확인. 대부분 Xcode 버전이나 서명 설정 문제 |
| 서명 오류 | `SPARKLE_PRIVATE_KEY` Secret이 올바른지 확인 |
| appcast 업데이트 안 됨 | Actions에 `contents: write` 권한이 있는지 확인 |
| 이전 버전에서 업데이트 안 됨 | appcast.xml에 해당 버전의 항목이 있는지 확인 |

---

## 참고사항

- **비용**: GitHub Actions는 public 저장소에서 무료입니다. private이면 월 2,000분 무료 제공.
- **macOS 러너**: macOS 러너는 Linux보다 소진이 빠릅니다 (1분 = 10분 소진). public repo면 상관없음.
- **Apple Developer 계정**: 현재 없어도 이 자동화는 완전히 동작합니다. 나중에 계정을 만들면 공증(Notarization) 단계만 CI에 추가하면 돼요.
