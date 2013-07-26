###
config
###

# animate ALL the things!
@css_animation = true

# cache selectors for great justice
@use_cached_selectors = true

# only one of the below css animation techniques may be set to true
@replace_technique = false
@reflow_technique  = false
@timeout_technique = true

# load css sheets of images instead of individual files
@use_css_sheets = true

# use the 60 events per second capped rollup stream instead of raw?
@use_capped_stream = true

# send cleanup events when closing event streams for SUPER LAME servers like heroku :(
@force_stream_close = true

# some urls
emojistatic_img_path = 'http://emojistatic.github.io/images/32/'
emojistatic_css_uri  = 'http://emojistatic.github.io/css-sheets/emoji-32px.min.css'

###
inits
###
@score_cache = {}
@selector_cache = {}

@iOS = false
p = navigator.platform
@iOS = true if( p == 'iPad' || p == 'iPhone' || p == 'iPod' || p == 'iPhone Simulator' || p == 'iPad Simulator' )

###
methods related to the polling UI
###
# grab the initial data and scores and pass along to draw the grid
@refreshUIFromServer = (callback) ->
  $.get('/data', (response) ->
    drawEmojiStats(response, callback)
  , "json")

###
methods related to the streaming UI
###
@startScoreStreaming = ->
  if use_capped_stream then startCappedScoreStreaming() else startRawScoreStreaming()

@startRawScoreStreaming = ->
  console.log "Subscribing to score stream (raw)"
  @source = new EventSource('/subscribe/raw')
  @source.onmessage = (event) -> incrementScore(event.data)

@startCappedScoreStreaming = ->
  console.log "Subscribing to score stream (60eps rollup)"
  @source = new EventSource('/subscribe/eps')
  @source.onmessage = (event) -> incrementMultipleScores(event.data)

@stopScoreStreaming = (async=true) ->
  console.log "Unsubscribing to score stream"
  @source.close()
  forceCloseScoreStream(async) if @force_stream_close

@startDetailStreaming = (id) ->
  console.log "Subscribing to detail stream for #{id}"
  @detail_id = id
  @detail_source = new EventSource("/subscribe/details/#{id}")
  @detail_source.addEventListener("stream.tweet_updates.#{id}", processDetailTweetUpdate, false)

@stopDetailStreaming = (async=true) ->
  console.log "Unsubscribing to detail stream #{@detail_id}"
  @detail_source.close()
  forceCloseDetailStream(@detail_id, async) if @force_stream_close

@forceCloseDetailStream = (id, async=true) ->
  console.log "Forcing disconnect cleanup for #{id}..."
  $.ajax({
      type: 'POST'
      url: "/subscribe/cleanup/details/#{id}"
      success: (data) ->
        console.log(" ...Received #{JSON.stringify data} from server.")
      async: async
    })
  true

@forceCloseScoreStream = (async=true) ->
  console.log "Forcing disconnect cleanup for score stream..."
  $.ajax({
      type: 'POST'
      url: "/subscribe/cleanup/scores"
      success: (data) ->
        console.log(" ...Received #{JSON.stringify data} from server.")
      async: async
    })
  true

processDetailTweetUpdate = (event) ->
  appendTweetList $.parseJSON(event.data), true


###
index page UI helpers
###

formatNumberWithCommas = (n) ->
  if n > 9999
    return (n + "").replace(/\B(?=(\d\d\d)+(\.|$))/g, ",")
  else
    return (n + "")

# redraw the entire emoji grid and scores based on data
drawEmojiStats = (stats, callback) ->
  selector = $("#data")
  selector.empty()
  for emoji_char in stats
    do (emoji_char) ->
      @score_cache[emoji_char.id] = emoji_char.score
      selector.append "
        <a href='/details/#{emoji_char.id}' title='#{emoji_char.name}' data-id='#{emoji_char.id}'>
        <li class='emoji_char' id='#{emoji_char.id}' data-title='#{emoji_char.name}'>
          <span class='char emojifont'>#{emoji.replace_unified(emoji_char.char)}</span>
          <span class='score' id='score-#{emoji_char.id}'>#{formatNumberWithCommas(emoji_char.score)}</span>
        </li>
        </a>"
  callback() if (callback)

