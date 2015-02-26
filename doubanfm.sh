#!/usr/bin/env bash

PATH_BASE=$HOME/.doubanfm.sh
PATH_COOKIES=$PATH_BASE/cookies.txt
PATH_PLAYER_PID=$PATH_BASE/player.pid
PATH_ALBUM_COVER=$PATH_BASE/albumcover
PATH_CONFIG=$PATH_BASE/config.json
PATH_PLAYLIST=$PATH_BASE/playlist.json
PATH_PLAYLIST_INDEX=$PATH_BASE/index

STATE_PLAYING=0
STATE_STOPED=1

BASE_URL=http://douban.fm/j/app
CURL="curl -s -c $PATH_COOKIES -b $PATH_COOKIES"
PLAYER=mpg123
DEFAULT_CONFIG='{
  "kbps": 192,
  "channel": 0
}'

# param: key
# return: value
get_config() {
  cat $PATH_CONFIG | jq -r .$1?
}

# param: key
# param: value
set_config() {
  # can't use pipeline, because input file can't as output file
  local config=$(cat $PATH_CONFIG | jq ".$1=$2")
  echo $config > $PATH_CONFIG
}

init_path() {
  [ -d $PATH_BASE ] || mkdir $PATH_BASE
  [ -d $PATH_ALBUM_COVER ] || mkdir $PATH_ALBUM_COVER
  [ -f $PATH_CONFIG ] || echo $DEFAULT_CONFIG > $PATH_CONFIG
  [ -f $PATH_PLAYLIST_INDEX ] || echo 0 > $PATH_PLAYLIST_INDEX
}

init_params() {
  PARAMS_APP_NAME=radio_desktop_win
  PARAMS_VERSION=100
  PARAMS_TYPE=n
  PARAMS_CHANNEL=$(get_config channel)
  PARAMS_KBPS=$(get_config kbps)
}

# wrap color red
red() {
  echo -e "\033[0;31m$@\033[0m"
}

# wrap color green
green() {
  echo -e "\033[0;32m$@\033[0m"
}

# wrap color yellow
yellow() {
  echo -e "\033[0;33m$@\033[0m"
}

# wrap color blue
blue() {
  echo -e "\033[0;34m$@\033[0m"
}

# wrap color magenta
magenta() {
  echo -e "\033[0;35m$@\033[0m"
}

# wrap color cyan
cyan() {
  echo -e "\033[0;36m$@\033[0m"
}

# return: playlist index
get_playlist_index() {
  cat $PATH_PLAYLIST_INDEX
}

# param: playlist index
set_playlist_index() {
  echo $1 > $PATH_PLAYLIST_INDEX
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

echo_error() {
  echo $(red "Error: $1.") >&2
}

load_user_info() {
  USER_NAME=$(get_config user.name)
  USER_EMAIL=$(get_config user.email)
  USER_ID=$(get_config user.id)
  USER_TOKEN=$(get_config user.token)
  USER_EXPIRE=$(get_config user.expire)
}

save_user_info() {
  set_config user {}
  set_config user.id $USER_ID
  set_config user.name \"$USER_NAME\"
  set_config user.email \"$USER_EMAIL\"
  set_config user.token \"$USER_TOKEN\"
  set_config user.expire $USER_EXPIRE
}

logged() {
  [ -n "$USER_ID" ] && [ $USER_ID != "null" ] && [ $USER_ID != "[]" ]
}

# param: playlist index
# param: key
# return: value
get_song_info() {
  load_playlist | jq -r .[$1].$2
}

# get song info
#
# param: key
# param: playlist index, default is current
# return: value
song() {
  [ -z $2 ] && local i=$(get_playlist_index)
  case $1 in
    album_url)
      echo http://music.douban.com$(get_song_info $i album) ;;
    picture_path)
      local picture_url=$(get_song_info $i picture_url)
      local picture_path=$PATH_ALBUM_COVER/${picture_url##*/}
      [ -f $picture_path ] || $CURL $picture_url > $picture_path
      echo $picture_path ;;
    *)
      get_song_info $i $1 ;;
  esac
}

# return: params string
build_params() {
  local params="kbps=$PARAMS_KBPS&channel=$PARAMS_CHANNEL"
  params+="&app_name=$PARAMS_APP_NAME&version=$PARAMS_VERSION"
  params+="&type=$PARAMS_TYPE&sid=$(song sid)"
  logged && params+="&user_id=$USER_ID&token=$USER_TOKEN&expire=$USER_EXPIRE"
  echo $params
}

# param: operation type
# return: playlist json
request_playlist() {
  PARAMS_TYPE=$1
  $CURL $BASE_URL/radio/people?$(build_params) | jq .song
}

# return: playlist json
load_playlist() {
  cat $PATH_PLAYLIST
}

get_playlist_length() {
  load_playlist | jq length
}

# param: operation type
update_playlist() {
  local playlist=$(request_playlist $1)
  echo $playlist > $PATH_PLAYLIST
  [ $(get_playlist_length) = 0 ] && echo_error "Playlist is empty" && quit
  set_playlist_index 0
}

