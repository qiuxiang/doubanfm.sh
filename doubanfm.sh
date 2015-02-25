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
  CONFIG=$(cat $PATH_CONFIG | jq ".$1=$2")
  echo $CONFIG > $PATH_CONFIG
}

PATH_BASE=$HOME/.doubanfm.sh
PATH_COOKIES=$PATH_BASE/cookies.txt
PATH_PLAYER_PID=$PATH_BASE/player.pid
PATH_ALBUM_COVER=$PATH_BASE/albumcover
PATH_CONFIG=$PATH_BASE/config.json
PATH_PLAYLIST_INDEX=$PATH_BASE/index

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
test -f $PATH_PLAYLIST_INDEX || echo 0 > $PATH_PLAYLIST_INDEX

PARAMS_APP_NAME=radio_desktop_win
PARAMS_VERSION=100
PARAMS_TYPE=n
PARAMS_CHANNEL=$(get_config channel)
PARAMS_KBPS=$(get_config kbps)

STATE_PLAYING=0
STATE_STOPED=1

# wrap color green
green() {
  echo -e "\033[0;32m$@\033[0m"
}

# wrap color yellow
yellow() {
  echo -e "\033[0;33m$@\033[0m"
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

# assign SONG
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
  test -f $SONG_PICTURE_PATH || $CURL $SONG_PICTURE_URL > $SONG_PICTURE_PATH
}

# return: params string
build_params() {
  local params="kbps=$PARAMS_KBPS&channel=$PARAMS_CHANNEL"
  params+="&app_name=$PARAMS_APP_NAME&version=$PARAMS_VERSION"
  params+="&type=$PARAMS_TYPE&sid=$SONG_SID"
  echo $params
}

# assign PLAYLIST
#
# param: operation type
update_playlist() {
  PARAMS_TYPE=$1
  PLAYLIST=$($CURL $BASE_URL/radio/people?$(build_params))
  PLAYLIST_LENGTH=$(echo $PLAYLIST | jq '.song | length')
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

print_song_info() {
  echo
  echo "   title: $(cyan $SONG_TITLE)"
  echo "  artist: $(cyan $SONG_ARTIST)"
  echo "   album: $(cyan $SONG_ALBUM_TITLE)"
  echo "    year: $(cyan $SONG_PUBLIC_TIME)"
  echo "  rating: $(cyan $SONG_RATING)"
  printf "    time: $(cyan %d:%02d)\n" $(( SONG_LENGTH / 60)) $(( SONG_LENGTH % 60))
}

notify_song_info() {
  notify-send -i $SONG_PICTURE_PATH "$SONG_TITLE" "$SONG_ARTIST《$SONG_ALBUM_TITLE》"
}

play_next() {
  local index=$(( $(get_playlist_index) + 1))
  if [ $PLAYLIST_LENGTH -eq $index ]; then
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
  test -f $PATH_PLAYER_PID && pkill -P $(get_player_pid)
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
      printf "\n  $(yellow paused)\n"
      ;;
    $STATE_STOPED)
      pkill -18 -P $(get_player_pid)
      PLAYER_STATE=$STATE_PLAYING
      printf "\n  $(cyan playing)\n"
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
    if [ $i -eq $current_index ]; then
      printf "♪ $(yellow $(get_song_info $i artist)) - $(green $(get_song_info $i title))\n"
    else
      printf "  $(yellow $(get_song_info $i artist)) - $(green $(get_song_info $i title))\n"
    fi
  done
}

print_channels() {
  echo todo
}

quit() {
  pkill -P $(get_player_pid)
  echo -e "\e[?25h" # show cursor
  exit
}

print_commands() {
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
    read -n 1 c
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
      h)
        print_commands
        ;;
    esac
  done
}

while getopts "c:" opt; do
  case $opt in
     c)
       PARAMS_CHANNEL=$OPTARG
       set_config channel $OPTARG
       ;;
     k)
       PARAMS_KBPS=$OPTARG
       set_config kbps $OPTARG
       ;;
  esac
done

trap quit INT
stty -echo 2> /dev/null
printf "\e[?25l" # hide cursor
update_and_play n
mainloop
