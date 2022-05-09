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

ENCODING_DIR = "/storage/Encoding"

class GetAMovie::Jobs::TranscodingJob < GetAMovie::Jobs::BaseJob
  private getter db : DB::Database

  def initialize(@db)
  end

  def begin
    loop do
      begin
        target = ""
        d = Dir.new(ENCODING_DIR)
        d.each do |file|
          if file.includes?(".mp4") ||
             file.includes?(".mkv")
            target = file
            break
          end
        end
        n = target.gsub(/\(|\)/, "")

        # Extract name and year of release from file name
        title = [] of String
        year = 0
        name_arr = n.split(" ").join(".").split(".")
        name_arr.each_with_index do |part, index|
          if !/\A\d+\z/.match(part)
            title << part
          else
            year = part
            break
          end
        end

        # Look it up
        title = title.join("%20")
        response = HTTP::Client.get("https://api.themoviedb.org/3/search/movie?api_key=66525ca337f3dc982c8497ea07caba09&language=en-US&query=#{title}&page=1&year=#{year.to_s}")
        response = JSON.parse(response.body)
        id = response["results"].try &.as_a[0].try &.["id"].try &.to_s
        FileUtils.mkdir "#{ENCODING_DIR}/#{id.to_s}"

        PG_DB.exec("DELETE FROM movies WHERE id = $1", id)
        PG_DB.exec("INSERT INTO movies (id, tmdb_id, dash_manifest_url, hls_manifest_url) VALUES ($1, $2, $3, $4)", id, id.to_s, "/Library/#{id}/stream.mpd", "/Library/#{id}/master.m3u8")

        # FFMPEG encode
        ffmpeg_command = "ffmpeg -i #{ENCODING_DIR}/\"#{target}\" -c:v libx264 -preset faster -b:v 3000k -maxrate 3000k -bufsize 6000k -vf \"format=yuv420p\" -g 50 -c:a aac -b:a 128k -ac 2 -ar 44100 #{ENCODING_DIR}/pass1.mp4"
        run ffmpeg_command

        frag_command = "./../contrib/Bento4-SDK-1-6-0-639.x86_64-unknown-linux/bin/mp4fragment #{ENCODING_DIR}/pass1.mp4 #{ENCODING_DIR}/pass2.mp4"
        run frag_command

        # Make DASH and HLS playlists from fragmented MP4
        dash_command = "./../contrib/Bento4-SDK-1-6-0-639.x86_64-unknown-linux/bin/mp4dash --force --hls --use-segment-template-number-padding --use-segment-timeline #{ENCODING_DIR}/pass2.mp4 -o #{ENCODING_DIR}/#{id.to_s}"
        run dash_command
      rescue
      end

      FileUtils.rm_rf "#{ENCODING_DIR}/#{target}"
      FileUtils.rm_rf "#{ENCODING_DIR}/pass1.mp4"
      FileUtils.rm_rf "#{ENCODING_DIR}/pass2.mp4"

      refresh_film_data id
    end
  end
end