# param: 0 or 1
# return: ♡ or ♥
heart() {
  if [ $1 = 1 ]; then
    printf "♥"
  else
    printf "♡"
  fi
}

# param: rating [0, 5]
# return: ★★★☆☆ 3.2
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
  echo "$s $1"
}

print_song_info() {
  local length=$(song length)
  local time=$(printf "%d:%02d" $(( length / 60)) $(( length % 60)))
  echo
  echo "  $(yellow $(song artist) - $(green $(song title))) ($time)"
  echo "  $(cyan \<$(song albumtitle)\> $(song public_time))"
  echo "  $(stars $(song rating_avg)) $(heart $(song liked))"
}

notify_song_info() {
  notify-send -i $(song picture_path) \
    "$(song title) $(heart $(song liked))" \
    "$(song artist)《$(song albumtitle)》\n$(stars $(song rating_avg))"
}

play_next() {
  local index=$(( $(get_playlist_index) + 1))
  if [ $(get_playlist_length) = $index ]; then
    update_playlist p
  else
    set_playlist_index $index
  fi

  play 2> /dev/null
}

# return: player pid
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
  PLAYER_STATE=$STATE_PLAYING
}

# param: operation type
update_and_play() {
  update_playlist $1
  play 2> /dev/null
}

pause() {
  case $PLAYER_STATE in
    $STATE_PLAYING)
      pkill -19 -P $(get_player_pid)
      PLAYER_STATE=$STATE_STOPED
      printf "\n  $(yellow Paused)\n"
      ;;
    $STATE_STOPED)
      pkill -18 -P $(get_player_pid)
      PLAYER_STATE=$STATE_PLAYING
      printf "\n  $(green Playing)\n"
      ;;
  esac
}

song_skip() {
  update_and_play s
}

song_rate() {
  if [ $(song liked) = 0 ]; then
    update_playlist r
    # todo: set song liked = 1
    printf "\n  $(green liked)\n"
  else
    update_playlist u
    # todo: set song liked = 0
    printf "\n  $(yellow unlike)\n"
  fi
}

song_remove() {
  update_and_play b
}

print_playlist() {
  local current_index=$(get_playlist_index)
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

print_channels() {
  echo todo
}

quit() {
  pkill -P $(get_player_pid) > /dev/null 2>&1
  show_cursor
  echo
  exit
}

print_commands() {
  cat << EOF

  [$(cyan p)] play or pause
  [$(cyan s)] skip this song
  [$(cyan n)] play next song without report
  [$(cyan b)] remove this song
  [$(cyan r)] like or unlike this song
  [$(cyan t)] print and notify the song info
  [$(cyan c)] print channels
  [$(cyan l)] print playlist
  [$(cyan i)] sign in
  [$(cyan o)] sign out
  [$(cyan q)] quit
EOF
}

sign_in() {
  echo
  if logged; then
    printf "  You already Login, press [o] to sign out.\n"
  else
    show_cursor
    enable_echo
    read -p "  Email: " email

    disable_echo
    hide_cursor
    read -p "  Password: " password

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
      printf "\n  $(cyan $USER_NAME \<$USER_EMAIL\>)\n"
    else
      printf "\n  $(red $message)\n"
    fi
  fi
}

sign_out() {
  USER_NAME=null
  USER_EMAIL=null
  USER_ID=null
  USER_TOKEN=null
  USER_EXPIRE=null
  set_config user {}
  printf "\n  Sign out\n"
  [ $PARAMS_CHANNEL = -3 ] && set_channel 0 && update_and_play
}

mainloop() {
  while true; do
    read -n 1 c
    case ${c:0:1} in
      t) print_song_info; notify_song_info ;;
      p) pause ;;
      s) song_skip ;;
      n) play_next ;;
      r) song_rate ;;
      b) song_remove ;;
      c) print_channels ;;
      l) print_playlist ;;
      i) sign_in ;;
      o) sign_out ;;
      q) quit ;;
      h) print_commands ;;
    esac
  done
}

set_kbps() {
  if [[ $1 =~ 64|128|192 ]]; then
    PARAMS_KBPS=$1
    set_config kbps $1
  else
    echo_error "Available kbps values is 64, 128, 192"
  fi
}

# param: channel id
set_channel() {
  if [[ $1 =~ ^-?[0-9]+$ ]]; then
    PARAMS_CHANNEL=$1
    set_config channel $1
  else
    echo_error "Channel id must be a number"
  fi
}

print_help() {
  cat << EOF
Usage: $0 [-c channel_id | -k kbps]

Options:
  -c channel_id    select channel
  -k kbps          set kbps, available values is 64, 128, 192
EOF
}

init_path
init_params

while getopts "c:k:h" opt; do
  case $opt in
    c) set_channel $OPTARG ;;
    k) set_kbps $OPTARG ;;
    h) print_help; exit ;;
  esac
done

trap quit INT
stty -echo 2> /dev/null
hide_cursor
load_user_info
update_and_play n
mainloop
