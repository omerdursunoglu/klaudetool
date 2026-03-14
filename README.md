# klaudetool

Claude Code icin CLI statusline ve macOS menu bar uygulamasi. Son mesaj sabitleme, kota/hiz limiti takibi, kullanim grafikleri ve bildirim sesleri.

## Bilesenler

### 1. CLI StatusLine (`cli/`)

Terminal icinde Claude Code durum cubuguna eklenen gelismis istatistik satiri.

**Ozellikler:**

- **Son mesaj sabitleme**: Gonderdiginiz son mesaj turuncu renkte durum cubugunun ustunde sabitlenir
- **Model bilgisi**: Kullanilan Claude modeli (Opus 4.6, Sonnet vb.)
- **Context window**: Doluluk orani renkli gosterge
- **5 saatlik hiz limiti**: Kullanim yuzdesi + sifirlanma suresi
- **7 gunluk hiz limiti**: Kullanim yuzdesi + sifirlanma suresi
- **Token sayaci**: Kullanilan / toplam context window
- **Oturum maliyeti**: Guncel oturum + toplam donem maliyeti
- **Abonelik suresi**: Yenilenmeye kalan gun

```
readme'yi guncelle                                                <- turuncu, sabitlenmis mesaj
Opus 4.6 | 11% | 5h 14% 1h21m | 7d 17% 5d12h | 2k/200k | $0.21 | 8d
```

**Renk kodlari:**
- Yesil: <%50 kullanim
- Sari: %50-80 kullanim
- Kirmizi: >%80 kullanim

### 2. macOS Menu Bar App (`app/`)

Menu bar'da rate limit grafiklerini gosteren ve bildirim sesleri calan SwiftUI uygulamasi.

**Ozellikler:**

- **Rate limit grafikleri**: 5 saatlik ve 7 gunluk kullanim gecmisini gorsel olarak gosterir
- **Menu bar ikonu**: 5h/7d kullanim cubugu dogrudan menu bar'da gorunur
- **Zaman araligi secimi**: 1h, 6h, 1d, 7d, 30d grafik gorunumleri
- **Bildirim sesleri**: Claude soru sordugunda veya gorevi tamamladiginda ses calar
- **Otomatik kabul tespiti**: Auto-accept edilen islemler icin ses calmaz
- **Claude durumu**: Idle / Working / Waiting for Input durumunu gosterir
- **Login'de baslatma**: SMAppService ile otomatik baslama destegi

## Paylasilan Veri

Her iki bilesen de `~/.claude/ratelimit_cache.json` dosyasini kullanir:
- CLI statusline proxy ile API rate limit header'larini yakalar ve cache'e yazar
- Menu bar app cache'i okuyarak grafikleri gunceller

## Kurulum

```bash
git clone https://github.com/omerdursunoglu/klaudetool.git
cd klaudetool
bash install.sh
```

Installer su islemleri yapar:
1. Hook dosyasini (`pin-last-message.py`) ve proxy'yi (`ratelimit-proxy.py`) `~/.claude/hooks/`'a kopyalar
2. `settings.json`'a `UserPromptSubmit` hook'unu ekler
3. StatusLine kurulumunu yapar (yeni kurulum veya mevcut statusline'a yama)
4. (Opsiyonel) KlaudeTool.app'i derleyip `~/Applications/`'a kurar

Ardindan Claude Code'u yeniden baslatin.

## Kaldirma

```bash
cd klaudetool
bash uninstall.sh
```

Kaldirilan dosyalar:
- `~/.claude/hooks/pin-last-message.py`
- `~/.claude/hooks/ratelimit-proxy.py`
- `~/.claude/last-prompt-*.txt`
- `~/.claude/ratelimit_cache.json`, `proxy_debug.json`, `total_cost.json`, `klaudetool_history.json`
- `settings.json` icinden `UserPromptSubmit` hook'u
- Statusline yedegi varsa geri yuklenir
- (Opsiyonel) `~/Applications/KlaudeTool.app`

## Manuel Kurulum

### CLI

```bash
mkdir -p ~/.claude/hooks
cp cli/hooks/pin-last-message.py ~/.claude/hooks/
cp cli/ratelimit-proxy.py ~/.claude/hooks/
cp cli/statusline.sh ~/.claude/statusline.sh
chmod +x ~/.claude/hooks/pin-last-message.py ~/.claude/statusline.sh
```

`~/.claude/settings.json` icine ekleyin:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "python3 ~/.claude/hooks/pin-last-message.py",
            "timeout": 3
          }
        ]
      }
    ]
  },
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh",
    "padding": 0
  }
}
```

### Menu Bar App

```bash
cd app
make bundle
cp -R KlaudeTool.app ~/Applications/
open ~/Applications/KlaudeTool.app
```

## Abonelik Yonetimi

Abonelik yenilenme gununu ayarlamak, degistirmek veya kaldirmak icin:

```bash
bash subscription.sh set 16    # Yenilenme gununu 16 olarak ayarla
bash subscription.sh status    # Mevcut durumu goster
bash subscription.sh remove    # Abonelik takibini kaldir
```

Aboneligi durdurduktan sonra tekrar baslattinizda `bash subscription.sh set <gun>` ile yeni yenilenme gununuzu ayarlayabilirsiniz.

## Gereksinimler

- Claude Code CLI
- Python 3
- macOS (hiz limiti takibi icin Keychain gerekli; pin ozelligi tum isletim sistemlerinde calisir)
- Swift 5.10+ (menu bar app icin)

## Lisans

MIT
