# Plain js Poll
# Problem: html caching does not work
# (even when server sends a 304, everything is refreshed)
# webNotificationPoll = ->
#   xhr = new XMLHttpRequest
#   channel = document.getElementById('clickerChannel')
#   url = channel.dataset.url
#   xhr.open 'GET', url
#   xhr.onload = ->
#     console.log xhr.getResponseHeader("Last-Modified")
#     if xhr.status == 200
#       channel.innerHTML = xhr.responseText
#     return
#   xhr.send()
#   return

getCookie = (name) ->
  match = document.cookie.match(new RegExp('(^| )' + name + '=([^;]+)'))
  if match
    return match[2]
  return

adjustVoteStatus = (channel) ->
  if channel.data('open')
    clickerId = channel.data('clicker')
    clickerInstance = channel.data('instance')
    clickerStatus = getCookie('clicker-' + clickerId)
    if clickerStatus == clickerInstance
      $('#clickerOpen').hide()
      $('#votedAlready').show()
  return

webNotificationPoll = ->
  channel = $('#clickerChannel')
  url = channel.data('url')
  val = $('input[name="vote[value]"]:checked').val();
  thankVote = $('#thankVote').is(':visible')
  $.ajax(
    url: url
    ifModified: true
    dataType: 'html'
    ).done (response, statusText, xhr) ->
    if response?
      responseChannel = $(response).find('#clickerChannel')
      clickerId = channel.data('clicker')
      clickerStatus = getCookie('clicker-' + clickerId)
      newClickerInstance = responseChannel.data('instance')
      newClickerOpen = responseChannel.data('open')
      $('#clickerChannel').html($(response).find('#clickerChannel').html())
      $('#clickerChannel').data('instance', newClickerInstance)
      $('#clickerChannel').data('open', newClickerOpen)
      if val?
        $('#vote_value_' + val).prop('checked',true)
        $('#submitClickerVote').prop('disabled', false)
      if clickerStatus == newClickerInstance
        $('#clickerOpen').hide()
        if thankVote
          $('#thankVote').show()
        else
          $('#votedAlready').show()
    return
  return


window.onload = ->
  channel = $('#clickerChannel')
  if channel.length > 0
    adjustVoteStatus(channel)
    window.clickerChannelId = setInterval(webNotificationPoll, 4000)
    $(document).on 'change', '.clickerVote', ->
      $('#submitClickerVote').prop('disabled', false)
      return
  return
