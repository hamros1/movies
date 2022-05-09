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

require "kemal"
require "pg"
require "xml"
require "yaml"
require "./getamovie/helpers/*"
require "./getamovie/*"
require "./getamovie/routes/**"
require "./getamovie/jobs/**"
require "./getamovie/series/**"

CONFIG   = Config.load
HMAC_KEY = CONFIG.hmac_key || Random::Secure.hex(32)

PG_DB      = DB.open CONFIG.database_url
REDDIT_URL = URI.parse("https://www.reddit.com")
HOST_URL   = make_host_url(Kemal.config)
TEST_IDS   = {"", "", "", "", ""}

MAX_ITEMS_PER_PAGE = 1500

HTTP_CHUNK_SIZE = 10485760 # ~10MB

connection_channel = Channel({Bool, Channel(PQ::Notification)}).new(32)
GetAMovie::Jobs.register GetAMovie::Jobs::NotificationJob.new(connection_channel, CONFIG.database_url)
GetAMovie::Jobs.register GetAMovie::Jobs::StatisticsRefreshJob.new(PG_DB)
GetAMovie::Jobs.register GetAMovie::Jobs::PullSuggestionsJob.new(PG_DB)
GetAMovie::Jobs.register GetAMovie::Jobs::PullContentInfoJob.new(PG_DB)
#GetAMovie::Jobs.register GetAMovie::Jobs::TranscodingJob.new(PG_DB)
#GetAMovie::Jobs.register GetAMovie::Jobs::TorrenterJob.new(PG_DB)
#GetAMovie::Jobs.register GetAMovie::Jobs::DownloaderJob.new(PG_DB)
GetAMovie::Jobs.register GetAMovie::Jobs::ImageArtworkJob.new(PG_DB)
GetAMovie::Jobs.register GetAMovie::Jobs::WatchJob.new(PG_DB)
#GetAMovie::Jobs.register GetAMovie::Jobs::SubtitleDownloadJob.new(PG_DB)
GetAMovie::Jobs.start_all

Kemal.config.extra_options do |parser|
  parser.banner = "Usage getamovie [arguments]"
  parser.on("-v", "--version", "Print version") do
    puts ""
    exit
  end
end

Kemal::CLI.new ARGV

LOGGER = GetAMovie::Logger.build

before_all do |env|
  preferences = begin
    Preferences.from_json(URI.decode_www_form(env.request.cookies["PREFS"]?.try &.value || "{}"))
  rescue
    Preferences.from_json("{}")
  end

  env.set "preferences", preferences

  if (Kemal.config.ssl || CONFIG.https_only) && CONFIG.hsts
    env.response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains; preload"
  end

  if env.request.cookies.has_key? "SID"
    sid = env.request.cookies["SID"].value

    if sid.starts_with? "v1:"
      raise "Cannot use token as SID"
    end

    if email = PG_DB.query_one?("SELECT email FROM session_ids WHERE id = $1", sid, as: String)
      user = PG_DB.query_one("SELECT * FROM users WHERE email = $1", email, as: User)
      csrf_token = generate_response(sid, {
        ":authorize_token",
        ":playlist_ajax",
        ":signout",
        ":token_ajax",
        ":watch_ajax",
      }, HMAC_KEY, PG_DB, 1.week)

      preferences = user.preferences
      env.set "preferences", preferences

      env.set "sid", sid
      env.set "csrf_token", csrf_token
      env.set "user", user
    end
  end

  locale = env.params.query["hl"]? || preferences.locale

  preferences.locale = locale
  env.set "preferences", preferences

  current_page = env.request.path
  if env.request.query
    query = HTTP::Params.parse(env.request.query.not_nil!)

    if query["referer"]?
      query["referer"] = get_referer(env, "/")
    end

    current_page += "?#{query}"
  end

  env.set "current_page", URI.encode_www_form(current_page)
end

GetAMovie::Routing.get "/", GetAMovie::Routes::Misc, :home
GetAMovie::Routing.get "/home", GetAMovie::Routes::Misc, :home
GetAMovie::Routing.get "/watch", GetAMovie::Routes::Watch, :handle
GetAMovie::Routing.get "/login", GetAMovie::Routes::Login, :login_page
GetAMovie::Routing.post "/login", GetAMovie::Routes::Login, :login
GetAMovie::Routing.post "/signout", GetAMovie::Routes::Login, :signout

