#!/usr/bin/env bash
#
# (c) 2015 Qiu Xiang <xiang.qiu@qq.com> under MIT licence
#

PATH_BASE=$HOME/.doubanfm.sh
PATH_COOKIES=$PATH_BASE/cookies.txt
PATH_PLAYER_PID=$PATH_BASE/player.pid
PATH_ALBUM_COVER=$PATH_BASE/albumcover
PATH_CONFIG=$PATH_BASE/config.json
PATH_PLAYLIST=$PATH_BASE/playlist.json
PATH_PLAYLIST_INDEX=$PATH_BASE/index
PATH_CHANNELS=$PATH_BASE/channels.json
PATH_CAPTCHA=$PATH_BASE/captcha.jpg

PLAYER_PLAYING=0
PLAYER_STOPPED=1
SONG_DISLIKE=0
SONG_LIKED=1

HOST=https://douban.fm
CURL="curl -L -s -c $PATH_COOKIES -b $PATH_COOKIES"
DEFAULT_CONFIG='{ "channel": 0 }'
CHANNEL_FAVORITE=-3

command -v mplayer > /dev/null && PLAYER=mplayer
test -z "$PLAYER" && echo "mplayer required" && exit 1

#
# get or set config
#
config() {
  if [ -z $2 ]; then
    jq -r ".$1" < $PATH_CONFIG
  else
    local config=$(jq ".$1=$2" < $PATH_CONFIG)
    echo $config > $PATH_CONFIG
  fi
}

init_path() {
  [ -d $PATH_BASE ] || mkdir $PATH_BASE
  [ -d $PATH_ALBUM_COVER ] || mkdir $PATH_ALBUM_COVER
  [ -f $PATH_CONFIG ] || echo $DEFAULT_CONFIG > $PATH_CONFIG
  [ -f $PATH_PLAYLIST ] || echo [] > $PATH_PLAYLIST
  [ -f $PATH_PLAYLIST_INDEX ] || echo 0 > $PATH_PLAYLIST_INDEX
}

init_params() {
  PARAMS_APP_NAME=radio_desktop_win
  PARAMS_VERSION=100
  PARAMS_TYPE=n
  PARAMS_CHANNEL=$(config channel)
}

red() {
  echo -e "\033[0;31m$@\033[0m"
}

green() {
  echo -e "\033[0;32m$@\033[0m"
}

yellow() {
  echo -e "\033[0;33m$@\033[0m"
}

blue() {
  echo -e "\033[0;34m$@\033[0m"
}

magenta() {
  echo -e "\033[0;35m$@\033[0m"
}

cyan() {
  echo -e "\033[0;36m$@\033[0m"
}

#
# get or set playlist index
#
playlist_index() {
  if [ -z $1 ]; then
    cat $PATH_PLAYLIST_INDEX
  else
    echo $1 > $PATH_PLAYLIST_INDEX
  fi
}

hide_cursor() {
  printf "\e[?25l"
}

show_cursor() {
  printf "\e[?25h"
}

disable_echo() {
  stty -echo 2> /dev/null
}

enable_echo() {
  stty echo 2> /dev/null
}

load_user() {
  USER=$(config user)
}

#
# low level get song info
#
# param: playlist index
# param: key
# return: value
#
get_song_info() {
  jq -r .[$1].$2 < $PATH_PLAYLIST
}

#
# get song info
#
# param: key
# param: playlist index, default is current
# return: value
#
song() {
  [ -z $2 ] && local i=$(playlist_index)
  case $1 in
    album_url)
      echo http://music.douban.com$(get_song_info $i album) ;;
    picture_path)
      local picture_url=$(get_song_info $i picture)
      local picture_path=$PATH_ALBUM_COVER/${picture_url##*/}
      [ -f $picture_path ] || $CURL $picture_url > $picture_path
      echo $picture_path ;;
    *)
      get_song_info $i $1 ;;
  esac
}

#
# return: params string
#
build_params() {
  local params="from=mainsite&channel=$PARAMS_CHANNEL"
  params+="&type=$PARAMS_TYPE&sid=$(song sid)"
  echo $params
}

#
# param: operation type
# return: playlist json
#
request_playlist() {
  PARAMS_TYPE=$1
  $CURL $HOST/j/mine/playlist?$(build_params) | jq .song
}

get_playlist_length() {
  jq length < $PATH_PLAYLIST
}

# param: operation type
update_playlist() {
  local playlist=$(request_playlist $1)
  echo $playlist > $PATH_PLAYLIST
  [ $(get_playlist_length) = 0 ] && printf "\n  $(red '播放列表为空')\n" && quit
  playlist_index 0
}

#
# param: 0 or 1
# return: ♡ or ♥
#
heart() {
  if [ $1 = 1 ]; then
    printf "♥"
  else
    printf "♡"
  fi
}

print_song_info() {
  local length=$(song length)
  local time=$(printf "%d:%02d" $(( length / 60)) $(( length % 60)))
  echo "$(yellow $(song artist)) $(green $(song title)) ($time) $(heart $(song like))"
  echo "$(cyan $(song albumtitle), $(song public_time))"
  echo
}

