这是一个 bash 实现的 [douban.fm](http://douban.fm) 客户端

![screenshot](https://cloud.githubusercontent.com/assets/1709072/13595315/3d66140e-e545-11e5-94f0-bb63b8f1b7e8.png)

```
用法：doubanfm [-c channel_id]

选项：
  -c channel_id    选择电台频道
  -i               登录
  -o               注销
```

依赖：
- `mplayer`（音频播放器）
- `jq`（用于 JSON 解析）
- `curl`（用于 HTTP 请求）
