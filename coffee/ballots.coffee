SEATTLE_LAT = 47.60579
SEATTLE_LONG = -122.3321
MAX_RANGE_METERS = 160000

# Initialize the google map
init_map = (latitude, longitude, map_div) ->
  # Stick a map on the page
  lat_lng = new google.maps.LatLng(latitude, longitude)
  myOptions = {
    zoom: 12,
    center: lat_lng,
    mapTypeId: google.maps.MapTypeId.ROADMAP
  }

  return new google.maps.Map(map_div, myOptions)

send_text_message = (id) ->
  number = $("#cell-number").val()
  $.ajax({
    url: "/message?number=#{number}&id=#{id}",
    success: alert("Text message sent!")
  })

load_map = (latitude, longitude) ->
  map = init_map(latitude, longitude, document.getElementById("map"))

  # Look up our nearest ballot box drop
  $.ajax({
    url: "/search?latitude=#{latitude}&longitude=#{longitude}&range=#{MAX_RANGE_METERS}",
    context: document.body,
    success: (boxes) ->
      # Put your location on the map too
      you_loc = new google.maps.LatLng(latitude, longitude)
      you = new google.maps.Marker({
        position: you_loc,
        map: map,
        title: "You!",
        icon: new google.maps.MarkerImage("/img/blue.png")
      })

      # Put a marker on the map
      box = boxes[0]
      marker_loc = new google.maps.LatLng(box["latitude"], box["longitude"])
      marker = new google.maps.Marker({
        position: marker_loc,
        map: map,
        title: box["name"],
        icon: new google.maps.MarkerImage("/img/ballot-box.gif")
      })

      # Show both
      bounds = new google.maps.LatLngBounds()
      bounds.extend(marker_loc)
      bounds.extend(you_loc)
      map.fitBounds(bounds)

      # Put the details in
      details = $("#details")
      details.append("<h1>#{box["name"]}</h1>")

      details.append("<p>#{box["address"]}<br/>#{box["city"]}, #{box["state"]} #{box["zip"]}</p>")
      details.append("<p><a href=\"http://maps.google.com/maps?q=#{box["address"]},#{box["city"]},%20#{box["state"]}%20#{box["zip"]}\">View in Google Maps</a></p>")

      details.append("<p><input type=\"text\" id=\"cell-number\" value=\"Enter your number\" /><br/><a id=\"text-me\" href=\"#\">Text it to me!</a></p>")
      $("#text-me").click(() -> send_text_message(box["id"]))

  })

location_success = (p) ->
  latitude = p.coords.latitude
  longitude = p.coords.longitude
  # If we're more than 160km (100 miles) from Seattle, lets just pretend we're from Seattle.
  $.ajax({
    url: "/range?from_lat=#{SEATTLE_LAT}&from_long=#{SEATTLE_LONG}&to_lat=#{latitude}&to_long=#{longitude}",
    context: document.body,
    success: (range) ->
      # We're all metric and stuff
      if range > MAX_RANGE_METERS
        alert("You're too far outside Seattle, so we're going to pretend you live there.")
        load_map(SEATTLE_LAT, SEATTLE_LONG)
      else
        # We're fine
        load_map(latitude, longitude)
    failure: (range) ->
      load_map(SEATTLE_LAT, SEATTLE_LONG)
  })


location_fail = (p) ->
  # Just load the center of Seattle
  alert("Could not find your location, defaulting to Seattle")
  load_map(SEATTLE_LAT, SEATTLE_LONG)

# Get browser location to kick the whole thing off
navigator.geolocation.getCurrentPosition(location_success, location_fail)


