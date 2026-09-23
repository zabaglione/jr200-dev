# Upstream provenance

- Repository: `https://github.com/zabaglione/jr100dev`
- Revision: `9a3921c4371d84c55fc468879dbed2f00fe42960`
- Source project: `games/relic_dive`
- Upstream game version: `1.6.1`
- License: MIT (`LICENSE`をこのdirectoryに完全収録)
- Copyright: `Copyright (c) 2026 JR-800 Web Emulator contributors`

## Imported source hashes

| upstream path | SHA-256 |
| --- | --- |
| `src/assets.asm` | `bf4c882419a5474957f8670925338b2a0ae64dfcdb8f37cca9cb2783a169b9c1` |
| `src/constants.inc` | `eed1ce9b0ce0bee3d83933ba53abeaae956b54a546d39dda32ca1a939ea34734` |
| `src/dungeon.asm` | `64d5dcbc073a64dedc4f78c7786697bc5f5367fb313d6dd7bb4bfdbff30fe479` |
| `src/extras.asm` | `f79bbcffe13b5f6d941c481388fca79a8e9d84e21b75a20bd780f91dc1ed40e6` |
| `src/items.asm` | `1ad8b45a0306009bf6642e18086b7defd5a0c0ee49927f1bba70c70debefd70c` |
| `src/main.asm` | `38e69538557effd2aa91e3f7e0d06028952f4eb99a496cace9f6d3bc0e53a2e7` |
| `src/map.asm` | `d27243bf452cf4818fdff12b6cfea7a1db30dce4ba6cdf96a386f7d6bbc5c867` |
| `src/platform.asm` | `178ecbe5db7001c5827ea995260a92c58282dbfe33003e725f99256317c45b61` |
| `src/sight_rays.inc` | `153c9661ac1d87b7952c76a9038e4492a47b8efdabc8236704c50f27e4b93ba6` |
| `src/terrain.asm` | `2b203bf4a1aaafe09fdb1ddd149428780797b66c430c8cb0c3ae6d30a9f8bc59` |
| `src/turns.asm` | `8f7f5de855f1315a86b4f9f59bc6c003d781612c63bd5a27cf2b06030327d822` |
| `src/ui.asm` | `3cacd51a95ca78dee491b4fb77761f6f5f00998044bda183e895d1bab1c4632f` |
| generated `build/game.asm` | `6daf54eebe1f0c04e499b6927e66f294f858b381c49671d4fc3c7b7163d7684b` |
| `LICENSE` | `057589caa530c3b20e5b988e8cfa6445ac3a8f0c8474584326afce89550ec070` |

## Port transformations

- JR-100の低位RAM、framebuffer、PCG、keyboard matrix、VIA soundをJR-200用配置へ変更
- MB8861H固有の`ADX`をM6800命令だけのmacroへ置換
- 文字codeはJR-200 ASCII、PCGはbank 1 (`0xC400`)、属性は`0xC500`から使用
- Key-On eventによるキーボード入力とJR-200 sound channel Cへ変更
- JR-200属性RAMで配色を追加。ゲーム規則、乱数、マップ、敵、アイテムは変更しない

`generated.inc` は上流build済みassemblyの圧縮文字列とタイトルデータ部分だけを抽出しています。
上流のメーカーROM、FONT、商用テープ、録音は取り込んでいません。
