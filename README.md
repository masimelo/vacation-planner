# 🎖️ 병사 휴가 플래너 — 배포 가이드

정적 HTML 앱 + Supabase(Postgres/인증) + Cloudflare Pages 구성.
서버 코드 없이 동작하며, **Supabase 설정을 비워두면 기존처럼 브라우저 저장만으로 그대로 작동**합니다.

```
.
├── public/                 ← 웹에 서빙되는 건 이 폴더뿐
│   ├── index.html          앱 본체 (클라우드 동기화 + 공동 편집 포함)
│   └── _headers            보안 헤더
├── wrangler.jsonc          Cloudflare 배포 설정
├── supabase-schema-v2.sql  DB 테이블 + 보안정책  ← 이걸 실행하세요
├── supabase-schema.sql     v1(1인용). 참고용으로만 남겨둠
└── README.md               이 문서
```

스키마 파일과 이 문서는 `public/` 밖에 있어서 웹에 노출되지 않습니다.

---

## 1단계 — Supabase 프로젝트 만들기 (약 5분)

1. <https://supabase.com> 가입 → **New project** 생성
   - Region은 `Northeast Asia (Seoul)` 선택 (속도)
   - DB 비밀번호는 직접 정하고 따로 보관 (앱에서는 안 씁니다)
2. 프로젝트가 준비되면 왼쪽 메뉴 **SQL Editor** → **New query**
3. `supabase-schema-v2.sql` 내용을 통째로 붙여넣고 **Run**
   - `Success. No rows returned` 이 나오면 정상
   - 여러 번 실행해도 안전합니다 (v1을 이미 돌렸다면 기존 데이터가 자동으로 옮겨집니다)
4. 상단 **Connect** 버튼 (또는 **Project Settings → API Keys**) 에서 두 값을 복사
   - **Project URL** → `https://xxxxx.supabase.co`
   - **Publishable key** → `sb_publishable_...` 로 시작하는 문자열

> Supabase가 키 형식을 바꿔서, 예전 `anon` 키(`eyJhbGci...`)는 **Legacy API keys** 탭에 있습니다.
> 둘 다 동작하지만 legacy 키는 2026년 말 폐지 예정이라 `sb_publishable_...` 쪽을 쓰세요.
>
> publishable key는 공개되어도 되는 키입니다. 실제 데이터 보호는 3단계에서 켠 **RLS 정책**이 담당합니다.
> 반대로 `service_role` / `sb_secret_...` 키는 **절대** 이 파일에 넣지 마세요.

---

## 2단계 — 키 넣기

`index.html`을 메모장 등으로 열고, 파일 아래쪽 `SUPABASE 설정` 주석 부분을 찾아 채웁니다.

```js
window.SUPABASE_URL      = 'https://xxxxx.supabase.co';
window.SUPABASE_ANON_KEY = 'sb_publishable_...';   // 변수명은 anon 이지만 publishable key를 넣으면 됩니다
```

---

## 3단계 — Cloudflare에 올리기

### Git 연동 (권장)

GitHub에 push하면 Cloudflare가 알아서 배포합니다.

1. <https://dash.cloudflare.com> → **Workers & Pages** → `vacation-planner` 선택
2. **Settings** → **Builds** → **Connect**
3. GitHub 계정 인증 → `masimelo/vacation-planner` 레포 선택
4. 빌드 설정 (정적 파일이라 빌드 과정이 없습니다)

| 항목 | 값 |
|---|---|
| Build command | *(비워둠)* |
| Deploy command | `npx wrangler deploy` |
| Root directory | `/` |

이후로는 `git push` 하면 자동 배포됩니다.

> ⚠️ `wrangler.jsonc`의 `name`이 대시보드의 Worker 이름과 **다르면 빌드가 실패합니다.**
> Worker 이름을 바꿨다면 이 파일도 같이 고치세요.

### 직접 업로드 (Git 없이)

**`public` 폴더만** 올리면 됩니다. 나머지 파일은 서빙 대상이 아닙니다.

> ⚠️ Cloudflare **Pages**를 직접 업로드로 만들면 나중에 Git 연동으로 **전환할 수 없습니다**
> (새 프로젝트를 만들어야 하고 주소가 바뀝니다). **Workers**는 전환이 됩니다.

---

## 4단계 — 로그인 주소 등록 ⚠️ 빠뜨리기 쉬움

Supabase가 아무 주소로나 로그인 링크를 보내지 않도록 허용 목록에 넣어야 합니다.

Supabase → **Authentication → URL Configuration**

| 항목 | 값 |
|---|---|
| Site URL | `https://vacation-planner.pages.dev` |
| Redirect URLs | `https://vacation-planner.pages.dev/**` |

이걸 안 하면 메일의 로그인 링크를 눌러도 되돌아오지 않습니다.

---

## 5단계 — 확인

