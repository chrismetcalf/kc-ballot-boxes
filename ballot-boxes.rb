#!/usr/bin/env ruby

require 'rubygems'
require 'sinatra'
require 'sinatra/reloader' if development?
require 'net/http'
require 'uri'
require 'json'
require 'erb'
require 'cgi'

# Load helper libraries
require './lib/boxes'

configure :production do
  set :raise_errors, false
end

get '/' do
  erb :index
end

get '/search', :provides => :json do
  content_type :json

  @latitude = params[:latitude]
  @longitude = params[:longitude]
  @range = params[:range]
  if @longitude.nil? || @longitude.empty? || @longitude.nil? || @longitude.empty?
    status 404
    return
  end

  @boxes = Box.lookup(@latitude, @longitude, @range)
  locations = []
  @boxes.each do |loc|
    locations << {
      "id" => loc.sid,
      "name" => loc.name,
      "address" => loc.address,
      "city" => loc.city,
      "state" => "WA",
      "zip" => loc.zip,
      "latitude" => loc.location.latitude,
      "longitude" => loc.location.longitude
    }
  end
  return locations.to_json
end

# Send a message using SMSify. We only let you text a particular location ID, in
# theory to prevent spamming.
get "/message" do
  number = params[:number]
  id = params[:id]

  if id.nil? || number.nil?
    return [400, "Invalid request"]
  end

  box = Box.find(id)
  if box.nil?
    return [404, "Could not find that box by ID"]
  end

  message = "Your nearest drop box: #{box["name"]}, #{box["address"]}, #{box["city"]}, #{box["state"]}"

  request = Net::HTTP::Post.new("/v1/smsmessaging/outbound/#{ENV["SMSIFY_NUMBER"]}/requests?address=#{number}&message=#{URI::escape(message)}")
  request.basic_auth(ENV["SMSIFY_USERNAME"], ENV["SMSIFY_PASSWORD"])
  response = Net::HTTP.start("api.smsified.com", 80) { |http| http.request(request)}

  if response.code == '201'
    return "Your text message was successfully sent."
  else
    puts 
    return [500, "There was an error sending your text message. Please try again later."]
  end
end

# I don't feel like implementing Haversine in Javascript, so I'll make it
# a service :)
get "/range" do
  from_lat = params[:from_lat]
  from_long = params[:from_long]
  to_lat = params[:to_lat]
  to_long = params[:to_long]

  puts Point.new(from_lat.to_i, from_long.to_i).range(Point.new(to_lat.to_i, to_long.to_i))
  return Point.new(from_lat.to_i, from_long.to_i).range(Point.new(to_lat.to_i, to_long.to_i)).to_s
end