# getter for cached score_selector elements
get_cached_selectors = (id) ->
  if @selector_cache[id] != undefined
    return [@selector_cache[id][0], @selector_cache[id][1]]
  else
    score_selector = document.getElementById("score-#{id}")
    container_selector = document.getElementById(id)
    @selector_cache[id] = [score_selector, container_selector]
    return [score_selector, container_selector]

# increment multiple scores from a JSON hash
incrementMultipleScores = (data) ->
  scores = $.parseJSON(data)
  incrementScore(key,value) for key,value of scores

# increment the score of a single emoji char
incrementScore = (id, incrby=1) ->
  if @use_cached_selectors
    [score_selector, container_selector] = get_cached_selectors(id)
  else
    score_selector = document.getElementById("score-#{id}")
    container_selector = document.getElementById(id)

  score_selector.innerHTML = formatNumberWithCommas(@score_cache[id] += incrby);
  if css_animation
    # various ways to do this....
    # some discussion at http://stackoverflow.com/questions/12814612/css3-transition-to-highlight-new-elements-created-in-jquery

    if replace_technique
      new_container = container_selector.cloneNode(true)
      new_container.classList.add('highlight_score_update_anim')
      container_selector.parentNode.replaceChild(new_container, container_selector)
      selector_cache[id] = [new_container.childNodes[3], new_container] if use_cached_selectors
    else if reflow_technique
      container_selector.classList.remove('highlight_score_update_anim')
      container_selector.focus()
      container_selector.classList.add('highlight_score_update_anim')
      # this has WAY worse performance it seems like on low power devices
    else if timeout_technique
      container_selector.classList.add('highlight_score_update_trans')
      setTimeout -> container_selector.classList.remove('highlight_score_update_trans')

###
detail page/view UI helpers
###
@emptyTweetList = ->
  tweet_list = $('#tweet_list')
  tweet_list.empty()

@appendTweetList = (tweet, new_marker = false) ->
  tweet_list = $('#tweet_list')
  tweet_list_elements = $("#tweet_list li")
  tweet_list_elements.last().remove() if tweet_list_elements.size() >= 20
  new_entry = $(formattedTweet(tweet, new_marker))
  tweet_list.prepend( new_entry )
  if css_animation
    new_entry.focus()
    # new_entry.removeClass('new') # no longer needed with animation style

###
general purpose UI helpers
###
String.prototype.linkifyHashtags = () ->
  this.replace /#(\w+)/g, "<a href='https://twitter.com/search?q=%23$1&src=hash' target='_blank'>#$1</a>"
String.prototype.linkifyUsernames = () ->
  this.replace /@(\w+)/g, "<a href='https://twitter.com/$1' target='_blank'>@$1</a>"
String.prototype.linkifyUrls = () ->
  # this.replace /(https?:\/\/[^\s]+)/g, "<a href='$1' target='_blank'>$1</a>"
  this.replace /(https?:\/\/t.co\/\w+)/g, "<a href='$1' target='_blank'>$1</a>"
String.prototype.linkify = () ->
  this.linkifyUrls().linkifyUsernames().linkifyHashtags()

