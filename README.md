doubanfm.sh is a bash implemented [douban.fm](http://douban.fm) client.
![screenshot](http://qiuxiang.qiniudn.com/doubanfm.sh.png?5295)

```
Usage: doubanfm [-c channel_id | -k kbps]

Options:
  -c channel_id    select channel
  -k kbps          set kbps, available values is 64, 128, 192
  -l               print channels list
  -i               sign in
  -o               sign out
```

Dependencies:
- `mpg123` or `mplayer` (audio player)
- `jq` (JSON parser)
- `curl` (HTTP request)
