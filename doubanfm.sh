#!/usr/bin/env bash

PATH_BASE=$HOME/.doubanfm.sh
PATH_COOKIES=$PATH_BASE/cookies.txt
PATH_PLAYER_PID=$PATH_BASE/player.pid
PATH_ALBUM_COVER=$PATH_BASE/albumcover
PATH_CONFIG=$PATH_BASE/config.json
PATH_PLAYLIST=$PATH_BASE/playlist.json
PATH_PLAYLIST_INDEX=$PATH_BASE/index
PATH_CHANNELS=$PATH_BASE/channels.json

PLAYER_PLAYING=0
PLAYER_STOPED=1
SONG_DISLIKE=0
SONG_LIKED=1

CURL="curl -s -c $PATH_COOKIES -b $PATH_COOKIES"
DEFAULT_CONFIG='{ "kbps": 192, "channel": 0 }'
CHANNEL_FAVORITE=-3
UNAME=$(uname)

command -v mpg123 > /dev/null && PLAYER=mpg123
command -v mplayer > /dev/null && PLAYER=mplayer
test -z "$PLAYER" && echo "mpg123 or mplayer required" && exit 1

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
  PARAMS_KBPS=$(config kbps)
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

load_user_info() {
  USER_NAME=$(config user.name)
  USER_EMAIL=$(config user.email)
  USER_ID=$(config user.id)
  USER_TOKEN=$(config user.token)
  USER_EXPIRE=$(config user.expire)
}

save_user_info() {
  config user {}
  config user.id $USER_ID
  config user.name \"$USER_NAME\"
  config user.email \"$USER_EMAIL\"
  config user.token \"$USER_TOKEN\"
  config user.expire $USER_EXPIRE
}

already_sign_in() {
  [ -n "$USER_ID" ] && [ $USER_ID != "null" ] && [ $USER_ID != "[]" ]
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
  local params="kbps=$PARAMS_KBPS&channel=$PARAMS_CHANNEL"
  params+="&app_name=$PARAMS_APP_NAME&version=$PARAMS_VERSION"
  params+="&type=$PARAMS_TYPE&sid=$(song sid)"
  already_sign_in && params+="&user_id=$USER_ID&token=$USER_TOKEN&expire=$USER_EXPIRE"
  echo $params
}

#
# param: operation type
# return: playlist json
#
request_playlist() {
  PARAMS_TYPE=$1
  $CURL http://douban.fm/j/app/radio/people?$(build_params) | jq .song
}

get_playlist_length() {
  jq length < $PATH_PLAYLIST
}

# param: operation type
update_playlist() {
  local playlist=$(request_playlist $1)
  echo $playlist > $PATH_PLAYLIST
  [ $(get_playlist_length) = 0 ] && printf "\n  $(red Error: playlist is empty.)" && quit
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

#
# param: rating [0, 5]
# return: ★★★☆☆ 3.2
#
stars() {
  local n=$(echo $1 | awk '{print int($1+0.5)}')
  local s=""
  for (( i = 0; i < 5; i++ )) do
    if [ $i -lt $n ]; then
      s+="★"
    else
      s+="☆"
    fi
  done
  echo $s $1
}

print_song_info() {
  local length=$(song length)
  local time=$(printf "%d:%02d" $(( length / 60)) $(( length % 60)))
  echo
  echo "  $(yellow $(song artist)) - $(green $(song title)) ($time)"
  echo "  $(cyan \<$(song albumtitle)\> $(song public_time))"
  echo "  $(stars $(song rating_avg)) $(heart $(song like))"
}

notify_song_info() {
  local title="$(song title) $(heart $(song like))"
  local artist_album="$(song artist)《$(song albumtitle)》"
  local stars="$(stars $(song rating_avg))"

  case $UNAME in
    Linux)
      notify-send "$title" "$artist_album\n$stars" -i "$(song picture_path)" ;;
    Darwin)
      terminal-notifier -title "$title" -subtitle "$artist_album" \
        -message "$stars" -appIcon "$(song picture_path)" -group "$0" ;;
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
      pkill -19 -P $(get_player_pid)
      PLAYER_STATE=$PLAYER_STOPED
      printf "\n  Paused\n" ;;
    $PLAYER_STOPED)
      pkill -18 -P $(get_player_pid)
      PLAYER_STATE=$PLAYER_PLAYING
      printf "\n  Playing\n" ;;
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
  if [ $(song like) = $SONG_DISLIKE ]; then
    local like=$SONG_LIKED
    local opration_type=r
    local message=Liked
  else
    local like=$SONG_DISLIKE
    local opration_type=u
    local message=Dislike
  fi

  local song=$(jq ".[$(playlist_index)] | .like=$like" < $PATH_PLAYLIST)
  update_playlist $opration_type
  local playlist=$(jq ". + [$song] | reverse" < $PATH_PLAYLIST)
  echo $playlist > $PATH_PLAYLIST
  printf "\n  $message\n"
}

song_remove() {
  update_and_play b
}

print_playlist() {
  local current_index=$(playlist_index)
  local playlist_length=$(get_playlist_length)
  echo
  for (( i = 0; i < playlist_length; i++ )) do
    if [ $i = $current_index ]; then
      echo "♪ $(yellow $(song artist $i)) - $(green $(song title $i))"
    else
      echo "  $(yellow $(song artist $i)) - $(green $(song title $i))"
    fi
  done
}