notify_song_info() {
  local title="$(song title) $(heart $(song like))"
  local artist_album="$(song artist) 《$(song albumtitle)》"

  case $(uname) in
    Linux)
      notify-send "$title" "$artist_album" -i "$(song picture_path)" ;;
    Darwin)
      terminal-notifier -title "$title" -subtitle "$artist_album" \
        -message "" -contentImage "$(song picture_path)" ;;
  esac
}

play_next() {
  local index=$(( $(playlist_index) + 1))
  if [ $(get_playlist_length) = $index ]; then
    update_playlist p
  else
    playlist_index $index
  fi

  play 2> /dev/null
}

get_player_pid() {
  cat $PATH_PLAYER_PID 2> /dev/null
}

play() {
  fetch_song_info
  print_song_info
  notify_song_info
  [ -f $PATH_PLAYER_PID ] && pkill -P $(get_player_pid)
  $PLAYER $(song url) &> /dev/null && request_playlist e > /dev/null && play_next &
  echo $! > $PATH_PLAYER_PID
  PLAYER_STATE=$PLAYER_PLAYING
}

#
# param: operation type
#
update_and_play() {
  update_playlist $1
  play 2> /dev/null
}

pause() {
  case $PLAYER_STATE in
    $PLAYER_PLAYING)
      pkill -18 -P $(get_player_pid)
      PLAYER_STATE=$PLAYER_STOPPED ;;
    $PLAYER_STOPPED)
      pkill -19 -P $(get_player_pid)
      PLAYER_STATE=$PLAYER_PLAYING ;;
  esac
}

song_skip() {
  if [ $PARAMS_CHANNEL = $CHANNEL_FAVORITE ]; then
    play_next
  else
    update_and_play s
  fi
}

song_rate() {
  local like=$SONG_DISLIKE
  local action_type=u
  local message="不再喜欢"

  if [ $(song like) = $SONG_DISLIKE ]; then
    local like=$SONG_LIKED
    local action_type=r
    local message="喜欢这首歌"
  fi

  local song=$(jq ".[$(playlist_index)] | .like=$like" < $PATH_PLAYLIST)
  update_playlist $action_type
  local playlist=$(jq ". + [$song] | reverse" < $PATH_PLAYLIST)
  echo $playlist > $PATH_PLAYLIST
  printf "$message\n\n"
}

song_remove() {
  printf "不再播放这首歌\n\n"
  update_and_play b
}

quit() {
  pkill -P $(get_player_pid) > /dev/null 2>&1
  show_cursor
  exit
}

print_commands() {
  cat << EOF
[$(cyan p)] 暂停或恢复播放
[$(cyan b)] 不再播放这首歌
[$(cyan r)] 喜欢这首歌或不再喜欢
[$(cyan n)] 下一首
[$(cyan i)] 显示当前歌曲信息
[$(cyan o)] 在浏览器中打开专辑页面
[$(cyan q)] 退出

EOF
}

sign_in() {
  if [ $USER != "null" ]; then
    printf "你已经登录，$USER\n"
  else
    local captcha_id=$(expr $($CURL $HOST/j/new_captcha) : '"\(.*\)"')
    $CURL "$HOST/misc/captcha?id=$captcha_id" > $PATH_CAPTCHA
    open $PATH_CAPTCHA

    enable_echo
    show_cursor
    read -p "邮箱：" email

    disable_echo
    hide_cursor
    read -p "密码：" password

    enable_echo
    show_cursor
    echo
    read -p "验证码：" captcha

    local data="source=radio&alias=$email&form_password=$password&"
    data+="captcha_solution=$captcha&captcha_id=$captcha_id&remember=on&task=sync_channel_list"
    local result=$($CURL -d $data $HOST/j/login)
    local message=$(echo $result | jq -r .err_msg)
    if [ $message = "null" ]; then
      USER=$(echo $result | jq -r .user_info.name)
      config user \"$USER\"
      printf "\n欢迎，$USER\n"
    else
      printf "\n$(red $message)\n"
    fi
  fi
}

sign_out() {
  config user ""
  printf "已注销\n\n"
}

open_in_browser() {
  open $(song album_url) > /dev/null 2>&1
}

mainloop() {
  while true; do
    read -n 1 c
    case ${c:0:1} in
      i) print_song_info; notify_song_info ;;
      o) open_in_browser ;;
      p) pause ;;
      n) song_skip ;;
      N) play_next ;;
      r) song_rate ;;
      b) song_remove ;;
      q) quit ;;
      h) print_commands ;;
    esac
  done
}

#
# param: channel id
#
set_channel() {
  if [[ $1 =~ ^-?[0-9]+$ ]]; then
    PARAMS_CHANNEL=$1
    config channel $1
  else
    printf "$(red channel_id '应该是数字')\n\n"
  fi
}

print_help() {
  cat << EOF
  用法：doubanfm [-c channel_id]

  选项：
    -c channel_id

EOF
}

welcome() {
  if [ $USER != "null" ]; then
    printf "欢迎，$USER\n\n"
  else
    echo
  fi
}

init_path
init_params
load_user

while getopts c:ih opt; do
  case $opt in
    c) set_channel $OPTARG ;;
    i) sign_in; exit ;;
    h) print_help; exit ;;
  esac
done

trap quit INT
disable_echo
hide_cursor
welcome
update_and_play n
mainloop
