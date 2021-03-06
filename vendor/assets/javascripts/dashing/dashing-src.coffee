Batman.config.pathPrefix = '/'
Batman.config.viewPrefix = '/dashing/widgets/'

Batman.Filters.prettyNumber = (num) ->
  num.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",") unless isNaN(num)

Batman.Filters.dashize = (str) ->
  dashes_rx1 = /([A-Z]+)([A-Z][a-z])/g;
  dashes_rx2 = /([a-z\d])([A-Z])/g;

  return str.replace(dashes_rx1, '$1_$2').replace(dashes_rx2, '$1_$2').replace(/_/g, '-').toLowerCase()

Batman.Filters.shortenedNumber = (num) ->
  return num if isNaN(num)
  if num >= 1000000000
    (num / 1000000000).toFixed(1) + 'B'
  else if num >= 1000000
    (num / 1000000).toFixed(1) + 'M'
  else if num >= 1000
    (num / 1000).toFixed(1) + 'K'
  else
    num

class window.Dashing extends Batman.App
  @on 'reload', (data) ->
    window.location.reload(true)

  @root ->
Dashing.params = Batman.URI.paramsFromQuery(window.location.search.slice(1));

class Dashing.Widget extends Batman.View
  constructor:  ->
    # Set the view path
    @constructor::source = Batman.Filters.underscore(@constructor.name)
    super

    @mixin($(@node).data())
    Dashing.widgets[@id] ||= []
    Dashing.widgets[@id].push(@)

    type = Batman.Filters.dashize(@view)
    $(@node).addClass("widget widget-#{type} #{@id}")

  @accessor 'updatedAtMessage', ->
    if updatedAt = @get('updatedAt')
      timestamp = new Date(updatedAt * 1000)
      hours = timestamp.getHours()
      minutes = ("0" + timestamp.getMinutes()).slice(-2)
      "Last updated at #{hours}:#{minutes}"

  @::on 'ready', ->
    Dashing.Widget.fire 'ready'

    # In case the events from the server came before the widget was rendered
    lastData = Dashing.lastEvents[@id]
    if lastData
      @mixin(lastData)
      @onData(lastData)

  receiveData: (data) =>
    @mixin(data)
    @onData(data)

  onData: (data) =>
    # Widgets override this to handle incoming data

Dashing.AnimatedValue =
  get: Batman.Property.defaultAccessor.get
  set: (k, to) ->
    if !to? || isNaN(to)
      @[k] = to
    else
      timer = "interval_#{k}"
      num = if (!isNaN(@[k]) && @[k]?) then @[k] else 0
      unless @[timer] || num == to
        to = parseFloat(to)
        num = parseFloat(num)
        up = to > num
        num_interval = Math.abs(num - to) / 90
        @[timer] =
          setInterval =>
            num = if up then Math.ceil(num+num_interval) else Math.floor(num-num_interval)
            if (up && num > to) || (!up && num < to)
              num = to
              clearInterval(@[timer])
              @[timer] = null
              delete @[timer]
            @[k] = num
            @set k, to
          , 10
      @[k] = num

Dashing.widgets = widgets = {}
Dashing.lastEvents = lastEvents = {}
Dashing.debugMode = false


setCookie = (name, value, days) ->
  if days
    date = new Date()
    date.setTime date.getTime() + (days * 24 * 60 * 60 * 1000)
    expires = "; expires=" + date.toGMTString()
  else
    expires = ""
  document.cookie = name + "=" + value + expires + "; path=/"

sendConnectionCloseSignal = (conn_id) ->
  $.ajax
    type: 'post'
    url: '/dashing/events?id='+conn_id
    dataType: 'json'
    cache: false
    async: false
    error: (jqXHR, textStatus, errorThrown) ->
      console.log "AJAX Error: #{textStatus} #{errorThrown}"
    success: (data, textStatus, jqXHR) ->
      console.log "Successful AJAX call: #{data}"

getCookie = (name) ->
  nameEQ = name + "="
  ca = document.cookie.split(";")
  i = 0

  while i < ca.length
    c = ca[i]
    c = c.substring(1, c.length)  while c.charAt(0) is " "
    return c.substring(nameEQ.length, c.length)  if c.indexOf(nameEQ) is 0
    i++
  null  

class GUID

  s4: ->
    Math.floor((1 + Math.random()) * 0x10000).toString(16).substring(1)

  create: () ->
    "#{@s4()}#{@s4()}-#{@s4()}-#{@s4()}-#{@s4()}-#{@s4()}#{@s4()}#{@s4()}"

guid = new GUID

window.uuid = guid.create()
window.repo_name = document.getElementById('current_repo').value;
window.unicast = false;
console.log("uuid in dashing = ", window.uuid)
console.log("repo in dashing = ", window.repo_name)

setCookie('CONN_ID',window.uuid)

source = new EventSource('/dashing/events?conn_uuid='+window.uuid+'&repo_name='+window.repo_name)
source.addEventListener 'open', (e) ->
  console.log("Connection opened", e)

source.addEventListener 'error', (e)->
  console.log("Connection error", e)
  if (e.currentTarget.readyState == EventSource.CLOSED)
    console.log("Connection closed")
#    setTimeout (->
#      window.location.reload()
#    ), 5*60*1000
  sendConnectionCloseSignal(window.uuid)

source.addEventListener 'message', (e) ->
  data = JSON.parse(e.data)
  if lastEvents[data.id]?.updatedAt != data.updatedAt
    if Dashing.debugMode
      console.log("Received data for #{data.id}", data)
    lastEvents[data.id] = data
    if widgets[data.id]?.length > 0
      for widget in widgets[data.id]
        widget.receiveData(data)

source.addEventListener 'dashboards', (e) ->
  data = JSON.parse(e.data)
  if Dashing.debugMode
    console.log("Received data for dashboards", data)
  if data.dashboard is '*' or window.location.pathname is "/#{data.dashboard}"
    Dashing.fire data.event, data

$(window).unload ->
  console.log "Handler for .unload() called.";
  source.close()
  sendConnectionCloseSignal(window.uuid)
  console.log "Handler for .unload() ended.";

$(document).ready ->
  Dashing.run()
