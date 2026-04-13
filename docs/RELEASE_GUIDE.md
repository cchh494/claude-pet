# ClaudePet 릴리즈 가이드

> **Claude에게 릴리즈를 요청할 때**: "ZIP 만들어줘" 또는 "새 버전 릴리즈하고 싶어"라고 말하면  
> Claude가 이 파일을 읽고 아래 절차에 따라 단계별로 안내합니다.

---

## 고정 정보 (변경 시 이 파일도 업데이트)

| 항목 | 값 |
|------|----|
| sign_update 경로 | `/Users/main/Library/Developer/Xcode/DerivedData/ClaudePet-bjpbajhvsnfemrhigrxsgbgaqkeq/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update` |
| appcast.xml 위치 | `/Users/main/Documents/claude-pet/docs/appcast.xml` |
| GitHub 저장소 | `https://github.com/cchh494/claude-pet` |
| appcast URL | `https://cchh494.github.io/claude-pet/appcast.xml` |
| 앱 저장 위치 패턴 | `/Users/main/Desktop/ClaudePet Version/ClaudePet x.x.x/ClaudePet.app` |

---

## Claude의 역할 vs 내가 할 일

| 단계 | 담당 | 내용 |
|------|------|------|
| 버전 번호 확인 | Claude | appcast.xml 읽어서 현재 최신 버전 확인 후 안내 |
| Xcode 버전 올리기 | **나** | Xcode에서 직접 수정 |
| 앱 빌드 | **나** | `⌘B` |
| .app 파일 위치 확인 | **나** | Claude에게 경로 알려주기 |
| ZIP 생성 명령어 제공 | Claude | `ditto` 명령어를 복붙 가능하게 제공 |
| ZIP 서명 명령어 제공 | Claude | `sign_update` 명령어를 복붙 가능하게 제공 |
| 파일 크기 확인 명령어 제공 | Claude | `stat` 명령어를 복붙 가능하게 제공 |
| appcast.xml 업데이트 | Claude | edSignature + length 받으면 자동으로 수정 |
| GitHub Release 생성 | **나** | 브라우저에서 직접 업로드 |
| git push | **나** | 터미널에서 직접 실행 |

---

## 릴리즈 절차 (Claude 안내 기준)

### STEP 1. 버전 정보 확인 (Claude가 함)
- `appcast.xml` 읽어서 현재 최신 버전 확인
- 새 버전 번호와 빌드 번호 제안 (예: 1.0.4 → 1.0.5, 빌드 4 → 5)

### STEP 2. Xcode 작업 (내가 함)
- `ClaudePet.xcodeproj` → Target → General에서:
  - **Marketing Version**: 새 버전으로 변경 (예: `1.0.5`)
  - **Current Project Version**: 빌드 번호 1 증가 (예: `5`)
- `⌘B` 로 빌드

### STEP 3. .app 파일 준비 (내가 함)
- 원하는 위치에 .app 파일 준비 후 Claude에게 경로 알려주기
- 예: `/Users/main/Desktop/ClaudePet Version/ClaudePet 1.0.5/ClaudePet.app`

### STEP 4. ZIP 생성 (Claude가 명령어 제공 → 내가 터미널에서 실행)

Claude가 아래 형식으로 명령어를 제공함:
```bash
ditto -c -k --keepParent \
  "/Users/main/Desktop/ClaudePet Version/ClaudePet [버전]/ClaudePet.app" \
  "/Users/main/Desktop/ClaudePet Version/ClaudePet [버전]/ClaudePet.zip"
```

### STEP 5. ZIP 서명 (Claude가 명령어 제공 → 내가 터미널에서 실행)

Claude가 아래 형식으로 명령어를 제공함:
```bash
/Users/main/Library/Developer/Xcode/DerivedData/ClaudePet-bjpbajhvsnfemrhigrxsgbgaqkeq/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update \
  "/Users/main/Desktop/ClaudePet Version/ClaudePet [버전]/ClaudePet.zip"
```

출력 예시:
```
sparkle:edSignature="xxxx...==" length="4361559"
```

→ 이 출력값을 그대로 Claude에게 붙여넣기

### STEP 6. appcast.xml 업데이트 (Claude가 함)
- edSignature와 length 값을 받아 `appcast.xml`에 새 `<item>` 블록 자동 추가

추가되는 블록 형식:
```xml
<item>
    <title>Version [버전]</title>
    <sparkle:releaseNotesLink>https://github.com/cchh494/claude-pet/releases/tag/v[버전]</sparkle:releaseNotesLink>
    <pubDate>[날짜]</pubDate>
    <sparkle:shortVersionString>[버전]</sparkle:shortVersionString>
    <sparkle:version>[빌드번호]</sparkle:version>
    <enclosure
        url="https://github.com/cchh494/claude-pet/releases/download/v[버전]/ClaudePet.zip"
        sparkle:edSignature="[서명값]"
        length="[파일크기]"
        type="application/octet-stream"/>
</item>
```

### STEP 7. GitHub Release 생성 (내가 함)
1. `https://github.com/cchh494/claude-pet/releases/new` 접속
2. Tag: `v[버전]` (예: `v1.0.5`)
3. Title: `ClaudePet [버전]`
4. `ClaudePet.zip` 파일 업로드
5. **Publish release** 클릭

### STEP 8. appcast.xml 푸시 (내가 함)
```bash
cd /Users/main/Documents/claude-pet
git add docs/appcast.xml
git commit -m "chore: add v[버전] to appcast"
git push
```

---

## 버전별 릴리즈 기록

| 버전  | 빌드 | 날짜       | 비고 |
|-------|------|------------|------|
| 1.0.0 | 1    | 2026-04-12 | 최초 릴리즈 |
| 1.0.3 | 3    | 2026-04-12 | |
| 1.0.4 | 4    | 2026-04-13 | |
| 1.0.5 | 5    | 2026-04-13 | |
| 1.0.6 | 6    | 2026-04-13 | |

---

## 참고

- Apple Developer 계정 없음 → **Notarization(공증) 미적용**
- 처음 실행 시 "개발자를 확인할 수 없음" 경고 → **우클릭 → 열기** 로 우회
- ZIP은 반드시 `ditto` 명령어로 생성 (Finder 압축 사용 시 Sparkle이 오작동할 수 있음)
