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

class RedditThing
  include JSON::Serializable

  property kind : String
  property data : RedditComment | RedditLink | RedditMore | RedditListing
end

class RedditComment
  include JSON::Serializable

  property author : String
  property body_html : String
  property replies : RedditThing | String
  property score : Int32
  property depth : Int32
  property permalink : String

  @[JSON::Field(converter: RedditComment::TimeConverter)]
  property created_utc : Time

  module TimeConverter
    def self.from_json(value : JSON::PullParser) : Time
      Time.unix(value.read_float.to_i)
    end

    def self.to_json(value : Time, json : JSON::Builder)
      json.number(value.to_unix)
    end
  end
end

class RedditLink
  include JSON::Serializable

  property author : String
  property score : Int32
  property subreddit : String
  property num_comments : Int32
  property id : String
  property permalink : String
  property title : String
end

struct RedditMore
  include JSON::Serializable

  property children : Array(String)
  property count : Int32
  property depth : Int32
end

class RedditListing
  include JSON::Serializable

  property children : Array(RedditThing)
  property modhash : String
end

def fetch_reddit_comments(id, sort_by = "confidence")
  client = make_client(REDDIT_URL)
  headers = HTTP::Headers{"User-Agent" => "Mozilla/5.0 (Windows NT 6.1; Win64; x64; rv:47.0) Gecko/20100101 Firefox/47.0"}

  search_results = client.get("/search.json?q=#{id}", headers)

  if search_results.status_code == 200
    search_results = RedditThing.from_json(search_results.body)

    thread = search_results.data.as(RedditListing).children.sort_by { |child| child.data.as(RedditLink).score }[-1]
    thread = thread.data.as(RedditLink)

    result = client.get("/r/#{thread.subreddit}/comments/#{thread.id}.json?limit=100&sort=#{sort_by}", headers).body
    result = Array(RedditThing).from_json(result)
  elsif search_results.status_code == 302
    result = client.get(search_results.headers["Location"], headers).body
    result = Array(RedditThing).from_json(result)

    thread = result[0].data.as(RedditListing).children[0].data.as(RedditLink)
  else
    raise InfoException.new("Could not fetch comments")
  end

  client.close

  comments = result[1].data.as(RedditListing).children
  return comments, thread
end

def template_reddit_comments(root, locale)
  String.build do |html|
    root.each do |child|
      if child.data.is_a?(RedditComment)
        child = child.data.as(RedditComment)
        body_html = HTML.unescape(child.body_html)

        replies_html = ""
        if child.replies.is_a?(RedditThing)
          replies = child.replies.as(RedditThing)
          replies_html = template_reddit_comments(replies.data.as(RedditListing).children, locale)
        end

        if child.depth > 0
          html << <<-END_HTML
          <div class="pure-g">
          <div class="pure-u-1-24">
          </div>
          <div class="pure-u-23-24">
          END_HTML
        else
          html << <<-END_HTML
          <div class="pure-g">
          <div class="pure-u-1">
          END_HTML
        end

        html << <<-END_HTML
        <p>
          <a href="javascript:void(0)" data-onclick="toggle_parent">[ - ]</a>
          <b><a href="https://www.reddit.com/user/#{child.author}">#{child.author}</a></b>
          #{t(locale, "`x` points", number_with_separator(child.score))}
          <span title="#{child.created_utc.to_s(t(locale, "%a %B %-d %T %Y UTC"))}">#{t(locale, "`x` ago", recode_date(child.created_utc, locale))}</span>
          <a href="https://www.reddit.com#{child.permalink}" title="#{t(locale, "permalink")}">#{t(locale, "permalink")}</a>
          </p>
          <div>
          #{body_html}
          #{replies_html}
        </div>
        </div>
        </div>
        END_HTML
      end
    end
  end
end

def replace_links(html)
  html = XML.parse_html(html)

  html.xpath_nodes(%q(//a)).each do |anchor|
    url = URI.parse(anchor["href"])

    if url.to_s == "#"
      begin
        length_seconds = decode_length_seconds(anchor.content)
      rescue ex
        length_seconds = decode_time(anchor.content)
      end

      if length_seconds > 0
        anchor["href"] = "javascript:void(0)"
        anchor["onclick"] = "player.currentTime(#{length_seconds})"
      else
        anchor["href"] = url.request_target
      end
    end
  end

  html = html.xpath_node(%q(//body)).not_nil!
  if node = html.xpath_node(%q(./p))
    html = node
  end

  return html.to_xml(options: XML::SaveOptions::NO_DECL)
end

def fill_links(html, scheme, host)
  html = XML.parse_html(html)

  html.xpath_nodes("//a").each do |match|
    url = URI.parse(match["href"])
    if !url.host && !match["href"].starts_with?("javascript") && !url.to_s.ends_with? "#"
      url.scheme = scheme
      url.host = host
      match["href"] = url
    end
  end

  return html.to_xml(options: XML::SaveOptions::NO_DECL)
end
