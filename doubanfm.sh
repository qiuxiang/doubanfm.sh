#!/usr/bin/env bash

# param: key
# return: value
get_config() {
  cat $PATH_CONFIG | jq .$1
}

# param: key
# param: value
set_config() {
  # can't use pipeline, because input file can't as output file
  CONFIG=`cat $PATH_CONFIG | jq ".$1=$2"`
  echo $CONFIG > $PATH_CONFIG
}

PATH_BASE=$HOME/.doubanfm.sh
PATH_COOKIES=$PATH_BASE/cookies.txt
PATH_PLAYER_PID=$PATH_BASE/player.pid
PATH_ALBUM_COVER=$PATH_BASE/albumcover
PATH_CONFIG=$PATH_BASE/config.json

BASE_URL=http://douban.fm/j/app
CURL="curl -s -c $PATH_COOKIES -b $PATH_COOKIES"
PLAYER=mpg123
DEFAULT_CONFIG='{
  "kbps": 192,
  "channel": 0
}'

test -d $PATH_BASE || mkdir $PATH_BASE
test -d $PATH_ALBUM_COVER || mkdir $PATH_ALBUM_COVER
test -f $PATH_PLAYER_PID && rm $PATH_PLAYER_PID
test -f $PATH_CONFIG || echo $DEFAULT_CONFIG > $PATH_CONFIG

PARAMS_APP_NAME=radio_desktop_win
PARAMS_VERSION=100
PARAMS_TYPE=n
PARAMS_CHANNEL=`get_config channel`
PARAMS_KBPS=`get_config kbps`

STATE_PLAYING=0
STATE_STOPED=1

green() {
  echo -e "\033[0;32m$@\033[0m"
}

yellow() {
  echo -e "\033[0;33m$@\033[0m"
}

cyan() {
  echo -e "\033[0;36m$@\033[0m"
}

# assign SONG
fetch_song_info() {
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
  SONG_LENGTH=`get_song_info length`
  SONG_KBPS=`get_song_info kbps`
  SONG_PICTURE_URL=`get_song_info picture`
  SONG_PICTURE_PATH=$PATH_ALBUM_COVER/${SONG_PICTURE_URL##*/}
  test -f $SONG_PICTURE_PATH || $CURL $SONG_PICTURE_URL > $SONG_PICTURE_PATH
}

# return: params string
build_params() {
  local params="kbps=$PARAMS_KBPS&channel=$PARAMS_CHANNEL"
  params+="&app_name=$PARAMS_APP_NAME&version=$PARAMS_VERSION"
  params+="&type=$PARAMS_TYPE&sid=$SONG_SID"
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

print_song_info() {
  echo
  echo "   title: `cyan $SONG_TITLE`"
  echo "  artist: `cyan $SONG_ARTIST`"
  echo "   album: `cyan $SONG_ALBUM_TITLE`"
  echo "    year: `cyan $SONG_PUBLIC_TIME`"
  echo "  rating: `cyan $SONG_RATING`"
  printf "    time: `cyan %d:%02d`\n\n" $(( SONG_LENGTH / 60)) $(( SONG_LENGTH % 60))
}

notify_song_info() {
  notify-send -i $SONG_PICTURE_PATH "$SONG_TITLE" "$SONG_ARTIST《$SONG_ALBUM_TITLE》"
}

play_next() {
  if [ $PLAYLIST_LENGTH -eq $(( PLAYLIST_COUNT + 1)) ]; then
    update_playlist p
  else
    let PLAYLIST_COUNT+=1
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
  test -f $PATH_PLAYER_PID && pkill -P `get_player_pid`
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
      pkill -19 -P `get_player_pid`
      PLAYER_STATE=$STATE_STOPED
      echo "  "`yellow paused`
      ;;
    $STATE_STOPED)
      pkill -18 -P `get_player_pid`
      PLAYER_STATE=$STATE_PLAYING
      echo "  "`cyan playing`
      ;;
  esac
}

song_skip() {
  update_and_play s
}

song_rate() {
  if [ $SONG_LIKED -eq 0 ]; then
    update_playlist r
    SONG_LIKED=1
  else
    update_playlist u
    SONG_LIKED=0
  fi
}

song_remove() {
  update_and_play b
}

print_playlist() {
  echo todo
}

print_channels() {
  echo todo
}

quit() {
  pkill -P `get_player_pid`
  exit
}

print_help() {
  cat << EOF

  p: play or pause
  n: next song
  b: remove this song
  r: like or unlike
  i: display song info
  c: print channels
  l: print playlist
  q: quit

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
      p)
        pause
        ;;
      n)
        song_skip
        ;;
      r)
        song_rate
        ;;
      b)
        song_remove
        ;;
      c)
        print_channels
        ;;
      l)
        print_playlist
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
