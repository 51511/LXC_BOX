# lxcbox 🚀

> **⚠️ 實驗性專案 — 正在努力不炸機中**

**下一代™ 革命性© 顛覆性® 容器桌面解決方案**
（其實就是一堆 shell script）

![Picture1](https://i.meee.com.tw/qxZd5Rx.png)
![Picture2](https://i.meee.com.tw/rmKAY4O.png)
![Picture3](https://i.meee.com.tw/y0wFIAj.png)
在2026/03/25，Wayland支援成功開發

---

## 這是什麼？

你有沒有想過：

> 「Distrobox 很好用，但我想要更底層、更快的版本？」

沒有？沒關係，我幫你想了。

**lxcbox** 是一個 Distrobox 風格的容器管理工具，但底層用 **LXC** 而不是 Podman/Docker。

```
Distrobox:  你的程式 → Podman → OCI → runc → kernel
lxcbox:     你的程式 → LXC → kernel
                              ↑
                         少了幾層廢話
```

---

## 架構（聽起來很厲害）

```
Void Linux Host（極簡、無 systemd、runit）
└── LXC Container（Debian bookworm）
    └── 你的程式（以為自己在 Debian 上）
        └── 其實顯示在 Void 的桌面上
            └── 用戶毫無察覺
                └── 這就是魔法
```

**Host 上只跑：**
- Linux kernel
- runit（init）
- LXC daemon
- Wayland / X11 compositor
- PipeWire（音效）
- GPU driver

---

## 為什麼不用 Distrobox？

| 功能 | Distrobox | lxcbox |
|------|-----------|--------|
| 底層 | Podman（OCI）| LXC（直接）|
| 層數 | 多到數不清 | 少 |
| 文件 | 豐富 | 你在看的這個 |
| 穩定性 | 高 | 誰知道？ |
| systemd | 可能有 | 沒有|
| 踩坑機率 | 低 | 很高（目前）|

---

## 為什麼不用 IncusOS？

因為 IncusOS 被 systemd 工具鏈綁死，只能用 Debian 當 Host，而且主要針對伺服器。

我們針對桌面。然後我們選了 Void Linux。然後踩了很多坑。然後寫了這個 README。

---

## 安裝

```sh
# 1. 先裝 Void Linux（這步驟不在本 README 範圍內，祝你好運）

# 2. 裝依賴
sudo xbps-install -S lxc debootstrap xhost

# 3. 設定 Host
sudo sh void-host-setup.sh

# 4. 建立第一個 container
lxcbox create --name mybox

# 5. 進去
lxcbox enter mybox

# 6. 裝你要的東西
apt install -y firefox-esr

# 7. 匯出到 Host
lxcbox-export --bin /usr/bin/firefox-esr

# 8. 在 Host 跑
xhost +local:
firefox-esr

# 9. 驚訝地發現它真的跑起來了
```
(Wayland只要進去Wayland資料夾做一樣的事)

---

## 已知問題（aka 特色功能）

- `sudo: unable to resolve host testbox` — 這是正常的，無視它
- 第一次跑 lxcbox 可能需要喝杯咖啡等 debootstrap
- Alpine Linux 不支援（musl + LXC 6.0 = segfault，我們學到了）
- 如果炸了請重新閱讀本 README
- 只支援Void Linux
- Wayland下apt可能會炸，如下
```
sh: 1: Syntax error: "fi" unexpected
E: Problem executing scripts DPkg::Pre-Invoke '\ || true; fi'
```
修復指令
```
sudo tee /etc/apt/apt.conf.d/01lxcbox-snapshot > /dev/null <<'EOF'
DPkg::Pre-Invoke {
    "sh -c 'if [ -x /usr/bin/lxcbox-host-exec ]; then /usr/bin/lxcbox-host-exec lxcbox-snapshot --auto || true; fi'";
};
EOF
```

---

## 跟其他方案比較

```
Docker Desktop:   要錢，要帳號，要靈魂
Podman:           好用，但多一層
Distrobox:        好用，但底層是 Podman
Flatpak:          沙盒很好，但 dependency 地獄換了個形式
Snap:             不要
IncusOS:          伺服器用，systemd，不是我們
lxcbox:           實驗性，可能炸，但架構乾淨
                  而且是我們自己做的所以感情分加很多
```

---

## 路線圖

- [x] CLI 能跑
- [x] GUI 能跑（X11）
- [x] Firefox 能跑
- [x] Wayland 完整支援
- [ ] 自動 snapshot（更新前自動備份）
- [ ] 多 container 管理
- [ ] `.desktop` export 完整支援
- [ ] 寫更多測試（或者至少假裝有測試）
- [ ] 說服別人這不是玩具
- [ ] 世界和平

---

## 技術棧

- **Shell**: POSIX sh（因為我們不需要 Python 來寫 shell script）
- **容器**: LXC 6.0
- **Host OS**: Void Linux（glibc 版，musl 版會 segfault，我們試過了）
- **Container OS**: Debian bookworm
- **GUI**: X11 / Wayland socket passthrough
- **音效**: PipeWire socket passthrough

---

## 為什麼選 Void Linux？

1. 沒有 systemd ✅
2. glibc（LXC 需要）✅
3. runit（超輕）✅
4. rolling release 但穩定 ✅
5. 名字聽起來很酷 ✅
6. Alpine 的 musl 讓 LXC segfault 所以被迫換過來 ✅

---

## 靈感來源

- **Distrobox** — 我們的精神來源，只是我們覺得 Podman 太重了
- **IncusOS** — 驗證了「極簡 Host + container 跑一切」這個概念可行
- **一個很長的 Claude 對話** — 從 Unix 歷史聊到 AT&T 訴訟再到寫出這個東西

---

## 貢獻

歡迎 PR。不保證會 merge。但歡迎。

如果你在生產環境用這個，請告訴我，因為我想知道是誰這麼勇敢。

---

## 授權

GNU GPL v3 


---


## 最後

> 「這不是 bug，這是還沒寫完的 feature。」
> — lxcbox 開發者(Leaf)，2026

**⚠️ 實驗性專案。在生產環境使用前請先備份。或者不要在生產環境用。或者用了也不要告訴我。**
