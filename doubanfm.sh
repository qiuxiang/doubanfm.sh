#!/usr/bin/env bash

PATH_BASE=$HOME/.doubanfm.sh
PATH_COOKIES=$PATH_BASE/cookies.txt

test -d $PATH_BASE || mkdir $PATH_BASE

BASE_URL=http://douban.fm/j/app
CURL="curl -s -c $PATH_COOKIES"
PLAY=mpg123
PLAY_PID=-1

COLOR_RED="\033[0;31m"
COLOR_GREEN="\033[0;32m"
COLOR_YELLOW="\033[0;33m"
COLOR_BLUE="\033[0;34m"
COLOR_MAGENTA="\033[0;35m"
COLOR_CYAN="\033[0;36m"
COLOR_RESET="\033[0m"

PARAMS_APP_NAME=radio_desktop_win
PARAMS_VERSION=100
PARAMS_TYPE=n
PARAMS_CHANNEL=0
PARAMS_SID=0
PARAMS_KBPS=192

# return: params string
build_params() {
  local params="kbps=$PARAMS_KBPS&channel=$PARAMS_CHANNEL"
  params+="&app_name=$PARAMS_APP_NAME&version=$PARAMS_VERSION"
  params+="&type=$PARAMS_TYPE&sid=$PARAMS_SID"
  echo $params
}

# param: operation type
# return: playlist json
get_playlist() {
  PARAMS_TYPE=$1
  $CURL $BASE_URL/radio/people?`build_params`
}

# assign PLAYLIST
#
# param: operation type
update_playlist() {
  PLAYLIST=`get_playlist $1`
  PLAYLIST_LENGTH=`echo $PLAYLIST | jq '.song | length'`
  PLAYLIST_COUNT=0
}

# get current song info (depends PLAYLIST and PLAYLIST_COUNT) with key
#
# param: key
# return: value
get_song_info() {
  echo $PLAYLIST | jq -r .song[$PLAYLIST_COUNT].$1
}

# assign SONG
fetch_song_info() {
  SONG_PICTURE_URL=`get_song_info picture`
  SONG_URL=`get_song_info url`
  SONG_SID=`get_song_info sid`
  SONG_ALBUM_URL=http://music.douban.com`get_song_info album`
  SONG_ALBUM_TITLE=`get_song_info albumtitle`
  SONG_TITLE=`get_song_info title`
  SONG_RATING=`get_song_info rating_avg`
  SONG_ARTIST=`get_song_info artist`
  SONG_LIKED=`get_song_info like`
  SONG_PUBLIC_TIME=`get_song_info public_time`
  SONG_COMPANY=`get_song_info company`
}

print_song_info() {
  echo -e "$COLOR_YELLOW$SONG_ARTIST - $COLOR_GREEN$SONG_TITLE"
  echo -e "$COLOR_CYAN$SONG_ALBUM_TITLE$COLOR_RESET ($SONG_ALBUM_URL)"
  echo -e "$SONG_COMPANY, $SONG_PUBLIC_TIME"
}

notify_song_info() {
  notify-send "$SONG_TITLE" "$SONG_ARTIST《$SONG_ALBUM_TITLE》"
}

play_next() {
  if [ $PLAYLIST_LENGTH -eq $(( PLAYLIST_COUNT + 1)) ]; then
    update_playlist p
    PLAYLIST_COUNT=0
  else
    let PLAYLIST_COUNT+=1
  fi

  play 2> /dev/null
}

play() {
  fetch_song_info
  print_song_info
  notify_song_info
  pkill -P $PLAY_PID > /dev/null
  $PLAY $SONG_URL &> /dev/null && play_next &
  PLAY_PID=$!
}

# param: operation type
update_and_play() {
  update_playlist $1
  play 2> /dev/null
}

skip() {
  update_and_play s
}

quit() {
  pkill -P $PLAY_PID
  exit
}

print_help() {
  cat <<EOF
Available commands:
  p                play or pause
  n                next song
  b                hate this song
  r                like or unlike
  i                display song info
  c                print channels
  l                print playlist
  q                quit
EOF
}

mainloop() {
  while true; do
    read -p "> " c
    case ${c:0:1} in
      i)
        print_song_info
        notify_song_info
        ;;
      n)
        skip
        ;;
      q)
        quit
        ;;
      *)
        print_help
        ;;
    esac
  done
}

trap quit INT
update_and_play n
mainloop
