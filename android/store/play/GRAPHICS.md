# Play store graphics pack

## Included
| File | Spec | Notes |
|------|------|--------|
| `feature-graphic.svg` | 1024×500 | Export PNG for Console |
| `CONTENT_RATING.md` | IARC answers | Fill questionnaire |
| `DATA_SAFETY.md` | Data safety | Form draft |
| `release-notes.txt` | <500 chars | Per-release whats-new |
| `BUILD_AAB.md` | AAB steps | Upload track |

## Export feature graphic
```bash
# Example with Inkscape / rsvg / any SVG→PNG
inkscape feature-graphic.svg -w 1024 -h 500 -o feature-graphic.png
```

## Phone screenshots (capture on device/emulator)
Minimum **2**, recommended **8**, PNG/JPEG, 16:9 or 9:16.

Suggested set (dark + light):
1. Today — hero card + timeline  
2. Brain — pending plan accept  
3. Focus — body double camera/presence  
4. Body double room — connected peers  
5. Medication  
6. Insights 7-day bars  
7. You — privacy & sync  
8. Onboarding welcome  

## Icon
Use adaptive icon from `res/mipmap` (or `@android:drawable/ic_menu_today` placeholder until brand pack lands).
Play requires 512×512 high-res icon.

## Hi-res icon checklist
- [ ] 512×512 PNG 32-bit  
- [ ] Feature graphic 1024×500 PNG  
- [ ] Phone screenshots  
- [ ] Optional 7" / 10" tablet screenshots  
