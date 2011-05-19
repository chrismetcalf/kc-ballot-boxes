require 'net/http'
require 'uri'
require 'json'
require 'cgi'
require 'singleton'
require 'dalli'

# Config:
DOMAIN = "www.datakc.org"
UID = "bjd8-qrep"

# Cache Client
class Cache
  include Singleton
  VERSION = 1

  def initialize(host = "localhost:11211")
    @cache = Dalli::Client.new(host)
  end

  def get(key)
    @cache.get(version_key(key))
  end

  def set(key, value, ttl = 3600)
    @cache.set(version_key(key), value)
  end

  def delete(key)
    @cache.delete(version_key(key))
  end

  private
    # Hash breaking versioned keys
    def version_key(key)
      return "#{key}_v#{VERSION}"
    end
end

# Helper classes
class Numeric
  def radians
    self * Math::PI / 180
  end

  def degrees
    self * 180 / Math::PI
  end
end

class String
  def underscore
    self.gsub(/([A-Z]+)([A-Z][a-z])/,'\1_\2').
      gsub(/([a-z\d])([A-Z])/,'\1_\2').
      gsub(/[^A-z_0-9]+/, '_').
      downcase
  end
end

class Box
  def self.set_columns(cols)
    @@col_map = Hash.new
    @@location_columns = []
    cols.each_with_index { |col, idx| 
      @@col_map[col["name"].underscore] = idx
      @@location_columns << idx if col["dataTypeName"] == "location"
    }
  end

  def initialize(entry)
    @row = entry
  end

  def location
    # For now we just return the first location column...
    Point.new(@row[@@location_columns[0]][1], @row[@@location_columns[0]][2])
  end

  def method_missing(m)
    if @@col_map.include?(m.to_s.underscore)
      @row[@@col_map[m.to_s.underscore]]
    end
  end

  # Performs the actual lookup and retuns an array of facilities
  def self.lookup(latitude, longitude, range, no_cache = false)
    if !no_cache
      # Check the cache first
      cached = Cache.instance.get("lookup_#{latitude}_#{longitude}_#{range}")
      if(!cached.nil?)
        return cached
      end
    end

    query = {
      "originalViewId" => UID,
      "name" => "Inline View",
      "query" => {
        "filterCondition" => {
           "children" => [
              {
                 "type" => "operator",
                 "value" => "AND",
                 "children" => [
                    {
                       "type" => "operator",
                       "value" => "WITHIN_CIRCLE",
                       "children" => [
                          {
                             "type" => "column",
                             "columnId" => 2724254
                          },
                          {
                             "type" => "literal",
                             "value" => latitude
                          },
                          {
                             "type" => "literal",
                             "value" => longitude
                          },
                          {
                             "type" => "literal",
                             "value" => range
                          }


                       ]
                    }
                 ]
              }
           ],
           "type" => "operator",
           "value" => "AND"
        }
      }
    }

    request = Net::HTTP::Post.new("/api/views/INLINE/rows.json?method=index")
    request.body = query.to_json
    request.add_field("X-APP-TOKEN", ENV["SOCRATA_APP_TOKEN"])
    request.content_type = "application/json"
    response = Net::HTTP.start(DOMAIN, 80){ |http| http.request(request) }

    if response.code != "200"
      raise "Error querying SODA API: #{response.body}"
    else
      view = JSON::parse(response.body)
      if view["meta"].nil? || view["data"].nil?
        raise "Could not parse server response"
      elsif view["data"].count <= 0
        # No results
        return []
      end

      Box.set_columns(view["meta"]["view"]["columns"])
      boxes = view["data"].collect{ |row| Box.new(row) }
      puts boxes.inspect
      point = Point.new(latitude, longitude)
      boxes = boxes.sort_by {|b| point.range(b.location)}
      puts boxes.inspect

      if !no_cache
        # Cache it!
        Cache.instance.set("lookup_#{latitude}_#{longitude}_#{range}", boxes)
      end
      return boxes
    end
  end

  # Looks up a particular facility
  # The response isn't exactly the same as the above, but we'll deal
  def self.find(id)
    # Check the cache first
    cached = Cache.instance.get("find_#{id}")
    if(!cached.nil?)
      return cached
    end

    request = Net::HTTP::Get.new("/api/views/#{UID}/rows/#{id}.json")
    request.add_field("X-APP-TOKEN", APP_TOKEN)
    response = Net::HTTP.start(DOMAIN, 80){ |http| http.request(request) }

    if response.code != "200"
      raise "Error querying SODA API: #{response.body}"
    else
      box = JSON::parse(response.body)

      # Cache it!
      Cache.instance.set("find_#{id}", box)
      return box
    end
  end

  # Hack(?) to solve our demarshalling problems with memcache
  # It'd probably be better if we cached the mapping separately
  def marshal_dump
    [@@col_map, @@location_columns, @row]
  end

  def marshal_load array
    @@col_map, @@location_columns, @row = array
  end
end

class Point
  attr_accessor :latitude, :longitude, :address

  # Initialize a point based off an address or set of points
  def initialize(*args)
    case args.size
    when 1
      # Address
      @address = args[0].to_s

      # Check the cache first
      cached = Cache.instance.get("geocode_#{CGI::escape(@address)}")
      if(!cached.nil?)
        @latitude = cached.latitude
        @longitude = cached.longitude
        return
      end

      # Geocode the address
      request = Net::HTTP::Get.new("/api/geocoding/#{CGI::escape(@address)}")
      request.add_field("X-APP-TOKEN", APP_TOKEN)
      response = Net::HTTP.start(DOMAIN, 80){ |http| http.request(request) }
      point = JSON::parse(response.body)
      if point.nil? || !point.key?("lat") || !point.key?("long")
        return
      end

      @latitude = point["lat"]
      @longitude = point["long"]

      # Cache this value
      Cache.instance.set("geocode_#{CGI::escape(@address)}", self)
    when 2
      # Lat/Long
      @latitude = args[0].to_f
      @longitude = args[1].to_f
    end
  end

  # Haversine calculation stolen from http://www.esawdust.com/blog/gps/files/HaversineFormulaInRuby.html
  # ... and heavily modified
  RAD_PER_DEG = 0.017453293 # PI/180
  R_METERS = 6378100
  def range(other)

    longitude_distance = other.longitude - self.longitude
    latitude_distance = other.latitude - self.latitude

    dlon_rad = longitude_distance * RAD_PER_DEG
    dlat_rad = latitude_distance * RAD_PER_DEG

    lat1_rad = self.latitude * RAD_PER_DEG
    lon1_rad = self.longitude * RAD_PER_DEG

    lat2_rad = other.latitude * RAD_PER_DEG
    lon2_rad = other.longitude * RAD_PER_DEG

    a = (Math.sin(dlat_rad/2))**2 + Math.cos(lat1_rad) * Math.cos(lat2_rad) * (Math.sin(dlon_rad/2))**2
    c = 2 * Math.atan2( Math.sqrt(a), Math.sqrt(1-a))

    return R_METERS * c          # delta between the two points in miles
  end

  def to_s
    "(#{@latitude}, #{@longitude})"
  end
end
