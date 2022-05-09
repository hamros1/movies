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

class GetAMovie::Jobs::TorrenterJob < GetAMovie::Jobs::BaseJob
  private getter db : DB::Database

  def initialize(@db)
  end

  def begin
    6000.times do |i|
      begin
        response = HTTP::Client.get "https://www.imdb.com/search/title/?title_type=feature&start=#{51*i}&ref_=adv_nxt"
        doc = XML.parse_html(response.body)

        html = doc.xpath_nodes "//h3[contains(@class, 'lister-item-header')]"
        html.each do |h|
          id = /<a\s+(?:[^>]*?\s+)?href=(["'])(.*?)\1/.match(h.children[3].to_s).try &.[2].try &.split("/").select { |s| s.starts_with? "tt" }.try &.join
          if id_ = id
            begin
              response = HTTP::Client.get "https://api.themoviedb.org/3/find/#{id_}?api_key=66525ca337f3dc982c8497ea07caba09&external_source=imdb_id"
              response = JSON.parse(response.body)

              id = response["movie_results"][0]["id"].try &.as_i
              if PG_DB.query_one?("SELECT EXISTS(SELECT 1 FROM movies WHERE tmdb_id=$1)", id, as: Bool)
                next
              end

              title = response["movie_results"][0]["title"].try &.to_s
              poster = response["movie_results"][0]["poster_path"].try &.to_s
              year = (/\(([^\)]+)\)/.match(h.children[5].content)).try(&.[1].to_s)
              if year
                year = HTML.escape(year.try &.to_s)
              end

              response = HTTP::Client.get "https://1337x.to/sort-category-search/#{title.split(" ").join("%20")}%20#{year}/Movies/seeders/desc/1/"
              doc = XML.parse_html(response.body)

              html = doc.xpath_nodes "//td[@class='coll-1 name']"
              html.each do |h|
                # Brainfuck
                #                if (h.children[1].content.includes?("[UTR]") || h.children[1].content.includes?(".UHD.BluRay.") || h.children[1].content.to_s.includes?("Tigole") || h.children[1].content.to_s.includes?("[QxR]") || h.children[1].content.to_s.includes?("RARBG") || h.children[1].content.to_s.includes?("AMZN") || h.children[1].content.to_s.includes?("YIFY") || h.children[1].content.to_s.includes?("REMASTERED")) && (h.children[1].content.to_s.includes?("H264") || h.children[1].content.includes?("x264") || h.children[1].content.to_s.includes?("x265") || h.children[1].content.to_s.includes?("HEVC")) && ((!h.children[1].content.to_s.includes?("sub")) || (!h.children[1].content.to_s.includes?("SUB")) || (!h.children[1].content.to_s.includes?("Sub"))) && (h.children[1].content.to_s.includes?("1080p") || h.children[1].content.to_s.includes?("2160p"))
                if (h.children[1].content.to_s.includes?("UTR") || (h.children[1].content.to_s.includes?("QxR"))) && (h.children[1].to_s.includes?("2160p") || h.children[1].to_s.includes?("1080p"))
                  if path = /<a\s+(?:[^>]*?\s+)?href=(["'])(.*?)\1/.match(h.children[1].to_s).try(&.[2])
                    response = HTTP::Client.get "https://1337x.to" + path
                    doc = XML.parse_html(response.body)

                    html = doc.xpath_nodes "//*[@class=\"tab-pane file-content\"]"
                    filename = html[0].children.to_a.select { |s| s.content.to_s.includes? title }.try(&.[0]).content.to_s
                    if filename
                      filename = HTML.escape(filename.try &.to_s)
                    end

                    html = doc.xpath_nodes "//*[@class=\"dropdown-menu\"]"

                    #                     magnet = doc.to_s.split("\"").select { |s| s.starts_with? "magnet:?" }.try(&.[0]).to_s
                    torrent = /<a\s+(?:[^>]*?\s+)?href=(["'])(.*?)\1/.match(html[0].to_s).try &.[2].try &.split("/").select { |s| s.ends_with? ".torrent" }.try &.join.to_s
                    torrent = "http://itorrents.org/torrent/#{torrent}"
                    if torrent
                      torrent = HTML.escape(torrent)
                    end

                    PG_DB.exec("INSERT INTO download (title, poster_path, year, magnet, filename) VALUES ($1, $2, $3, $4, $5)", title, poster, year, torrent, filename)
                    break
                  end
                end
              end
            rescue
              next
            end
          end
        end
      end
    rescue
      next
    end
  end
end