GetAMovie::Routing.ws "/api/watch_party", GetAMovie::Routes::Api::WatchParty, :watch_party
GetAMovie::Routing.ws "/api/experimental", GetAMovie::Routes::Api::Experimental, :experimental

get "/experimental" do |env|
  templated "experimental"
end

SOCKETS = Hash(HTTP::WebSocket, String).new

get "/api/search/:query" do |env|
  locale = LANGS[env.get("preferences").as(Preferences).locale]?

  search_query = env.params.url["query"]

  items = [] of Video
  first_results = PG_DB.query_all("SELECT * FROM (
  SELECT *,
  to_tsvector(movies.title)
  as document
  FROM movies
  ) v_search WHERE v_search.document @@ plainto_tsquery($1) LIMIT 10", search_query, as: Video)

  second_results = PG_DB.query_all("SELECT * FROM (
  SELECT *,
  to_tsvector(tv.title)
  as document
  FROM tv
  ) v_search WHERE v_search.document @@ plainto_tsquery($1) LIMIT 10", search_query, as: TV)

  items = first_results + second_results

  env.response.content_type = "application/json"
  JSON.build do |json|
    json.object do
      json.field "items" do
        json.array do
          items.each do |item|
            json.object do
              json.field "title", item.title
              json.field "description", item.release_date.try &.[0..3]

              if item.responds_to?(:number_of_seasons)
                json.field "url", "/tv/#{item.id}?season_select=1"
              else
                json.field "url", "/watch?trackId=#{item.id}"
              end

              json.field "image", "/images#{item.posters.try &.sample}"
            end
          end
        end
      end
    end
  end
end

post "/timestamp_ajax" do |env|
  locale = LANGS[env.get("preferences").as(Preferences).locale]?

  user = env.get? "user"
  sid = env.get? "sid"

  if !user
    next error_json(403, "No such user")
  end

  user = user.as(User)
  sid = sid.as(String)

  id = env.params.query["id"]?
  if !id
    env.response.status_code = 400
    next
  end

  watched = env.params.query["watched"]?
  if !watched
    env.response.status_code = 400
    next
  end

  if env.params.query["action_update_timestamp"]?
    action = "action_update_timestamp"
  end

  case action
  when "action_update_timestamp"
    PG_DB.exec("DELETE FROM timestamps WHERE video_id = $1 AND email = $2", id, user.email)
    PG_DB.exec("INSERT INTO timestamps (video_id, percent, email) VALUES ($1, $2, $3)", id.to_i, watched.to_i, user.email.to_s)
  else
    next error_json(400, "Unsupported action #{action}")
  end

  env.response.content_type = "application/json"
  "{}"
end

get "/authorize_token" do |env|
  locale = LANGS[env.get("preferences").as(Preferences).locale]?

  user = env.get? "user"
  sid = env.get? "sid"
  referer = get_referer(env)

  if !user
    next env.redirect referer
  end

  user = user.as(User)
  sid = sid.as(String)
  csrf_token = generate_response(sid, {":authorize_token"}, HMAC_KEY, PG_DB)

  scopes = env.params.query["scopes"]?.try &.split(",")
  scopes ||= [] of String

  callback_url = env.params.query["callback_url"]?
  if callback_url
    callback_url = URI.parse(callback_url)
  end

  expire = env.params.query["expire"]?.try &.to_i?
end

post "/authorize_token" do |env|
  locale = LANGS[env.get("preferences").as(Preferences).locale]?

  user = env.get? "user"
  sid = env.get? "sid"
  referer = get_referer(env)

  if !user
    next env.redirect referer
  end

  user = env.get("user").as(User)
  sid = sid.as(String)
  token = env.params.body["csrf_token"]?

  begin
    validate_request(token, sid, env.request, HMAC_KEY, PG_DB)
  rescue ex
    next error_template(400, ex)
  end

  scopes = env.params.body.select { |k, v| k.match(/^scopes\[\d+\]$/) }.map { |k, v| v }
  callback_url = env.params.body["callbackUrl"]?
  expire = env.params.body["expire"]?.try &.to_i?

  access_token = generate_token(user.email, scopes, expire, HMAC_KEY, PG_DB)

  if callback_url
    access_token = URI.encode_www_form(access_token)
    url = URI.parse(callback_url)

    if url.query
      query = HTTP::Params.parse(url.query.not_nil!)
    else
      query = HTTP::Params.new
    end

    query["token"] = access_token
    url.query = query.to_s

    env.redirect url.to_s
  else
    csrf_token = ""
    env.set "access_token", access_token
  end
