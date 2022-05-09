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

class GetAMovie::Routes::Watch < GetAMovie::Routes::BaseRoute
  def handle(env)
    locale = LANGS[env.get("preferences").as(Preferences).locale]?

    if env.params.query.to_s.includes?("%20") || env.params.query.to_s.includes?("+")
      url = "/watch?" + env.params.query.to_s.gsub("%20", "").delete("+")
      return env.redirect url
    end

    if env.params.query["trackId"]?
      id = env.params.query["trackId"]

      if env.params.query["trackId"].empty?
        return error_template(400, "Invalid parameters.")
      end

      if id.size > 11
        url = "/watch?v=#{id[0, 11]}"
        env.params.query.delete_all("trackId")
        if env.params.query.size > 0
          url += "&#{env.params.query}"
        end

        return env.redirect url
      end
    else
      return env.redirect "/"
    end

    embed_link = "/embed/#{id}"
    if env.params.query.size > 1
      embed_params = HTTP::Params.parse(env.params.query.to_s)
      embed_params.delete_all("v")
      embed_link += "?"
      embed_link += embed_params.to_s
    end

    plid = env.params.query["list"]?.try &.gsub(/[^a-zA-Z0-9_-]/, "")

    preferences = env.get("preferences").as(Preferences)

    user = env.get?("user").try &.as(User)
    if user
      watched = user.watched
    end

    nojs = env.params.query["nojs"]?

    nojs ||= "0"
    nojs = nojs == "1"

    params = process_video_params(env.params.query, preferences)
    begin
      video = get_video(id, PG_DB)
    rescue ex : VideoRedirect
      return env.redirect env.request.resource.gsub(id, ex.video_id)
    rescue ex
      return error_template(500, ex)
    end

    if watched && !watched.includes? id
      PG_DB.exec("UPDATE users SET watched = array_append(watched, $1) WHERE email = $2", id, user.as(User).email)
    end

    if nojs
      if preferences
        source = preferences.comments[0]
        if source.empty?
          source = preferences.comments[1]
        end

        if source == "reddit"
          begin
            comments, reddit_thread = fetch_reddit_comments(id)
            comment_html = template_reddit_comments(comments, locale)

            comment_html = fill_links(comment_html, "https", "www.reddit.com")
            comment_html = replace_links(comment_html)
          rescue ex
          end
        end
      end

      comment_html ||= ""
    end

    aspect_ratio = "16:9"

    thumbnail = "/dash/#{video.id}/default.jpg"

    captions = PG_DB.query_all("SELECT * FROM captions WHERE id = $1", video.id, as: Caption)
    
    actors = [] of Actor

    video.actors.try &.to_a[0 .. 2].each do |actor|
      begin
        rs = PG_DB.query_all("SELECT * FROM actors WHERE name = $1", actor, as: Actor)
        actors.push(rs[0])
      rescue
      end
    end

    ch = env.params.query["ch"]?.try &.to_s
    if channel = ch
      templated "watch_party", x: false
    else
      templated "watch", x: false
    end
  end

  def redirect(env)
    url = "/watch?trackId=#{env.params.url["id"]}"
    if env.params.query.size > 0
      url += "&#{env.params.query}"
    end

    return env.redirect url
  end
end
