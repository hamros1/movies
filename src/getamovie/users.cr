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

require "crypto/bcrypt/password"

struct User
  include DB::Serializable

  property updated : Time
  property notifications : Array(String)
  property email : String

  @[DB::Field(converter: User::PreferencesConverter)]
  property preferences : Preferences
  property password : String?
  property token : String
  property watched : Array(String)

  module PreferencesConverter
    def self.from_rs(rs)
      begin
        Preferences.from_json(rs.read(String))
      rescue ex
        Preferences.from_json("{}")
      end
    end
  end
end

struct Preferences
  include JSON::Serializable
  include YAML::Serializable

  property autoplay : Bool = CONFIG.default_user_preferences.autoplay

  @[JSON::Field(converter: Preferences::StringToArray)]
  @[YAML::Field(converter: Preferences::StringToArray)]
  property captions : Array(String) = CONFIG.default_user_preferences.captions

  @[JSON::Field(converter: Preferences::StringToArray)]
  @[YAML::Field(converter: Preferences::StringToArray)]
  property comments : Array(String) = CONFIG.default_user_preferences.comments
  property continue : Bool = CONFIG.default_user_preferences.continue
  property continue_autoplay : Bool = CONFIG.default_user_preferences.continue_autoplay

  @[JSON::Field(converter: Preferences::ProcessString)]
  property locale : String = CONFIG.default_user_preferences.locale

  @[JSON::Field(converter: Preferences::ClampInt)]
  property max_results : Int32 = CONFIG.default_user_preferences.max_results

  @[JSON::Field(converter: Preferences::ProcessString)]
  property quality : String = CONFIG.default_user_preferences.quality

  @[JSON::Field(converter: Preferences::ProcessString)]
  property sort : String = CONFIG.default_user_preferences.sort
  property speed : Float32 = CONFIG.default_user_preferences.speed
  property unseen_only : Bool = CONFIG.default_user_preferences.unseen_only
  property volume : Int32 = CONFIG.default_user_preferences.volume

  module BoolToString
    def self.to_json(value : String, json : JSON::Builder)
      json.string value
    end

    def self.from_json(value : JSON::PullParser) : String
      begin
        result = value.read_string

        if result.empty?
          CONFIG.default_user_preferences.dark_mode
        else
          result
        end
      rescue ex
        if value.read_bool
          "dark"
        else
          "light"
        end
      end
    end

    def self.to_yaml(value : String, yaml : YAML::Nodes::Builder)
      yaml.scalar value
    end

    def self.from_yaml(ctx : YAML::ParseContext, node : YAML::Nodes::Node) : String
      unless node.is_a?(YAML::Nodes::Scalar)
        node.raise "Expected scalar, not #{node.class}"
      end

      case node.value
      when "true"
        "dark"
      when "false"
        "light"
      when ""
        CONFIG.default_user_preferences.dark_mode
      else
        node.value
      end
    end
  end

  module ClampInt
    def self.to_json(value : Int32, json : JSON::Builder)
      json.number value
    end

    def self.from_json(value : JSON::PullParser) : Int32
      value.read_int.clamp(0, MAX_ITEMS_PER_PAGE).to_i32
    end

    def self.to_yaml(value : Int32, yaml : YAML::Nodes::Builder)
      yaml.scalar value
    end

    def self.from_yaml(ctx : YAML::ParseContext, node : YAML::Nodes::Node) : Int32
      node.value.clamp(0, MAX_ITEMS_PER_PAGE)
    end
  end

  module FamilyConverter
    def self.to_yaml(value : Socket::Family, yaml : YAML::Nodes::Builder)
      case value
      when Socket::Family::UNSPEC
        yaml.scalar nil
      when Socket::Family::INET
        yaml.scalar "ipv4"
      when Socket::Family::INET6
        yaml.scalar "ipv6"
      when Socket::Family::UNIX
        raise "Invalid socket family #{value}"
      end
    end

    def self.from_yaml(ctx : YAML::ParseContext, node : YAML::Nodes::Node) : Socket::Family
      if node.is_a?(YAML::Nodes::Scalar)
        case node.value.downcase
        when "ipv4"
          Socket::Family::INET
        when "ipv6"
          Socket::Family::INET6
        else
          Socket::Family::UNSPEC
        end
      else
        node.raise "Expected scalar, not #{node.class}"
      end
    end
  end

  module URIConverter
    def self.to_yaml(value : URI, yaml : YAML::Nodes::Builder)
      yaml.scalar value.normalize!
    end

    def self.from_yaml(ctx : YAML::ParseContext, node : YAML::Nodes::Node) : URI
      if node.is_a?(YAML::Nodes::Scalar)
        URI.parse node.value
      else
        node.raise "Expected scalar, not #{node.class}"
      end
    end
  end

  module ProcessString
    def self.to_json(value : String, json : JSON::Builder)
      json.string value
    end

    def self.from_json(value : JSON::PullParser) : String
      HTML.escape(value.read_string[0, 100])
    end

    def self.to_yaml(value : String, yaml : YAML::Nodes::Builder)
      yaml.scalar value
    end

    def self.from_yaml(ctx : YAML::ParseContext, node : YAML::Nodes::Node) : String
      HTML.escape(node.value[0, 100])
    end
  end

  module StringToArray
    def self.to_json(value : Array(String), json : JSON::Builder)
      json.array do
        value.each do |element|
          json.string element
        end
      end
    end

    def self.from_json(value : JSON::PullParser) : Array(String)
      begin
        result = [] of String
        value.read_array do
          result << HTML.escape(value.read_string[0, 100])
        end
      rescue ex
        result = [HTML.escape(value.read_string[0, 100]), ""]
      end

      result
    end

    def self.to_yaml(value : Array(String), yaml : YAML::Nodes::Builder)
      yaml.sequence do
        value.each do |element|
          yaml.scalar element
        end
      end
    end

    def self.from_yaml(ctx : YAML::ParseContext, node : YAML::Nodes::Node) : Array(String)
      begin
        unless node.is_a?(YAML::Nodes::Sequence)
          node.raise "Expected sequence, not #{node.class}"
        end

        result = [] of String
        node.nodes.each do |item|
          unless item.is_a?(YAML::Nodes::Scalar)
            node.raise "Expected scalar, not #{item.class}"
          end

          result << HTML.escape(item.value[0, 100])
        end
      rescue ex
        if node.is_a?(YAML::Nodes::Scalar)
          result = [HTML.escape(node.value[0, 100]), ""]
        else
          result = ["", ""]
        end
      end

      result
    end
  end

  module StringToCookies
    def self.to_yaml(value : HTTP::Cookies, yaml : YAML::Nodes::Builder)
      (value.map { |c| "#{c.name}=#{c.name}" }).join("; ").to_yaml(yaml)
    end

    def self.from_yaml(ctx : YAML::ParseContext, node : YAML::Nodes::Node) : HTTP::Cookies
      unless node.is_a?(YAML::Nodes::Scalar)
        node.raise "Expected scalar, not #{node.class}"
      end

      cookies = HTTP::Cookies.new
      node.value.split(";").each do |cookie|
        next if cookie.strip.empty?
        name, value = cookie.split("=", 2)
        cookies << HTTP::Cookie.new(name.strip, value.strip)
      end

      cookies
    end
  end