end

get "/token_manager" do |env|
  locale = LANGS[env.get("preferences").as(Preferences).locale]?

  user = env.get? "user"
  sid = env.get? "sid"
  referer = get_referer(env, "/suggestions_manager")

  if !user
    next env.redirect referer
  end

  user = user.as(User)

  tokens = PG_DB.query_all("SELECT id, issued FROM session_ids WHERE email = $1 ORDER BY issued DESC", user.email, as: {session: String, issued: Time})
end

post "/token_ajax" do |env|
  locale = LANGS[env.get("preferences").as(Preferences).locale]?

  user = env.get? "user"
  sid = env.get? "sid"
  referer = get_referer(env)

  redirect = env.params.query["redirect"]?
  redirect ||= "true"
  redirect = redirect == "true"

  if !user
    if redirect
      next env.redirect referer
    else
      next error_json(403, "No such user")
    end
  end

  user = user.as(User)
  sid = sid.as(String)
  token = env.params.body["csrf_token"]?

  begin
    validate_request(token, sid, env.request, HMAC_KEY, PG_DB)
  rescue ex
    if redirect
      next error_template(400, ex)
    else
      next error_json(400, ex)
    end
  end

  if env.params.query["action_revoke_token"]?
    action = "action_revoke_token"
  else
    next env.redirect referer
  end

  session = env.params.query["session"]?
  session ||= ""

  case action
  when .starts_with? "action_revoke_token"
    PG_DB.exec("DELETE FROM session_ids * WHERE id = $1 AND email = $2", session, user.email)
  else
    next error_json(400, "Unspported action #{action}")
  end

  if redirect
    env.redirect referer
  else
    env.response.content_type = "application/json"
    "{}"
  end
end

get "/actor/:id" do |env|
  locale = LANGS[env.get("preferences").as(Preferences).locale]?

  user = env.get? "user"

  id = env.params.url["id"].to_i
  if !id
    raise InfoException.new("Actor not found")
  end

  actor = PG_DB.query_all("SELECT * FROM actors WHERE id = $1", id, as: Actor)[0]

  templated "actor"
end

get "/tv/:id" do |env|
  locale = LANGS[env.get("preferences").as(Preferences).locale]?

  user = env.get? "user"

  id = env.params.url["id"].to_i

  if !id
    raise InfoException.new("TV show not found.")
  end

  tv = get_tv(PG_DB, id)

  season = env.params.query["season_select"]?.try &.to_i
  if !season
    season = 1
  end

  episode = env.params.query["episode"]?.try &.to_i

  if episode
    video = PG_DB.query_one?("SELECT * FROM tv_episodes WHERE tv_id = $1 AND season_number = $2 AND episode_number = $3", tv.id, season, episode, as: Episode)
    if !video
      raise InfoException.new("Episode not found.")
    else
      captions = [] of Caption
      templated "watch_episode"
    end
  else
    templated "series_overview", x: false
  end
end

get "/browse/movies" do |env|
  locale = LANGS[env.get("preferences").as(Preferences).locale]?

  ids = [] of Int32
  begin
    env.request.cookies.each do |cookie|
      ids << (cookie.name.to_i)
    rescue
    end
  end

  continuations = PG_DB.query_all("SELECT * FROM movies WHERE id = ANY($1) ORDER BY random()", ids.shuffle, as: Video)

  items = PG_DB.query_all("SELECT * FROM movies ORDER BY random() LIMIT 120", as: Video)
    .reverse

  templated "browse_movies"
end

get "/browse/tv/" do |env|
  locale = LANGS[env.get("preferences").as(Preferences).locale]?

  items = PG_DB.query_all("SELECT * FROM tv ORDER BY random() LIMIT 120", as: TV)
    .reverse

  templated "browse_tv"
end