1. 배포된 주소 접속 → 우측 상단 **☁️ 로그인** 클릭
2. 이메일 입력 → **로그인 링크 받기**
3. 메일함에서 링크 클릭 → 앱으로 돌아오며 버튼이 **☁️ 동기화됨** 으로 바뀜
4. 휴가를 하나 추가하고 **💾 저장**
5. Supabase → **Table Editor → planner_data** 에 행이 생겼는지 확인
6. 휴대폰에서 같은 주소 접속 → 같은 이메일로 로그인 → 데이터가 따라오면 성공

---

## 동작 방식

| 상황 | 동작 |
|---|---|
| 로그인 안 함 / 키 미설정 | 기존과 동일하게 `localStorage`에만 저장 |
| 로그인 직후 | 서버본과 로컬본의 `updated_at`을 비교해 **최신 쪽을 채택** |
| 저장 버튼 | 로컬 저장 즉시 + 1.5초 뒤 서버에 자동 업로드 (연타 방지) |
| 오프라인 | 로컬 저장은 계속 되고, 다음 저장 때 서버로 올라감 |
| 수동 제어 | ☁️ 버튼 → **서버에 저장 / 서버에서 불러오기** |

로컬이 항상 1차 저장소라, Supabase가 죽어도 앱은 멈추지 않습니다.

---

## 공동 편집 (여러 명이 한 플래너를)

데이터는 **계정**이 아니라 **플래너**에 붙어 있고, 플래너마다 멤버 목록이 있습니다.
멤버가 아니면 RLS가 조회 자체를 막습니다.

**초대하는 쪽**
1. ☁️ → **🔗 초대 링크 복사**
2. 나온 주소(`.../?join=코드`)를 상대에게 전달

**초대받는 쪽**
1. 링크 열기 → ☁️ → 이메일로 로그인
2. 로그인하면 자동으로 그 플래너에 참여됩니다 (링크의 코드는 로그인 왕복 중에도 보관됩니다)

**동시 편집**
저장할 때 마지막으로 읽은 시각을 같이 보냅니다. 그사이 남이 저장했다면 서버가 저장을 거부하고,
앱이 *덮어쓸지 / 취소할지*를 물어봅니다. 모르는 사이에 남의 작업이 사라지지 않습니다.
다른 창에서 돌아오면 서버가 더 최신인지 확인해서 알려줍니다 (자동으로 덮어쓰지는 않습니다).

**초대 링크 회수**
소유자는 ☁️ → **이전 링크 무효화**. 이미 참여한 사람은 그대로 남고, 기존 링크만 죽습니다.

> ⚠️ **남을 초대하려면 SMTP 설정이 반드시 필요합니다.**
> Supabase 기본 메일 서비스는 (1) 시간당 2통, (2) **프로젝트 팀 멤버로 등록된 주소로만** 발송됩니다.
> 그 외 주소로는 `Email address not authorized` 로 실패하므로, 기본 상태에서는 초대가 동작하지 않습니다.
> Authentication → Emails 에서 외부 SMTP(Resend, Brevo 등)를 연결하면 모든 주소로 보낼 수 있습니다.
> 연결 직후 한도는 시간당 30통이고, Authentication → Rate Limits 에서 조정합니다.

---

## 커스텀 도메인 (선택)

도메인이 있다면 Cloudflare Pages → 프로젝트 → **Custom domains → Set up a domain**.
HTTPS 인증서는 자동 발급됩니다. 도메인을 바꿨다면 **4단계의 URL 등록도 새 주소로 다시** 해주세요.

---

## 비용

| 항목 | 무료 한도 | 이 앱의 사용량 |
|---|---|---|
| Cloudflare Pages | 대역폭 무제한, 월 500회 배포 | 문제 없음 |
| Supabase Free | DB 500MB, 월 활성사용자 50,000명 | 1인 사용 시 0.001% 수준 |

개인 사용 기준으로 계속 무료입니다.
단, Supabase 무료 프로젝트는 **7일간 접속이 없으면 일시정지**되니 (대시보드에서 즉시 재개 가능),
가끔 접속하거나 유료 플랜을 쓰세요.

---

## 문제 해결

**로그인 메일이 안 옴**
먼저 **받는 주소가 내 것인지 남의 것인지**를 보세요.

- **남의 주소** → 기본 메일 서비스는 팀 멤버 외에는 발송을 거부합니다. SMTP를 연결해야 합니다
- **내 주소인데 안 옴** → 스팸함 확인. 기본 서비스는 시간당 2통이라, 연달아 시도했다면 한도에 걸린 것입니다

Authentication → Emails 에서 SMTP(예: Resend)를 연결하면 둘 다 해결됩니다.

**링크를 눌렀는데 로그인이 안 됨**
4단계 Redirect URLs 등록을 확인하세요. 주소 끝에 `/**` 가 있어야 합니다.

**`new row violates row-level security policy` 오류**
`supabase-schema.sql`이 끝까지 실행되지 않았습니다. SQL Editor에서 다시 Run 하세요.

**데이터가 안 올라감**
브라우저 개발자도구(F12) → Console 탭의 빨간 오류 메시지를 확인하세요.
`Invalid API key` 면 2단계 키를 잘못 붙여넣은 것입니다.