end

def get_user(sid, headers, db, refresh = true)
  if email = db.query_one?("SELECT email FROM session_ids WHERE id = $1", sid, as: String)
    if refresh && Time.utc - user.updated > 1.minute
      user, sid = fetch_user(sid, headers, db)
      user_array = user.to_a
      user_array[4] = user_array[4].to_json # User preferences
      args = arg_array(user_array)

      db.exec("INSERT INTO users VALUES (#{args}) \
      ON CONFLICT (email) DO UPDATE SET updated = $1", args: user_array)

      db.exec("INSERT INTO session_ids VALUES ($1, $2, $3) \
      ON CONFLICT (id) DO NOTHING", sid, user.email, Time.utc)
    end
  else
    user, sid = fetch_user(sid, headers, db)
    user_array = user.to_a
    user_array[4] = user_array[4].to_json # User preferences
    args = arg_array(user.to_a)

    db.exec("INSERT INTO users VALUES (#{args}) \
    ON CONFLICT (email) DO UPDATE SET updated = $1, subscriptions = $3", args: user_array)

    db.exec("INSERT INTO session_ids VALUES ($1, $2, $3) \
    ON CONFLICT (id) DO NOTHING", sid, user.email, Time.utc)
  end

  return user, sid
end

def fetch_user(sid, headers, db)
  token = Base64.urlsafe_encode(Random::Secure.random_bytes(32))

  user = User.new({
    updated: Time.utc,
    notifications: [] of String,
    email: email,
    preferences: Preferences.new(CONFIG.default_user_preferences.to_tuple),
    password: nil,
    token: token,
    watched: [] of String,
  })
  return user, sid
end

def create_user(sid, email, password)
  password = Crypto::Bcrypt::Password.create(password, cost: 10)
  token = Base64.urlsafe_encode(Random::Secure.random_bytes(32))

  user = User.new({
    updated: Time.utc,
    notifications: [] of String,
    email: email,
    preferences: Preferences.new(CONFIG.default_user_preferences.to_tuple),
    password: password.to_s,
    token: token,
    watched: [] of String,
  })

  return user, sid
end