get "/browse/:category" do |env|
  locale = LANGS[env.get("preferences").as(Preferences).locale]?

  category = URI.decode_www_form(env.params.url["category"])

  content_type = category
    .split[-1]
    .downcase

  if content_type == "movies"
    columns = "*"
  elsif content_type == "tv"
    columns = "*"
  else
    next InfoException.new("Category does not exist")
  end

  case category
  when .includes? "action and adventure"
    query = "SELECT #{columns} FROM #{content_type} WHERE
    (array_to_string(genres, ', ') LIKE '%Action%') OR
    (array_to_string(genres, ', ') LIKE '%Adventure%')"
  when .includes? "comedy"
    query = "SELECT #{columns} FROM #{content_type} WHERE
    (array_to_string(genres, ', ') LIKE '%Comedy%')"
  when .includes? "drama"
    query = "SELECT #{columns} FROM #{content_type} WHERE
    (array_to_string(genres, ', ') LIKE '%Drama%')"
  when .includes? "fantasy"
    query = "SELECT #{columns} FROM #{content_type} WHERE
    (array_to_string(genres, ', ') LIKE '%Fantasy%')"
  when .includes? "horror"
    query = "SELECT #{columns} FROM #{content_type} WHERE
    (array_to_string(genres, ', ') LIKE '%Horror%')"
  when .includes? "military and war"
    query = "SELECT #{columns} FROM #{content_type} WHERE
    (array_to_string(genres, ', ') LIKE '%Military%') OR
    (array_to_string(genres, ', ') LIKE '%War%')"
  when .includes? "mystery and thriller"
    query = "SELECT #{columns} FROM #{content_type} WHERE
    (array_to_string(genres, ', ') LIKE '%Mystery%') OR
    (array_to_string(genres, ', ') LIKE '%Thriller%')"
  when .includes? "romance"
    query = "SELECT #{columns} FROM #{content_type} WHERE
    (array_to_string(genres, ', ') LIKE '%Romance%')"
  when .includes? "science fiction"
    query = "SELECT #{columns} FROM #{content_type} WHERE
    (array_to_string(genres, ', ') LIKE '%Science Fiction%')"
  else
    next InfoException.new("Category does not exist")
  end

  if content_type == "movies"
    category = category.capitalize
    items = PG_DB.query_all("#{query} ORDER by random()", as: Video)
  elsif content_type == "tv"
    category = category.capitalize
      .gsub("tv", "TV")
    items = PG_DB.query_all("#{query} ORDER by random()", as: TV)
  else
    next InfoException.new("Category does not exist")
  end

  templated "browse_category"
end

get "/browse" do |env|
  locale = LANGS[env.get("preferences").as(Preferences).locale]?

  referer = get_referer(env)

  ids = [] of Int32
  begin
    env.request.cookies.each do |cookie|
      ids << (cookie.name.to_i)
    rescue
    end
  end

  continuations = PG_DB.query_all("SELECT * FROM movies WHERE id = ANY($1) ORDER BY random()", ids.shuffle, as: Video)

  templated "browse"
end

get "/movies" do |env|
  locale = LANGS[env.get("preferences").as(Preferences).locale]?

  user = env.get? "user"

  env.set "search", "content_type:movie "

  templated "movies"
end

get "/admin/add_movie_caption" do |env|
  locale = LANGS[env.get("preferences").as(Preferences).locale]?

  templated "add_movie_subtitle"
end

post "/admin/add_movie_caption" do |env|
  locale = LANGS[env.get("preferences").as(Preferences).locale]?

  referer = get_referer(env)

  id = env.params.body["id"]?.try &.to_i
  if !id
    next error_template(401, "ID is a required field")
  end

  language = env.params.body["language"]?
  if !language
    next error_template(401, "Language is a required field")
  end

  caption_url = env.params.body["caption_url"]?
  if !caption_url
    next error_template(401, "Caption URL is a required field")
  end

  begin
    PG_DB.exec("DELETE FROM captions WHERE id = $1", id)
  rescue
  end
  begin
    PG_DB.exec("INSERT INTO captions (id,language,caption_url) VALUES ($1, $2, $3)", id, language, caption_url)
  rescue
  end

  env.redirect "/watch?trackId=" + id.to_s
end

get "/api/v1/auth/tokens" do |env|
  env.response.content_type = "application/json"
  user = env.get("user").as(User)
  scopes = env.get("scopes").as(Array(String))

  tokens = PG_DB.query_all("SELECT id, issued FROM session_ids WHERE email = $1", user.email, as: {session: String, issued: Time})

  JSON.build do |json|
    json.array do
      tokens.each do |token|
        json.object do
          json.field "session", token[:session]
          json.field "issued", token[:issued].to_unix
        end
      end
    end
  end
end

