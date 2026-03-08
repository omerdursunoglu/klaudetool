# lastmessage

Claude Code'da son mesajinizi durum cubuguna sabitleyin, kota ve hiz limitlerini canli takip edin.


## Ozellikler

### 1. Son mesaj sabitleme

Claude Code'da mesaj gonderdiginizde, yanitlar akarken ne sordugunuzu unutmaniz cok kolay. Bu ozellik son mesajinizi durum cubugunun ustunde turuncu renkte sabitler.

**Nasil calisir:**

- `UserPromptSubmit` hook'u Enter'a bastiginiz anda devreye girer
- Mesajinizi oturuma ozel bir dosyaya yazar (`~/.claude/last-prompt-{pid}.txt`)
- Her terminal oturumu kendi PID'ine gore ayri dosya kullanir, boylece 8 terminal acarsaniz her birinde o terminale yazdiginiz son mesaj gorunur
- StatusLine bu dosyayi okuyup istatistik satirinin ustunde gosterir
- Mesaj terminal genisligine sigmiyorsa otomatik olarak kirpilir ve sonuna `...` eklenir

```
readme'yi de bu iki özelliğini detaylıca anlatarak güncelle   <- turuncu, sabitlenmis mesaj
Opus 4.6 | 11% | 5h 14% 1h21m | 7d 17% 5d12h | 2k/200k | $0.21 | 8d
```

### 2. Gelismis istatistik cubugu

StatusLine, Claude Code oturumunuza ait tum kritik bilgileri tek satirda gosterir:

| Bilgi | Ornek | Aciklama |
|-------|-------|----------|
| Model | `Opus 4.6` | Kullanilan Claude modeli |
| Context | `11%` | Context window doluluk orani |
| 5 saatlik limit | `5h 14% 1h21m` | 5 saatlik hiz limiti kullanimi ve sifirlama suresi |
| 7 gunluk limit | `7d 17% 5d12h` | 7 gunluk hiz limiti kullanimi ve sifirlama suresi |
| Token | `2k/200k` | Kullanilan / toplam context window boyutu |
| Maliyet | `$0.21` | Bu oturumdaki toplam API maliyeti |
| Abonelik | `8d` | Abonelik yenilenme tarihine kalan gun |

**Renk kodlari:**

Tum yuzde degerleri duruma gore renklendirilir:
- **Yesil**: Dusuk kullanim (<%50) - rahat bolgede
- **Sari**: Orta kullanim (%50-80) - dikkatli olun
- **Kirmizi**: Yuksek kullanim (>%80) - limite yaklasiyorsunuz

Abonelik yenilenme suresi icin:
- **Yesil**: 10+ gun
- **Sari**: 5-10 gun
- **Turuncu**: 3-5 gun
- **Kirmizi**: 3 gunden az

**Hiz limiti takibi:**

- macOS Keychain'den OAuth token'i otomatik olarak okunur
- Anthropic API'ye hafif bir istek atilarak rate limit header'lari alinir
- Sonuclar `~/.claude/ratelimit_cache.json` dosyasinda onbellekelenir
- Onbellek her 5 dakikada bir yenilenir, gereksiz API cagrisi yapilmaz

**Abonelik takibi:**

- `~/.claude/subscription.json` dosyasindan yenilenme gunu okunur
- Bir sonraki yenilenme tarihine kalan gun hesaplanir
- Ay sonu tasmalarini (ornegin 31. gun) otomatik yonetir

**Otomatik uyum (auto-fit):**

Terminal genisligi ne olursa olsun en fazla bilgiyi gosterir. 4 detay seviyesi vardir:

```
Tam:     Opus 4.6 | 11% | 5h 14% 1h21m | 7d 17% 5d12h | 2k/200k | $0.21 | 8d
Orta:    Opus 4.6 | 11% | 5h 14% | 7d 17%
Kompakt: Opus 4.6 5h:14% 7d:17% 11%
Minimal: 5h:14% 7d:17% 11%
```

En detayli format denenir; sigmiyorsa bir alt seviyeye gecer. Terminal genisligi `stty`, `COLUMNS`, `os.get_terminal_size()` ve `tput cols` yontemleriyle sirayla denenerek tespit edilir.


## Kurulum

```bash
git clone https://github.com/dijitalbaslangic/lastmessage.git
cd lastmessage
bash install.sh
```

Ardindan Claude Code'u yeniden baslatin.

## Kaldirma

```bash
cd lastmessage
bash uninstall.sh
```

Bu komut sadece su islemleri yapar:
- `~/.claude/hooks/pin-last-message.sh` dosyasini siler
- `~/.claude/last-prompt-*.txt` gecici dosyalarini siler
- `settings.json` icinden `UserPromptSubmit` hook'unu kaldirir
- Statusline yedegi varsa geri yukler (`statusline.sh.bak`)

## Manuel kurulum

Kendiniz kurmak isterseniz:

### 1. Hook'u kopyalayin

```bash
mkdir -p ~/.claude/hooks
cp hooks/pin-last-message.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/pin-last-message.sh
```

### 2. Hook'u ayarlara ekleyin

`~/.claude/settings.json` icindeki `"hooks"` objesine ekleyin:

```json
"UserPromptSubmit": [
  {
    "hooks": [
      {
        "type": "command",
        "command": "python3 ~/.claude/hooks/pin-last-message.sh",
        "timeout": 3
      }
    ]
  }
]
```

### 3. StatusLine (istege bagli)

Zaten bir statusline'iniz varsa, `statusline-patch.py` icindeki kodu son `print()` satirindan once ekleyin.

Statusline'iniz yoksa, hazir olani kopyalayin:

```bash
cp statusline.sh ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh
```

Ve `~/.claude/settings.json` dosyasina ekleyin:

```json
"statusLine": {
  "type": "command",
  "command": "~/.claude/statusline.sh",
  "padding": 0
}
```

## Gereksinimler

- Claude Code CLI
- Python 3
- macOS (hiz limiti takibi icin Keychain gerekli; pin ozelligi tum isletim sistemlerinde calisir)

## Lisans

MIT
