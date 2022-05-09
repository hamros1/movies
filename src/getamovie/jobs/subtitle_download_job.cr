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

class GetAMovie::Jobs::SubtitleDownloadJob < GetAMovie::Jobs::BaseJob
  private getter db : DB::Database

  def initialize(@db)
  end

  def begin
    imdb_id = db.query_all("SELECT imdb_id FROM movies ORDER BY random()", as: String | Nil)
    imdb_id.each do |imdb|
      if id = imdb
        langs = [] of String
        offset = 0
        loop do
          begin
	    url = "https://www.opensubtitles.org/en/search/imdbid-#{id[2 .. -1]}/sublanguageid-all/offset-#{offset}"
	    puts url
	    response = HTTP::Client.get url
            response = XML.parse_html(response.body)

            html1 = response.xpath_nodes("//a[contains(@href,'/subtitleserve/sub/')]/@href")
            html2 = response.xpath_nodes("//a[contains(@href,'/offset-#{offset}/sublanguageid')]/@title")
            html3 = response.xpath_nodes("//*[contains(@class,'msg hint')]")
            html2.each_with_index do |lang, index|
              lang = lang.content.to_s
              langs << lang

              if !(langs.select!(lang)).empty?
                next
              end

              url = "https://opensubtitles.org" + html1[index].content.to_s
              file = url.split("/")[-1]
              puts "#{id} #{file} #{lang} #{url}"

              #            command = "mkdir #{lang}"
              #            process = Process.new(command, shell: true)
              #            process.wait

              #            command = "wget -O #{lang}/#{file}.zip #{url}"
              #            process = Process.new(command, shell: true)
              #            process.wait

              #            command = "unzip -o #{lang}/*.zip -d #{lang}"
              #            process = Process.new(command, shell: true)
              #            process.wait

              #            command = "rm -rf #{lang}/*.zip"
              #            process = Process.new(command, shell: true)
              #            process.wait

              sleep 5.seconds
            end
            offset += 40
          rescue ex
	    puts ex.message
            break
          end
        end
      end
    end
  end
end