post "/api/v1/auth/tokens/register" do |env|
  locale = LANGS[env.get("preferences").as(Preferences).locale]?

  user = env.get("user").as(User)

  case env.request.headers["Content-Type"]?
  when "application/x-www-form-urlencoded"
    scopes = env.params.body.select { |k, v| k.match(/^scopes\[\d+\]$/) }.map { |k, v| v }
    callback_url = env.params.body["callbackUrl"]?
    expire = env.params.body["expire"]?.try &.to_i?
  when "application/json"
    scopes = env.params.json["scopes"].as(Array).map { |v| v.as_s }
    callback_url = env.params.json["callbackUrl"]?.try &.as(String)
    expire = env.params.json["expire"]?.try &.as(Int64)
  else
    next error_json(400, "Invalid or mising header 'Content-Type'")
  end

  if callback_url && callback_url.empty?
    callback_url = nil
  end

  if callback_url
    callback_url = URI.parse(callback_url)
  end

  if sid = env.get?("sid").try &.as(String)
    env.response.content_type = "text/html"

    csrf_token = generate_response(sid, {":authorize_token"}, HMAC_KEY, PG_DB, use_nonce: true)
  else
    env.response.content_type = "application/json"

    superset_scopes = env.get("scopes").as(Array(String))

    authorized_scopes = [] of String
    scopes.each do |scope|
      if scopes_include_scope(superset_scopes, scope)
        authorized_scopes << scope
      end
    end

    access_token = generate_token(user.email, authorized_scopes, expire, HMAC_KEY, PG_DB)

    if callback_url
      access_token = URI.encode_www_form(access_token)

      if query = callback_url.query
        query = HTTP::Params.parse(query.not_nil!)
      else
        query = HTTP::Params.new
      end

      query["token"] = access_token
      callback_url.query = query.to_s

      env.redirect callback_url.to_s
    else
      access_token
    end
  end
end

post "/api/v1/auth/tokens/unregister" do |env|
  env.response.content_type = "application/json"
  user = env.get("user").as(User)
  scopes = env.get("scopes").as(Array(String))

  session = env.params.json["session"]?.try &.as(String)
  session ||= env.get("session").as(String)

  if session == env.get("session").as(String)
    PG_DB.exec("DELETE FROM session_ids * WHERE id = $1", session)
  elsif scopes_include_scope(scopes, "GET:tokens")
    PG_DB.exec("DELETE FROM session_ids * WHERE id = $1", session)
  else
    next error_json(400, "Cannot revoke session #{session}")
  end

  env.response.status_code = 204
end

get "/images/:id" do |env|
  id = env.params.url["id"]

  url = "https://image.tmdb.org/t/p/original/#{id}"

  begin
    HTTP::Client.get(url) do |response|
      env.response.status_code = response.status_code
      response.headers.each do |key, value|
        env.response.headers[key] = value
      end

      env.response.headers["Access-Control-Allow-Origin"] = "*"

      if response.status_code >= 300 && response.status_code != 404
        env.response.headers.delete("Transfer-Encoding")
        break
      end

      proxy_file(response, env)
    end
  rescue ex
  end
end

get "/images/:id/:w" do |env|
  id = env.params.url["id"]
  w = env.params.url["w"]
  url = "https://image.tmdb.org/t/p/w#{w}/#{id}"

  begin
    HTTP::Client.get(url) do |response|
      env.response.status_code = response.status_code
      response.headers.each do |key, value|
        env.response.headers[key] = value
      end

      env.response.headers["Access-Control-Allow-Origin"] = "*"

      if response.status_code >= 300 && response.status_code != 404
        env.response.headers.delete("Transfer-Encoding")
        break
      end

      proxy_file(response, env)
    end
  rescue ex
  end
end

