这是一个 bash 实现的 [douban.fm](http://douban.fm) 客户端

![screenshot](http://qiuxiang.qiniudn.com/doubanfm.sh.png?5295)

```
用法：doubanfm [-c channel_id | -k kbps]

选项：
  -c channel_id    选择兆赫，用 -l 参数可以查看可用的兆赫
  -k kbps          设置码率，有效值为 64、128、192
  -l               显示频道列表
  -i               登录
  -o               注销
```

依赖：
- `mpg123` 或 `mplayer`（音频播放器）
- `jq`（JSON 解析）
- `curl`（HTTP 请求）
