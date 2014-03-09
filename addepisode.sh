#!/bin/bash

# create an audio podcast episode from a youtube video
# expanded upon https://github.com/jweslley/youtube-dl-mp3

URL=$1

CONFIG_FILE="config"

# get settings from configuration file
USER=`grep ^USER $CONFIG_FILE | sed 's/^USER=//'`
HOST=`grep ^HOST $CONFIG_FILE | sed 's/^HOST=//'`
PUBLIC_URL=`grep ^PUBLIC_URL $CONFIG_FILE | sed 's/^PUBLIC_URL=//'`
REMOTE_BASE_DIR=`grep ^REMOTE_BASE_DIR $CONFIG_FILE | sed 's/^REMOTE_BASE_DIR=//'`

REMOTE_FILE_DIR="$REMOTE_BASE_DIR/files"
REMOTE_PAGE_DIR="$REMOTE_BASE_DIR/pages"
RSS_FILE="$REMOTE_BASE_DIR/rss2.xml"
LOCAL_TEMP_DIR="tmp"
TMP_FILE="youtube-mp3-$RANDOM.tmp"

mkdir -p $LOCAL_TEMP_DIR
cd $LOCAL_TEMP_DIR

# get the video details to be downloaded
youtube-dl --ignore-errors --get-title --get-url --get-filename "$URL" > $TMP_FILE 2> "$TMP_FILE.err"

echo "Done getting the video information"

# open the temp file for reading using a custom file descriptor
exec 42< $TMP_FILE

# read the video title, making sure it exists before proceeding
while read VIDEO_TITLE <&42 ; do

  # read the video url and file name, save the episode title
  EPISODE_TITLE=`echo "$VIDEO_TITLE" | tr -cd "A-Za-z0-9_- "`
  read VIDEO_URL <&42
  read VIDEO_FILENAME <&42

  # download the video url and convert to mp3
  wget "$VIDEO_URL" -O "$VIDEO_FILENAME"
  ffmpeg -i "$VIDEO_FILENAME" "$VIDEO_FILENAME.wav"
  lame "$VIDEO_FILENAME.wav" "$VIDEO_TITLE"

  # remove illegal characters from filename
  EPISODE_FILENAME=`echo "$VIDEO_TITLE" | tr -cd "A-Za-z0-9_-"`
  mv "$VIDEO_TITLE" "$EPISODE_FILENAME.mp3"

done

# close the file descriptor
exec 42<&-

echo "Done converting the video to mp3"

# copy the file to the server
scp "$EPISODE_FILENAME.mp3" $USER@$HOST:$REMOTE_FILE_DIR

echo "Done copying the file to the server"

EPISODE_UUID=`uuidgen`
EPISODE_COUNT=`ls -1 | wc -l`
EPISODE_NUMBER=$(($EPISODE_COUNT + 1))
EPISODE_LINK="$PUBLIC_URL/pages/$EPISODE_NUMBER.html"
EPISODE_DATE=`date +"%a, %d %b %Y %T %z"`
EPISODE_DESCRIPTION="<![CDATA[ <p>Listen. Learn.</p> ]]>"
EPISODE_URL="$PUBLIC_URL/files/$EPISODE_FILENAME.mp3"
EPISODE_LENGTH=`wc -c < $EPISODE_FILENAME.mp3` # actually the filesize in bytes

# connect to the remote server
ssh $USER@$HOST bash -c "'

cd $REMOTE_BASE_DIR

# increase the publish date so the client knows the file changed
sed -i\".bak\" \"13s/.*/  <lastBuildDate>$EPISODE_DATE<\/lastBuildDate>/\" $RSS_FILE

# remove the last two closing tags in the rss file
sed -E -i\".bak\" \"/\/channel|\/rss/d\" $RSS_FILE

# add the new podcast item to the rss file
cat >>$RSS_FILE <<EOL
  <item>
    <title>$EPISODE_TITLE</title>
    <guid isPermaLink=\"false\">$EPISODE_UUID</guid>
    <link>$EPISODE_LINK</link>
    <pubDate>$EPISODE_DATE</pubDate>
    <description>$EPISODE_DESCRIPTION</description>
    <enclosure url=\"$EPISODE_URL\" length=\"$EPISODE_LENGTH\" type=\"audio/mpeg\" />
  </item>

</channel>
</rss>
EOL

# create a html file for the podcast to link to
touch "$REMOTE_PAGE_DIR/$EPISODE_NUMBER.html"

# remove the file backup
rm *.bak

'"

echo "Done creating podcast episode for $EPISODE_TITLE"

# remove the temporary files
#cd ..
#rm -rf $LOCAL_TEMP_DIR