def refresh_series_data(i)
  response = HTTP::Client.get(URI.encode("https://api.themoviedb.org/3/tv/#{i}?api_key=66525ca337f3dc982c8497ea07caba09&append_to_response=content_ratings,videos"))
  response = JSON.parse(response.body)

  release_date = response["first_air_date"]
  genres = response["genres"].try &.as_a.map { |g| g["name"] }
  title = response["name"]
  number_of_episodes = response["number_of_episodes"]
  number_of_seasons = response["number_of_seasons"]
  overview = response["overview"]
  tagline = response["tagline"]
  popularity = response["popularity"]
  average_rating = response["vote_average"]
  certification = response["content_ratings"]["results"].try &.as_a.select { |r| r["iso_3166_1"] == "US" }[0].try &.["rating"]
  trailer_url = response["videos"]["results"].try &.as_a.select { |r| r["type"] == "Trailer" }[0].try &.["key"].try &.as_s
  trailer_url = "https://www.youtube.com/watch?v=" + trailer_url

  response = HTTP::Client.get(URI.encode("https://api.themoviedb.org/3/tv/#{i}/credits?api_key=66525ca337f3dc982c8497ea07caba09"))
  response = JSON.parse(response.body)
  cast = response["cast"].try &.as_a.map { |c| c["name"] }

  response = HTTP::Client.get(URI.encode("https://api.themoviedb.org/3/tv/#{i}/images?api_key=66525ca337f3dc982c8497ea07caba09"))
  response = JSON.parse(response.body)

  backdrops = response["backdrops"].try &.as_a.map { |b| b["file_path"] }
  posters = response["posters"].try &.as_a.map { |p| p["file_path"] }

  PG_DB.exec("UPDATE tv SET title = $1, number_of_episodes = $2, number_of_seasons = $3, overview = $4, release_date = $5, genres = $6, tagline = $7, backdrops = $8, posters = $9, popularity = $10, average_rating = $11, actors = $12, certification = $13, trailer_url = $14 WHERE tmdb_id = $15",
    title, number_of_episodes, number_of_seasons, overview, release_date, genres, tagline, backdrops, posters, popularity, average_rating, cast, certification, trailer_url, i)

  # Get episodes for all seasons
  number_of_seasons.to_s.to_i.times do |s|
    begin
      response = HTTP::Client.get(URI.encode("https://api.themoviedb.org/3/tv/#{i}/season/#{s + 1}?api_key=66525ca337f3dc982c8497ea07caba09"))
      response = JSON.parse(response.body)
      number_of_episodes = response["episodes"].try &.as_a.size

      number_of_episodes.times do |episode|
        begin
          response = HTTP::Client.get(URI.encode("https://api.themoviedb.org/3/tv/#{i}/season/#{s + 1}/episode/#{episode + 1}?api_key=66525ca337f3dc982c8497ea07caba09"))
          response = JSON.parse(response.body)
          air_date = response["air_date"]
          name = response["name"]
          overview = response["overview"]
          response = HTTP::Client.get(URI.encode("https://api.themoviedb.org/3/tv/#{i}/season/#{s + 1}/episode/#{episode + 1}/images?api_key=66525ca337f3dc982c8497ea07caba09"))
          response = JSON.parse(response.body)
          images = response["stills"].try &.as_a.map { |s| s["file_path"] }
          PG_DB.exec("DELETE FROM tv_episodes WHERE tv_id = $1 AND season_number = $2 AND episode_number = $3", i, s + 1, episode + 1)
          PG_DB.exec("INSERT INTO tv_episodes (air_date,name,overview,tv_id,season_number,episode_number,images) VALUES ($1, $2, $3, $4, $5, $6, $7)", air_date, name, overview, i, s + 1, episode + 1, images)
        rescue
        end
      end
    rescue
    end
  end

  response = HTTP::Client.get(URI.encode("https://api.themoviedb.org/3/tv/#{i}/credits?api_key=66525ca337f3dc982c8497ea07caba09"))
  response = JSON.parse(response.body)
  response["cast"].try &.as_a[0..2].each do |member|
    begin
      id = member["id"]
      response = HTTP::Client.get(URI.encode("https://api.themoviedb.org/3/person/#{id}?api_key=66525ca337f3dc982c8497ea07caba09"))
      response = JSON.parse(response.body)

      biography = response["biography"].try &.as_s
      birthday = response["birthday"].try &.as_s
      known_for = response["known_for_department"].try &.as_s
      name = response["name"].try &.as_s
      place_of_birth = response["place_of_birth"].try &.as_s
      profile_path = response["profile_path"].try &.as_s
      popularity = response["popularity"]

      begin
        PG_DB.exec("INSERT INTO actors (id, name, profile_path, biography, place_of_birth, birthday, known_for, popularity) VALUES ($1,$2,$3,$4,$5,$6,$7,$8)", id, name, profile_path, biography, place_of_birth, birthday, known_for, popularity)
      rescue ex
	puts ex.message
      end
    rescue ex
      puts ex.message
    end
  end
