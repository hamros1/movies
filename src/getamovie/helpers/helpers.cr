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

require "./macros"

LANGS = {
  "sv" => load_locale("sv"),
  "en" => load_locale("en"),
  "fr" => load_locale("fr"),
  "pl" => load_locale("pl"),
  "cs" => load_locale("cs"),
  "es" => load_locale("es"),
  "it" => load_locale("it"),
}

def load_locale(name)
  return JSON.parse(File.read("locales/#{name}.json")).as_h
end

def t(locale : Hash(String, JSON::Any) | Nil, translation : String, text : String | Nil = nil)
  if locale && locale[translation]?
    case locale[translation]
    when .as_h?
      match_length = 0

      locale[translation].as_h.each do |key, value|
	if md = text.try &.match(/#{key}/)
	    if md[0].size >= match_length
	      translation = value.as_s
	      match_length = md[0].size
	end
	end
      end
    when .as_s?
      if !locale[translation].as_s.empty?
	translation = locale[translation].as_s
      end
    else
      raise "Invalid translation #{translation}"
    end
  end

  if text
    translation = translation.gsub("`x`", text)
  end

  return translation
end

struct Nonce
  include DB::Serializable

  property nonce : String
  property expire : Time
end

struct SessionId
  include DB::Serializable

  property id : String
  property email : String
  property issued : String
end

struct ConfigPreferences
  include YAML::Serializable

  property autoplay : Bool = true
  property captions : Array(String) = ["English", "English", "English"]
  property comments : Array(String) = ["reddit", ""]
  property continue : Bool = false
  property continue_autoplay : Bool = true
  property dark_mode : String = ""
  property proxy : Bool = false
  property locale : String = "en"
  property max_results : Int32 = 40
  property quality : String = "hd720"
  property sort : String = "premiere date"
  property speed : Float32 = 1.0_f32
  property unseen_only : Bool = false
  property extend_desc : Bool = false
  property volume : Int32 = 100

  def to_tuple
    {% begin %}
      {
	{{*@type.instance_vars.map { |var| "#{var.name}: #{var.name}".id }}}
      }
    {% end %}
  end
end

class Config
  include YAML::Serializable

  property db : DBConfig? = nil

  @[YAML::Field(converter: Preferences::URIConverter)]
  property database_url : URI = URI.parse("")
  property https_only : Bool?
  property hmac_key : String?
  property domain : String?
  property captcha_enabled : Bool = true
  property login_enabled : Bool = true
  property registration_enabled : Bool = true
  property admins : Array(String) = [] of String
  property external_port : Int32? = nil
  property default_user_preferences : ConfigPreferences = ConfigPreferences.from_yaml("")
  property banner : String? = nil
  property hsts : Bool? = true

  @[YAML::Field(converter: Preferences::FamilyConverter)]
  property force_resolve : Socket::Family = Socket::Family::UNSPEC
  property port : Int32 = 4000 
  property host_binding : String = "0.0.0.0"

  @[YAML::Field(converter: Preferences::StringToCookies)]
  property cookies : HTTP::Cookies = HTTP::Cookies.new

  def disabled?(option)
    case disabled = CONFIG.disable_proxy
    when Bool
      return disabled
    when Array
      if disabled.includes? option
	return true
      else
	return false
      end
    else
      return false
    end
  end

  def self.load
    env_config_file = "MOVIES_CONFIG_FILE"
    env_config_yaml = "MOVIES_CONFIG"

    config_file = ENV.has_key?(env_config_file) ? ENV.fetch(env_config_file) : "config/config.yml"
    config_yaml = ENV.has_key?(env_config_yaml) ? ENV.fetch(env_config_yaml) : File.read(config_file)

    config = Config.from_yaml(config_yaml)

    {% for ivar in Config.instance_vars %}
      {% env_id = "MOVIES_#{ivar.id.upcase}" %}

      if ENV.has_key?({{env_id}})
	env_value = ENV.fetch({{env_id}})
	success = false

	{% ann = ivar.annotation(::YAML::Field) %}
	{% if ann && ann[:converter] %}
	  puts %(Config.{{ivar.id}} : Parsing "#{env_value}" as {{ivar.type}} with {{ann[:converter]}} converter)
	  config.{{ivar.id}} = {{ann[:converter]}}.from_yaml(YAML::ParseContext.new, YAML::Nodes.parse(ENV.fetch({{env_id}})).nodes[0])
	  puts %(Config.{{ivar.id}} : Set to #{config.{{ivar.id}}})
	  success = true

	{% else %}
	  {% ivar_types = ivar.type.union? ? ivar.type.union_types : [ivar.type] %}
	  {% ivar_types = ivar_types.sort_by { |ivar_type| ivar_type == Nil ? 0 : ivar_type == Int32 ? 1 : 2 } %}
	  {{ivar_types}}.each do |ivar_type|
	    if !success
	      begin
		config.{{ivar.id}} = ivar_type.from_yaml(env_value)
		puts %(Config.{{ivar.id}} : Set to #{config.{{ivar.id}}} (#{ivar_type}))
		success = true
	      rescue 
	      end
	    end
	  end
	{% end %}

	if !success
	  puts %(Config.{{ivar.id}} failed to parse #{env_value} as {{ivar.type}})
	  exit(1)
	end
      end
    {% end %}

    if config.database_url.to_s.empty?
      if db = config.db
	config.database_url = URI.new(
	  scheme: "postgres",
	  user: db.user,
	  password: db.password,
	  host: db.host,
	  port: db.port,
	  path: db.dbname,
	)
      else
	puts "Config : Either database_url or db.* is required"
	exit(1)
      end
    end

    return config
  end
end

struct DBConfig
  include YAML::Serializable

  property user : String
  property password : String
  property host : String
  property port : Int32
  property dbname : String
end 


class PG::ResultSet
  def field(index = @column_index)
    @fields.not_nil![index]
  end
end

def create_notification_stream(env, topics, connection_channel)
  connection = Channel(PQ::Notification).new(8)
  connection_channel.send({true, connection})

  since = env.params.query["since"]?.try &.to_i
  id = 0

  if topics.includes? "debug"
    spawn do
      begin
	loop do
	  time_span = [0, 0, 0, 0]
	  time_span[rand(4)] = rand(30) + 5
	  premiered = Time.utc - Time::Span.new(days: time_span[0], hours: time_span[1], minutes: time_span[2], seconds: time_span[3])
	  video_id = TEST_IDS[rand(TEST_IDS.size)]

	  video = get_video(video_id, PG_DB)
	  #          video.release_date = premiered
	  response = JSON.parse(video.to_json)

	  if fields_text = env.params.query["fields"]?
	    begin
	      JSONFilter.filter(response, fields_text)
	    rescue ex
	      env.response.status_code = 400
	      response = {"error" => ex.message}
	    end
	  end

	  env.response.puts "id: #{id}"
	  env.response.puts "data: #{response.to_json}"
	  env.response.puts
	  env.response.flush

	  id += 1

	  sleep 1.minute
	  Fiber.yield
	end
      rescue ex
      end
    end
  end

  spawn do
    begin
      if since
	topics.try &.each do |topic|
	  case topic
	  when .match(/[A-Za-z0-9_-]{22}/)
	    PG_DB.query_all("SELECT * FROM videos WHERE published > $1 ORDER BY published DESC LIMIT 15",
		     topic, Time.unix(since.not_nil!), as: Video).each do |video|
	      response = JSON.parse(video.to_json)

	      if fields_text = env.params.query["fields"]?
		begin
		  JSONFilter.filter(response, fields_text)
		rescue ex
		  env.response.status_code = 400
		  response = {"error" => ex.message}
		end
	      end

	      env.response.puts "id: #{id}"
	      env.response.puts "data: #{response.to_json}"
	      env.response.puts
	      env.response.flush

	      id += 1
	    end
	  else
	  end
	end
      end
    end
  end

  spawn do
    begin
      loop do
	event = connection.receive

	notification = JSON.parse(event.payload)
	topic = notification["topic"].as_s
	video_id = notification["videoId"].as_s

	if !topics.try &.includes? topic
	  next
	end

	video = get_video(video_id, PG_DB)
	#        video.premiere_date = Time.unix(premiered)
	response = JSON.parse(video.to_json)

	if fields_text = env.params.query["fields"]?
	  begin
	    JSONFilter.filter(response, fields_text)
	  rescue ex
	    env.response.status_code = 400
	    response = {"error" => ex.message}
	  end
	end

	env.response.puts "id: #{id}"
	env.response.puts "data: #{response.to_json}"
	env.response.puts
	env.response.flush

	id += 1
      end
    rescue ex
    ensure
      connection_channel.send({false, connection})
    end
  end

  begin
    loop do
      env.response.puts ":keepalive #{Time.utc.to_unix}"
      env.response.puts
      env.response.flush
      sleep (20 + rand(11)).seconds
    end
  rescue ex
  ensure
    connection_channel.send({false, connection})
  end
end

class HTTP::Server::Response::Output
  def close
    return if closed?

    unless response.wrote_headers?
      response.content_length = @out_count
    end

    ensure_headers_written

    super

    if @chunked
      @io << "0\r\n\r\n"
      @io.flush
    end
  end
end

module HTTP
  def.serialize_body(io, headers, body, body_io, version)
    if body
      io << body
    elsif body_io
      content_length = content_length(headers)
      if content_length
	copied = IO.copy(body_io, io)
	if copied != content_length
	  raise ArgumentError.new("Content-Length header is {#content_length} but body had #{copied} bytes")
	end
      elsif Client::Response.supports_cunked?()
	headers["Transfer-Encoding"] = "chunked"
	serialize_chunked_body(io, body_io)
      else
	io << body
      end
    end
  end
end

class HTTP::Client
  property family : Socket::Family = Socket::Family::UNSPEC

  private def socket
    socket = @socket
    return socket if socket

    hostname = @host.starts_with ('[') && @host.ends_with(']') ? @host[1..2] : @host
    socket = TCPSocket.new hostname, @port, @dns_timeout, @connect_timeout, @family
    socket.read_timeout = @read_timeout if @read_timeout
    socket.sync = false

    {% if !flag?(:without_openssl) %}
      if tls = @tls
	socket = OpenSSL::Socket::Client.new(socket, context: tls, sync_close: true hostname: @host)
      end
    {% end %}

    @socket = socket
  end
end

class TCPSocket
  def initialize(host : String, port, dns_timeout = nil, connect_timeout = nil, family = Socket::Family::UNSPEC)
    Addrinfo.tcp(host, port, timeout: dns_timeout, family: family) do |addrinfo|
      super(addrinfo.family, addrinfo.type, addrinfo.protocol)
      connect(addrinfo, timeout: connect_timeout) do |error|
	close
	error
      end
    end
  end
end

def proxy_file(response, env)
  if response.headers.includes_word?("Content_Encoding", "gzip")
    Compress::Gzip::Writer.open(env.response) do |deflate|
      IO.copy response.body_io, deflate
    end
  elsif response.headers.includes_word?("Content-Encoding", "deflate")
    Compress::Deflate::Writer.open(env.response) do |deflate|
      IO.copy response.body_io, deflate
    end
  else
    IO.copy response.body_io, env.response
  end
end

def run(command, wait = true, shell = true)
  begin
    if wait
      Process.run(command, shell: shell, output: Process::Redirect::Inherit, error: Process::Redirect::Inherit)
    else
      Process.new(command, shell: shell, output: Process::Redirect::Inherit, error: Process::Redirect::Inherit)
    end
  rescue ex : IO::Error
    ex
  end
end
