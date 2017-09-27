
require 'rubygems'


# require 'net/http'
require 'rest-client'
require 'json'


class OpenWeatherCalls

  # Do not send requests more than 1 time per 10 minutes from one device/one API key. Normally the weather is not changing so frequently.
  # Use the name of the server as api.openweathermap.org. Please never use the IP address of the server.
  # Call API by city ID instead of city name, city coordinates or zip code. In this case you get precise respond
  # exactly for your city. The cities' IDs can be found in the following file: Cities' IDs list.


  # get uxv id
  # get current location of uxv id (coordinates)
  # get weather(wind speed) for current location (coordinates)
  # incorporate weather data in experiment validation (e.g. max-distance, endurance)

  # key to https://home.openweathermap.org/
  @default_key = "3a87a263c645ea5eb18ad7417be4cb0d"
  @samant_key = "6f34ab9e18d41f43f1b0c4772724e172"

  # perform a GET to :
  # https://samples.openweathermap.org/data/2.5/forecast/daily?lat=35&lon=139&cnt=10&appid=b1b15e88fa797225412429c1c50c122a1

  # example:
  # http://api.openweathermap.org/data/2.5/forecast?id=524901&APPID={APIKEY}

  # weather data can be obtained in JSON and XML formats.
  #     API call:
  #             api.openweathermap.org/data/2.5/forecast?lat={lat}&lon={lon}
  # Parameters:
  #     lat, lon coordinates of the location of your interest
  # Examples of API calls:
  #                     api.openweathermap.org/data/2.5/forecast?lat=35&lon=139&cnt=5&appid=6f34ab9e18d41f43f1b0c4772724e172
  #                     api.openweathermap.org/data/2.5/forecast?lat=35&lon=139&cnt=5&appid=3a87a263c645ea5eb18ad7417be4cb0d



  # a call to skaramagas weather forecast...
  # api.openweathermap.org/data/2.5/forecast?lat=38.005692&lon=23.599784&cnt=5&appid=3a87a263c645ea5eb18ad7417be4cb0d
  #list.speed Wind speed. Unit Default: meter/sec, Metric: meter/sec, Imperial: miles/hour.

  def self.get_forecast(coord1, coord2)

    url = 'api.openweathermap.org/data/2.5/forecast?lat='+coord1+'&lon='+coord2+'&cnt=5&appid=3a87a263c645ea5eb18ad7417be4cb0d'
    puts url

    result = RestClient::Request.execute(method: :post, url: url,
                                       headers: {content_type: "application/json" , accept: "application/json"})

    # result = '{"cod"=>"200",
    #  "message"=>0.0101,
    #  "cnt"=>5,
    #  "list"=>[{"dt"=>1500303600, "main"=>{"temp"=>296.08, "temp_min"=>293.36, "temp_max"=>296.08, "pressure"=>1002.59, "sea_level"=>1023.05, "grnd_level"=>1002.59, "humidity"=>100, "temp_kf"=>2.72}, "weather"=>[{"id"=>501, "main"=>"Rain", "description"=>"moderate rain", "icon"=>"10d"}], "clouds"=>{"all"=>92}, "wind"=>{"speed"=>3.32, "deg"=>329.002}, "rain"=>{"3h"=>3.38}, "sys"=>{"pod"=>"d"}, "dt_txt"=>"2017-07-17 15:00:00"}, {"dt"=>1500314400, "main"=>{"temp"=>294.01, "temp_min"=>291.971, "temp_max"=>294.01, "pressure"=>1003.59, "sea_level"=>1023.98, "grnd_level"=>1003.59, "humidity"=>100, "temp_kf"=>2.04}, "weather"=>[{"id"=>500, "main"=>"Rain", "description"=>"light rain", "icon"=>"10n"}], "clouds"=>{"all"=>68}, "wind"=>{"speed"=>2.42, "deg"=>329.502}, "rain"=>{"3h"=>2.385}, "sys"=>{"pod"=>"n"}, "dt_txt"=>"2017-07-17 18:00:00"}, {"dt"=>1500325200, "main"=>{"temp"=>293.07, "temp_min"=>291.713, "temp_max"=>293.07, "pressure"=>1005.14, "sea_level"=>1025.64, "grnd_level"=>1005.14, "humidity"=>100, "temp_kf"=>1.36}, "weather"=>[{"id"=>500, "main"=>"Rain", "description"=>"light rain", "icon"=>"10n"}], "clouds"=>{"all"=>88}, "wind"=>{"speed"=>2.38, "deg"=>342.509}, "rain"=>{"3h"=>1.52}, "sys"=>{"pod"=>"n"}, "dt_txt"=>"2017-07-17 21:00:00"}, {"dt"=>1500336000, "main"=>{"temp"=>292.42, "temp_min"=>291.738, "temp_max"=>292.42, "pressure"=>1005.57, "sea_level"=>1026.02, "grnd_level"=>1005.57, "humidity"=>100, "temp_kf"=>0.68}, "weather"=>[{"id"=>500, "main"=>"Rain", "description"=>"light rain", "icon"=>"10n"}], "clouds"=>{"all"=>92}, "wind"=>{"speed"=>2.41, "deg"=>6.00238}, "rain"=>{"3h"=>1.465}, "sys"=>{"pod"=>"n"}, "dt_txt"=>"2017-07-18 00:00:00"}, {"dt"=>1500346800, "main"=>{"temp"=>291.858, "temp_min"=>291.858, "temp_max"=>291.858, "pressure"=>1005.9, "sea_level"=>1026.46, "grnd_level"=>1005.9, "humidity"=>100, "temp_kf"=>0}, "weather"=>[{"id"=>501, "main"=>"Rain", "description"=>"moderate rain", "icon"=>"10n"}], "clouds"=>{"all"=>92}, "wind"=>{"speed"=>2.97, "deg"=>10.5046}, "rain"=>{"3h"=>5.075}, "sys"=>{"pod"=>"n"}, "dt_txt"=>"2017-07-18 03:00:00"}], "city"=>{"id"=>256257, "name"=>"Oropos", "coord"=>{"lat"=>38.3, "lon"=>23.75}, "country"=>"GR", "population"=>1000}}'

    puts "results"
    puts result.inspect
    json_res = JSON.parse(result)
    json_res["list"]

  end

  json_result = get_forecast("38.303860", "23.730180")
  puts "list"
  puts json_result

end