formattedTweet = (tweet, new_marker = false) ->
  tweet_url = "https://twitter.com/#{tweet.screen_name}/status/#{tweet.id}"
  #mini_profile_url = tweet.avatar.replace('_normal','_mini')
  prepared_tweet = tweet.text.linkify()
  class_to_be = "styled_tweet"
  class_to_be += " new" if new_marker && css_animation
  "<li class='#{class_to_be}'>
  <i class='icon-li icon-angle-right'></i>
  <blockquote class='twitter-tweet'>
   <p class='emojifont-restricted'>
      #{emoji.replace_unified prepared_tweet}
    </p>
   &mdash;
    <a href='https://twitter.com/#{tweet.screen_name}' target='_blank'>
      <strong class='emojifont-restricted'>#{emoji.replace_unified tweet.name}</strong>
    </a>
    <span class='screen_name'>@#{tweet.screen_name}</span>
    <span class='intents'>
      <a class='icon' href='https://twitter.com/intent/tweet?in_reply_to=#{tweet.id}'><i class='icon-reply'></i></a>
      <a class='icon' href='https://twitter.com/intent/retweet?tweet_id=#{tweet.id}'><i class='icon-retweet'></i></a>
      <a class='icon' href='https://twitter.com/intent/favorite?tweet_id=#{tweet.id}'><i class='icon-star'></i></a>
      <a class='icon' href='#{tweet_url}'><i class='icon-external-link'></i></a>
    </span>
  </blockquote>
  </li>"

###
Polling
###
@startRefreshTimer = ->
  @refreshTimer = setInterval refreshUIFromServer, 3000

@stopRefreshTimer = ->
  clearInterval(@refreshTimer)

###
Shit to dynamically load css-sheets only on browsers that don't properly support emoji fun
###
@loadEmojiSheet = (css_url) ->
  cssId = 'emoji-css-sheet' # you could encode the css path itself to generate id..
  if (!document.getElementById(cssId))
    head  = document.getElementsByTagName('head')[0]
    link  = document.createElement('link')
    link.id   = cssId
    link.rel  = 'stylesheet'
    link.type = 'text/css'
    link.href = css_url
    link.media = 'all'
    head.appendChild(link)

###
Secret disco mode (easter egg)
###
@enableDiscoMode = () ->
  @disco_time = true
  console.log "woo disco time!!!!"
  $('body').append("<div id='discoball'></div>")
  $('#discoball').focus()
  
  start_music = ->
    @audio = new Audio();
    canPlayOgg = !!audio.canPlayType && audio.canPlayType('audio/ogg; codecs="vorbis"') != ""
    canPlayMP3 = !!audio.canPlayType && audio.canPlayType('audio/mpeg; codecs="mp3"') != ""
    if canPlayMP3
      console.log "can haz play mp3"
      @audio.setAttribute("src","/disco/getlucky-64.mp3")
    else if canPlayOgg
      console.log "can haz play ogg"
      @audio.setAttribute("src","/disco/getlucky-64.ogg")
    @audio.load()
    @audio.play()
  setTimeout start_music, 2000

  $('body').addClass('disco')
  $('.emoji_char').addClass('disco')
  $('.navbar').addClass('navbar-inverse')
  $('#discoball').addClass('in-position')

@disableDiscoMode = () ->
  @disco_time = false
  $('#discoball').removeClass('in-position')
  $('.disco').removeClass('disco')
  $('.navbar').removeClass('navbar-inverse')
  
  kill_music = -> @audio.pause()
  setTimeout kill_music, 2000

initDiscoMode = () ->
  @disco_time = false
  disco_keys = [68,73,83,67,79]
  disco_index = 0
  $(document).keydown (e) ->
    if e.keyCode is disco_keys[disco_index++]
      if disco_index is disco_keys.length
        enableDiscoMode()
    else
      disco_index = 0

  $(document).keyup (e) ->
      if e.keyCode is 27
        if disco_time is true
          disableDiscoMode()

###
Configuration vars we need to set globally
###
$ ->
  emoji.img_path = emojistatic_img_path
  emoji.init_env()
  console.log "INFO: js-emoji replace mode is #{emoji.replace_mode}"
  if emoji.replace_mode == 'css' && use_css_sheets
    console.log "In a browser that supports CSS fanciness but not emoji characters, dynamically injecting css-sheet!"
    emoji.use_css_imgs = true
    loadEmojiSheet(emojistatic_css_uri)

  initDiscoMode()
