# lastmessage

Claude Code'da son mesajinizi durum cubuguna sabitleyin. Yanitlar akarken ne sordugunuzu bir daha unutmayin.


## Ne yapar?

Claude Code'da mesaj gonderdiginizde, mesajiniz durum cubugunda turuncu renkte sabitlenir (istatistik satirinin ustunde). Her terminal oturumu kendi mesajini bagimsiz olarak takip eder - 8 terminal acin, her birinde o terminale yazdiginiz son mesaj gorunur.

## Nasil calisir?

1. **`UserPromptSubmit` hook** Enter'a bastiginizda mesajinizi yakalar
2. Oturuma ozel dosyaya yazar (`~/.claude/last-prompt-{pid}.txt`)
3. **StatusLine** okuyup istatistiklerin ustunde gosterir

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
