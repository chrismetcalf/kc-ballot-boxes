(function() {
  var MAX_RANGE_METERS, SEATTLE_LAT, SEATTLE_LONG, init_map, load_map, location_fail, location_success, send_text_message;
  SEATTLE_LAT = 47.60579;
  SEATTLE_LONG = -122.3321;
  MAX_RANGE_METERS = 160000;
  init_map = function(latitude, longitude, map_div) {
    var lat_lng, myOptions;
    lat_lng = new google.maps.LatLng(latitude, longitude);
    myOptions = {
      zoom: 12,
      center: lat_lng,
      mapTypeId: google.maps.MapTypeId.ROADMAP
    };
    return new google.maps.Map(map_div, myOptions);
  };
  send_text_message = function(id) {
    var number;
    number = $("#cell-number").val();
    return $.ajax({
      url: "/message?number=" + number + "&id=" + id,
      success: alert("Text message sent!")
    });
  };
  load_map = function(latitude, longitude) {
    var map;
    map = init_map(latitude, longitude, document.getElementById("map"));
    return $.ajax({
      url: "/search?latitude=" + latitude + "&longitude=" + longitude + "&range=" + MAX_RANGE_METERS,
      context: document.body,
      success: function(boxes) {
        var bounds, box, details, marker, marker_loc, you, you_loc;
        you_loc = new google.maps.LatLng(latitude, longitude);
        you = new google.maps.Marker({
          position: you_loc,
          map: map,
          title: "You!",
          icon: new google.maps.MarkerImage("/img/blue.png")
        });
        box = boxes[0];
        marker_loc = new google.maps.LatLng(box["latitude"], box["longitude"]);
        marker = new google.maps.Marker({
          position: marker_loc,
          map: map,
          title: box["name"],
          icon: new google.maps.MarkerImage("/img/ballot-box.gif")
        });
        bounds = new google.maps.LatLngBounds();
        bounds.extend(marker_loc);
        bounds.extend(you_loc);
        map.fitBounds(bounds);
        details = $("#details");
        details.append("<h1>" + box["name"] + "</h1>");
        details.append("<p>" + box["address"] + "<br/>" + box["city"] + ", " + box["state"] + " " + box["zip"] + "</p>");
        details.append("<p><a href=\"http://maps.google.com/maps?q=" + box["address"] + "," + box["city"] + ",%20" + box["state"] + "%20" + box["zip"] + "\">View in Google Maps</a></p>");
        details.append("<p><input type=\"text\" id=\"cell-number\" value=\"Enter your number\" /><br/><a id=\"text-me\" href=\"#\">Text it to me!</a></p>");
        return $("#text-me").click(function() {
          return send_text_message(box["id"]);
        });
      }
    });
  };
  location_success = function(p) {
    var latitude, longitude;
    latitude = p.coords.latitude;
    longitude = p.coords.longitude;
    return $.ajax({
      url: "/range?from_lat=" + SEATTLE_LAT + "&from_long=" + SEATTLE_LONG + "&to_lat=" + latitude + "&to_long=" + longitude,
      context: document.body,
      success: function(range) {
        if (range > MAX_RANGE_METERS) {
          alert("You're too far outside Seattle, so we're going to pretend you live there.");
          return load_map(SEATTLE_LAT, SEATTLE_LONG);
        } else {
          return load_map(latitude, longitude);
        }
      },
      failure: function(range) {
        return load_map(SEATTLE_LAT, SEATTLE_LONG);
      }
    });
  };
  location_fail = function(p) {
    alert("Could not find your location, defaulting to Seattle");
    return load_map(SEATTLE_LAT, SEATTLE_LONG);
  };
  navigator.geolocation.getCurrentPosition(location_success, location_fail);
}).call(this);
