# This file is a component in the Rosencrantz Entertainment Conglomerate
# Copyright (C) 2021 Hampus Andreas Niklas Rosencrantz

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

struct VideoPreferences
  include JSON::Serializable

  property autoplay : Bool
  property comments : Array(String)
  property continue : Bool
  property continue_autoplay : Bool
  property controls : Bool
  property preferred_captions : Array(String)
  property quality : String
  property speed : Float32 | Float64
  property video_end : Float64 | Int32
  property video_start : Float64 | Int32
  property volume : Int32
end

class VideoRedirect < Exception
  property video_id : String

  def initialize(@video_id)
  end
end

struct Video
  include DB::Serializable

  property backdrops : Array(String) | Nil
  property posters : Array(String) | Nil
  property genres : Array(String)
  property id : Int32
  property tmdb_id : String | Nil
  property overview : String | Nil
  property release_date : String | Nil
  property runtime : Int32
  property tagline : String | Nil
  property title : String
  property captions : Array(String) = [] of String
  
  # non local files
  property dash_manifest_url : String | Nil
  property hls_manifest_url : String | Nil

  property actors : Array(String) | Nil
  property spoken_languages : Array(String) | Nil

  property popularity : String | Nil
  property average_rating : String | Nil
  property certification : String | Nil
  property trailer_url : String | Nil

  property imdb_id : String | Nil

  module JSONConverter
    def self.from_rs(rs)
      JSON.parse(rs.read(String)).as_h
    end
  end

  def to_json(locale, json : JSON::Builder)
    json.object do
      json.field "type", "video"

      json.field "backdrop_path", self.backdrop_path
      json.field "id", self.id
      json.field "tmdb_id", self.tmdb_id
      json.field "overview", self.overview
      json.field "release_date", self.release_date
      json.field "runtime", self.runtime
      json.field "tagline", self.tagline
      json.field "title", self.title

    end
  end

  def to_json(locale, json : JSON::Builder | Nil = nil)
    if json
      to_json(locale, json)
    else
      JSON.build do |json|
        to_json(locale, json)
      end
    end
  end
end

class Caption
  include DB::Serializable
  property id : Int32
  property language : String
  property caption_url : String
end

def get_video(id, db)
  if video = db.query_one?("SELECT * FROM movies WHERE id = $1", id, as: Video)
    return video
  else
    raise InfoException.new("Video does not exist.")
  end
end

def process_video_params(query, preferences)
  autoplay = query["autoplay"]?.try { |q| (q == "true" || q == "1").to_unsafe }
  comments = query["comments"]?.try &.split(",").map { |a| a.downcase }
  continue = query["continue"]?.try { |q| (q == "true" || q == "1").to_unsafe }
  continue_autoplay = query["continue_autoplay"]?.try { |q| (q == "true" || q == "1").to_unsafe }
  preferred_captions = query["subtitles"]?.try &.split(",").map { |a| a.downcase }
  quality = query["quality"]?
  speed = query["speed"]?.try &.rchop("x").to_f?
  volume = query["volume"]?.try &.to_i?

  if preferences
    autoplay ||= preferences.autoplay.to_unsafe
    comments ||= preferences.comments
    continue ||= preferences.continue.to_unsafe
    continue_autoplay ||= preferences.continue_autoplay.to_unsafe
    preferred_captions ||= preferences.captions
    quality ||= preferences.quality
    speed ||= preferences.speed
    volume ||= preferences.volume
  end

  autoplay ||= CONFIG.default_user_preferences.autoplay.to_unsafe
  comments ||= CONFIG.default_user_preferences.comments
  continue ||= CONFIG.default_user_preferences.continue.to_unsafe
  continue_autoplay ||= CONFIG.default_user_preferences.continue_autoplay.to_unsafe
  preferred_captions ||= CONFIG.default_user_preferences.captions
  quality ||= CONFIG.default_user_preferences.quality
  speed ||= CONFIG.default_user_preferences.speed
  volume ||= CONFIG.default_user_preferences.volume

  autoplay = autoplay == 1
  continue = continue == 1
  continue_autoplay = continue_autoplay == 1

  quality = "high"

  if start = query["t"]? || query["time_continue"]? || query["start"]?
    video_start = decode_time(start)
  end
  video_start ||= 0

  if query["end"]?
    video_end = decode_time(query["end"])
  end
  video_end ||= -1

  controls = query["controls"]?.try &.to_i?
  controls ||= 1
  controls = controls >= 1

  params = VideoPreferences.from_json({
    autoplay:           autoplay,
    comments:           comments,
    continue:           continue,
    continue_autoplay:  continue_autoplay,
    controls:           controls,
    preferred_captions: preferred_captions,
    quality:            quality,
    speed:              speed,
    video_end:          video_end,
    video_start:        video_start,
    volume:             volume,
  }.to_json)

  return params
end
