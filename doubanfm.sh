#!/usr/bin/env bash

PATH_BASE=$HOME/.doubanfm.sh
PATH_COOKIES=$PATH_BASE/cookies.txt
PATH_PLAYER_PID=$PATH_BASE/player.pid
PATH_ALBUM_COVER=$PATH_BASE/albumcover
PATH_CONFIG=$PATH_BASE/config.json
PATH_PLAYLIST_INDEX=$PATH_BASE/.index

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

fetch_song_info() {
  local index=$(get_playlist_index)
  SONG_URL=$(get_song_info $index url)
  SONG_SID=$(get_song_info $index sid)
  SONG_ALBUM_URL=http://music.douban.com$(get_song_info $index album)
  SONG_ALBUM_TITLE=$(get_song_info $index albumtitle)
  SONG_TITLE=$(get_song_info $index title)
  SONG_RATING=$(get_song_info $index rating_avg)
  SONG_ARTIST=$(get_song_info $index artist)
  SONG_LIKED=$(get_song_info $index like)
  SONG_PUBLIC_TIME=$(get_song_info $index public_time)
  SONG_COMPANY=$(get_song_info $index company)
  SONG_LENGTH=$(get_song_info $index length)
  SONG_KBPS=$(get_song_info $index kbps)
  SONG_PICTURE_URL=$(get_song_info $index picture)
  SONG_PICTURE_PATH=$PATH_ALBUM_COVER/${SONG_PICTURE_URL##*/}
  # save song picture
  [ -f $SONG_PICTURE_PATH ] || $CURL $SONG_PICTURE_URL > $SONG_PICTURE_PATH
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

# return: params string
build_params() {
  local params="kbps=$PARAMS_KBPS&channel=$PARAMS_CHANNEL"
  params+="&app_name=$PARAMS_APP_NAME&version=$PARAMS_VERSION"
  params+="&type=$PARAMS_TYPE&sid=$SONG_SID"
  logged && params+="&user_id=$USER_ID&token=$USER_TOKEN&expire=$USER_EXPIRE"
  echo $params
}

# param: operation type
update_playlist() {
  PARAMS_TYPE=$1
  PLAYLIST=$($CURL $BASE_URL/radio/people?$(build_params))
  PLAYLIST_LENGTH=$(echo $PLAYLIST | jq '.song | length')
  [ $PLAYLIST_LENGTH = 0 ] && echo_error "Playlist is empty" && exit 1
  set_playlist_index 0
}

# get song info from PLAYLIST
#
# param: playlist index
# param: key
# return: value
get_song_info() {
  echo $PLAYLIST | jq -r .song[$1].$2
}

# param: 0 or 1
# return: ♡ or ♥
liked_symbol() {
  if [ $1 = 1 ]; then
    printf "♥"
  else
    printf "♡"
  fi
}

print_song_info() {
  local time=$(printf "%d:%02d" $(( SONG_LENGTH / 60)) $(( SONG_LENGTH % 60)))
  echo
  echo "  $(yellow $SONG_ARTIST) - $(green $SONG_TITLE) ($time)"
  echo "  $(cyan \<$SONG_ALBUM_TITLE\> $SONG_PUBLIC_TIME)"
  echo "  $SONG_RATING $(liked_symbol $SONG_LIKED)"
}

notify_song_info() {
  notify-send -i $SONG_PICTURE_PATH \
    "$SONG_TITLE" "$SONG_ARTIST《$SONG_ALBUM_TITLE》"
}

play_next() {
  local index=$(( $(get_playlist_index) + 1))
  if [ $PLAYLIST_LENGTH = $index ]; then
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
  $PLAYER $SONG_URL &> /dev/null && play_next &
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
  if [ $SONG_LIKED = 0 ]; then
    update_playlist r
    SONG_LIKED=1
    printf "\n  $(green liked)\n"
  else
    update_playlist u
    SONG_LIKED=0
    printf "\n  $(yellow unlike)\n"
  fi
}

song_remove() {
  update_and_play b
}

print_playlist() {
  local current_index=$(get_playlist_index)
  echo
  for (( i = 0; i < PLAYLIST_LENGTH; i++ )) do
    local artist=$(yellow $(get_song_info $i artist))
    local title=$(green $(get_song_info $i title))
    if [ $i = $current_index ]; then
      echo "♪ $artist - $title"
    else
      echo "  $artist - $title"
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
  [$(cyan n)] next song
  [$(cyan b)] remove this song
  [$(cyan r)] like or unlike
  [$(cyan t)] display song info
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
      n) song_skip ;;
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