#
# return: channels json
#
get_channels() {
  [ -f $PATH_CHANNELS ] || $CURL http://douban.fm/j/app/radio/channels | jq .channels > $PATH_CHANNELS
  cat $PATH_CHANNELS
}

print_channels() {
  local channels=$(get_channels)
  local channels_length=$(echo $channels | jq length)

  echo
  if [ $PARAMS_CHANNEL = $CHANNEL_FAVORITE ]; then
    echo "→ $(cyan 红心兆赫)($CHANNEL_FAVORITE)"
  else
    echo "  $(cyan 红心兆赫)($CHANNEL_FAVORITE)"
  fi

  for (( i = 0; i < channels_length; i++ )) do
    local channel_id=$(echo $channels | jq -r .[$i].channel_id)
    local name=$(echo $channels | jq -r .[$i].name)
    if [ $i = $PARAMS_CHANNEL ]; then
      echo "→ $(cyan $name)($channel_id)"
    else
      echo "  $(cyan $name)($channel_id)"
    fi
  done
}

quit() {
  pkill -P $(get_player_pid) > /dev/null 2>&1
  show_cursor
  echo
  exit
}

print_commands() {
  cat << EOF

  [$(cyan p)] pause
  [$(cyan b)] no longer play this song
  [$(cyan r)] like or dislike this song
  [$(cyan n)] play the next song
  [$(cyan i)] print and notify this song's info
  [$(cyan i)] open alubm page in browser
  [$(cyan q)] quit
EOF
}

sign_in() {
  if already_sign_in; then
    echo "You already sign in as $(cyan $USER_NAME \<$USER_EMAIL\>)"
  else
    show_cursor
    enable_echo
    read -p "Email: " email

    disable_echo
    hide_cursor
    read -p "Password: " password

    local data="email=$email&password=$password&"
    data+="app_name=$PARAMS_APP_NAME&version=$PARAMS_VERSION"
    local result=$($CURL -d $data http://www.douban.com/j/app/login)
    local message=$(echo $result | jq -r .err)
    if [ $message = "ok" ]; then
      USER_NAME=$(echo $result | jq -r .user_name)
      USER_EMAIL=$(echo $result | jq -r .email)
      USER_ID=$(echo $result | jq -r .user_id)
      USER_TOKEN=$(echo $result | jq -r .token)
      USER_EXPIRE=$(echo $result | jq -r .expire)
      save_user_info
      printf "\n\n$(green Sign in success as $USER_NAME \<$USER_EMAIL\>)\n"
    else
      printf "\n\n$(red Sign in failed with $message)\n"
    fi
  fi
}

sign_out() {
  USER_NAME=null
  USER_EMAIL=null
  USER_ID=null
  USER_TOKEN=null
  USER_EXPIRE=null
  config user {}
  echo Sign out
}

open_in_brower() {
  xdg-open $(song album_url) > /dev/null 2>&1
}

mainloop() {
  while true; do
    read -n 1 c
    case ${c:0:1} in
      i) print_song_info; notify_song_info ;;
      o) open_in_brower ;;
      p) pause ;;
      n) song_skip ;;
      N) play_next ;;
      r) song_rate ;;
      b) song_remove ;;
      c) print_channels ;;
      l) print_playlist ;;
      q) quit ;;
      h) print_commands ;;
    esac
  done
}

set_kbps() {
  if [[ $1 =~ 64|128|192 ]]; then
    PARAMS_KBPS=$1
    config kbps $1
  else
    printf "  $(red Note: Available kbps values is 64, 128, 192.)\n\n"
  fi
}

#
# param: channel id
#
set_channel() {
  if [[ $1 =~ ^-?[0-9]+$ ]]; then
    PARAMS_CHANNEL=$1
    config channel $1
  else
    printf "  $(red Note: Channel id must be a number.)\n\n"
  fi
}

print_help() {
  cat << EOF
Usage: $0 [-c channel_id | -k kbps]

Options:
  -c channel_id    select channel
  -k kbps          set kbps, available values is 64, 128, 192
  -l               print channels list
  -i               sign in
  -o               sign out
EOF
}

welcome() {
  if already_sign_in; then
    echo "  Welcome $(cyan $USER_NAME \<$USER_EMAIL\>)"
  else
    echo "  Welcome $(cyan guest)"
  fi

  if [ $PARAMS_CHANNEL = $CHANNEL_FAVORITE ]; then
    local channel_name=$(red 红心兆赫)
  else
    local channel_name=$(yellow $(get_channels | jq -r .[$PARAMS_CHANNEL].name))
  fi
  echo "  Current channel is $channel_name"
}

init_path
init_params
load_user_info

while getopts c:k:lioh opt; do
  case $opt in
    c) set_channel $OPTARG ;;
    k) set_kbps $OPTARG ;;
    l) print_channels; echo; exit ;;
    i) sign_in; exit ;;
    o) sign_out; exit ;;
    h) print_help; exit ;;
  esac
done

trap quit INT
disable_echo
hide_cursor
welcome
update_and_play n
mainloop