end

def refresh_film_data(i)
  response = HTTP::Client.get(URI.encode("https://api.themoviedb.org/3/movie/#{i}?api_key=66525ca337f3dc982c8497ea07caba09&append_to_response=release_dates,videos"))
  response = JSON.parse(response.body)

  backdrop_path = response["backdrop_path"]
  overview = response["overview"]
  genres = response["genres"].try &.as_a.map { |g| g["name"] }
  poster_path = response["poster_path"]
  release_date = response["release_date"]
  runtime = response["runtime"]
  tagline = response["tagline"]
  title = response["title"]
  spoken_languages = response["spoken_languages"].try &.as_a.map { |l| l["name"] }
  imdb_id = response["imdb_id"].try &.as_s
  popularity = response["popularity"]
  average_rating = response["vote_average"]
  certification = response["release_dates"]["results"].try &.as_a.select { |r| r["iso_3166_1"] == "US" }[0].try &.["release_dates"][0]["certification"]
  trailer_url = response["videos"]["results"].try &.as_a.select { |r| r["type"] == "Trailer" }[0].try &.["key"].try &.as_s
  trailer_url = "https://www.youtube.com/watch?v=" + trailer_url

  response = HTTP::Client.get(URI.encode("https://api.themoviedb.org/3/movie/#{i}/credits?api_key=66525ca337f3dc982c8497ea07caba09"))
  response = JSON.parse(response.body)

  cast = response["cast"].try &.as_a.map { |c| c["name"] }

  response = HTTP::Client.get(URI.encode("https://api.themoviedb.org/3/movie/#{i}/images?api_key=66525ca337f3dc982c8497ea07caba09"))
  response = JSON.parse(response.body)

  backdrops = response["backdrops"].try &.as_a.map { |b| b["file_path"] }
  posters = response["posters"].try &.as_a.map { |p| p["file_path"] }

  PG_DB.exec("UPDATE movies SET backdrops = $1, overview = $2, release_date = $3, runtime = $4, tagline = $5, title = $6, genres = $7, posters = $8, actors = $9, popularity = $10, average_rating = $11, certification = $12, trailer_url = $13, spoken_languages = $14, imdb_id = $15 WHERE tmdb_id = $16", backdrops, overview, release_date, runtime, tagline, title, genres, posters, cast, popularity, average_rating, certification, trailer_url, spoken_languages, imdb_id, i)

  response = HTTP::Client.get(URI.encode("https://api.themoviedb.org/3/movie/#{i}/credits?api_key=66525ca337f3dc982c8497ea07caba09"))
  response = JSON.parse(response.body)

  response["cast"].try &.as_a[0..2].each do |member|
    begin
      id = member["id"]
      response = HTTP::Client.get(URI.encode("https://api.themoviedb.org/3/person/#{id}?api_key=66525ca337f3dc982c8497ea07caba09"))
      response = JSON.parse(response.body)

      biography = response["biography"].try &.as_s
      birthday = response["birthday"].try &.as_s
      known_for = response["known_for_department"].try &.as_s
      name = response["name"].try &.as_s
      place_of_birth = response["place_of_birth"].try &.as_s
      profile_path = response["profile_path"].try &.as_s
      popularity = response["popularity"]

      begin
        PG_DB.exec("INSERT INTO actors (id, name, profile_path, biography, place_of_birth, birthday, known_for, popularity) VALUES ($1,$2,$3,$4,$5,$6,$7,$8)", id, name, profile_path, biography, place_of_birth, birthday, known_for, popularity)
      rescue ex
	puts ex.message
      end
    rescue ex
      puts ex.message
    end
  end
end

error 500 do |env, ex|
  error_template(500, ex)
end

static_headers do |response, filepath, filestat|
  response.headers.add("Cache-Control", "max-age=2629800")
end

public_folder "assets"

Kemal.config.powered_by_header = false
add_handler FilteredCompressHandler.new
add_handler APIHandler.new
add_handler AuthHandler.new
add_handler DenyFrame.new
add_context_storage_type(Array(String))
add_context_storage_type(Preferences)
add_context_storage_type(User)

Kemal.config.host_binding = Kemal.config.host_binding != "0.0.0.0" ? Kemal.config.host_binding : CONFIG.host_binding
Kemal.config.port = Kemal.config.port != 3000 ? Kemal.config.port : CONFIG.port
Kemal.run
